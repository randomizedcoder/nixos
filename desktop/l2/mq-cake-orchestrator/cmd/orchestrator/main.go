// cmd/orchestrator/main.go
package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/config"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/matrix"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/preflight"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/process"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/qdisc"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/results"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/runner"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/stress"
	"github.com/randomizedcoder/mq-cake-orchestrator/internal/tools"
)

func main() {
	configPath := flag.String("config", "config.yaml", "Path to config file")
	debug := flag.Bool("debug", false, "Enable debug output (show commands and qdisc config)")
	stressMode := flag.Bool("stress", false, "Run concurrent stress test with flow ramping")
	metricsAddr := flag.String("metrics-addr", "0.0.0.0", "Prometheus metrics listen address (default: 0.0.0.0)")
	socketStatsInterval := flag.Duration("socket-stats", 0, "Print TCP/UDP socket counts and ping RTT at this interval (e.g., 1s, 10s). 0 disables.")
	showCommands := flag.Bool("show-commands", false, "Print full commands for each tool")
	flag.Parse()

	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Config error: %v\n", err)
		os.Exit(1)
	}

	// Create root context with manual cancellation
	ctx, cancel := context.WithCancel(context.Background())

	// Handle signals - cancel context and allow cleanup
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	// Single waitgroup for all goroutines
	var wg sync.WaitGroup

	// Initialize components
	r := runner.NewLocalRunner()
	manager := process.NewManager(r, &wg, cfg, *debug)
	qc := qdisc.NewController(r, cfg, *debug)

	// Signal handler goroutine
	go func() {
		sig := <-sigChan
		fmt.Printf("\nReceived signal %v, shutting down...\n", sig)
		cancel() // Cancel the context

		// Give processes time to clean up
		time.Sleep(500 * time.Millisecond)

		// Second signal = force exit
		sig = <-sigChan
		fmt.Printf("\nReceived second signal %v, force exiting...\n", sig)
		os.Exit(1)
	}()

	fmt.Println("mq-cake-orchestrator starting...")

	// Start Prometheus metrics server if in stress mode
	if *stressMode {
		go func() {
			addr := fmt.Sprintf("%s:%d", *metricsAddr, cfg.Stress.MetricsPort)
			fmt.Printf("Prometheus metrics server on %s\n", addr)
			http.Handle("/metrics", promhttp.Handler())
			if err := http.ListenAndServe(addr, nil); err != nil {
				fmt.Printf("Metrics server error: %v\n", err)
			}
		}()
	}

	// Stress test mode: all tools run concurrently with flow ramping
	if *stressMode {
		runStressTest(ctx, cfg, r, *debug, *socketStatsInterval, *showCommands)
		return
	}

	// Sequential mode: run each tool individually
	fmt.Printf("Config: %d tools, %d qdiscs, %d flow counts\n",
		len(cfg.Tools), len(cfg.Matrix.Qdiscs), len(cfg.Matrix.FlowCounts))

	// Pre-flight validation
	var baselineRTT float64
	if cfg.Preflight.Enabled {
		fmt.Println("\n=== Pre-flight Checks ===")
		validator := preflight.NewValidator(r, cfg)
		if err := validator.Validate(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "\nPre-flight failed: %v\n", err)
			os.Exit(1)
		}
		baselineRTT = validator.GetBaselineRTT()
		fmt.Println("\n=== Pre-flight Complete ===")
	}

	// Build test matrix
	testPoints := matrix.BuildMatrix(cfg)
	fmt.Printf("Running %d test points\n\n", len(testPoints))

	// Initialize tools map
	toolMap := map[string]tools.Tool{
		"iperf2":   tools.NewIperf2(),
		"iperf3":   tools.NewIperf3(),
		"flent":    tools.NewFlent(cfg.Output.ResultsDir),
		"crusader": tools.NewCrusader(),
		"wrk":      tools.NewWrk("100k"),
		"dnsperf":  tools.NewDNSPerf(""),
		"fping":    tools.NewFping(),
	}

	// Initialize test run
	run := &results.TestRun{
		Metadata: results.Metadata{
			StartTime:     time.Now(),
			BaselineRTTMs: baselineRTT,
		},
	}

	// Get host info
	if hostname, err := os.Hostname(); err == nil {
		run.Metadata.Host = hostname
	}

	var currentQdisc string

	// Main test loop
	for i, tp := range testPoints {
		select {
		case <-ctx.Done():
			fmt.Println("\nTest interrupted")
			goto export
		default:
		}

		fmt.Printf("[%d/%d] qdisc=%s flows=%d tool=%s\n",
			i+1, len(testPoints), tp.Qdisc, tp.FlowCount, tp.Tool)

		// Switch qdisc if needed
		if tp.Qdisc != currentQdisc {
			fmt.Printf("  Switching qdisc to %s...\n", tp.Qdisc)
			if err := qc.Set(ctx, tp.Qdisc); err != nil {
				fmt.Printf("  ERROR: qdisc switch failed: %v\n", err)
				continue
			}
			currentQdisc = tp.Qdisc
			time.Sleep(2 * time.Second) // Let qdisc settle
		}

		// Get tool
		tool, ok := toolMap[tp.Tool]
		if !ok {
			fmt.Printf("  ERROR: unknown tool %s\n", tp.Tool)
			continue
		}

		// Run tool
		result, err := manager.RunTool(ctx, tool, tp.FlowCount)
		if err != nil {
			fmt.Printf("  ERROR: %v\n", err)
			continue
		}

		fmt.Printf("  Throughput: %.2f Gbps\n", result.ThroughputGbps)

		// Collect qdisc stats
		var qdiscStats map[string]string
		if cfg.Telemetry.CollectQdiscStats {
			qdiscStats, _ = qc.GetStats(ctx)
		}

		run.Results = append(run.Results, results.TestResult{
			TestPoint:  tp,
			Result:     result,
			QdiscStats: qdiscStats,
		})

		// Cooldown between tests
		time.Sleep(cfg.Timing.Cooldown)
	}

export:
	run.Metadata.EndTime = time.Now()

	fmt.Printf("\n=== Test Complete ===\n")
	fmt.Printf("Completed %d test points\n", len(run.Results))

	if len(run.Results) > 0 {
		if err := results.Export(run, &cfg.Output); err != nil {
			fmt.Printf("Export failed: %v\n", err)
		} else {
			fmt.Printf("Results saved to %s\n", cfg.Output.ResultsDir)
		}
	}

	// Wait for goroutines with timeout
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		fmt.Println("Shutdown complete")
	case <-time.After(10 * time.Second):
		fmt.Println("Shutdown timed out")
	}
}

// runStressTest runs concurrent stress test with flow ramping
func runStressTest(ctx context.Context, cfg *config.Config, r runner.Runner, debug bool, socketStatsInterval time.Duration, showCommands bool) {
	fmt.Println("\n=== Stress Test Mode ===")
	fmt.Printf("Config: %d tools, step_duration=%s\n",
		len(cfg.Stress.Tools), cfg.Stress.StepDuration)

	// Print tool flow configuration
	fmt.Println("\nTool Configuration:")
	for _, tc := range cfg.Stress.Tools {
		fmt.Printf("  %s: start=%d, increment=%d, max=%d\n",
			tc.Name, tc.Start, tc.Increment, tc.Max)
	}

	// Pre-flight validation
	if cfg.Preflight.Enabled {
		fmt.Println("\n=== Pre-flight Checks ===")
		validator := preflight.NewValidator(r, cfg)
		if err := validator.Validate(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "\nPre-flight failed: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("=== Pre-flight Complete ===")
	}

	// Create stress runner
	sr := stress.NewRunner(r, cfg, debug, socketStatsInterval, showCommands)

	// Ensure cleanup on exit
	defer func() {
		fmt.Println("\nCleaning up all processes...")
		sr.Cleanup()
		fmt.Println("Cleanup complete")
	}()

	// Run stress test for each qdisc
	allResults := make(map[string][]stress.StepResult)
	for _, qdiscName := range cfg.Matrix.Qdiscs {
		// Check if cancelled before starting next qdisc
		select {
		case <-ctx.Done():
			fmt.Println("\nTest cancelled, cleaning up...")
			return
		default:
		}

		results, err := sr.Run(ctx, qdiscName)
		if err != nil {
			if err == context.Canceled {
				fmt.Println("\nTest cancelled, cleaning up...")
				return
			}
			fmt.Printf("Stress test failed for %s: %v\n", qdiscName, err)
			continue
		}
		allResults[qdiscName] = results
	}

	// Print summary
	fmt.Println("\n=== Stress Test Summary ===")
	for qdiscName, results := range allResults {
		if len(results) == 0 {
			continue
		}
		fmt.Printf("\nQdisc: %s\n", qdiscName)
		fmt.Printf("  Steps completed: %d\n", len(results))

		// Find max flows before breaking
		lastStep := results[len(results)-1]
		fmt.Printf("  Max total flows: %d\n", lastStep.TotalFlows)

		if lastStep.BreakingFlag {
			fmt.Printf("  Breaking point: %s\n", lastStep.BreakReason)
		}

		// Print throughput summary
		fmt.Println("  Final throughput by tool:")
		for tool, tp := range lastStep.Throughput {
			fmt.Printf("    %s: %.2f Gbps\n", tool, tp)
		}
	}

	fmt.Println("\n=== Stress Test Complete ===")
}
