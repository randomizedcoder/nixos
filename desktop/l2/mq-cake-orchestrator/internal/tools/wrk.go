// internal/tools/wrk.go
package tools

import (
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Wrk implements HTTP benchmarking using the wrk tool
type Wrk struct {
	// FileSize is the test file to use (e.g., "1k", "100k", "1m")
	FileSize string
	// Threads is the number of wrk threads (default: 8)
	Threads int
}

// NewWrk creates a new Wrk tool instance
// fileSize should be one of: "1k", "10k", "100k", "1m", "2m", "5m", "10m"
func NewWrk(fileSize string) *Wrk {
	if fileSize == "" {
		fileSize = "100k"
	}
	return &Wrk{
		FileSize: fileSize,
		Threads:  8,
	}
}

func (t *Wrk) Name() string {
	return "wrk"
}

// ServerCmd returns the command to start nginx
// Note: nginx is started via mq-cake-nginx script, not directly
func (t *Wrk) ServerCmd(port int) []string {
	// nginx is managed separately via mq-cake-nginx script
	// This returns a placeholder - actual server management is external
	return []string{"mq-cake-nginx", "start"}
}

// ClientCmd returns the wrk command to run the benchmark
// flows parameter maps to connections (-c) in wrk
func (t *Wrk) ClientCmd(target string, port int, flows int, duration time.Duration) []string {
	fileSize := t.FileSize
	if fileSize == "" {
		fileSize = "100k"
	}
	url := "http://" + target + "/" + fileSize + ".bin"

	// wrk requires connections >= threads
	// Reduce threads if flows is less than default thread count
	threads := max(1, min(t.Threads, flows))

	return []string{
		"wrk",
		"-t", strconv.Itoa(threads),
		"-c", strconv.Itoa(flows),
		"-d", strconv.Itoa(int(duration.Seconds())) + "s",
		"--latency",
		url,
	}
}

// Parse extracts metrics from wrk output
// Sample output:
//
//	Running 30s test @ http://10.2.0.2/100k.bin
//	  8 threads and 100 connections
//	  Thread Stats   Avg      Stdev     Max   +/- Stdev
//	    Latency     1.23ms  234.56us   5.67ms   89.12%
//	    Req/Sec    10.12k   456.78    12.34k    78.90%
//	  Latency Distribution
//	     50%    1.12ms
//	     75%    1.34ms
//	     90%    1.56ms
//	     99%    2.34ms
//	  2424242 requests in 30.00s, 237.42GB read
//	Requests/sec:  80808.08
//	Transfer/sec:      7.91GB
func (t *Wrk) Parse(output string, flows int, duration time.Duration) (*NormalizedResult, error) {
	result := &NormalizedResult{
		Tool:      t.Name(),
		Timestamp: time.Now(),
		Duration:  duration,
		FlowCount: flows,
	}

	// Parse Requests/sec: 80808.08
	rpsRe := regexp.MustCompile(`Requests/sec:\s+([\d.]+)`)
	if matches := rpsRe.FindStringSubmatch(output); len(matches) >= 2 {
		// Store RPS in a way that's meaningful - we'll compute throughput from Transfer/sec
		// RPS could be stored in a custom field, but for now we focus on throughput
		_, _ = strconv.ParseFloat(matches[1], 64)
	}

	// Parse Transfer/sec: 7.91GB (throughput)
	transferRe := regexp.MustCompile(`Transfer/sec:\s+([\d.]+)([GMKB]+)`)
	if matches := transferRe.FindStringSubmatch(output); len(matches) >= 3 {
		val, _ := strconv.ParseFloat(matches[1], 64)
		unit := matches[2]
		// Convert to Gbps (bytes to bits, then to Gbps)
		var bytesPerSec float64
		switch unit {
		case "GB":
			bytesPerSec = val * 1e9
		case "MB":
			bytesPerSec = val * 1e6
		case "KB":
			bytesPerSec = val * 1e3
		case "B":
			bytesPerSec = val
		}
		// bytes/sec to Gbps: bytes * 8 / 1e9
		result.ThroughputGbps = bytesPerSec * 8 / 1e9
	}

	// Parse Latency Distribution percentiles
	// Format:
	//   50%    1.12ms
	//   75%    1.34ms
	//   90%    1.56ms
	//   99%    2.34ms
	p50Re := regexp.MustCompile(`50%\s+([\d.]+)(ms|us|s)`)
	if matches := p50Re.FindStringSubmatch(output); len(matches) >= 3 {
		result.LatencyP50Ms = parseLatencyToMs(matches[1], matches[2])
	}

	p99Re := regexp.MustCompile(`99%\s+([\d.]+)(ms|us|s)`)
	if matches := p99Re.FindStringSubmatch(output); len(matches) >= 3 {
		result.LatencyP99Ms = parseLatencyToMs(matches[1], matches[2])
	}

	// Parse average latency from Thread Stats (fallback if distribution not available)
	// Latency     1.23ms  234.56us   5.67ms   89.12%
	if result.LatencyP50Ms == 0 {
		avgLatRe := regexp.MustCompile(`Latency\s+([\d.]+)(ms|us|s)`)
		if matches := avgLatRe.FindStringSubmatch(output); len(matches) >= 3 {
			result.LatencyP50Ms = parseLatencyToMs(matches[1], matches[2])
		}
	}

	// Check for socket errors (connection/read/write errors)
	// Socket errors: connect 0, read 100, write 0, timeout 5
	socketErrRe := regexp.MustCompile(`Socket errors:.*timeout\s+(\d+)`)
	if matches := socketErrRe.FindStringSubmatch(output); len(matches) >= 2 {
		timeouts, _ := strconv.ParseInt(matches[1], 10, 64)
		// Calculate loss as a rough approximation
		totalReqRe := regexp.MustCompile(`(\d+)\s+requests in`)
		if reqMatches := totalReqRe.FindStringSubmatch(output); len(reqMatches) >= 2 {
			totalReq, _ := strconv.ParseFloat(reqMatches[1], 64)
			if totalReq > 0 {
				result.PacketLossPct = float64(timeouts) / totalReq * 100
			}
		}
	}

	result.RawOutput = output
	return result, nil
}

// parseLatencyToMs converts a latency value with unit to milliseconds
func parseLatencyToMs(value, unit string) float64 {
	val, _ := strconv.ParseFloat(value, 64)
	switch strings.ToLower(unit) {
	case "s":
		return val * 1000
	case "ms":
		return val
	case "us":
		return val / 1000
	default:
		return val
	}
}

func (t *Wrk) SupportsFlowCount() bool {
	// wrk uses -c for connections, which maps to "flows"
	return true
}

func (t *Wrk) DefaultPort() int {
	return 80
}

// ChunkFactor returns how many chunks to divide each step into.
// wrk doesn't support native streaming, so we run 5 chunks per step.
// For a 60s step, this means 12s chunks with metrics after each.
func (t *Wrk) ChunkFactor() int {
	return 5
}

// StartOffset returns the stagger offset for chunked execution.
// wrk starts immediately (offset 0) since it's the primary HTTP benchmark.
func (t *Wrk) StartOffset() time.Duration {
	return 0
}
