// internal/tools/iperf2.go
package tools

import (
	"regexp"
	"strconv"
	"strings"
	"time"
)

type Iperf2 struct{}

func NewIperf2() *Iperf2 {
	return &Iperf2{}
}

func (t *Iperf2) Name() string {
	return "iperf2"
}

func (t *Iperf2) ServerCmd(port int) []string {
	return []string{"iperf", "-s", "-p", strconv.Itoa(port)}
}

func (t *Iperf2) ClientCmd(target string, port int, flows int, duration time.Duration) []string {
	return []string{
		"iperf",
		"-c", target,
		"-p", strconv.Itoa(port),
		"-P", strconv.Itoa(flows),
		"-t", strconv.Itoa(int(duration.Seconds())),
		"-i", "2",
	}
}

// SupportsStreaming returns true - iperf2 has excellent streaming support
func (t *Iperf2) SupportsStreaming() bool {
	return true
}

// StreamClientCmd returns client command with streaming flags enabled.
// Uses CSV format (-y C) for easy parsing and enhanced reporting (-e).
// Reports every 1 second for real-time metrics.
func (t *Iperf2) StreamClientCmd(target string, port int, flows int, duration time.Duration) []string {
	return []string{
		"iperf",
		"-c", target,
		"-p", strconv.Itoa(port),
		"-P", strconv.Itoa(flows),
		"-t", strconv.Itoa(int(duration.Seconds())),
		"-i", "1",  // Report every 1 second
		"-e",       // Enhanced reporting
		"-y", "C",  // CSV format for easy parsing
	}
}

// ParseLine parses CSV format from -y C -e output.
// CSV format with enhanced (-e) reporting:
// Header: time,srcaddress,srcport,dstaddr,dstport,transferid,istart,iend,bytes,speed,...
// Data:   -0800:20260218111259.511098,10.1.0.2,51018,10.2.0.2,5001,4,0.0,1.0,76073032,608584256,...
//
// Field indices:
//   [0] time (with timezone prefix like -0800:timestamp)
//   [1] srcaddress
//   [2] srcport
//   [3] dstaddr
//   [4] dstport
//   [5] transferid (-1 for SUM lines)
//   [6] istart (interval start)
//   [7] iend (interval end)
//   [8] bytes transferred
//   [9] speed in bits/sec
func (t *Iperf2) ParseLine(line string, acc *StreamAccumulator) bool {
	// Skip header lines and empty lines
	if strings.HasPrefix(line, "time,") || len(strings.TrimSpace(line)) == 0 {
		return false
	}

	// Skip non-CSV lines (text output may be mixed in)
	if !strings.Contains(line, ",") {
		return false
	}

	fields := strings.Split(line, ",")
	if len(fields) < 10 {
		return false
	}

	// Skip individual flow lines, we only want SUM lines (transferid=-1)
	// This gives us aggregate throughput across all flows
	if fields[5] != "-1" {
		return false
	}

	// fields[8] = bytes transferred
	// fields[9] = speed in bits/sec
	bandwidth, err := strconv.ParseFloat(fields[9], 64)
	if err != nil {
		return false
	}

	transfer, _ := strconv.ParseFloat(fields[8], 64)

	acc.Lock()
	acc.ThroughputGbps = bandwidth / 1e9 // Convert bits/sec to Gbps
	acc.BytesTransferred += int64(transfer)
	acc.LastUpdate = time.Now()
	acc.IntervalCount++
	acc.Unlock()
	return true
}

// ParseLineText parses enhanced text format (alternative if -y C is not used).
// Example: [  3]  0.0- 1.0 sec  1.12 GBytes  9.62 Gbits/sec
func (t *Iperf2) ParseLineText(line string, acc *StreamAccumulator) bool {
	// Match interval lines: [  3] 0.0- 1.0 sec  1.12 GBytes  9.62 Gbits/sec
	re := regexp.MustCompile(`\[\s*\d+\]\s+[\d.]+-[\d.]+\s+sec\s+[\d.]+\s+\w+\s+([\d.]+)\s+(G|M|K)?bits/sec`)
	matches := re.FindStringSubmatch(line)
	if len(matches) < 2 {
		return false
	}

	value, err := strconv.ParseFloat(matches[1], 64)
	if err != nil {
		return false
	}

	// Convert to Gbps based on unit
	if len(matches) >= 3 {
		switch matches[2] {
		case "G": // already Gbps
		case "M":
			value /= 1000
		case "K":
			value /= 1000000
		default:
			value /= 1000000000
		}
	}

	acc.Lock()
	acc.ThroughputGbps = value
	acc.LastUpdate = time.Now()
	acc.IntervalCount++
	acc.Unlock()
	return true
}

func (t *Iperf2) Parse(output string, flows int, duration time.Duration) (*NormalizedResult, error) {
	result := &NormalizedResult{
		Tool:      t.Name(),
		Timestamp: time.Now(),
		Duration:  duration,
		FlowCount: flows,
	}

	var matches []string

	// For multiple flows, parse [SUM] line for aggregate throughput
	// There may be multiple [SUM] lines (one per interval), we need the final cumulative one
	// Final summary line starts from 0.0: [SUM] 0.0000-5.1006 sec  5.65 GBytes  9.51 Gbits/sec
	sumRe := regexp.MustCompile(`\[SUM\]\s+0\.0+[-][\d.]+\s+sec.*?(\d+\.?\d*)\s+(G|M|K)?bits/sec`)
	allSumMatches := sumRe.FindAllStringSubmatch(output, -1)
	if len(allSumMatches) > 0 {
		// Use the last cumulative [SUM] line (the one spanning full duration)
		matches = allSumMatches[len(allSumMatches)-1]
	}

	// For single flow, parse the final line with full duration
	// Example: [  1] 0.0000-10.0032 sec  11.0 GBytes  9.44 Gbits/sec
	if len(matches) < 2 {
		// Look for final summary line (matches full duration starting from 0.0)
		singleRe := regexp.MustCompile(`\[\s*\d+\]\s+0\.0+[-][\d.]+\s+sec.*?(\d+\.?\d*)\s+(G|M|K)?bits/sec`)
		allMatches := singleRe.FindAllStringSubmatch(output, -1)
		if len(allMatches) > 0 {
			// Use the last match (final summary)
			matches = allMatches[len(allMatches)-1]
		}
	}

	if len(matches) >= 2 {
		val, _ := strconv.ParseFloat(matches[1], 64)
		unit := ""
		if len(matches) >= 3 {
			unit = matches[2]
		}
		switch unit {
		case "G":
			result.ThroughputGbps = val
		case "M":
			result.ThroughputGbps = val / 1000
		case "K":
			result.ThroughputGbps = val / 1000000
		default:
			result.ThroughputGbps = val / 1000000000
		}
	}

	result.RawOutput = output
	return result, nil
}

func (t *Iperf2) SupportsFlowCount() bool {
	return true
}

func (t *Iperf2) DefaultPort() int {
	return 5001
}
