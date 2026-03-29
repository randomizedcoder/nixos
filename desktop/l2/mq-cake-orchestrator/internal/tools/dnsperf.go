// internal/tools/dnsperf.go
package tools

import (
	"regexp"
	"strconv"
	"time"
)

// DNSPerf implements DNS benchmarking using the dnsperf tool
type DNSPerf struct {
	// QueryFile is the path to the DNS query file
	QueryFile string
	// TargetQPS is the target queries per second (0 = unlimited)
	TargetQPS int
}

// NewDNSPerf creates a new DNSPerf tool instance
func NewDNSPerf(queryFile string) *DNSPerf {
	if queryFile == "" {
		queryFile = "/var/lib/mq-cake/dns/queries.txt"
	}
	return &DNSPerf{
		QueryFile: queryFile,
		TargetQPS: 50000, // Default target QPS
	}
}

func (t *DNSPerf) Name() string {
	return "dnsperf"
}

// ServerCmd returns the command to start PowerDNS
// Note: PowerDNS is started via mq-cake-pdns script, not directly
func (t *DNSPerf) ServerCmd(port int) []string {
	// PowerDNS is managed separately via mq-cake-pdns script
	return []string{"mq-cake-pdns", "start"}
}

// ClientCmd returns the dnsperf command to run the benchmark
// flows parameter maps to concurrent queries (-c) in dnsperf
func (t *DNSPerf) ClientCmd(target string, port int, flows int, duration time.Duration) []string {
	cmd := []string{
		"dnsperf",
		"-s", target,
		"-p", strconv.Itoa(port),
		"-d", t.QueryFile,
		"-c", strconv.Itoa(flows), // concurrent queries
		"-l", strconv.Itoa(int(duration.Seconds())),
	}

	// Add target QPS if specified
	if t.TargetQPS > 0 {
		cmd = append(cmd, "-Q", strconv.Itoa(t.TargetQPS))
	}

	return cmd
}

// SupportsStreaming returns true - dnsperf has verbose per-query output
func (t *DNSPerf) SupportsStreaming() bool {
	return true
}

// StreamClientCmd returns dnsperf command with verbose streaming flags.
// -v: verbose per-query output
// -S 1: print QPS statistics every 1 second
// -W: log warnings/errors to stdout (not stderr)
func (t *DNSPerf) StreamClientCmd(target string, port int, flows int, duration time.Duration) []string {
	cmd := []string{
		"dnsperf",
		"-s", target,
		"-p", strconv.Itoa(port),
		"-d", t.QueryFile,
		"-c", strconv.Itoa(flows),
		"-l", strconv.Itoa(int(duration.Seconds())),
		"-v",       // Verbose: report each query to stdout
		"-S", "1",  // Statistics interval: every 1 second
		"-W",       // Log warnings/errors to stdout
	}

	if t.TargetQPS > 0 {
		cmd = append(cmd, "-Q", strconv.Itoa(t.TargetQPS))
	}

	return cmd
}

// ParseLine parses both per-query verbose output and periodic stats from dnsperf.
// Periodic stats format: "Statistics: Queries sent: N Queries completed: M (P%)"
// Latency format: "Average latency: 0.032s"
func (t *DNSPerf) ParseLine(line string, acc *StreamAccumulator) bool {
	// Parse periodic statistics line
	// Format: "Queries sent: N Queries completed: M"
	statsRe := regexp.MustCompile(`Queries sent:\s*(\d+)\s+Queries completed:\s*(\d+)`)
	if matches := statsRe.FindStringSubmatch(line); len(matches) >= 3 {
		sent, _ := strconv.ParseInt(matches[1], 10, 64)
		completed, _ := strconv.ParseInt(matches[2], 10, 64)

		acc.Lock()
		acc.QueriesSent = sent
		acc.QueriesCompleted = completed
		if sent > 0 {
			acc.PacketLossPct = float64(sent-completed) / float64(sent) * 100
		}
		acc.LastUpdate = time.Now()
		acc.IntervalCount++
		acc.Unlock()
		return true
	}

	// Parse QPS from statistics
	// Format: "Queries per second: 49950.827"
	qpsRe := regexp.MustCompile(`Queries per second:\s*([\d.]+)`)
	if matches := qpsRe.FindStringSubmatch(line); len(matches) >= 2 {
		qps, _ := strconv.ParseFloat(matches[1], 64)
		acc.Lock()
		acc.QPS = qps
		// Convert QPS to throughput: ~100 bytes per query = 800 bits
		acc.ThroughputGbps = qps * 800 / 1e9
		acc.LastUpdate = time.Now()
		acc.Unlock()
		return true
	}

	// Parse average latency from stats
	// Format: "Average Latency (s): 0.032 (min 0.000089, max 0.045672)"
	latencyRe := regexp.MustCompile(`[Aa]verage [Ll]atency.*?:\s*([\d.]+)`)
	if matches := latencyRe.FindStringSubmatch(line); len(matches) >= 2 {
		latency, _ := strconv.ParseFloat(matches[1], 64)
		acc.Lock()
		acc.LatencyMs = latency * 1000 // Convert seconds to ms
		acc.AvgLatencyMs = acc.LatencyMs
		acc.LastUpdate = time.Now()

		// Also parse max latency if present on the same line
		// Format: "max 0.045672)" within latency line
		maxLatRe := regexp.MustCompile(`max\s+([\d.]+)\)`)
		if maxMatches := maxLatRe.FindStringSubmatch(line); len(maxMatches) >= 2 {
			maxLat, _ := strconv.ParseFloat(maxMatches[1], 64)
			if maxLat*1000 > acc.MaxLatencyMs {
				acc.MaxLatencyMs = maxLat * 1000 // Convert seconds to ms
			}
		}
		acc.Unlock()
		return true
	}

	return false
}

// Parse extracts metrics from dnsperf output
// Sample output:
//
//	Statistics:
//
//	  Queries sent:         1500000
//	  Queries completed:    1498523 (99.90%)
//	  Queries lost:         1477 (0.10%)
//
//	  Response codes:       NOERROR 1498523 (100.00%)
//
//	  Average packet size:  request 45, response 61
//	  Run time (s):         30.000892
//	  Queries per second:   49950.827083
//
//	  Average Latency (s):  0.001234 (min 0.000089, max 0.045672)
//	  Latency StdDev (s):   0.000567
func (t *DNSPerf) Parse(output string, flows int, duration time.Duration) (*NormalizedResult, error) {
	result := &NormalizedResult{
		Tool:      t.Name(),
		Timestamp: time.Now(),
		Duration:  duration,
		FlowCount: flows,
	}

	// Parse Queries per second: 49950.827083
	qpsRe := regexp.MustCompile(`Queries per second:\s+([\d.]+)`)
	if matches := qpsRe.FindStringSubmatch(output); len(matches) >= 2 {
		qps, _ := strconv.ParseFloat(matches[1], 64)
		// Convert QPS to a throughput metric
		// Assume ~100 bytes per DNS query+response = 800 bits
		// QPS * 800 bits = bits/sec, then convert to Gbps
		result.ThroughputGbps = qps * 800 / 1e9
	}

	// Parse Queries lost: 1477 (0.10%)
	lossRe := regexp.MustCompile(`Queries lost:\s+\d+\s+\(([\d.]+)%\)`)
	if matches := lossRe.FindStringSubmatch(output); len(matches) >= 2 {
		result.PacketLossPct, _ = strconv.ParseFloat(matches[1], 64)
	}

	// Parse Average Latency (s): 0.001234 (min 0.000089, max 0.045672)
	latRe := regexp.MustCompile(`Average Latency \(s\):\s+([\d.]+)`)
	if matches := latRe.FindStringSubmatch(output); len(matches) >= 2 {
		latSec, _ := strconv.ParseFloat(matches[1], 64)
		result.LatencyP50Ms = latSec * 1000 // Convert seconds to milliseconds
	}

	// Parse max latency for P99 approximation
	maxLatRe := regexp.MustCompile(`max\s+([\d.]+)\)`)
	if matches := maxLatRe.FindStringSubmatch(output); len(matches) >= 2 {
		maxLatSec, _ := strconv.ParseFloat(matches[1], 64)
		result.LatencyP99Ms = maxLatSec * 1000
	}

	result.RawOutput = output
	return result, nil
}

func (t *DNSPerf) SupportsFlowCount() bool {
	// dnsperf uses -c for concurrent queries, which maps to "flows"
	return true
}

func (t *DNSPerf) DefaultPort() int {
	return 53
}
