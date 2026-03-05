// internal/tools/iperf3.go
package tools

import (
	"encoding/json"
	"regexp"
	"strconv"
	"time"
)

type Iperf3 struct{}

func NewIperf3() *Iperf3 {
	return &Iperf3{}
}

func (t *Iperf3) Name() string {
	return "iperf3"
}

func (t *Iperf3) ServerCmd(port int) []string {
	return []string{"iperf3", "-s", "-p", strconv.Itoa(port)}
}

func (t *Iperf3) ClientCmd(target string, port int, flows int, duration time.Duration) []string {
	// Cap at 128 streams (iperf3 limit)
	if flows > 128 {
		flows = 128
	}
	return []string{
		"iperf3",
		"-c", target,
		"-p", strconv.Itoa(port),
		"-P", strconv.Itoa(flows),
		"-t", strconv.Itoa(int(duration.Seconds())),
		"-i", "2",
		"--json",
	}
}

// SupportsStreaming returns true - iperf3 supports streaming in text mode
func (t *Iperf3) SupportsStreaming() bool {
	return true
}

// StreamClientCmd returns client command for streaming (text mode, no --json).
// JSON mode outputs everything at the end, so we use text mode for streaming.
func (t *Iperf3) StreamClientCmd(target string, port int, flows int, duration time.Duration) []string {
	if flows > 128 {
		flows = 128
	}
	return []string{
		"iperf3",
		"-c", target,
		"-p", strconv.Itoa(port),
		"-P", strconv.Itoa(flows),
		"-t", strconv.Itoa(int(duration.Seconds())),
		"-i", "1", // Report every 1 second
		// Note: NO --json flag for streaming - use text mode
	}
}

// ParseLine parses text mode output from iperf3.
// Example with retransmits:
//
//	[  5]   0.00-1.00   sec  1.13 GBytes  9.72 Gbits/sec    0   1.87 MBytes
//
// Columns: ID, interval, transfer, bandwidth, retransmits, cwnd
// Example without retransmits (receiver):
//
//	[  5]   0.00-1.00   sec  1.12 GBytes  9.59 Gbits/sec
//
// Also handles [SUM] lines for multiple flows:
//
//	[SUM]   0.00-1.00   sec  10.1 GBytes  86.7 Gbits/sec    5
func (t *Iperf3) ParseLine(line string, acc *StreamAccumulator) bool {
	// Match interval lines with optional retransmits
	// Format: [ID/SUM] interval  transfer  bandwidth  [retransmits]  [cwnd]
	re := regexp.MustCompile(`\[\s*(?:\d+|SUM)\]\s+[\d.]+-[\d.]+\s+sec\s+[\d.]+\s+\w+\s+([\d.]+)\s+(G|M|K)?bits/sec(?:\s+(\d+))?`)
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

	// Parse retransmits if present
	var retrans int64
	if len(matches) >= 4 && matches[3] != "" {
		retrans, _ = strconv.ParseInt(matches[3], 10, 64)
	}

	acc.Lock()
	acc.ThroughputGbps = value
	acc.Retransmits += retrans
	acc.LastUpdate = time.Now()
	acc.IntervalCount++
	acc.Unlock()
	return true
}

func (t *Iperf3) Parse(output string, flows int, duration time.Duration) (*NormalizedResult, error) {
	result := &NormalizedResult{
		Tool:      t.Name(),
		Timestamp: time.Now(),
		Duration:  duration,
		FlowCount: flows,
	}

	// Parse JSON output
	var data struct {
		End struct {
			SumReceived struct {
				BitsPerSecond float64 `json:"bits_per_second"`
			} `json:"sum_received"`
			Streams []struct {
				Sender struct {
					Retransmits int64 `json:"retransmits"`
				} `json:"sender"`
			} `json:"streams"`
		} `json:"end"`
	}

	if err := json.Unmarshal([]byte(output), &data); err != nil {
		result.RawOutput = output
		return result, nil // Return partial result on parse error
	}

	result.ThroughputGbps = data.End.SumReceived.BitsPerSecond / 1e9

	for _, stream := range data.End.Streams {
		result.Retransmits += stream.Sender.Retransmits
	}

	return result, nil
}

func (t *Iperf3) SupportsFlowCount() bool {
	return true
}

func (t *Iperf3) DefaultPort() int {
	return 5201
}
