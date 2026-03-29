// internal/tools/fping.go
package tools

import (
	"regexp"
	"strconv"
	"time"
)

// Fping implements ICMP latency measurement using fping
// This provides pure network latency without application server overhead
type Fping struct{}

func NewFping() *Fping {
	return &Fping{}
}

func (t *Fping) Name() string {
	return "fping"
}

// ServerCmd returns empty - fping doesn't need a server (uses ICMP)
func (t *Fping) ServerCmd(port int) []string {
	// No server needed - ICMP echo handled by kernel
	return []string{"true"} // No-op
}

// ClientCmd returns the fping command
// -c count, -p period (ms between pings), -q quiet (summary only)
func (t *Fping) ClientCmd(target string, port int, flows int, duration time.Duration) []string {
	// Calculate ping count based on duration (1 ping per 100ms)
	count := int(duration.Seconds()) * 10

	return []string{
		"fping",
		"-c", strconv.Itoa(count), // Number of pings
		"-p", "100",               // 100ms between pings
		"-q",                      // Quiet mode (summary only)
		target,
	}
}

// SupportsStreaming returns true - fping has native per-ping output
func (t *Fping) SupportsStreaming() bool {
	return true
}

// StreamClientCmd returns fping command without -q flag for per-ping output.
// Without -q, fping outputs each ping result as it arrives.
func (t *Fping) StreamClientCmd(target string, port int, flows int, duration time.Duration) []string {
	// Calculate ping count based on duration (1 ping per 100ms)
	count := int(duration.Seconds()) * 10

	return []string{
		"fping",
		"-c", strconv.Itoa(count), // Number of pings
		"-p", "100",               // 100ms between pings
		// Note: NO -q flag - we want per-ping output for streaming
		target,
	}
}

// ParseLine parses per-ping output from fping (without -q flag).
// Success format: 1.1.1.1 : [0], 64 bytes, 12.7 ms (12.7 avg, 0% loss)
// Timeout format: 1.1.1.1 : [0], timed out (NaN avg, 100% loss)
// Final summary:  1.1.1.1 : xmt/rcv/%loss = 15/9/40%, min/avg/max = 7.55/9.81/10.9
func (t *Fping) ParseLine(line string, acc *StreamAccumulator) bool {
	// Match per-ping success line with RTT
	// Format: IP : [seq], 64 bytes, RTT ms (avg avg, loss% loss)
	successRe := regexp.MustCompile(`\[\d+\],\s+64 bytes,\s+([\d.]+)\s+ms\s+\(([\d.]+)\s+avg,\s+(\d+)%\s+loss\)`)
	if matches := successRe.FindStringSubmatch(line); len(matches) >= 4 {
		rtt, _ := strconv.ParseFloat(matches[1], 64)
		avg, _ := strconv.ParseFloat(matches[2], 64)
		loss, _ := strconv.ParseInt(matches[3], 10, 64)

		acc.Lock()
		acc.LatencyMs = rtt          // Current ping RTT
		acc.AvgLatencyMs = avg       // Running average
		acc.PacketLossPct = float64(loss)
		if rtt > acc.MaxLatencyMs {
			acc.MaxLatencyMs = rtt
		}
		acc.LastUpdate = time.Now()
		acc.IntervalCount++
		acc.Unlock()
		return true
	}

	// Match timeout line
	// Format: IP : [seq], timed out (NaN avg, loss% loss)
	timeoutRe := regexp.MustCompile(`\[\d+\],\s+timed out\s+\([^)]+,\s+(\d+)%\s+loss\)`)
	if matches := timeoutRe.FindStringSubmatch(line); len(matches) >= 2 {
		loss, _ := strconv.ParseInt(matches[1], 10, 64)
		acc.Lock()
		acc.PacketLossPct = float64(loss)
		acc.LastUpdate = time.Now()
		acc.IntervalCount++
		acc.Unlock()
		return true
	}

	// Match final summary line (same as quiet mode)
	// Format: IP : xmt/rcv/%loss = N/M/P%, min/avg/max = X/Y/Z
	summaryRe := regexp.MustCompile(`xmt/rcv/%loss\s*=\s*\d+/\d+/(\d+)%.*min/avg/max\s*=\s*([\d.]+)/([\d.]+)/([\d.]+)`)
	if matches := summaryRe.FindStringSubmatch(line); len(matches) >= 5 {
		loss, _ := strconv.ParseFloat(matches[1], 64)
		avg, _ := strconv.ParseFloat(matches[3], 64)
		maxLat, _ := strconv.ParseFloat(matches[4], 64)

		acc.Lock()
		acc.PacketLossPct = loss
		acc.AvgLatencyMs = avg
		acc.MaxLatencyMs = maxLat
		acc.LatencyMs = avg // Use avg as latest for summary
		acc.LastUpdate = time.Now()
		acc.Unlock()
		return true
	}

	return false
}

// Parse extracts latency metrics from fping output
// Sample output (stderr):
// 10.2.0.2 : xmt/rcv/%loss = 100/100/0%, min/avg/max = 30.1/31.5/35.2
func (t *Fping) Parse(output string, flows int, duration time.Duration) (*NormalizedResult, error) {
	result := &NormalizedResult{
		Tool:      t.Name(),
		Timestamp: time.Now(),
		Duration:  duration,
		FlowCount: 1, // fping is always single "flow"
	}

	// Parse min/avg/max latency
	// Format: min/avg/max = 30.1/31.5/35.2
	latencyRe := regexp.MustCompile(`min/avg/max\s*=\s*([\d.]+)/([\d.]+)/([\d.]+)`)
	if matches := latencyRe.FindStringSubmatch(output); len(matches) >= 4 {
		result.LatencyP50Ms, _ = strconv.ParseFloat(matches[2], 64) // avg as P50 approximation
		result.LatencyP99Ms, _ = strconv.ParseFloat(matches[3], 64) // max as P99 approximation
	}

	// Parse packet loss
	// Format: xmt/rcv/%loss = 100/95/5%  (sent/received/loss_percent)
	lossRe := regexp.MustCompile(`xmt/rcv/%loss\s*=\s*\d+/\d+/(\d+)%`)
	if matches := lossRe.FindStringSubmatch(output); len(matches) >= 2 {
		result.PacketLossPct, _ = strconv.ParseFloat(matches[1], 64)
	}

	// fping doesn't measure throughput, but we report 0 to avoid breaking the schema
	result.ThroughputGbps = 0

	result.RawOutput = output
	return result, nil
}

func (t *Fping) SupportsFlowCount() bool {
	return false // ICMP ping is always single "flow"
}

func (t *Fping) DefaultPort() int {
	return 0 // ICMP doesn't use ports
}
