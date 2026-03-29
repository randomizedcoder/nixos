// internal/telemetry/streaming.go
package telemetry

import (
	"bufio"
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/randomizedcoder/mq-cake-orchestrator/internal/config"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/runner"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/tools"
)

// StreamingCollector manages real-time metrics collection from tool output.
// It parses tool output (streaming or chunked) and immediately updates
// Prometheus metrics on each data point for real-time visualization.
type StreamingCollector struct {
	mu           sync.RWMutex
	accumulators map[string]*tools.StreamAccumulator
	qdisc        string
	runner       runner.Runner
	cfg          *config.Config
	debug        bool
}

// NewStreamingCollector creates a new StreamingCollector
func NewStreamingCollector(qdisc string, r runner.Runner, cfg *config.Config, debug bool) *StreamingCollector {
	return &StreamingCollector{
		accumulators: make(map[string]*tools.StreamAccumulator),
		qdisc:        qdisc,
		runner:       r,
		cfg:          cfg,
		debug:        debug,
	}
}

// StartStreaming begins parsing output from a streaming tool process.
// It spawns goroutines to read stdout/stderr and parse lines as they arrive,
// updating Prometheus metrics IMMEDIATELY on each parsed line.
func (sc *StreamingCollector) StartStreaming(ctx context.Context, tool tools.Tool, proc runner.Process) {
	sp, ok := tool.(tools.StreamingParser)
	if !ok {
		return
	}

	acc := &tools.StreamAccumulator{Tool: tool.Name()}
	sc.mu.Lock()
	sc.accumulators[tool.Name()] = acc
	sc.mu.Unlock()

	// Set tool mode metric
	ToolMode.WithLabelValues(tool.Name()).Set(1) // 1 = streaming

	// Parse stdout in real-time
	go func() {
		scanner := bufio.NewScanner(proc.Stdout())
		for scanner.Scan() {
			select {
			case <-ctx.Done():
				return
			default:
			}
			line := scanner.Text()
			if sp.ParseLine(line, acc) {
				// IMMEDIATE Prometheus update - this is the key for real-time visualization
				sc.updatePrometheusMetrics(tool.Name(), acc)
				if sc.debug {
					acc.Lock()
					fmt.Printf("  [%s] stream: %.2f Gbps, lat=%.2fms, loss=%.2f%%\n",
						tool.Name(), acc.ThroughputGbps, acc.LatencyMs, acc.PacketLossPct)
					acc.Unlock()
				}
			}
		}
	}()

	// Parse stderr (some tools like fping output to stderr)
	go func() {
		scanner := bufio.NewScanner(proc.Stderr())
		for scanner.Scan() {
			select {
			case <-ctx.Done():
				return
			default:
			}
			line := scanner.Text()
			if sp.ParseLine(line, acc) {
				sc.updatePrometheusMetrics(tool.Name(), acc)
			}
		}
	}()
}

// RunChunked executes a tool in chunks and updates Prometheus after each chunk.
// This is for tools without native streaming (like wrk, crusader).
func (sc *StreamingCollector) RunChunked(ctx context.Context, tool tools.Tool, ct tools.ChunkedTool,
	stepDuration time.Duration, flows int, target string) {

	acc := &tools.StreamAccumulator{Tool: tool.Name()}
	sc.mu.Lock()
	sc.accumulators[tool.Name()] = acc
	sc.mu.Unlock()

	// Set tool mode metric
	ToolMode.WithLabelValues(tool.Name()).Set(2) // 2 = chunked

	chunkDuration := stepDuration / time.Duration(ct.ChunkFactor())

	// Apply stagger offset to avoid simultaneous restarts
	select {
	case <-ctx.Done():
		return
	case <-time.After(ct.StartOffset()):
	}

	deadline := time.Now().Add(stepDuration)
	port := tool.DefaultPort()
	iteration := 0

	for time.Now().Before(deadline) {
		select {
		case <-ctx.Done():
			return
		default:
		}

		remaining := time.Until(deadline)
		runFor := min(chunkDuration, remaining)
		if runFor < 2*time.Second {
			break // Don't run very short chunks
		}

		// Update chunk iteration metric
		ChunkIteration.WithLabelValues(tool.Name()).Set(float64(iteration))

		// Run tool for chunk duration
		clientCmd := tool.ClientCmd(target, port, flows, runFor)
		output, err := sc.runner.Run(ctx, sc.cfg.Namespaces.Client, clientCmd)

		if err == nil {
			result, parseErr := tool.Parse(output, flows, runFor)
			if parseErr == nil && result != nil {
				// Update accumulator with chunk results
				acc.Lock()
				acc.ThroughputGbps = result.ThroughputGbps
				acc.LatencyMs = result.LatencyP99Ms
				if result.LatencyP50Ms > 0 {
					acc.AvgLatencyMs = result.LatencyP50Ms
				}
				if result.LatencyP99Ms > acc.MaxLatencyMs {
					acc.MaxLatencyMs = result.LatencyP99Ms
				}
				acc.PacketLossPct = result.PacketLossPct
				acc.Retransmits += result.Retransmits
				acc.LastUpdate = time.Now()
				acc.IntervalCount++
				acc.Unlock()

				// IMMEDIATE Prometheus update after each chunk
				sc.updatePrometheusMetrics(tool.Name(), acc)

				if sc.debug {
					fmt.Printf("  [%s] chunk %d: %.2f Gbps, p99=%.2fms, loss=%.2f%%\n",
						tool.Name(), iteration, result.ThroughputGbps, result.LatencyP99Ms, result.PacketLossPct)
				}
			}
		} else if sc.debug {
			fmt.Printf("  [%s] chunk %d error: %v\n", tool.Name(), iteration, err)
		}

		iteration++
	}
}

// updatePrometheusMetrics updates all relevant Prometheus metrics for a tool.
// Called immediately on each data point for real-time visualization.
func (sc *StreamingCollector) updatePrometheusMetrics(toolName string, acc *tools.StreamAccumulator) {
	acc.Lock()
	defer acc.Unlock()

	// Gauges - current values (for real-time dashboards)
	ThroughputGbps.WithLabelValues(toolName, sc.qdisc).Set(acc.ThroughputGbps)
	LatencyP50Ms.WithLabelValues(toolName, sc.qdisc).Set(acc.AvgLatencyMs)
	LatencyP99Ms.WithLabelValues(toolName, sc.qdisc).Set(acc.LatencyMs)
	PacketLossPct.WithLabelValues(toolName, sc.qdisc).Set(acc.PacketLossPct)
	Retransmits.WithLabelValues(toolName, sc.qdisc).Set(float64(acc.Retransmits))
	MaxLatencyMs.WithLabelValues(toolName, sc.qdisc).Set(acc.MaxLatencyMs)

	// Histograms - for percentile calculations over time
	if acc.ThroughputGbps > 0 {
		ThroughputHistogram.WithLabelValues(toolName, sc.qdisc).Observe(acc.ThroughputGbps)
	}
	if acc.LatencyMs > 0 {
		LatencyHistogram.WithLabelValues(toolName, sc.qdisc).Observe(acc.LatencyMs)
	}

	// Update sample count
	StreamingSamplesTotal.WithLabelValues(toolName).Inc()
	LastUpdateTimestamp.WithLabelValues(toolName).SetToCurrentTime()
}

// GetAccumulator returns the accumulator for a specific tool
func (sc *StreamingCollector) GetAccumulator(toolName string) *tools.StreamAccumulator {
	sc.mu.RLock()
	defer sc.mu.RUnlock()
	return sc.accumulators[toolName]
}

// GetLatest returns the latest accumulated metrics for all tools
func (sc *StreamingCollector) GetLatest() map[string]*tools.StreamAccumulator {
	sc.mu.RLock()
	defer sc.mu.RUnlock()
	result := make(map[string]*tools.StreamAccumulator, len(sc.accumulators))
	for k, v := range sc.accumulators {
		result[k] = v
	}
	return result
}

// Reset clears all accumulators for a new test run
func (sc *StreamingCollector) Reset() {
	sc.mu.Lock()
	defer sc.mu.Unlock()
	for _, acc := range sc.accumulators {
		acc.Reset()
	}
}
