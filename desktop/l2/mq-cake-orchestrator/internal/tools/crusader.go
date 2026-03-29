// internal/tools/crusader.go
package tools

import (
	"regexp"
	"strconv"
	"time"
)

type Crusader struct{}

func NewCrusader() *Crusader {
	return &Crusader{}
}

func (t *Crusader) Name() string {
	return "crusader"
}

func (t *Crusader) ServerCmd(port int) []string {
	// Crusader server uses fixed port 35481
	return []string{"crusader", "serve"}
}

func (t *Crusader) ClientCmd(target string, port int, flows int, duration time.Duration) []string {
	// Crusader runs 3 tests (download, upload, bidirectional) each taking load-duration
	// Use download-only mode to fit within timeout and match other tools' behavior
	return []string{
		"crusader", "test", target,
		"--download",
		"--load-duration", strconv.Itoa(int(duration.Seconds())),
	}
}

func (t *Crusader) Parse(output string, flows int, duration time.Duration) (*NormalizedResult, error) {
	result := &NormalizedResult{
		Tool:      t.Name(),
		Timestamp: time.Now(),
		Duration:  duration,
		FlowCount: flows,
	}

	// Parse crusader output
	// Example: "Throughput: 9415.04 Mbps"
	tpRe := regexp.MustCompile(`Throughput:\s*(\d+\.?\d*)\s*Mbps`)
	matches := tpRe.FindStringSubmatch(output)
	if len(matches) >= 2 {
		val, _ := strconv.ParseFloat(matches[1], 64)
		result.ThroughputGbps = val / 1000
	}

	// Parse latency
	// Example: "Latency: 2.0 ms"
	latRe := regexp.MustCompile(`Latency:\s*(\d+\.?\d*)\s*ms`)
	latMatches := latRe.FindStringSubmatch(output)
	if len(latMatches) >= 2 {
		val, _ := strconv.ParseFloat(latMatches[1], 64)
		result.LatencyP50Ms = val
	}

	// Parse packet loss
	// Example: "Packet loss: 0%"
	lossRe := regexp.MustCompile(`Packet loss:\s*(\d+\.?\d*)%`)
	lossMatches := lossRe.FindStringSubmatch(output)
	if len(lossMatches) >= 2 {
		val, _ := strconv.ParseFloat(lossMatches[1], 64)
		result.PacketLossPct = val
	}

	result.RawOutput = output
	return result, nil
}

func (t *Crusader) SupportsFlowCount() bool {
	return false // Crusader has fixed stream count
}

func (t *Crusader) DefaultPort() int {
	return 35481
}

// ChunkFactor returns how many chunks to divide each step into.
// crusader doesn't support native streaming, so we run 3 chunks per step.
// For a 60s step, this means 20s chunks with metrics after each.
func (t *Crusader) ChunkFactor() int {
	return 3
}

// StartOffset returns the stagger offset for chunked execution.
// crusader starts 4 seconds after wrk to avoid simultaneous restarts.
func (t *Crusader) StartOffset() time.Duration {
	return 4 * time.Second
}
