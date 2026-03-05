// internal/tools/tool.go
package tools

import (
	"sync"
	"time"
)

// NormalizedResult is the standardized output schema for all tools
type NormalizedResult struct {
	Tool           string        `json:"tool"`
	Timestamp      time.Time     `json:"timestamp"`
	Duration       time.Duration `json:"duration"`
	FlowCount      int           `json:"flow_count"`
	ThroughputGbps float64       `json:"throughput_gbps"`
	LatencyP50Ms   float64       `json:"latency_p50_ms,omitempty"`
	LatencyP99Ms   float64       `json:"latency_p99_ms,omitempty"`
	PacketLossPct  float64       `json:"packet_loss_pct"`
	Retransmits    int64         `json:"retransmits,omitempty"`
	JitterMs       float64       `json:"jitter_ms,omitempty"`
	RawOutput      string        `json:"raw_output,omitempty"`
}

// Tool defines the interface all load generators must implement
type Tool interface {
	// Name returns the tool identifier
	Name() string

	// ServerCmd returns the command to start the server
	ServerCmd(port int) []string

	// ClientCmd returns the command to run the client
	ClientCmd(target string, port int, flows int, duration time.Duration) []string

	// Parse converts raw output to NormalizedResult
	Parse(output string, flows int, duration time.Duration) (*NormalizedResult, error)

	// SupportsFlowCount returns true if tool supports parallel flows
	SupportsFlowCount() bool

	// DefaultPort returns the default port for this tool
	DefaultPort() int
}

// StreamingParser extends Tool with real-time parsing capability.
// Tools implementing this interface can parse output line-by-line as it arrives,
// enabling real-time metrics updates instead of waiting for process completion.
type StreamingParser interface {
	// SupportsStreaming returns true if the tool outputs intermediate results
	// that can be parsed in real-time (e.g., per-interval reports)
	SupportsStreaming() bool

	// StreamClientCmd returns client command with streaming flags enabled.
	// This typically includes flags like -i 1 for per-second reporting.
	StreamClientCmd(target string, port int, flows int, duration time.Duration) []string

	// ParseLine processes a single line of output and updates the accumulator.
	// Returns true if this line contained metrics that were parsed.
	ParseLine(line string, acc *StreamAccumulator) bool
}

// ChunkedTool defines tools that don't support native streaming output.
// These tools are run in shorter chunks with staggered restarts to provide
// pseudo-real-time metrics updates.
type ChunkedTool interface {
	// ChunkFactor returns how many chunks to divide each step into.
	// For example, ChunkFactor()=5 with a 60s step means 12s chunks.
	ChunkFactor() int

	// StartOffset returns the stagger offset to avoid simultaneous restarts
	// across multiple chunked tools.
	StartOffset() time.Duration
}

// StreamAccumulator holds streaming metrics state.
// It is updated by ParseLine() calls and used to update Prometheus metrics.
type StreamAccumulator struct {
	mu         sync.Mutex
	Tool       string
	LastUpdate time.Time

	// Throughput metrics (iperf2, iperf3, wrk)
	ThroughputGbps   float64 // Latest interval throughput
	BytesTransferred int64   // Cumulative bytes

	// Latency metrics (fping, dnsperf, crusader)
	LatencyMs    float64 // Latest sample latency
	AvgLatencyMs float64 // Running average latency
	MaxLatencyMs float64 // Maximum latency seen

	// Loss/error metrics
	PacketLossPct float64 // Current packet loss percentage
	Retransmits   int64   // TCP retransmits (iperf3)

	// DNS-specific metrics (dnsperf)
	QueriesSent      int64   // Total queries sent
	QueriesCompleted int64   // Queries that got responses
	QPS              float64 // Queries per second

	// HTTP-specific metrics (wrk)
	RequestsTotal  int64   // Total HTTP requests
	RequestsPerSec float64 // Requests per second

	// General
	IntervalCount int // Number of intervals parsed
}

// Lock locks the accumulator for thread-safe updates
func (a *StreamAccumulator) Lock() {
	a.mu.Lock()
}

// Unlock unlocks the accumulator
func (a *StreamAccumulator) Unlock() {
	a.mu.Unlock()
}

// Reset clears the accumulator for a new test run
func (a *StreamAccumulator) Reset() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.LastUpdate = time.Time{}
	a.ThroughputGbps = 0
	a.BytesTransferred = 0
	a.LatencyMs = 0
	a.AvgLatencyMs = 0
	a.MaxLatencyMs = 0
	a.PacketLossPct = 0
	a.Retransmits = 0
	a.QueriesSent = 0
	a.QueriesCompleted = 0
	a.QPS = 0
	a.RequestsTotal = 0
	a.RequestsPerSec = 0
	a.IntervalCount = 0
}
