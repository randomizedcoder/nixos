// internal/telemetry/metrics.go
package telemetry

import (
	"context"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/runner"
)

// Prometheus metrics for MQ-CAKE stress testing
var (
	// Throughput metrics
	ThroughputGbps = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_test_throughput_gbps",
			Help: "Test throughput in Gbps",
		},
		[]string{"tool", "qdisc"},
	)

	// Latency metrics
	LatencyP50Ms = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_test_latency_p50_ms",
			Help: "P50 latency in milliseconds",
		},
		[]string{"tool", "qdisc"},
	)

	LatencyP99Ms = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_test_latency_p99_ms",
			Help: "P99 latency in milliseconds",
		},
		[]string{"tool", "qdisc"},
	)

	// Packet loss
	PacketLossPct = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_test_packet_loss_pct",
			Help: "Packet loss percentage",
		},
		[]string{"tool", "qdisc"},
	)

	// Flow count metrics
	TotalFlows = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "mqcake_test_total_flows",
			Help: "Total concurrent flows across all tools",
		},
	)

	ToolFlows = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_test_tool_flows",
			Help: "Concurrent flows per tool",
		},
		[]string{"tool"},
	)

	// Instance metrics
	ToolInstances = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_tool_instances_running",
			Help: "Number of running instances per tool",
		},
		[]string{"tool"},
	)

	// Test progress
	TestStep = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "mqcake_test_current_step",
			Help: "Current ramping step number",
		},
	)

	TestPointsCompleted = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "mqcake_test_points_completed",
			Help: "Number of completed test points",
		},
	)

	TestPointsFailed = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "mqcake_test_points_failed",
			Help: "Number of failed test points",
		},
	)

	// Socket count metrics (from ss)
	TCPSockets = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_socket_tcp_count",
			Help: "Number of TCP sockets on load generators",
		},
		[]string{"namespace", "state"},
	)

	UDPSockets = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_socket_udp_count",
			Help: "Number of UDP sockets on load generators",
		},
		[]string{"namespace"},
	)

	// CPU metrics
	CPUUsage = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_cpu_usage_pct",
			Help: "CPU usage percentage per core",
		},
		[]string{"core"},
	)

	// Qdisc drop metrics
	QdiscDrops = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_qdisc_drops",
			Help: "Packet drops from qdisc",
		},
		[]string{"interface", "qdisc"},
	)

	QdiscBacklog = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_qdisc_backlog_bytes",
			Help: "Qdisc backlog in bytes",
		},
		[]string{"interface", "qdisc"},
	)

	// Qdisc packet/byte counters
	QdiscPackets = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "mqcake_qdisc_packets_total",
			Help: "Total packets sent through qdisc",
		},
		[]string{"interface", "qdisc"},
	)

	QdiscBytes = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "mqcake_qdisc_bytes_total",
			Help: "Total bytes sent through qdisc",
		},
		[]string{"interface", "qdisc"},
	)

	// Retransmit metrics
	Retransmits = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_test_retransmits",
			Help: "TCP retransmits per tool",
		},
		[]string{"tool", "qdisc"},
	)

	// Breaking point indicator
	BreakingPointDetected = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_breaking_point_detected",
			Help: "Set to 1 when breaking point is detected (0 otherwise)",
		},
		[]string{"qdisc", "reason"},
	)

	// Test duration
	StepDurationSeconds = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "mqcake_step_duration_seconds",
			Help: "Duration of each ramping step in seconds",
		},
	)

	// === STREAMING-SPECIFIC METRICS ===

	// Histogram for streaming throughput observations (for percentile queries)
	ThroughputHistogram = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "mqcake_streaming_throughput_gbps",
			Help:    "Streaming throughput samples in Gbps",
			Buckets: []float64{0.1, 0.5, 1, 2, 5, 8, 9, 9.5, 10, 10.5, 11, 12, 15, 20},
		},
		[]string{"tool", "qdisc"},
	)

	// Histogram for streaming latency observations
	LatencyHistogram = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "mqcake_streaming_latency_ms",
			Help:    "Streaming latency samples in milliseconds",
			Buckets: []float64{1, 5, 10, 20, 30, 40, 50, 75, 100, 150, 200, 300, 500, 1000},
		},
		[]string{"tool", "qdisc"},
	)

	// Counter for total streaming samples (useful for rate() queries)
	StreamingSamplesTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "mqcake_streaming_samples_total",
			Help: "Total number of streaming samples collected per tool",
		},
		[]string{"tool"},
	)

	// Timestamp of last update (for staleness detection in Grafana)
	LastUpdateTimestamp = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_streaming_last_update_timestamp",
			Help: "Unix timestamp of last streaming update",
		},
		[]string{"tool"},
	)

	// Max latency seen during current step (resets each step)
	MaxLatencyMs = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_streaming_max_latency_ms",
			Help: "Maximum latency seen during current step",
		},
		[]string{"tool", "qdisc"},
	)

	// Streaming mode indicator (1=streaming, 2=chunked, 0=legacy)
	ToolMode = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_tool_mode",
			Help: "Tool execution mode (1=streaming, 2=chunked, 0=legacy)",
		},
		[]string{"tool"},
	)

	// Chunk iteration counter (for chunked tools)
	ChunkIteration = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "mqcake_chunk_iteration",
			Help: "Current chunk iteration for chunked tools",
		},
		[]string{"tool"},
	)
)

// SocketStats holds socket count information
type SocketStats struct {
	TCPEstablished int
	TCPTimeWait    int
	TCPCloseWait   int
	TCPListening   int
	TCPTotal       int
	UDPTotal       int
}

// CollectSocketStats collects socket statistics from a namespace using ss
func CollectSocketStats(ctx context.Context, r runner.Runner, namespace string) (*SocketStats, error) {
	stats := &SocketStats{}

	// Get TCP socket counts by state
	// ss -t -a -n shows all TCP sockets
	tcpOutput, err := r.Run(ctx, namespace, []string{"ss", "-t", "-a", "-n"})
	if err != nil {
		return nil, fmt.Errorf("ss tcp failed: %w", err)
	}

	// Parse TCP output
	// Format: State      Recv-Q Send-Q Local Address:Port  Peer Address:Port
	lines := strings.Split(tcpOutput, "\n")
	for _, line := range lines {
		fields := strings.Fields(line)
		if len(fields) < 1 {
			continue
		}
		state := fields[0]
		switch state {
		case "ESTAB":
			stats.TCPEstablished++
		case "TIME-WAIT":
			stats.TCPTimeWait++
		case "CLOSE-WAIT":
			stats.TCPCloseWait++
		case "LISTEN":
			stats.TCPListening++
		}
		// Skip header line
		if state != "State" && state != "Netid" {
			stats.TCPTotal++
		}
	}
	// Subtract 1 for header line
	if stats.TCPTotal > 0 {
		stats.TCPTotal--
	}

	// Get UDP socket count
	udpOutput, err := r.Run(ctx, namespace, []string{"ss", "-u", "-a", "-n"})
	if err != nil {
		return nil, fmt.Errorf("ss udp failed: %w", err)
	}

	// Count UDP lines (skip header)
	udpLines := strings.Split(udpOutput, "\n")
	for _, line := range udpLines {
		if strings.TrimSpace(line) != "" && !strings.HasPrefix(line, "State") && !strings.HasPrefix(line, "Netid") {
			stats.UDPTotal++
		}
	}
	// Subtract 1 for header
	if stats.UDPTotal > 0 {
		stats.UDPTotal--
	}

	return stats, nil
}

// UpdateSocketMetrics updates Prometheus metrics with socket stats
func UpdateSocketMetrics(namespace string, stats *SocketStats) {
	TCPSockets.WithLabelValues(namespace, "established").Set(float64(stats.TCPEstablished))
	TCPSockets.WithLabelValues(namespace, "time_wait").Set(float64(stats.TCPTimeWait))
	TCPSockets.WithLabelValues(namespace, "close_wait").Set(float64(stats.TCPCloseWait))
	TCPSockets.WithLabelValues(namespace, "listening").Set(float64(stats.TCPListening))
	TCPSockets.WithLabelValues(namespace, "total").Set(float64(stats.TCPTotal))
	UDPSockets.WithLabelValues(namespace).Set(float64(stats.UDPTotal))
}

// CollectAllSocketStats collects socket stats from both load generator namespaces
func CollectAllSocketStats(ctx context.Context, r runner.Runner, clientNS, serverNS string) (client, server *SocketStats, err error) {
	client, err = CollectSocketStats(ctx, r, clientNS)
	if err != nil {
		return nil, nil, fmt.Errorf("client socket stats: %w", err)
	}

	server, err = CollectSocketStats(ctx, r, serverNS)
	if err != nil {
		return client, nil, fmt.Errorf("server socket stats: %w", err)
	}

	return client, server, nil
}

// QdiscStats holds qdisc statistics
type QdiscStats struct {
	Drops   int64
	Backlog int64
	Packets int64
	Bytes   int64
}

// CollectQdiscStats collects qdisc statistics from an interface
func CollectQdiscStats(ctx context.Context, r runner.Runner, dutNS, iface string) (*QdiscStats, string, error) {
	// tc -s qdisc show dev <iface>
	output, err := r.Run(ctx, dutNS, []string{"tc", "-s", "qdisc", "show", "dev", iface})
	if err != nil {
		return nil, "", fmt.Errorf("tc qdisc show failed: %w", err)
	}

	stats := &QdiscStats{}
	var qdiscType string

	// Parse qdisc type from first line
	// Example: qdisc fq_codel 0: root refcnt 2 limit 10240p
	typeRe := regexp.MustCompile(`qdisc\s+(\S+)`)
	if matches := typeRe.FindStringSubmatch(output); len(matches) >= 2 {
		qdiscType = matches[1]
	}

	// Parse statistics
	// Example: Sent 1234567890 bytes 1234567 pkt (dropped 100, overlimits 0 requeues 0)
	// Or: dropped 100
	droppedRe := regexp.MustCompile(`dropped\s+(\d+)`)
	if matches := droppedRe.FindStringSubmatch(output); len(matches) >= 2 {
		stats.Drops, _ = strconv.ParseInt(matches[1], 10, 64)
	}

	// Parse backlog: backlog 0b 0p requeues 0
	backlogRe := regexp.MustCompile(`backlog\s+(\d+)b`)
	if matches := backlogRe.FindStringSubmatch(output); len(matches) >= 2 {
		stats.Backlog, _ = strconv.ParseInt(matches[1], 10, 64)
	}

	// Parse sent packets and bytes
	sentRe := regexp.MustCompile(`Sent\s+(\d+)\s+bytes\s+(\d+)\s+pkt`)
	if matches := sentRe.FindStringSubmatch(output); len(matches) >= 3 {
		stats.Bytes, _ = strconv.ParseInt(matches[1], 10, 64)
		stats.Packets, _ = strconv.ParseInt(matches[2], 10, 64)
	}

	return stats, qdiscType, nil
}

// UpdateQdiscMetrics updates Prometheus metrics with qdisc stats
func UpdateQdiscMetrics(iface, qdiscType string, stats *QdiscStats) {
	QdiscDrops.WithLabelValues(iface, qdiscType).Set(float64(stats.Drops))
	QdiscBacklog.WithLabelValues(iface, qdiscType).Set(float64(stats.Backlog))
	// Note: Counters should only go up, but tc stats are cumulative from boot
	// We use Add(0) initially, then track deltas in the stress runner
	QdiscPackets.WithLabelValues(iface, qdiscType).Add(0)
	QdiscBytes.WithLabelValues(iface, qdiscType).Add(0)
}

// UpdateToolMetrics is a convenience function to update all metrics for a tool result
func UpdateToolMetrics(tool, qdisc string, throughput, latencyP50, latencyP99, loss float64, retransmits int64) {
	ThroughputGbps.WithLabelValues(tool, qdisc).Set(throughput)
	LatencyP50Ms.WithLabelValues(tool, qdisc).Set(latencyP50)
	LatencyP99Ms.WithLabelValues(tool, qdisc).Set(latencyP99)
	PacketLossPct.WithLabelValues(tool, qdisc).Set(loss)
	Retransmits.WithLabelValues(tool, qdisc).Set(float64(retransmits))
}

// SetBreakingPoint marks a breaking point detection
func SetBreakingPoint(qdisc, reason string) {
	BreakingPointDetected.WithLabelValues(qdisc, reason).Set(1)
}

// ClearBreakingPoint clears breaking point indicators
func ClearBreakingPoint(qdisc string) {
	// Reset to 0 for common reasons
	for _, reason := range []string{"latency", "packet_loss", "cpu", "throughput"} {
		BreakingPointDetected.WithLabelValues(qdisc, reason).Set(0)
	}
}

// FormatSocketStats formats socket stats for CLI output
func FormatSocketStats(namespace string, stats *SocketStats) string {
	return fmt.Sprintf("%s: TCP=%d (ESTAB=%d, TW=%d, CW=%d, LISTEN=%d) UDP=%d",
		namespace,
		stats.TCPTotal,
		stats.TCPEstablished,
		stats.TCPTimeWait,
		stats.TCPCloseWait,
		stats.TCPListening,
		stats.UDPTotal,
	)
}
