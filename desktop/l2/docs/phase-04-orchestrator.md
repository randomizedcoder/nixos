# Phase 4: Go Orchestrator

**Goal**: Automate the test matrix with a Go program that manages load generators and exports metrics.

**Prerequisites**: [Phase 3](./phase-03-loadgen.md) complete (manual load generation works).

**Outcome**: `mq-cake-orchestrator` runs all qdisc/flow-count combinations and produces results.

---

## Design Principles

| Principle | Implementation |
|-----------|----------------|
| **Single Context** | `signal.NotifyContext` in main, passed to all components |
| **Single WaitGroup** | Created in main, passed forward to all goroutines |
| **Context first argument** | All functions: `func Foo(ctx context.Context, ...)` |
| **Check ctx.Done() first** | Always check cancellation before other channel ops |
| Interface-driven tooling | All tools implement `Tool` interface |
| Runner pattern | Decouple execution (local/SSH) from tool logic |
| Declarative test matrix | `[]TestPoint` instead of nested loops |
| Zombie prevention | `Setpgid` + kill process group on cleanup |

---

## Context & Signal Handling Pattern

```go
func main() {
    // Create context that cancels on SIGINT or SIGTERM
    // This replaces 10+ lines of manual signal handling with one line
    ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    defer stop()  // Deregister signal handling on exit

    // Single waitgroup for ALL goroutines - created here, passed forward
    var wg sync.WaitGroup

    // ... start all components, passing ctx and &wg ...

    // Block until signal received
    <-ctx.Done()
    fmt.Println("Shutdown signal received")

    // ... cleanup (close connections, etc.) ...

    // Wait for all goroutines with timeout safety net
    done := make(chan struct{})
    go func() {
        wg.Wait()
        close(done)
    }()

    select {
    case <-done:
        fmt.Println("Graceful shutdown complete")
    case <-time.After(10 * time.Second):
        fmt.Println("Shutdown timed out")
    }
}
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         mq-cake-orchestrator                                │
├─────────────────────────────────────────────────────────────────────────────┤
│  main()                                                                     │
│    │                                                                        │
│    ├── ctx, stop := signal.NotifyContext(...)   // Cancels on signal        │
│    ├── var wg sync.WaitGroup                    // Single waitgroup         │
│    │                                                                        │
│  ┌─┴───────────────────────────────────────────────────────────────────┐   │
│  │                         Tool Interface                               │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌────────┐   │   │
│  │  │ iperf2  │  │ iperf3  │  │  flent  │  │ crusader │  │  ping  │   │   │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬─────┘  └───┬────┘   │   │
│  └───────┴────────────┴────────────┴────────────┴────────────┴────────┘   │
│                                    │                                       │
│  ┌─────────────────────────────────▼───────────────────────────────────┐   │
│  │              Runner Interface (ctx as first arg)                     │   │
│  │  ┌─────────────┐                           ┌─────────────┐          │   │
│  │  │ LocalRunner │  (ip netns exec)          │  SSHRunner  │ (future) │   │
│  │  └─────────────┘                           └─────────────┘          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                       │
│  ┌─────────────────────────────────▼───────────────────────────────────┐   │
│  │                       Process Manager                                │   │
│  │  • Setpgid for process group cleanup                                │   │
│  │  • context.WithTimeout per tool                                     │   │
│  │  • Kill process group on ctx.Done()                                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                       │
│  ┌────────────┬───────────────────┬┴───────────────────┬────────────────┐  │
│  │            │                   │                    │                │  │
│  ▼            ▼                   ▼                    ▼                ▼  │
│ PreFlight  TestMatrix         Results             Telemetry        Qdisc  │
│ Validator  Controller         Collector           (CPU/proc)       Ctrl   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
mq-cake-orchestrator/
├── cmd/
│   └── orchestrator/
│       └── main.go
├── internal/
│   ├── config/
│   │   └── config.go
│   ├── runner/
│   │   ├── runner.go          # Runner interface
│   │   ├── local.go           # LocalRunner (ip netns exec)
│   │   └── ssh.go             # SSHRunner (future: multi-machine)
│   ├── process/
│   │   ├── manager.go         # errgroup-based process management
│   │   └── cleanup.go         # Zombie prevention, signal handling
│   ├── tools/
│   │   ├── tool.go            # Tool interface
│   │   ├── iperf2.go
│   │   ├── iperf3.go
│   │   ├── flent.go
│   │   ├── crusader.go
│   │   └── ping.go            # Background latency probe
│   ├── matrix/
│   │   └── testpoint.go       # Declarative test matrix
│   ├── qdisc/
│   │   └── controller.go
│   ├── telemetry/
│   │   └── cpu.go             # Per-core CPU stats from /proc/stat
│   ├── results/
│   │   ├── schema.go          # Normalized result schema
│   │   └── export.go          # JSON/CSV export
│   └── preflight/
│       └── validate.go        # Pre-flight checks (mq-cake-verify)
├── config.yaml
├── flake.nix                  # Nix Flake for reproducibility
├── go.mod
└── go.sum
```

---

## Core Interfaces

### Runner Interface (Execution Abstraction)

```go
// internal/runner/runner.go

package runner

import (
    "context"
    "io"
)

// Runner abstracts command execution (local, SSH, etc.)
type Runner interface {
    // Run executes a command and returns combined output
    Run(ctx context.Context, namespace string, cmd []string) (string, error)

    // Start executes a command in background, returns process handle
    Start(ctx context.Context, namespace string, cmd []string) (Process, error)
}

// Process represents a running background process
type Process interface {
    Wait() error
    Kill() error
    Stdout() io.Reader
    Stderr() io.Reader
}
```

### LocalRunner Implementation

```go
// internal/runner/local.go

package runner

import (
    "context"
    "os/exec"
    "syscall"
)

type LocalRunner struct{}

func (r *LocalRunner) Run(ctx context.Context, namespace string, cmd []string) (string, error) {
    args := append([]string{"netns", "exec", namespace}, cmd...)
    c := exec.CommandContext(ctx, "ip", args...)

    // Set process group for clean termination
    c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

    out, err := c.CombinedOutput()
    return string(out), err
}

func (r *LocalRunner) Start(ctx context.Context, namespace string, cmd []string) (Process, error) {
    args := append([]string{"netns", "exec", namespace}, cmd...)
    c := exec.CommandContext(ctx, "ip", args...)
    c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

    if err := c.Start(); err != nil {
        return nil, err
    }
    return &localProcess{cmd: c}, nil
}

type localProcess struct {
    cmd *exec.Cmd
}

func (p *localProcess) Kill() error {
    // Kill entire process group to prevent zombies
    return syscall.Kill(-p.cmd.Process.Pid, syscall.SIGKILL)
}
```

### Tool Interface

```go
// internal/tools/tool.go

package tools

import (
    "context"
    "time"
)

// NormalizedResult is the standardized output schema for all tools
type NormalizedResult struct {
    Tool           string        `json:"tool"`
    Timestamp      time.Time     `json:"timestamp"`
    Duration       time.Duration `json:"duration"`
    FlowCount      int           `json:"flow_count"`
    ThroughputGbps float64       `json:"throughput_gbps"`
    LatencyP50Ms   float64       `json:"latency_p50_ms"`
    LatencyP99Ms   float64       `json:"latency_p99_ms"`
    PacketLossPct  float64       `json:"packet_loss_pct"`
    Retransmits    int64         `json:"retransmits"`
    JitterMs       float64       `json:"jitter_ms"`
    RawOutput      string        `json:"raw_output,omitempty"`
}

// Tool defines the interface all load generators must implement
type Tool interface {
    Name() string

    // ServerCmd returns the command to start the server
    ServerCmd(port int) []string

    // ClientCmd returns the command to run the client
    ClientCmd(target string, port int, flows int, duration time.Duration) []string

    // Parse converts raw output to NormalizedResult
    Parse(output string, flows int) (*NormalizedResult, error)

    // SupportsFlowCount returns true if tool supports parallel flows
    SupportsFlowCount() bool
}
```

---

## Declarative Test Matrix

```go
// internal/matrix/testpoint.go

package matrix

import "time"

// TestPoint represents a single test configuration
type TestPoint struct {
    Qdisc     string
    FlowCount int
    Tool      string
    Duration  time.Duration
}

// BuildMatrix creates all test combinations from config
func BuildMatrix(cfg *config.Config) []TestPoint {
    var points []TestPoint

    for _, qdisc := range cfg.Matrix.Qdiscs {
        for _, flows := range cfg.Matrix.FlowCounts {
            for _, tool := range cfg.Tools {
                points = append(points, TestPoint{
                    Qdisc:     qdisc,
                    FlowCount: flows,
                    Tool:      tool,
                    Duration:  cfg.Timing.PerToolDuration,
                })
            }
        }
    }

    // Optional: shuffle to avoid thermal throttling bias
    if cfg.Matrix.Shuffle {
        rand.Shuffle(len(points), func(i, j int) {
            points[i], points[j] = points[j], points[i]
        })
    }

    return points
}
```

---

## Process Manager (No Signal Handling Here)

**Key insight**: Signal handling happens in `main()` via `signal.NotifyContext`. The process manager just receives context and waitgroup - it doesn't set up its own signal handlers.

```go
// internal/process/manager.go

package process

import (
    "context"
    "fmt"
    "sync"
    "syscall"
    "time"
)

// Manager handles tool execution. It does NOT handle signals - that's main()'s job.
type Manager struct {
    runner runner.Runner
    wg     *sync.WaitGroup  // Passed from main
}

// NewManager creates a manager. Context and waitgroup come from main().
func NewManager(r runner.Runner, wg *sync.WaitGroup) *Manager {
    return &Manager{
        runner: r,
        wg:     wg,
    }
}

// RunTool executes a tool with proper timeout and cleanup.
// Context is first argument per Go convention.
func (m *Manager) RunTool(
    ctx context.Context,
    tool tools.Tool,
    cfg *config.Config,
    flows int,
) (*tools.NormalizedResult, error) {
    // Check context cancellation FIRST, before any operations
    select {
    case <-ctx.Done():
        return nil, ctx.Err()
    default:
    }

    // Create timeout context for this tool run
    toolCtx, cancel := context.WithTimeout(ctx, cfg.Timing.PerToolDuration+30*time.Second)
    defer cancel()

    // Start server process
    serverProc, err := m.runner.Start(toolCtx, cfg.Namespaces.Server, tool.ServerCmd(5001))
    if err != nil {
        return nil, fmt.Errorf("failed to start server: %w", err)
    }

    // Ensure server is killed when we return (any exit path)
    defer serverProc.Kill()

    // Shutdown watcher - kills server if context cancelled mid-run
    go func() {
        <-toolCtx.Done()
        serverProc.Kill()
    }()

    time.Sleep(1 * time.Second) // Let server initialize

    // Run client (context first)
    output, err := m.runner.Run(toolCtx, cfg.Namespaces.Client,
        tool.ClientCmd(cfg.Network.ServerIP, 5001, flows, cfg.Timing.PerToolDuration))
    if err != nil {
        return nil, fmt.Errorf("client failed: %w", err)
    }

    return tool.Parse(output, flows)
}
```

---

## CPU Telemetry Collection

```go
// internal/telemetry/cpu.go

package telemetry

import (
    "bufio"
    "os"
    "strconv"
    "strings"
)

// CPUStats holds per-core CPU usage
type CPUStats struct {
    Timestamp time.Time
    PerCore   []CoreStats
    Total     CoreStats
}

type CoreStats struct {
    Core    int
    User    uint64
    System  uint64
    Idle    uint64
    Percent float64
}

// CollectCPUStats reads /proc/stat and computes CPU utilization
func CollectCPUStats() (*CPUStats, error) {
    file, err := os.Open("/proc/stat")
    if err != nil {
        return nil, err
    }
    defer file.Close()

    stats := &CPUStats{Timestamp: time.Now()}
    scanner := bufio.NewScanner(file)

    for scanner.Scan() {
        line := scanner.Text()
        if strings.HasPrefix(line, "cpu") {
            fields := strings.Fields(line)
            if len(fields) < 5 {
                continue
            }

            user, _ := strconv.ParseUint(fields[1], 10, 64)
            system, _ := strconv.ParseUint(fields[3], 10, 64)
            idle, _ := strconv.ParseUint(fields[4], 10, 64)

            cs := CoreStats{User: user, System: system, Idle: idle}

            if fields[0] == "cpu" {
                stats.Total = cs
            } else {
                coreNum, _ := strconv.Atoi(strings.TrimPrefix(fields[0], "cpu"))
                cs.Core = coreNum
                stats.PerCore = append(stats.PerCore, cs)
            }
        }
    }

    return stats, nil
}

// CollectDuring collects CPU stats at intervals during a test
func CollectDuring(ctx context.Context, interval time.Duration) <-chan *CPUStats {
    ch := make(chan *CPUStats)
    go func() {
        defer close(ch)
        ticker := time.NewTicker(interval)
        defer ticker.Stop()
        for {
            select {
            case <-ctx.Done():
                return
            case <-ticker.C:
                if stats, err := CollectCPUStats(); err == nil {
                    ch <- stats
                }
            }
        }
    }()
    return ch
}
```

---

## Pre-Flight Validation

```go
// internal/preflight/validate.go

package preflight

import (
    "context"
    "fmt"
)

type Validator struct {
    ctx    context.Context  // From main - for cancellation
    runner runner.Runner
    cfg    *config.Config
}

// NewValidator creates a validator. Context is first argument per Go convention.
func NewValidator(ctx context.Context, r runner.Runner, cfg *config.Config) *Validator {
    return &Validator{ctx: ctx, runner: r, cfg: cfg}
}

// Validate runs all pre-flight checks before starting the test matrix
func (v *Validator) Validate() error {
    checks := []struct {
        name string
        fn   func() error
    }{
        {"namespaces exist", v.checkNamespaces},
        {"interfaces present", v.checkInterfaces},
        {"forwarding enabled", v.checkForwarding},
        {"end-to-end ping", v.checkPing},
        {"tools available", v.checkTools},
        {"baseline latency", v.measureBaseline},
    }

    for _, check := range checks {
        // Check for cancellation between checks
        select {
        case <-v.ctx.Done():
            return v.ctx.Err()
        default:
        }

        fmt.Printf("Pre-flight: %s... ", check.name)
        if err := check.fn(); err != nil {
            fmt.Println("FAIL")
            return fmt.Errorf("%s: %w", check.name, err)
        }
        fmt.Println("OK")
    }

    return nil
}

func (v *Validator) checkPing() error {
    // Context first in runner.Run()
    _, err := v.runner.Run(v.ctx, v.cfg.Namespaces.Client,
        []string{"ping", "-c", "3", "-W", "2", v.cfg.Network.ServerIP})
    return err
}

func (v *Validator) measureBaseline() error {
    // Zero-load latency measurement for calibration
    output, err := v.runner.Run(v.ctx, v.cfg.Namespaces.Client,
        []string{"ping", "-c", "20", "-i", "0.1", v.cfg.Network.ServerIP})
    if err != nil {
        return err
    }

    // Parse and store baseline RTT
    // This will be subtracted from test results to isolate qdisc impact
    fmt.Printf("Baseline RTT: %s\n", parseRTT(output))
    return nil
}
```

---

## Configuration File (Enhanced)

```yaml
# config.yaml

namespaces:
  client: ns-gen-a
  server: ns-gen-b
  dut: ns-dut

interfaces:
  dut_ingress: enp66s0f0
  dut_egress: enp66s0f1

network:
  client_ip: 10.1.0.2
  server_ip: 10.2.0.2
  bandwidth: 10gbit

tools:
  - iperf2
  - iperf3
  - flent
  - crusader

matrix:
  qdiscs:
    - fq_codel
    - cake
    - mq-cake

  flow_counts:
    - 1
    - 10
    - 100
    - 500

  shuffle: true  # Randomize order to avoid thermal bias

timing:
  per_tool_duration: 30s
  cooldown_between_tests: 5s
  tool_startup_delay: 1s

telemetry:
  collect_cpu: true
  cpu_sample_interval: 1s
  collect_qdisc_stats: true

preflight:
  enabled: true
  measure_baseline: true

output:
  results_dir: /tmp/mq-cake-results
  format: both  # json, csv, or both
  include_raw_output: false
```

---

## Main Orchestrator

```go
// cmd/orchestrator/main.go

package main

import (
    "context"
    "fmt"
    "os"
    "os/signal"
    "sync"
    "syscall"
    "time"
)

func main() {
    cfg := config.Load("config.yaml")

    // ================================================================
    // CONTEXT: Create context that cancels on SIGINT or SIGTERM
    // This is the root context - passed to ALL components
    // ================================================================
    ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    defer stop()  // Deregister signal handling on exit

    // ================================================================
    // WAITGROUP: Single waitgroup for ALL goroutines
    // Created here in main, passed forward to all components
    // ================================================================
    var wg sync.WaitGroup

    // ================================================================
    // COMPONENTS: Initialize with ctx and &wg
    // ================================================================
    runner := &runner.LocalRunner{}
    manager := process.NewManager(runner, &wg)
    qc := qdisc.NewController(ctx, runner, cfg)  // ctx first

    // Pre-flight validation (uses ctx for cancellation)
    if cfg.Preflight.Enabled {
        validator := preflight.NewValidator(ctx, runner, cfg)
        if err := validator.Validate(); err != nil {
            fmt.Fprintf(os.Stderr, "Pre-flight failed: %v\n", err)
            os.Exit(1)
        }
    }

    // Build test matrix
    testPoints := matrix.BuildMatrix(cfg)
    fmt.Printf("Running %d test points\n", len(testPoints))

    tools := loadTools(cfg.Tools)
    var allResults []results.TestResult
    var currentQdisc string

    // ================================================================
    // MAIN LOOP: Run test matrix
    // ================================================================
    for i, tp := range testPoints {
        // Check for cancellation at start of each iteration
        select {
        case <-ctx.Done():
            fmt.Println("Test matrix interrupted")
            goto cleanup
        default:
        }

        fmt.Printf("[%d/%d] qdisc=%s flows=%d tool=%s\n",
            i+1, len(testPoints), tp.Qdisc, tp.FlowCount, tp.Tool)

        // Switch qdisc only when it changes
        if tp.Qdisc != currentQdisc {
            if err := qc.Set(ctx, tp.Qdisc); err != nil {  // ctx first
                fmt.Printf("ERROR: Failed to set qdisc: %v\n", err)
                continue
            }
            currentQdisc = tp.Qdisc
            time.Sleep(2 * time.Second)
        }

        // CPU telemetry goroutine (tracked by waitgroup)
        var cpuStats []*telemetry.CPUStats
        if cfg.Telemetry.CollectCPU {
            wg.Add(1)
            go func() {
                defer wg.Done()
                for s := range telemetry.CollectDuring(ctx, cfg.Telemetry.CPUSampleInterval) {
                    cpuStats = append(cpuStats, s)
                }
            }()
        }

        // Run tool (ctx first)
        tool := tools[tp.Tool]
        result, err := manager.RunTool(ctx, tool, cfg, tp.FlowCount)
        if err != nil {
            fmt.Printf("ERROR: %v\n", err)
            continue
        }

        testResult := results.TestResult{
            TestPoint:  tp,
            Result:     result,
            CPUStats:   cpuStats,
            QdiscStats: qc.GetStats(ctx),
        }
        allResults = append(allResults, testResult)

        time.Sleep(cfg.Timing.Cooldown)
    }

cleanup:
    // ================================================================
    // CLEANUP: Export results before waiting
    // ================================================================
    if len(allResults) > 0 {
        if err := results.Export(allResults, cfg.Output); err != nil {
            fmt.Printf("Failed to export results: %v\n", err)
        } else {
            fmt.Printf("Results saved to %s\n", cfg.Output.ResultsDir)
        }
    }

    // ================================================================
    // WAIT: Wait for all goroutines with timeout safety net
    // ================================================================
    done := make(chan struct{})
    go func() {
        wg.Wait()
        close(done)
    }()

    select {
    case <-done:
        fmt.Println("Graceful shutdown complete")
    case <-time.After(10 * time.Second):
        fmt.Println("Shutdown timed out after 10s")
    }
}
```

---

## Shutdown Flow

```
Signal (SIGINT/SIGTERM) received
         │
         ▼
    ctx cancelled
    (ctx.Done() closes)
         │
         ├────────────────────────────────────────────┐
         │                                            │
         ▼                                            ▼
  Main loop sees ctx.Done()               Tool shutdown watchers see ctx.Done()
  in select, jumps to cleanup             kill server processes
         │                                            │
         ▼                                            ▼
  results.Export() called                 runner.Start() returns
         │                                 manager.RunTool() returns error
         ▼                                            │
  Cleanup complete                                    │
         │                                            │
         ├────────────────────────────────────────────┘
         │
         ▼
  wg.Wait() (with 10s timeout)
         │
         ▼
  All goroutines exited
  (or timeout expires)
         │
         ▼
  main() exits
```

---

## WaitGroup Rules

| Rule | Example |
|------|---------|
| **Add() before `go func()`** | `wg.Add(1); go func() { defer wg.Done(); ... }()` |
| **Done() via defer** | First line inside goroutine: `defer wg.Done()` |
| **Never Add() inside goroutine** | Race condition - main might Wait() first |
| **Single waitgroup** | Created in main, passed as `*sync.WaitGroup` |

---

## Anti-Patterns to Avoid

```go
// ❌ WRONG: Add() inside goroutine (race condition)
go func() {
    wg.Add(1)  // main might call Wait() before this runs!
    defer wg.Done()
}()

// ❌ WRONG: Combining ctx.Done() with other channels
select {
case <-ctx.Done():
    return ctx.Err()
case result := <-resultCh:  // Go randomly picks - ctx check may be skipped!
    return result
}

// ✅ CORRECT: Check ctx.Done() FIRST, separately
select {
case <-ctx.Done():
    return ctx.Err()
default:
}
// Now safe to use other channels
result := <-resultCh

// ✅ CORRECT: Add() before go, Done() in defer
wg.Add(1)
go func() {
    defer wg.Done()
    // ... work ...
}()
```

---

## Nix Flake Integration

```nix
# flake.nix
{
  description = "MQ-CAKE Performance Testing Orchestrator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.buildGoModule {
          pname = "mq-cake-orchestrator";
          version = "0.1.0";
          src = ./.;
          vendorHash = null; # Update with: nix-prefetch { ... }

          # Ensure reproducible builds
          CGO_ENABLED = 0;
          ldflags = [ "-s" "-w" ];
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            go
            gopls
            golangci-lint

            # Test tools (pinned versions)
            iperf2
            iperf3
            flent
            netperf
            crusader
          ];
        };

        # NixOS module for the test environment
        nixosModules.default = { config, lib, pkgs, ... }: {
          options.services.mq-cake-test.enable = lib.mkEnableOption "MQ-CAKE test";

          config = lib.mkIf config.services.mq-cake-test.enable {
            environment.systemPackages = [
              self.packages.${system}.default
              pkgs.iperf2
              pkgs.iperf3
              pkgs.flent
              pkgs.netperf
              pkgs.crusader
            ];

            boot.kernelModules = [ "sch_cake" "sch_fq_codel" ];
          };
        };
      }
    );
}
```

---

## Running the Orchestrator

```bash
# Build with Nix Flake
nix build

# Or build manually
cd mq-cake-orchestrator
go build -o mq-cake-orchestrator ./cmd/orchestrator

# Setup test environment first
sudo mq-cake-setup
sudo mq-cake-verify

# Run full test suite
sudo ./mq-cake-orchestrator --config config.yaml

# Run subset (for debugging)
sudo ./mq-cake-orchestrator --config config.yaml \
  --qdiscs mq-cake \
  --flows 100,500 \
  --tools iperf2
```

---

## Output Schema

```json
{
  "metadata": {
    "start_time": "2025-02-15T12:00:00Z",
    "end_time": "2025-02-15T12:45:00Z",
    "host": "l2",
    "kernel": "6.6.18",
    "baseline_rtt_ms": 0.15
  },
  "results": [
    {
      "test_point": {
        "qdisc": "mq-cake",
        "flow_count": 500,
        "tool": "iperf2"
      },
      "result": {
        "throughput_gbps": 9.17,
        "latency_p50_ms": 32.1,
        "latency_p99_ms": 45.2,
        "packet_loss_pct": 0.0,
        "retransmits": 42
      },
      "cpu_stats": {
        "peak_core_pct": 78.5,
        "cores_above_90pct": 0,
        "distribution": "spread"
      },
      "qdisc_stats": {
        "drops": 0,
        "backlog_bytes": 1234
      }
    }
  ]
}
```

---

## Success Criteria

| Metric | fq_codel | cake | mq-cake | Target |
|--------|----------|------|---------|--------|
| Throughput @ 500 flows | baseline | may drop | >= baseline | mq-cake matches fq_codel |
| P99 latency @ 500 flows | <100ms | <100ms | <100ms | All qdiscs bounded |
| Peak CPU per core | spread | **1 core saturated** | spread | mq-cake spreads load |
| Qdisc drops | 0 | may have | 0 | No drops under test |

The key proof: **cake shows single-core saturation at high flow counts; mq-cake distributes across cores.**

---

## Troubleshooting

### Pre-flight fails

Run manual verification:
```bash
sudo mq-cake-verify
```

### Ctrl+C doesn't clean up

Kill orphaned processes:
```bash
pkill -f iperf
pkill -f netserver
pkill -f crusader
sudo mq-cake-teardown
```

### Results show unexpected latency

Check baseline measurement - high baseline indicates cable/NIC issues, not qdisc.
