// internal/tools/flent.go
package tools

import (
	"regexp"
	"strconv"
	"time"
)

type Flent struct {
	OutputDir string
}

func NewFlent(outputDir string) *Flent {
	return &Flent{OutputDir: outputDir}
}

func (t *Flent) Name() string {
	return "flent"
}

func (t *Flent) ServerCmd(port int) []string {
	// Flent uses netserver
	return []string{"netserver", "-p", strconv.Itoa(port)}
}

func (t *Flent) ClientCmd(target string, port int, flows int, duration time.Duration) []string {
	// Flent doesn't support arbitrary flow counts - it uses RRUL which has fixed flows
	return []string{
		"flent", "rrul",
		"-l", strconv.Itoa(int(duration.Seconds())),
		"-H", target,
		"-D", t.OutputDir,
	}
}

// SupportsStreaming returns true - flent has verbose streaming with socket stats
func (t *Flent) SupportsStreaming() bool {
	return true
}

// StreamClientCmd returns flent command with verbose streaming flags.
// -v: verbose logging to console
// --socket-stats: parse socket stats during test (TCP cwnd and RTT values)
// -s 0.5: measurement step size of 0.5s for finer granularity
func (t *Flent) StreamClientCmd(target string, port int, flows int, duration time.Duration) []string {
	return []string{
		"flent", "rrul",
		"-l", strconv.Itoa(int(duration.Seconds())),
		"-H", target,
		"-D", t.OutputDir,
		"-v",              // Verbose logging to console
		"--socket-stats",  // Capture TCP cwnd and RTT during test
		"-s", "0.5",       // Step size 0.5s for finer granularity
	}
}

// ParseLine parses flent verbose output for throughput and latency metrics.
// Verbose output includes netperf progress, RTT measurements, and throughput data.
func (t *Flent) ParseLine(line string, acc *StreamAccumulator) bool {
	parsed := false

	// Parse RTT measurements (various formats)
	// Format: "RTT: 1.23 ms" or "rtt 1.23ms" or similar
	rttRe := regexp.MustCompile(`[Rr][Tt][Tt].*?(\d+\.?\d*)\s*ms`)
	if matches := rttRe.FindStringSubmatch(line); len(matches) >= 2 {
		rtt, err := strconv.ParseFloat(matches[1], 64)
		if err == nil {
			acc.Lock()
			acc.LatencyMs = rtt
			if rtt > acc.MaxLatencyMs {
				acc.MaxLatencyMs = rtt
			}
			// Update running average
			if acc.IntervalCount > 0 {
				acc.AvgLatencyMs = (acc.AvgLatencyMs*float64(acc.IntervalCount) + rtt) / float64(acc.IntervalCount+1)
			} else {
				acc.AvgLatencyMs = rtt
			}
			acc.LastUpdate = time.Now()
			acc.IntervalCount++
			acc.Unlock()
			parsed = true
		}
	}

	// Parse throughput measurements
	// Format: "12.34 Gbits/s" or "1234.56 Mbits/s" or similar
	tpRe := regexp.MustCompile(`(\d+\.?\d*)\s*(G|M|K)?bits?/s`)
	if matches := tpRe.FindStringSubmatch(line); len(matches) >= 2 {
		value, err := strconv.ParseFloat(matches[1], 64)
		if err == nil {
			// Convert to Gbps
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
			acc.Unlock()
			parsed = true
		}
	}

	// Parse socket stats: cwnd values
	// Format: "cwnd:123" or "cwnd 123"
	cwndRe := regexp.MustCompile(`cwnd[:\s]+(\d+)`)
	if matches := cwndRe.FindStringSubmatch(line); len(matches) >= 2 {
		// cwnd is captured but not stored in StreamAccumulator currently
		// Could add a field for it if needed
		parsed = true
	}

	return parsed
}

func (t *Flent) Parse(output string, flows int, duration time.Duration) (*NormalizedResult, error) {
	result := &NormalizedResult{
		Tool:      t.Name(),
		Timestamp: time.Now(),
		Duration:  duration,
		FlowCount: flows,
	}

	// Parse flent RRUL summary output for throughput
	// Format: " TCP totals       :     18109.77          N/A          N/A Mbits/s"
	// Or:     " TCP download sum :      8725.58          N/A          N/A Mbits/s"

	var throughputMbps float64

	// Try TCP totals first (bidirectional)
	totalsRe := regexp.MustCompile(`TCP totals\s*:\s*(\d+\.?\d*)`)
	matches := totalsRe.FindStringSubmatch(output)
	if len(matches) >= 2 {
		throughputMbps, _ = strconv.ParseFloat(matches[1], 64)
	}

	// Fallback to TCP download sum
	if throughputMbps == 0 {
		downloadRe := regexp.MustCompile(`TCP download sum\s*:\s*(\d+\.?\d*)`)
		matches = downloadRe.FindStringSubmatch(output)
		if len(matches) >= 2 {
			throughputMbps, _ = strconv.ParseFloat(matches[1], 64)
		}
	}

	// Convert Mbits/s to Gbps
	result.ThroughputGbps = throughputMbps / 1000

	// Parse ping latency (ICMP avg)
	// Format: " Ping (ms) ICMP   :         1.10         0.57         3.45 ms"
	pingRe := regexp.MustCompile(`Ping \(ms\) ICMP\s*:\s*(\d+\.?\d*)`)
	pingMatches := pingRe.FindStringSubmatch(output)
	if len(pingMatches) >= 2 {
		result.LatencyP50Ms, _ = strconv.ParseFloat(pingMatches[1], 64)
	}

	result.RawOutput = output
	return result, nil
}

func (t *Flent) SupportsFlowCount() bool {
	return false // RRUL has fixed flow count
}

func (t *Flent) DefaultPort() int {
	return 12865
}
