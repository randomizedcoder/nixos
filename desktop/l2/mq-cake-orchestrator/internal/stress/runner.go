// internal/stress/runner.go
package stress

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/randomizedcoder/mq-cake-orchestrator/internal/config"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/process"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/qdisc"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/runner"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/telemetry"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/tools"
)

// StepResult holds metrics collected at a ramping step
type StepResult struct {
	Step         int
	TotalFlows   int
	FlowsByTool  map[string]int
	Duration     time.Duration
	Throughput   map[string]float64 // tool -> Gbps
	LatencyP99   map[string]float64 // tool -> ms
	PacketLoss   map[string]float64 // tool -> %
	SocketStats  map[string]*telemetry.SocketStats
	QdiscStats   map[string]*telemetry.QdiscStats
	MaxCPUPct    float64
	BreakingFlag bool
	BreakReason  string
}

// Runner orchestrates concurrent stress testing with flow ramping
type Runner struct {
	cfg                  *config.Config
	runner               runner.Runner
	scaler               *process.ToolScaler
	qc                   *qdisc.Controller
	toolMap              map[string]tools.Tool
	debug                bool
	socketStatsInterval  time.Duration
	showCommands         bool
	mu                   sync.Mutex
	stepResult           *StepResult
}

// NewRunner creates a new stress test runner
func NewRunner(r runner.Runner, cfg *config.Config, debug bool, socketStatsInterval time.Duration, showCommands bool) *Runner {
	return &Runner{
		cfg:    cfg,
		runner: r,
		scaler: process.NewToolScaler(r, cfg, debug),
		qc:     qdisc.NewController(r, cfg, debug),
		toolMap: map[string]tools.Tool{
			"iperf2":   tools.NewIperf2(),
			"iperf3":   tools.NewIperf3(),
			"flent":    tools.NewFlent(cfg.Output.ResultsDir),
			"crusader": tools.NewCrusader(),
			"wrk":      tools.NewWrk("100k"),
			"dnsperf":  tools.NewDNSPerf(""),
			"fping":    tools.NewFping(),
		},
		debug:               debug,
		socketStatsInterval: socketStatsInterval,
		showCommands:        showCommands,
	}
}

// Run executes the stress test with flow ramping
func (sr *Runner) Run(ctx context.Context, qdiscName string) ([]StepResult, error) {
	var results []StepResult

	// Configure qdisc on DUT
	fmt.Printf("=== Stress Test: qdisc=%s ===\n", qdiscName)
	if err := sr.qc.Set(ctx, qdiscName); err != nil {
		return nil, fmt.Errorf("qdisc setup failed: %w", err)
	}
	time.Sleep(2 * time.Second) // Let qdisc settle

	// Configure netem if enabled
	if sr.cfg.Netem.Enabled {
		fmt.Printf("Configuring netem: latency=%dms jitter=%dms\n",
			sr.cfg.Netem.Latency, sr.cfg.Netem.Jitter)
		if err := sr.configureNetem(ctx); err != nil {
			fmt.Printf("WARNING: netem setup failed: %v\n", err)
		}
	}

	// Build current flow counts from config
	currentFlows := make(map[string]int)
	for _, tc := range sr.cfg.Stress.Tools {
		currentFlows[tc.Name] = tc.Start
	}

	// Print tool commands if requested
	if sr.showCommands {
		fmt.Println("\nTool Commands:")
		for _, tc := range sr.cfg.Stress.Tools {
			if tc.Start > 0 {
				sr.printToolCommands(tc.Name, tc.Start)
			}
		}
	}

	// Start all tools at initial flow counts
	fmt.Println("\nStarting all tools at initial flow counts...")
	for _, tc := range sr.cfg.Stress.Tools {
		if tc.Start > 0 {
			fmt.Printf("  Starting %s with %d flows\n", tc.Name, tc.Start)
			if err := sr.scaler.StartTool(ctx, tc.Name, tc.Start); err != nil {
				fmt.Printf("  WARNING: failed to start %s: %v\n", tc.Name, err)
			}
		}
	}

	// Wait for tools to stabilize
	time.Sleep(sr.cfg.Stress.StabilizeDelay)

	// Ramping loop
	step := 1
	for {
		select {
		case <-ctx.Done():
			fmt.Println("\nStress test interrupted")
			sr.scaler.StopAll()
			return results, ctx.Err()
		default:
		}

		// Calculate total flows
		totalFlows := 0
		for _, flows := range currentFlows {
			totalFlows += flows
		}

		fmt.Printf("\n[Step %d] Total flows: %d\n", step, totalFlows)
		sr.printFlowBreakdown(currentFlows)
		sr.printQdiscConfig(ctx, qdiscName)

		// Update Prometheus metrics
		telemetry.TestStep.Set(float64(step))
		telemetry.TotalFlows.Set(float64(totalFlows))
		for tool, flows := range currentFlows {
			telemetry.ToolFlows.WithLabelValues(tool).Set(float64(flows))
			telemetry.ToolInstances.WithLabelValues(tool).Set(float64(sr.scaler.InstanceCount(tool)))
		}

		// Run tools for step duration and collect metrics
		stepResult := sr.runStep(ctx, step, currentFlows, qdiscName)
		results = append(results, stepResult)

		// Check for breaking point
		if stepResult.BreakingFlag {
			fmt.Printf("\n!!! Breaking point detected at step %d !!!\n", step)
			fmt.Printf("Reason: %s\n", stepResult.BreakReason)
			fmt.Printf("Total flows: %d\n", totalFlows)
			break
		}

		// Check if all tools are at max
		if sr.allAtMax(currentFlows) {
			fmt.Printf("\nAll tools at max - test complete\n")
			break
		}

		// Check context before scaling
		select {
		case <-ctx.Done():
			fmt.Println("\nStress test interrupted")
			sr.scaler.StopAll()
			return results, ctx.Err()
		default:
		}

		// Increment flows for next step
		fmt.Println("\n  Scaling for next step...")
		for i, tc := range sr.cfg.Stress.Tools {
			if tc.Increment > 0 && currentFlows[tc.Name] < tc.Max {
				newFlows := min(currentFlows[tc.Name]+tc.Increment, tc.Max)
				if newFlows != currentFlows[tc.Name] {
					fmt.Printf("  Scaling %s: %d -> %d\n", tc.Name, currentFlows[tc.Name], newFlows)
					if err := sr.scaler.ScaleTo(ctx, tc.Name, newFlows); err != nil {
						fmt.Printf("  WARNING: scaling %s failed: %v\n", tc.Name, err)
					}
					currentFlows[sr.cfg.Stress.Tools[i].Name] = newFlows
				}
			}
		}

		// Stabilization delay
		time.Sleep(sr.cfg.Stress.StabilizeDelay)
		step++
	}

	// Graceful shutdown
	fmt.Println("\nStopping all tools...")
	sr.scaler.StopAll()

	return results, nil
}

// runStep runs all tools concurrently for the step duration and collects metrics.
// Uses streaming mode when available for real-time Prometheus metrics updates.
func (sr *Runner) runStep(ctx context.Context, step int, flows map[string]int, qdiscName string) StepResult {
	result := StepResult{
		Step:        step,
		FlowsByTool: make(map[string]int),
		Throughput:  make(map[string]float64),
		LatencyP99:  make(map[string]float64),
		PacketLoss:  make(map[string]float64),
		SocketStats: make(map[string]*telemetry.SocketStats),
		QdiscStats:  make(map[string]*telemetry.QdiscStats),
	}

	// Copy flow counts
	for tool, count := range flows {
		result.FlowsByTool[tool] = count
		result.TotalFlows += count
	}

	// Create timeout context for this step
	stepCtx, cancel := context.WithTimeout(ctx, sr.cfg.Stress.StepDuration+30*time.Second)
	defer cancel()

	// Create streaming collector for real-time metrics
	collector := telemetry.NewStreamingCollector(qdiscName, sr.runner, sr.cfg, sr.debug)

	// Run clients concurrently with streaming support
	var wg sync.WaitGroup
	var mu sync.Mutex

	for _, tc := range sr.cfg.Stress.Tools {
		if flows[tc.Name] == 0 {
			continue
		}

		wg.Add(1)
		go func(toolName string) {
			defer wg.Done()

			tool := sr.toolMap[toolName]

			// Mode 1: Streaming tools (iperf2, iperf3, fping, dnsperf, flent)
			if sp, ok := tool.(tools.StreamingParser); ok && sp.SupportsStreaming() {
				sr.runStreamingTool(stepCtx, tool, sp, flows[toolName], collector, &result, &mu)
				return
			}

			// Mode 2: Chunked tools (wrk, crusader)
			if ct, ok := tool.(tools.ChunkedTool); ok {
				collector.RunChunked(stepCtx, tool, ct, sr.cfg.Stress.StepDuration,
					flows[toolName], sr.cfg.Network.ServerIP)
				// Get results from accumulator
				if acc := collector.GetAccumulator(toolName); acc != nil {
					acc.Lock()
					mu.Lock()
					result.Throughput[toolName] = acc.ThroughputGbps
					result.LatencyP99[toolName] = acc.MaxLatencyMs
					result.PacketLoss[toolName] = acc.PacketLossPct
					mu.Unlock()
					acc.Unlock()
				}
				return
			}

			// Mode 3: Legacy single-run (fallback)
			outputs, err := sr.scaler.RunClients(stepCtx, toolName, sr.cfg.Stress.StepDuration)
			if err != nil {
				fmt.Printf("  [%s] client error: %v\n", toolName, err)
				return
			}

			// Parse results from all instances
			var totalThroughput float64
			var maxLatency float64
			var maxLoss float64

			for _, output := range outputs {
				parsed, err := tool.Parse(output, flows[toolName], sr.cfg.Stress.StepDuration)
				if err != nil {
					continue
				}
				totalThroughput += parsed.ThroughputGbps
				if parsed.LatencyP99Ms > maxLatency {
					maxLatency = parsed.LatencyP99Ms
				}
				if parsed.PacketLossPct > maxLoss {
					maxLoss = parsed.PacketLossPct
				}
			}

			mu.Lock()
			result.Throughput[toolName] = totalThroughput
			result.LatencyP99[toolName] = maxLatency
			result.PacketLoss[toolName] = maxLoss
			mu.Unlock()

			// Update Prometheus metrics
			telemetry.ThroughputGbps.WithLabelValues(toolName, qdiscName).Set(totalThroughput)
			telemetry.LatencyP99Ms.WithLabelValues(toolName, qdiscName).Set(maxLatency)
			telemetry.PacketLossPct.WithLabelValues(toolName, qdiscName).Set(maxLoss)
			telemetry.ToolMode.WithLabelValues(toolName).Set(0) // 0 = legacy

			if sr.debug {
				fmt.Printf("  [%s] throughput=%.2f Gbps, p99=%.2f ms, loss=%.2f%%\n",
					toolName, totalThroughput, maxLatency, maxLoss)
			}
		}(tc.Name)
	}

	// Collect socket stats periodically during the step
	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-stepCtx.Done():
				return
			case <-ticker.C:
				client, server, err := telemetry.CollectAllSocketStats(
					stepCtx, sr.runner,
					sr.cfg.Namespaces.Client, sr.cfg.Namespaces.Server,
				)
				if err == nil {
					telemetry.UpdateSocketMetrics(sr.cfg.Namespaces.Client, client)
					telemetry.UpdateSocketMetrics(sr.cfg.Namespaces.Server, server)

					mu.Lock()
					result.SocketStats[sr.cfg.Namespaces.Client] = client
					result.SocketStats[sr.cfg.Namespaces.Server] = server
					mu.Unlock()

					if sr.debug {
						fmt.Printf("  Sockets: %s\n", telemetry.FormatSocketStats(sr.cfg.Namespaces.Client, client))
						fmt.Printf("  Sockets: %s\n", telemetry.FormatSocketStats(sr.cfg.Namespaces.Server, server))
					}
				}
			}
		}
	}()

	// Collect qdisc stats periodically
	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-stepCtx.Done():
				return
			case <-ticker.C:
				for _, iface := range []string{sr.cfg.Interfaces.DUTIngress, sr.cfg.Interfaces.DUTEgress} {
					stats, qdiscType, err := telemetry.CollectQdiscStats(
						stepCtx, sr.runner, sr.cfg.Namespaces.DUT, iface,
					)
					if err == nil {
						telemetry.UpdateQdiscMetrics(iface, qdiscType, stats)
						mu.Lock()
						result.QdiscStats[iface] = stats
						mu.Unlock()
					}
				}
			}
		}
	}()

	// Print verbose socket stats if enabled (interval > 0)
	if sr.socketStatsInterval > 0 {
		// Print initial socket stats immediately
		sr.printSocketStats(stepCtx)

		// Continue printing at the configured interval
		go func() {
			ticker := time.NewTicker(sr.socketStatsInterval)
			defer ticker.Stop()

			for {
				select {
				case <-stepCtx.Done():
					return
				case <-ticker.C:
					sr.printSocketStats(stepCtx)
				}
			}
		}()
	}

	wg.Wait()

	// Final socket stats collection
	client, server, _ := telemetry.CollectAllSocketStats(ctx, sr.runner,
		sr.cfg.Namespaces.Client, sr.cfg.Namespaces.Server)
	if client != nil {
		result.SocketStats[sr.cfg.Namespaces.Client] = client
	}
	if server != nil {
		result.SocketStats[sr.cfg.Namespaces.Server] = server
	}

	// Print step summary
	sr.printStepSummary(&result)

	// Check for breaking point
	sr.checkBreakingPoint(&result)

	return result
}

// checkBreakingPoint determines if we've hit a breaking point
func (sr *Runner) checkBreakingPoint(result *StepResult) {
	// Check latency threshold
	for tool, latency := range result.LatencyP99 {
		if latency > sr.cfg.Stress.MaxLatencyP99Ms {
			result.BreakingFlag = true
			result.BreakReason = fmt.Sprintf("%s P99 latency %.2fms > threshold %.2fms",
				tool, latency, sr.cfg.Stress.MaxLatencyP99Ms)
			return
		}
	}

	// Check packet loss threshold
	for tool, loss := range result.PacketLoss {
		if loss > sr.cfg.Stress.MaxPacketLossPct {
			result.BreakingFlag = true
			result.BreakReason = fmt.Sprintf("%s packet loss %.2f%% > threshold %.2f%%",
				tool, loss, sr.cfg.Stress.MaxPacketLossPct)
			return
		}
	}

	// Check CPU threshold
	if result.MaxCPUPct > sr.cfg.Stress.MaxCPUPct {
		result.BreakingFlag = true
		result.BreakReason = fmt.Sprintf("CPU usage %.2f%% > threshold %.2f%%",
			result.MaxCPUPct, sr.cfg.Stress.MaxCPUPct)
		return
	}

	// Check qdisc drops (if significant increase)
	for iface, stats := range result.QdiscStats {
		if stats.Drops > 1000 {
			fmt.Printf("  WARNING: %s drops=%d\n", iface, stats.Drops)
		}
	}
}

// allAtMax returns true if all tools are at their max flow count
func (sr *Runner) allAtMax(current map[string]int) bool {
	for _, tc := range sr.cfg.Stress.Tools {
		if tc.Increment > 0 && current[tc.Name] < tc.Max {
			return false
		}
	}
	return true
}

// printFlowBreakdown prints current flows per tool
func (sr *Runner) printFlowBreakdown(flows map[string]int) {
	fmt.Print("  Flows: ")
	first := true
	for tool, count := range flows {
		if count > 0 {
			if !first {
				fmt.Print(", ")
			}
			fmt.Printf("%s=%d", tool, count)
			first = false
		}
	}
	fmt.Println()
}

// printQdiscConfig prints the current qdisc configuration on DUT interfaces
func (sr *Runner) printQdiscConfig(ctx context.Context, qdiscName string) {
	fmt.Printf("  Qdisc: %s\n", qdiscName)
	for _, iface := range []string{sr.cfg.Interfaces.DUTIngress, sr.cfg.Interfaces.DUTEgress} {
		output, err := sr.runner.Run(ctx, sr.cfg.Namespaces.DUT, []string{
			"tc", "qdisc", "show", "dev", iface,
		})
		if err == nil && len(output) > 0 {
			fmt.Printf("    %s:\n", iface)
			lines := splitLines(output)
			for _, line := range lines {
				fmt.Printf("      %s\n", line)
			}
		}
	}
}

// splitLines splits output into lines
func splitLines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			line := s[start:i]
			if len(line) > 0 {
				lines = append(lines, line)
			}
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

// printStepSummary prints a summary of the step results
func (sr *Runner) printStepSummary(result *StepResult) {
	fmt.Println("  Results:")

	// Throughput
	totalThroughput := 0.0
	for tool, tp := range result.Throughput {
		fmt.Printf("    %s: %.2f Gbps", tool, tp)
		if lat, ok := result.LatencyP99[tool]; ok && lat > 0 {
			fmt.Printf(", P99=%.2fms", lat)
		}
		if loss, ok := result.PacketLoss[tool]; ok && loss > 0 {
			fmt.Printf(", loss=%.2f%%", loss)
		}
		fmt.Println()
		totalThroughput += tp
	}
	fmt.Printf("    Total throughput: %.2f Gbps\n", totalThroughput)

	// Socket stats
	for ns, stats := range result.SocketStats {
		fmt.Printf("    %s\n", telemetry.FormatSocketStats(ns, stats))
	}
}

// runStreamingTool runs a tool with streaming output parsing for real-time metrics.
func (sr *Runner) runStreamingTool(ctx context.Context, tool tools.Tool, sp tools.StreamingParser,
	flows int, collector *telemetry.StreamingCollector, result *StepResult, mu *sync.Mutex) {

	toolName := tool.Name()
	port := tool.DefaultPort()

	// Get streaming command
	clientCmd := sp.StreamClientCmd(sr.cfg.Network.ServerIP, port, flows, sr.cfg.Stress.StepDuration)

	// Start process with streaming output
	proc, err := sr.runner.Start(ctx, sr.cfg.Namespaces.Client, clientCmd)
	if err != nil {
		fmt.Printf("  [%s] stream start error: %v\n", toolName, err)
		return
	}

	// Start streaming parser
	collector.StartStreaming(ctx, tool, proc)

	// Wait for process to complete or context cancellation
	waitDone := make(chan error, 1)
	go func() {
		waitDone <- proc.Wait()
	}()

	select {
	case <-ctx.Done():
		// Context cancelled - kill the process
		if sr.debug {
			fmt.Printf("  [%s] context cancelled, killing process\n", toolName)
		}
		proc.Kill()
		<-waitDone // Wait for process to actually exit
	case err := <-waitDone:
		if err != nil && sr.debug {
			fmt.Printf("  [%s] stream completed with: %v\n", toolName, err)
		}
	}

	// Collect final results from accumulator
	if acc := collector.GetAccumulator(toolName); acc != nil {
		acc.Lock()
		mu.Lock()
		result.Throughput[toolName] = acc.ThroughputGbps
		result.LatencyP99[toolName] = acc.MaxLatencyMs
		if acc.AvgLatencyMs > 0 {
			// Store avg latency if we don't have max
			if result.LatencyP99[toolName] == 0 {
				result.LatencyP99[toolName] = acc.AvgLatencyMs
			}
		}
		result.PacketLoss[toolName] = acc.PacketLossPct
		mu.Unlock()
		acc.Unlock()
	}
}

// configureNetem applies netem configuration to load generator interfaces
func (sr *Runner) configureNetem(ctx context.Context) error {
	latency := sr.cfg.Netem.Latency
	jitter := sr.cfg.Netem.Jitter
	limit := sr.cfg.Netem.Limit

	// Apply to client namespace
	_, err := sr.runner.Run(ctx, sr.cfg.Namespaces.Client, []string{
		"tc", "qdisc", "replace", "dev", sr.getClientInterface(),
		"root", "netem",
		"delay", fmt.Sprintf("%dms", latency), fmt.Sprintf("%dms", jitter),
		"distribution", "normal",
		"limit", fmt.Sprintf("%d", limit),
	})
	if err != nil {
		return fmt.Errorf("client netem: %w", err)
	}

	// Apply to server namespace
	_, err = sr.runner.Run(ctx, sr.cfg.Namespaces.Server, []string{
		"tc", "qdisc", "replace", "dev", sr.getServerInterface(),
		"root", "netem",
		"delay", fmt.Sprintf("%dms", latency), fmt.Sprintf("%dms", jitter),
		"distribution", "normal",
		"limit", fmt.Sprintf("%d", limit),
	})
	if err != nil {
		return fmt.Errorf("server netem: %w", err)
	}

	return nil
}

// getClientInterface returns the interface in the client namespace
func (sr *Runner) getClientInterface() string {
	// X710 port 0 in ns-gen-a
	return "enp35s0f0np0"
}

// getServerInterface returns the interface in the server namespace
func (sr *Runner) getServerInterface() string {
	// X710 port 1 in ns-gen-b
	return "enp35s0f1np1"
}

// Cleanup stops all running tool instances
func (sr *Runner) Cleanup() {
	sr.scaler.StopAll()
}

// printSocketStats prints TCP/UDP socket summary and ping RTT
func (sr *Runner) printSocketStats(ctx context.Context) {
	timestamp := time.Now().Format("15:04:05")
	fmt.Printf("\n  === Socket Stats @ %s ===\n", timestamp)

	// TCP summary from client namespace - only print the "TCP:" summary line
	tcpOut, err := sr.runner.Run(ctx, sr.cfg.Namespaces.Client, []string{
		"ss", "-t", "-s",
	})
	if err == nil {
		for _, line := range splitLines(tcpOut) {
			if hasPrefix(line, "TCP:") {
				fmt.Printf("  [%s] %s\n", sr.cfg.Namespaces.Client, line)
			}
		}
	}

	// TCP summary from server namespace
	tcpOut, err = sr.runner.Run(ctx, sr.cfg.Namespaces.Server, []string{
		"ss", "-t", "-s",
	})
	if err == nil {
		for _, line := range splitLines(tcpOut) {
			if hasPrefix(line, "TCP:") {
				fmt.Printf("  [%s] %s\n", sr.cfg.Namespaces.Server, line)
			}
		}
	}

	// UDP summary from client namespace - only print the "UDP:" summary line
	udpOut, err := sr.runner.Run(ctx, sr.cfg.Namespaces.Client, []string{
		"ss", "-u", "-s",
	})
	if err == nil {
		for _, line := range splitLines(udpOut) {
			if hasPrefix(line, "UDP:") {
				fmt.Printf("  [%s] %s\n", sr.cfg.Namespaces.Client, line)
			}
		}
	}

	// UDP summary from server namespace
	udpOut, err = sr.runner.Run(ctx, sr.cfg.Namespaces.Server, []string{
		"ss", "-u", "-s",
	})
	if err == nil {
		for _, line := range splitLines(udpOut) {
			if hasPrefix(line, "UDP:") {
				fmt.Printf("  [%s] %s\n", sr.cfg.Namespaces.Server, line)
			}
		}
	}

	// Ping RTT from client to server
	pingOut, err := sr.runner.Run(ctx, sr.cfg.Namespaces.Client, []string{
		"ping", "-c", "3", "-W", "2", sr.cfg.Network.ServerIP,
	})
	if err == nil {
		// Extract the summary line with RTT
		for _, line := range splitLines(pingOut) {
			if len(line) > 0 && (contains(line, "rtt") || contains(line, "round-trip")) {
				fmt.Printf("  [Ping] %s\n", line)
			}
		}
	} else {
		fmt.Printf("  [Ping] failed: %v\n", err)
	}
}

// hasPrefix checks if s starts with prefix
func hasPrefix(s, prefix string) bool {
	return len(s) >= len(prefix) && s[:len(prefix)] == prefix
}

// contains checks if s contains substr
func contains(s, substr string) bool {
	return len(s) >= len(substr) && findSubstring(s, substr) >= 0
}

// findSubstring finds substr in s
func findSubstring(s, substr string) int {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}

// printToolCommands prints the full server and client commands for a tool
func (sr *Runner) printToolCommands(toolName string, flows int) {
	tool, ok := sr.toolMap[toolName]
	if !ok {
		fmt.Printf("  %s: unknown tool\n", toolName)
		return
	}

	port := tool.DefaultPort()
	serverIP := sr.cfg.Network.ServerIP
	duration := sr.cfg.Stress.StepDuration

	fmt.Printf("  %s:\n", toolName)

	// Print server command
	serverCmd := tool.ServerCmd(port)
	if len(serverCmd) > 0 {
		fmt.Printf("    server [%s]: %s\n", sr.cfg.Namespaces.Server, formatCmd(serverCmd))
	}

	// Print client command - check if it supports streaming
	var clientCmd []string
	if sp, ok := tool.(tools.StreamingParser); ok && sp.SupportsStreaming() {
		clientCmd = sp.StreamClientCmd(serverIP, port, flows, duration)
	} else {
		clientCmd = tool.ClientCmd(serverIP, port, flows, duration)
	}
	if len(clientCmd) > 0 {
		fmt.Printf("    client [%s]: %s\n", sr.cfg.Namespaces.Client, formatCmd(clientCmd))
	}
}

// formatCmd formats a command slice as a single string
func formatCmd(cmd []string) string {
	if len(cmd) == 0 {
		return ""
	}
	result := cmd[0]
	for i := 1; i < len(cmd); i++ {
		// Quote arguments with spaces
		if containsSpace(cmd[i]) {
			result += " \"" + cmd[i] + "\""
		} else {
			result += " " + cmd[i]
		}
	}
	return result
}

// containsSpace checks if s contains a space
func containsSpace(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] == ' ' {
			return true
		}
	}
	return false
}
