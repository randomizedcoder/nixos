# Phase 4: Go Orchestrator - Implementation Plan

**Design Reference**: [phase-04-orchestrator.md](./phase-04-orchestrator.md)

**Prerequisites**: Phase 3 complete (manual load generation works with all tools and qdiscs)

**Overview**: Implement a Go program that automates the test matrix, manages load generators, collects metrics, and exports results.

**Log File**: [phase-04-orchestrator_log.md](./phase-04-orchestrator_log.md) (update on completion of each sub-phase)

---

## Project Structure

```
mq-cake-orchestrator/
├── cmd/
│   └── orchestrator/
│       └── main.go                 # Entry point with signal handling
├── internal/
│   ├── config/
│   │   └── config.go               # YAML config parsing
│   ├── runner/
│   │   ├── runner.go               # Runner interface
│   │   └── local.go                # LocalRunner (ip netns exec)
│   ├── process/
│   │   └── manager.go              # Process lifecycle management
│   ├── tools/
│   │   ├── tool.go                 # Tool interface + NormalizedResult
│   │   ├── iperf2.go               # iperf2 implementation
│   │   ├── iperf3.go               # iperf3 implementation
│   │   ├── flent.go                # flent implementation
│   │   ├── crusader.go             # crusader implementation
│   │   └── ping.go                 # Background latency probe
│   ├── matrix/
│   │   └── testpoint.go            # Test matrix builder
│   ├── qdisc/
│   │   └── controller.go           # Qdisc switching
│   ├── telemetry/
│   │   └── cpu.go                  # CPU stats from /proc/stat
│   ├── results/
│   │   ├── schema.go               # Result data structures
│   │   └── export.go               # JSON/CSV export
│   └── preflight/
│       └── validate.go             # Pre-flight checks
├── config.yaml                      # Default configuration
├── go.mod
├── go.sum
└── flake.nix                        # Nix Flake for building
```

---

## Sub-Phase 4.1: Initialize Go Module and Project Structure

### Steps

1. **Create directory structure**:
   ```bash
   mkdir -p mq-cake-orchestrator/{cmd/orchestrator,internal/{config,runner,process,tools,matrix,qdisc,telemetry,results,preflight}}
   cd mq-cake-orchestrator
   ```

2. **Initialize Go module**:
   ```bash
   go mod init github.com/randomizedcoder/mq-cake-orchestrator
   ```

3. **Create `cmd/orchestrator/main.go`** with minimal structure:
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
   )

   func main() {
       // Context with signal cancellation
       ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
       defer stop()

       // Single waitgroup for all goroutines
       var wg sync.WaitGroup

       fmt.Println("mq-cake-orchestrator starting...")

       // Wait for signal
       <-ctx.Done()
       fmt.Println("Shutdown signal received")

       // Wait for goroutines
       wg.Wait()
       fmt.Println("Shutdown complete")
   }
   ```

4. **Verify build**:
   ```bash
   go build -o mq-cake-orchestrator ./cmd/orchestrator
   ./mq-cake-orchestrator
   # Ctrl+C should trigger clean shutdown
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.1.1 | `go mod tidy` | No errors |
| 4.1.2 | `go build ./cmd/orchestrator` | Binary created |
| 4.1.3 | `./mq-cake-orchestrator` then Ctrl+C | Clean "Shutdown complete" |
| 4.1.4 | Directory structure matches plan | All dirs exist |

### Definition of Done

- [ ] Go module initialized
- [ ] Directory structure created
- [ ] main.go with signal handling compiles
- [ ] Clean shutdown on Ctrl+C
- [ ] Log file updated

---

## Sub-Phase 4.2: Implement Configuration (internal/config)

### Steps

1. **Create `internal/config/config.go`**:
   ```go
   // internal/config/config.go
   package config

   import (
       "os"
       "time"

       "gopkg.in/yaml.v3"
   )

   type Config struct {
       Namespaces  NamespaceConfig  `yaml:"namespaces"`
       Interfaces  InterfaceConfig  `yaml:"interfaces"`
       Network     NetworkConfig    `yaml:"network"`
       Tools       []string         `yaml:"tools"`
       Matrix      MatrixConfig     `yaml:"matrix"`
       Timing      TimingConfig     `yaml:"timing"`
       Telemetry   TelemetryConfig  `yaml:"telemetry"`
       Preflight   PreflightConfig  `yaml:"preflight"`
       Output      OutputConfig     `yaml:"output"`
   }

   type NamespaceConfig struct {
       Client string `yaml:"client"`
       Server string `yaml:"server"`
       DUT    string `yaml:"dut"`
   }

   type InterfaceConfig struct {
       DUTIngress string `yaml:"dut_ingress"`
       DUTEgress  string `yaml:"dut_egress"`
   }

   type NetworkConfig struct {
       ClientIP  string `yaml:"client_ip"`
       ServerIP  string `yaml:"server_ip"`
       Bandwidth string `yaml:"bandwidth"`
   }

   type MatrixConfig struct {
       Qdiscs     []string `yaml:"qdiscs"`
       FlowCounts []int    `yaml:"flow_counts"`
       Shuffle    bool     `yaml:"shuffle"`
   }

   type TimingConfig struct {
       PerToolDuration  time.Duration `yaml:"per_tool_duration"`
       Cooldown         time.Duration `yaml:"cooldown_between_tests"`
       ToolStartupDelay time.Duration `yaml:"tool_startup_delay"`
   }

   type TelemetryConfig struct {
       CollectCPU        bool          `yaml:"collect_cpu"`
       CPUSampleInterval time.Duration `yaml:"cpu_sample_interval"`
       CollectQdiscStats bool          `yaml:"collect_qdisc_stats"`
   }

   type PreflightConfig struct {
       Enabled         bool `yaml:"enabled"`
       MeasureBaseline bool `yaml:"measure_baseline"`
   }

   type OutputConfig struct {
       ResultsDir       string `yaml:"results_dir"`
       Format           string `yaml:"format"` // json, csv, both
       IncludeRawOutput bool   `yaml:"include_raw_output"`
   }

   // Load reads and parses the YAML configuration file
   func Load(path string) (*Config, error) {
       data, err := os.ReadFile(path)
       if err != nil {
           return nil, err
       }

       var cfg Config
       if err := yaml.Unmarshal(data, &cfg); err != nil {
           return nil, err
       }

       // Set defaults
       if cfg.Timing.PerToolDuration == 0 {
           cfg.Timing.PerToolDuration = 30 * time.Second
       }
       if cfg.Timing.Cooldown == 0 {
           cfg.Timing.Cooldown = 5 * time.Second
       }
       if cfg.Timing.ToolStartupDelay == 0 {
           cfg.Timing.ToolStartupDelay = 1 * time.Second
       }
       if cfg.Output.ResultsDir == "" {
           cfg.Output.ResultsDir = "/tmp/mq-cake-results"
       }

       return &cfg, nil
   }
   ```

2. **Create `config.yaml`**:
   ```yaml
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
     shuffle: true

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
     format: both
     include_raw_output: false
   ```

3. **Add yaml dependency**:
   ```bash
   go get gopkg.in/yaml.v3
   ```

4. **Update main.go to load config**:
   ```go
   import "github.com/randomizedcoder/mq-cake-orchestrator/internal/config"

   func main() {
       cfg, err := config.Load("config.yaml")
       if err != nil {
           fmt.Fprintf(os.Stderr, "Failed to load config: %v\n", err)
           os.Exit(1)
       }
       fmt.Printf("Loaded config: %d tools, %d qdiscs, %d flow counts\n",
           len(cfg.Tools), len(cfg.Matrix.Qdiscs), len(cfg.Matrix.FlowCounts))
       // ...
   }
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.2.1 | `go build ./...` | Compiles |
| 4.2.2 | `./mq-cake-orchestrator` with config.yaml | Loads config, prints stats |
| 4.2.3 | Missing config.yaml | Error message |
| 4.2.4 | Malformed YAML | Parse error |

### Definition of Done

- [ ] Config struct defined with all fields
- [ ] YAML parsing works
- [ ] Defaults applied for missing values
- [ ] main.go loads and uses config
- [ ] Log file updated

---

## Sub-Phase 4.3: Implement Runner Interface (internal/runner)

### Steps

1. **Create `internal/runner/runner.go`**:
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
       Pid() int
   }
   ```

2. **Create `internal/runner/local.go`**:
   ```go
   // internal/runner/local.go
   package runner

   import (
       "bytes"
       "context"
       "fmt"
       "io"
       "os/exec"
       "syscall"
   )

   // LocalRunner executes commands via ip netns exec
   type LocalRunner struct{}

   // NewLocalRunner creates a new LocalRunner
   func NewLocalRunner() *LocalRunner {
       return &LocalRunner{}
   }

   // Run executes a command in a namespace and waits for completion
   func (r *LocalRunner) Run(ctx context.Context, namespace string, cmd []string) (string, error) {
       args := append([]string{"netns", "exec", namespace}, cmd...)
       c := exec.CommandContext(ctx, "ip", args...)

       // Set process group for clean termination
       c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

       out, err := c.CombinedOutput()
       return string(out), err
   }

   // Start executes a command in background
   func (r *LocalRunner) Start(ctx context.Context, namespace string, cmd []string) (Process, error) {
       args := append([]string{"netns", "exec", namespace}, cmd...)
       c := exec.CommandContext(ctx, "ip", args...)
       c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

       var stdout, stderr bytes.Buffer
       c.Stdout = &stdout
       c.Stderr = &stderr

       if err := c.Start(); err != nil {
           return nil, fmt.Errorf("failed to start: %w", err)
       }

       return &localProcess{
           cmd:    c,
           stdout: &stdout,
           stderr: &stderr,
       }, nil
   }

   type localProcess struct {
       cmd    *exec.Cmd
       stdout *bytes.Buffer
       stderr *bytes.Buffer
   }

   func (p *localProcess) Wait() error {
       return p.cmd.Wait()
   }

   func (p *localProcess) Kill() error {
       if p.cmd.Process == nil {
           return nil
       }
       // Kill entire process group to prevent zombies
       return syscall.Kill(-p.cmd.Process.Pid, syscall.SIGKILL)
   }

   func (p *localProcess) Stdout() io.Reader {
       return p.stdout
   }

   func (p *localProcess) Stderr() io.Reader {
       return p.stderr
   }

   func (p *localProcess) Pid() int {
       if p.cmd.Process == nil {
           return 0
       }
       return p.cmd.Process.Pid
   }
   ```

3. **Test runner**:
   ```go
   // In main.go temporarily:
   r := runner.NewLocalRunner()
   out, err := r.Run(ctx, "ns-gen-a", []string{"ip", "addr", "show"})
   fmt.Println(out, err)
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.3.1 | `go build ./...` | Compiles |
| 4.3.2 | `sudo ./mq-cake-orchestrator` (with test code) | Runs ip addr in namespace |
| 4.3.3 | Start/Kill process | Clean termination |
| 4.3.4 | Context cancellation | Process killed |

### Definition of Done

- [ ] Runner interface defined
- [ ] LocalRunner implements interface
- [ ] Run() executes commands in namespace
- [ ] Start() launches background processes
- [ ] Kill() kills process group
- [ ] Log file updated

---

## Sub-Phase 4.4: Implement Tool Interface (internal/tools)

### Steps

1. **Create `internal/tools/tool.go`**:
   ```go
   // internal/tools/tool.go
   package tools

   import (
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
   ```

2. **Create `internal/tools/iperf2.go`**:
   ```go
   // internal/tools/iperf2.go
   package tools

   import (
       "fmt"
       "regexp"
       "strconv"
       "strings"
       "time"
   )

   type Iperf2 struct{}

   func NewIperf2() *Iperf2 {
       return &Iperf2{}
   }

   func (t *Iperf2) Name() string {
       return "iperf2"
   }

   func (t *Iperf2) ServerCmd(port int) []string {
       return []string{"iperf", "-s", "-p", strconv.Itoa(port)}
   }

   func (t *Iperf2) ClientCmd(target string, port int, flows int, duration time.Duration) []string {
       return []string{
           "iperf",
           "-c", target,
           "-p", strconv.Itoa(port),
           "-P", strconv.Itoa(flows),
           "-t", strconv.Itoa(int(duration.Seconds())),
           "-i", "1",
       }
   }

   func (t *Iperf2) Parse(output string, flows int, duration time.Duration) (*NormalizedResult, error) {
       result := &NormalizedResult{
           Tool:      t.Name(),
           Timestamp: time.Now(),
           Duration:  duration,
           FlowCount: flows,
       }

       // Parse [SUM] line for aggregate throughput
       // Example: [SUM]  0.0-30.0 sec  25.8 GBytes  7.38 Gbits/sec
       sumRe := regexp.MustCompile(`\[SUM\].*?(\d+\.?\d*)\s+(G|M|K)?bits/sec`)
       matches := sumRe.FindStringSubmatch(output)
       if len(matches) >= 2 {
           val, _ := strconv.ParseFloat(matches[1], 64)
           unit := ""
           if len(matches) >= 3 {
               unit = matches[2]
           }
           switch unit {
           case "G":
               result.ThroughputGbps = val
           case "M":
               result.ThroughputGbps = val / 1000
           case "K":
               result.ThroughputGbps = val / 1000000
           default:
               result.ThroughputGbps = val / 1000000000
           }
       }

       result.RawOutput = output
       return result, nil
   }

   func (t *Iperf2) SupportsFlowCount() bool {
       return true
   }

   func (t *Iperf2) DefaultPort() int {
       return 5001
   }
   ```

3. **Create `internal/tools/iperf3.go`**:
   ```go
   // internal/tools/iperf3.go
   package tools

   import (
       "encoding/json"
       "strconv"
       "time"
   )

   type Iperf3 struct{}

   func NewIperf3() *Iperf3 {
       return &Iperf3{}
   }

   func (t *Iperf3) Name() string {
       return "iperf3"
   }

   func (t *Iperf3) ServerCmd(port int) []string {
       return []string{"iperf3", "-s", "-p", strconv.Itoa(port)}
   }

   func (t *Iperf3) ClientCmd(target string, port int, flows int, duration time.Duration) []string {
       // Cap at 128 streams (iperf3 limit)
       if flows > 128 {
           flows = 128
       }
       return []string{
           "iperf3",
           "-c", target,
           "-p", strconv.Itoa(port),
           "-P", strconv.Itoa(flows),
           "-t", strconv.Itoa(int(duration.Seconds())),
           "--json",
       }
   }

   func (t *Iperf3) Parse(output string, flows int, duration time.Duration) (*NormalizedResult, error) {
       result := &NormalizedResult{
           Tool:      t.Name(),
           Timestamp: time.Now(),
           Duration:  duration,
           FlowCount: flows,
       }

       // Parse JSON output
       var data struct {
           End struct {
               SumReceived struct {
                   BitsPerSecond float64 `json:"bits_per_second"`
               } `json:"sum_received"`
               Streams []struct {
                   Sender struct {
                       Retransmits int64 `json:"retransmits"`
                   } `json:"sender"`
               } `json:"streams"`
           } `json:"end"`
       }

       if err := json.Unmarshal([]byte(output), &data); err != nil {
           result.RawOutput = output
           return result, nil // Return partial result on parse error
       }

       result.ThroughputGbps = data.End.SumReceived.BitsPerSecond / 1e9

       for _, stream := range data.End.Streams {
           result.Retransmits += stream.Sender.Retransmits
       }

       return result, nil
   }

   func (t *Iperf3) SupportsFlowCount() bool {
       return true
   }

   func (t *Iperf3) DefaultPort() int {
       return 5201
   }
   ```

4. **Create stubs for flent and crusader** (similar pattern)

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.4.1 | `go build ./...` | Compiles |
| 4.4.2 | Unit test: iperf2 ServerCmd | Returns correct args |
| 4.4.3 | Unit test: iperf2 Parse | Extracts throughput |
| 4.4.4 | Unit test: iperf3 Parse JSON | Extracts throughput |

### Definition of Done

- [ ] Tool interface defined
- [ ] NormalizedResult struct complete
- [ ] Iperf2 implementation with parser
- [ ] Iperf3 implementation with JSON parser
- [ ] Flent stub implementation
- [ ] Crusader stub implementation
- [ ] Log file updated

---

## Sub-Phase 4.5: Implement Test Matrix (internal/matrix)

### Steps

1. **Create `internal/matrix/testpoint.go`**:
   ```go
   // internal/matrix/testpoint.go
   package matrix

   import (
       "math/rand"
       "time"

       "github.com/randomizedcoder/mq-cake-orchestrator/internal/config"
   )

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

       if cfg.Matrix.Shuffle {
           rand.Shuffle(len(points), func(i, j int) {
               points[i], points[j] = points[j], points[i]
           })
       }

       return points
   }

   // CountTestPoints returns total test count without building
   func CountTestPoints(cfg *config.Config) int {
       return len(cfg.Matrix.Qdiscs) * len(cfg.Matrix.FlowCounts) * len(cfg.Tools)
   }
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.5.1 | `go build ./...` | Compiles |
| 4.5.2 | Unit test: 3 qdiscs × 4 flows × 4 tools = 48 | Correct count |
| 4.5.3 | Shuffle disabled | Same order each run |
| 4.5.4 | Shuffle enabled | Different order |

### Definition of Done

- [ ] TestPoint struct defined
- [ ] BuildMatrix generates all combinations
- [ ] Shuffle option works
- [ ] Log file updated

---

## Sub-Phase 4.6: Implement Qdisc Controller (internal/qdisc)

### Steps

1. **Create `internal/qdisc/controller.go`**:
   ```go
   // internal/qdisc/controller.go
   package qdisc

   import (
       "context"
       "fmt"
       "strings"

       "github.com/randomizedcoder/mq-cake-orchestrator/internal/config"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/runner"
   )

   // Controller manages qdisc configuration on DUT interfaces
   type Controller struct {
       runner     runner.Runner
       cfg        *config.Config
       currentQdisc string
   }

   // NewController creates a new qdisc controller
   func NewController(r runner.Runner, cfg *config.Config) *Controller {
       return &Controller{
           runner: r,
           cfg:    cfg,
       }
   }

   // Set configures the specified qdisc on both DUT interfaces
   func (c *Controller) Set(ctx context.Context, qdisc string) error {
       // Check context first
       select {
       case <-ctx.Done():
           return ctx.Err()
       default:
       }

       interfaces := []string{c.cfg.Interfaces.DUTIngress, c.cfg.Interfaces.DUTEgress}

       for _, iface := range interfaces {
           var cmd []string

           switch qdisc {
           case "fq_codel":
               cmd = []string{"tc", "qdisc", "replace", "dev", iface, "root", "fq_codel"}

           case "cake":
               cmd = []string{
                   "tc", "qdisc", "replace", "dev", iface, "root", "cake",
                   "bandwidth", c.cfg.Network.Bandwidth,
                   "diffserv4", "nat", "wash", "split-gso",
               }

           case "mq-cake", "cake_mq":
               // Try native cake_mq first
               cmd = []string{
                   "tc", "qdisc", "replace", "dev", iface, "root", "cake_mq",
                   "bandwidth", c.cfg.Network.Bandwidth,
                   "diffserv4", "nat", "wash", "split-gso",
               }
               _, err := c.runner.Run(ctx, c.cfg.Namespaces.DUT, cmd)
               if err != nil {
                   // Fallback to mq + cake
                   return c.setMQFallback(ctx, iface)
               }
               continue

           default:
               return fmt.Errorf("unknown qdisc: %s", qdisc)
           }

           if _, err := c.runner.Run(ctx, c.cfg.Namespaces.DUT, cmd); err != nil {
               return fmt.Errorf("failed to set %s on %s: %w", qdisc, iface, err)
           }
       }

       c.currentQdisc = qdisc
       return nil
   }

   func (c *Controller) setMQFallback(ctx context.Context, iface string) error {
       // Set mq as root
       cmd := []string{"tc", "qdisc", "replace", "dev", iface, "root", "mq"}
       if _, err := c.runner.Run(ctx, c.cfg.Namespaces.DUT, cmd); err != nil {
           return fmt.Errorf("mq fallback failed: %w", err)
       }
       // Note: Adding per-queue cake would require queue enumeration
       return nil
   }

   // Current returns the currently configured qdisc
   func (c *Controller) Current() string {
       return c.currentQdisc
   }

   // GetStats retrieves qdisc statistics
   func (c *Controller) GetStats(ctx context.Context) (map[string]string, error) {
       stats := make(map[string]string)

       for _, iface := range []string{c.cfg.Interfaces.DUTIngress, c.cfg.Interfaces.DUTEgress} {
           cmd := []string{"tc", "-s", "qdisc", "show", "dev", iface}
           out, err := c.runner.Run(ctx, c.cfg.Namespaces.DUT, cmd)
           if err != nil {
               return nil, err
           }
           stats[iface] = out
       }

       return stats, nil
   }
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.6.1 | `go build ./...` | Compiles |
| 4.6.2 | Integration: Set fq_codel | tc shows fq_codel |
| 4.6.3 | Integration: Set cake | tc shows cake with options |
| 4.6.4 | Integration: Set mq-cake | tc shows mq-cake or fallback |
| 4.6.5 | GetStats returns output | Non-empty stats |

### Definition of Done

- [ ] Controller struct implemented
- [ ] Set() configures all three qdiscs
- [ ] mq-cake fallback works
- [ ] GetStats() retrieves statistics
- [ ] Log file updated

---

## Sub-Phase 4.7: Implement Process Manager (internal/process)

### Steps

1. **Create `internal/process/manager.go`**:
   ```go
   // internal/process/manager.go
   package process

   import (
       "context"
       "fmt"
       "sync"
       "time"

       "github.com/randomizedcoder/mq-cake-orchestrator/internal/config"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/runner"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/tools"
   )

   // Manager handles tool execution with proper lifecycle management
   type Manager struct {
       runner runner.Runner
       wg     *sync.WaitGroup
       cfg    *config.Config
   }

   // NewManager creates a new process manager
   func NewManager(r runner.Runner, wg *sync.WaitGroup, cfg *config.Config) *Manager {
       return &Manager{
           runner: r,
           wg:     wg,
           cfg:    cfg,
       }
   }

   // RunTool executes a tool with proper server/client lifecycle
   func (m *Manager) RunTool(
       ctx context.Context,
       tool tools.Tool,
       flows int,
   ) (*tools.NormalizedResult, error) {
       // Check context FIRST
       select {
       case <-ctx.Done():
           return nil, ctx.Err()
       default:
       }

       // Create timeout context for this tool run
       timeout := m.cfg.Timing.PerToolDuration + 30*time.Second
       toolCtx, cancel := context.WithTimeout(ctx, timeout)
       defer cancel()

       port := tool.DefaultPort()

       // Start server
       serverProc, err := m.runner.Start(
           toolCtx,
           m.cfg.Namespaces.Server,
           tool.ServerCmd(port),
       )
       if err != nil {
           return nil, fmt.Errorf("server start failed: %w", err)
       }

       // Ensure server cleanup on any exit
       defer serverProc.Kill()

       // Watch for cancellation
       go func() {
           <-toolCtx.Done()
           serverProc.Kill()
       }()

       // Wait for server startup
       time.Sleep(m.cfg.Timing.ToolStartupDelay)

       // Run client
       output, err := m.runner.Run(
           toolCtx,
           m.cfg.Namespaces.Client,
           tool.ClientCmd(m.cfg.Network.ServerIP, port, flows, m.cfg.Timing.PerToolDuration),
       )
       if err != nil {
           return nil, fmt.Errorf("client failed: %w", err)
       }

       return tool.Parse(output, flows, m.cfg.Timing.PerToolDuration)
   }
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.7.1 | `go build ./...` | Compiles |
| 4.7.2 | Integration: RunTool with iperf2 | Result returned |
| 4.7.3 | Context cancellation | Server killed, error returned |
| 4.7.4 | No zombie processes | `pgrep iperf` empty after test |

### Definition of Done

- [ ] Manager coordinates server/client lifecycle
- [ ] Context cancellation kills processes
- [ ] Timeout prevents hung tests
- [ ] No zombie processes
- [ ] Log file updated

---

## Sub-Phase 4.8: Implement Telemetry Collection (internal/telemetry)

### Steps

1. **Create `internal/telemetry/cpu.go`**:
   ```go
   // internal/telemetry/cpu.go
   package telemetry

   import (
       "bufio"
       "context"
       "os"
       "strconv"
       "strings"
       "time"
   )

   // CPUStats holds CPU usage data
   type CPUStats struct {
       Timestamp time.Time
       PerCore   []CoreStats
       Total     CoreStats
   }

   // CoreStats holds per-core CPU counters
   type CoreStats struct {
       Core   int
       User   uint64
       System uint64
       Idle   uint64
   }

   // CollectCPUStats reads /proc/stat and returns current CPU counters
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
           if !strings.HasPrefix(line, "cpu") {
               continue
           }

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

       return stats, nil
   }

   // Collector periodically collects CPU stats
   type Collector struct {
       interval time.Duration
       samples  []*CPUStats
   }

   // NewCollector creates a CPU stats collector
   func NewCollector(interval time.Duration) *Collector {
       return &Collector{interval: interval}
   }

   // CollectDuring collects CPU stats for the duration of the context
   func (c *Collector) CollectDuring(ctx context.Context) []*CPUStats {
       ticker := time.NewTicker(c.interval)
       defer ticker.Stop()

       var samples []*CPUStats

       for {
           select {
           case <-ctx.Done():
               return samples
           case <-ticker.C:
               if stats, err := CollectCPUStats(); err == nil {
                   samples = append(samples, stats)
               }
           }
       }
   }
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.8.1 | `go build ./...` | Compiles |
| 4.8.2 | Unit test: CollectCPUStats | Returns valid data |
| 4.8.3 | Integration: CollectDuring 5s | Multiple samples |

### Definition of Done

- [ ] CPU stats collection from /proc/stat
- [ ] Per-core stats available
- [ ] Periodic collection via CollectDuring
- [ ] Log file updated

---

## Sub-Phase 4.9: Implement Results Export (internal/results)

### Steps

1. **Create `internal/results/schema.go`**:
   ```go
   // internal/results/schema.go
   package results

   import (
       "time"

       "github.com/randomizedcoder/mq-cake-orchestrator/internal/matrix"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/telemetry"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/tools"
   )

   // TestRun represents a complete test run
   type TestRun struct {
       Metadata Metadata     `json:"metadata"`
       Results  []TestResult `json:"results"`
   }

   // Metadata contains run-level information
   type Metadata struct {
       StartTime     time.Time `json:"start_time"`
       EndTime       time.Time `json:"end_time"`
       Host          string    `json:"host"`
       Kernel        string    `json:"kernel"`
       BaselineRTTMs float64   `json:"baseline_rtt_ms"`
   }

   // TestResult combines test config with results
   type TestResult struct {
       TestPoint  matrix.TestPoint         `json:"test_point"`
       Result     *tools.NormalizedResult  `json:"result"`
       CPUStats   []*telemetry.CPUStats    `json:"cpu_stats,omitempty"`
       QdiscStats map[string]string        `json:"qdisc_stats,omitempty"`
   }
   ```

2. **Create `internal/results/export.go`**:
   ```go
   // internal/results/export.go
   package results

   import (
       "encoding/csv"
       "encoding/json"
       "fmt"
       "os"
       "path/filepath"
       "time"

       "github.com/randomizedcoder/mq-cake-orchestrator/internal/config"
   )

   // Export writes results to disk
   func Export(run *TestRun, cfg *config.OutputConfig) error {
       if err := os.MkdirAll(cfg.ResultsDir, 0755); err != nil {
           return err
       }

       timestamp := time.Now().Format("20060102-150405")
       baseName := filepath.Join(cfg.ResultsDir, "results-"+timestamp)

       if cfg.Format == "json" || cfg.Format == "both" {
           if err := exportJSON(run, baseName+".json"); err != nil {
               return err
           }
       }

       if cfg.Format == "csv" || cfg.Format == "both" {
           if err := exportCSV(run, baseName+".csv"); err != nil {
               return err
           }
       }

       return nil
   }

   func exportJSON(run *TestRun, path string) error {
       f, err := os.Create(path)
       if err != nil {
           return err
       }
       defer f.Close()

       enc := json.NewEncoder(f)
       enc.SetIndent("", "  ")
       return enc.Encode(run)
   }

   func exportCSV(run *TestRun, path string) error {
       f, err := os.Create(path)
       if err != nil {
           return err
       }
       defer f.Close()

       w := csv.NewWriter(f)
       defer w.Flush()

       // Header
       w.Write([]string{
           "qdisc", "flow_count", "tool", "duration_s",
           "throughput_gbps", "latency_p50_ms", "latency_p99_ms",
           "packet_loss_pct", "retransmits",
       })

       for _, r := range run.Results {
           if r.Result == nil {
               continue
           }
           w.Write([]string{
               r.TestPoint.Qdisc,
               fmt.Sprintf("%d", r.TestPoint.FlowCount),
               r.TestPoint.Tool,
               fmt.Sprintf("%.0f", r.TestPoint.Duration.Seconds()),
               fmt.Sprintf("%.3f", r.Result.ThroughputGbps),
               fmt.Sprintf("%.2f", r.Result.LatencyP50Ms),
               fmt.Sprintf("%.2f", r.Result.LatencyP99Ms),
               fmt.Sprintf("%.2f", r.Result.PacketLossPct),
               fmt.Sprintf("%d", r.Result.Retransmits),
           })
       }

       return nil
   }
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.9.1 | `go build ./...` | Compiles |
| 4.9.2 | Export JSON | Valid JSON file created |
| 4.9.3 | Export CSV | Valid CSV with headers |
| 4.9.4 | Export both | Both files created |

### Definition of Done

- [ ] TestRun/TestResult structs defined
- [ ] JSON export works
- [ ] CSV export works
- [ ] Directory created if missing
- [ ] Log file updated

---

## Sub-Phase 4.10: Implement Pre-flight Validation (internal/preflight)

### Steps

1. **Create `internal/preflight/validate.go`**:
   ```go
   // internal/preflight/validate.go
   package preflight

   import (
       "context"
       "fmt"
       "regexp"
       "strconv"
       "strings"

       "github.com/randomizedcoder/mq-cake-orchestrator/internal/config"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/runner"
   )

   // Validator performs pre-flight checks
   type Validator struct {
       runner      runner.Runner
       cfg         *config.Config
       BaselineRTT float64
   }

   // NewValidator creates a validator
   func NewValidator(r runner.Runner, cfg *config.Config) *Validator {
       return &Validator{runner: r, cfg: cfg}
   }

   // Validate runs all pre-flight checks
   func (v *Validator) Validate(ctx context.Context) error {
       checks := []struct {
           name string
           fn   func(context.Context) error
       }{
           {"namespaces exist", v.checkNamespaces},
           {"interfaces present", v.checkInterfaces},
           {"forwarding enabled", v.checkForwarding},
           {"end-to-end ping", v.checkPing},
           {"tools available", v.checkTools},
       }

       if v.cfg.Preflight.MeasureBaseline {
           checks = append(checks, struct {
               name string
               fn   func(context.Context) error
           }{"baseline latency", v.measureBaseline})
       }

       for _, check := range checks {
           select {
           case <-ctx.Done():
               return ctx.Err()
           default:
           }

           fmt.Printf("Pre-flight: %s... ", check.name)
           if err := check.fn(ctx); err != nil {
               fmt.Println("FAIL")
               return fmt.Errorf("%s: %w", check.name, err)
           }
           fmt.Println("OK")
       }

       return nil
   }

   func (v *Validator) checkNamespaces(ctx context.Context) error {
       out, err := v.runner.Run(ctx, v.cfg.Namespaces.Client, []string{"true"})
       if err != nil {
           return fmt.Errorf("namespace %s not accessible: %w", v.cfg.Namespaces.Client, err)
       }
       return nil
   }

   func (v *Validator) checkInterfaces(ctx context.Context) error {
       cmd := []string{"ip", "link", "show", v.cfg.Interfaces.DUTIngress}
       _, err := v.runner.Run(ctx, v.cfg.Namespaces.DUT, cmd)
       return err
   }

   func (v *Validator) checkForwarding(ctx context.Context) error {
       cmd := []string{"sysctl", "-n", "net.ipv4.ip_forward"}
       out, err := v.runner.Run(ctx, v.cfg.Namespaces.DUT, cmd)
       if err != nil {
           return err
       }
       if strings.TrimSpace(out) != "1" {
           return fmt.Errorf("ip_forward=%s, expected 1", strings.TrimSpace(out))
       }
       return nil
   }

   func (v *Validator) checkPing(ctx context.Context) error {
       cmd := []string{"ping", "-c", "3", "-W", "2", v.cfg.Network.ServerIP}
       _, err := v.runner.Run(ctx, v.cfg.Namespaces.Client, cmd)
       return err
   }

   func (v *Validator) checkTools(ctx context.Context) error {
       tools := []string{"iperf", "iperf3", "netperf", "crusader"}
       for _, tool := range tools {
           cmd := []string{"which", tool}
           if _, err := v.runner.Run(ctx, v.cfg.Namespaces.Client, cmd); err != nil {
               return fmt.Errorf("%s not found", tool)
           }
       }
       return nil
   }

   func (v *Validator) measureBaseline(ctx context.Context) error {
       cmd := []string{"ping", "-c", "20", "-i", "0.1", v.cfg.Network.ServerIP}
       out, err := v.runner.Run(ctx, v.cfg.Namespaces.Client, cmd)
       if err != nil {
           return err
       }

       // Parse rtt min/avg/max/mdev = 0.045/0.052/0.085/0.012 ms
       re := regexp.MustCompile(`rtt min/avg/max/mdev = ([\d.]+)/([\d.]+)`)
       matches := re.FindStringSubmatch(out)
       if len(matches) >= 3 {
           v.BaselineRTT, _ = strconv.ParseFloat(matches[2], 64)
           fmt.Printf("(%.3fms) ", v.BaselineRTT)
       }

       return nil
   }
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.10.1 | `go build ./...` | Compiles |
| 4.10.2 | Integration: Validate with setup | All checks pass |
| 4.10.3 | Validate without setup | Fails appropriately |
| 4.10.4 | Baseline RTT measured | Non-zero value |

### Definition of Done

- [ ] All pre-flight checks implemented
- [ ] Baseline RTT captured
- [ ] Clear error messages on failure
- [ ] Log file updated

---

## Sub-Phase 4.11: Integrate Main Orchestration Loop

### Steps

1. **Complete `cmd/orchestrator/main.go`**:
   ```go
   // cmd/orchestrator/main.go
   package main

   import (
       "context"
       "flag"
       "fmt"
       "os"
       "os/signal"
       "sync"
       "syscall"
       "time"

       "github.com/randomizedcoder/mq-cake-orchestrator/internal/config"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/matrix"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/preflight"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/process"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/qdisc"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/results"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/runner"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/telemetry"
       "github.com/randomizedcoder/mq-cake-orchestrator/internal/tools"
   )

   func main() {
       configPath := flag.String("config", "config.yaml", "Path to config file")
       flag.Parse()

       cfg, err := config.Load(*configPath)
       if err != nil {
           fmt.Fprintf(os.Stderr, "Config error: %v\n", err)
           os.Exit(1)
       }

       // Root context with signal cancellation
       ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
       defer stop()

       // Single waitgroup for all goroutines
       var wg sync.WaitGroup

       // Initialize components
       r := runner.NewLocalRunner()
       manager := process.NewManager(r, &wg, cfg)
       qc := qdisc.NewController(r, cfg)

       // Pre-flight validation
       if cfg.Preflight.Enabled {
           validator := preflight.NewValidator(r, cfg)
           if err := validator.Validate(ctx); err != nil {
               fmt.Fprintf(os.Stderr, "Pre-flight failed: %v\n", err)
               os.Exit(1)
           }
       }

       // Build test matrix
       testPoints := matrix.BuildMatrix(cfg)
       fmt.Printf("Running %d test points\n\n", len(testPoints))

       // Initialize tools
       toolMap := map[string]tools.Tool{
           "iperf2":   tools.NewIperf2(),
           "iperf3":   tools.NewIperf3(),
           // Add flent, crusader
       }

       // Run test matrix
       run := &results.TestRun{
           Metadata: results.Metadata{
               StartTime: time.Now(),
           },
       }

       var currentQdisc string

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
               if err := qc.Set(ctx, tp.Qdisc); err != nil {
                   fmt.Printf("  ERROR: qdisc switch failed: %v\n", err)
                   continue
               }
               currentQdisc = tp.Qdisc
               time.Sleep(2 * time.Second)
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

           run.Results = append(run.Results, results.TestResult{
               TestPoint: tp,
               Result:    result,
           })

           time.Sleep(cfg.Timing.Cooldown)
       }

   export:
       run.Metadata.EndTime = time.Now()

       if len(run.Results) > 0 {
           if err := results.Export(run, &cfg.Output); err != nil {
               fmt.Printf("Export failed: %v\n", err)
           } else {
               fmt.Printf("\nResults saved to %s\n", cfg.Output.ResultsDir)
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
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.11.1 | `go build ./...` | Compiles |
| 4.11.2 | `sudo ./mq-cake-orchestrator` | Runs test matrix |
| 4.11.3 | Ctrl+C during run | Clean shutdown, partial results saved |
| 4.11.4 | Results files created | JSON and/or CSV exist |

### Definition of Done

- [ ] Full orchestration loop works
- [ ] Pre-flight runs first
- [ ] Qdisc switching integrated
- [ ] Results exported
- [ ] Clean shutdown on Ctrl+C
- [ ] Log file updated

---

## Sub-Phase 4.12: Create Nix Flake for Building

### Steps

1. **Create `flake.nix`** in mq-cake-orchestrator/:
   ```nix
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
             vendorHash = null;  # Update after go mod vendor

             CGO_ENABLED = 0;
             ldflags = [ "-s" "-w" ];

             meta = with pkgs.lib; {
               description = "MQ-CAKE qdisc performance testing orchestrator";
               license = licenses.mit;
             };
           };

           devShells.default = pkgs.mkShell {
             buildInputs = with pkgs; [
               go
               gopls
               golangci-lint
             ];
           };
         }
       );
   }
   ```

2. **Build with Nix**:
   ```bash
   cd mq-cake-orchestrator
   nix build
   ./result/bin/mq-cake-orchestrator --help
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.12.1 | `nix flake check` | No errors |
| 4.12.2 | `nix build` | Binary in result/ |
| 4.12.3 | `nix develop` | Dev shell with Go tools |

### Definition of Done

- [ ] flake.nix builds orchestrator
- [ ] Dev shell works
- [ ] Binary is statically linked (CGO_ENABLED=0)
- [ ] Log file updated

---

## Sub-Phase 4.13: Integration Test - Full Test Run

### Steps

1. **Setup test environment**:
   ```bash
   sudo mq-cake-teardown
   sudo mq-cake-setup
   sudo mq-cake-verify
   ```

2. **Run orchestrator with reduced matrix**:
   ```bash
   # Edit config.yaml to use shorter durations for testing
   # per_tool_duration: 10s
   # flow_counts: [1, 10]
   # tools: [iperf2]

   sudo ./mq-cake-orchestrator
   ```

3. **Verify results**:
   ```bash
   cat /tmp/mq-cake-results/results-*.json | jq .
   cat /tmp/mq-cake-results/results-*.csv
   ```

4. **Run full matrix**:
   ```bash
   # Restore config.yaml to full settings
   sudo ./mq-cake-orchestrator
   ```

5. **Verify no zombies**:
   ```bash
   pgrep -f iperf
   pgrep -f netserver
   pgrep -f crusader
   # All should be empty
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 4.13.1 | Pre-flight passes | All checks OK |
| 4.13.2 | Reduced matrix completes | All test points run |
| 4.13.3 | JSON results valid | jq parses successfully |
| 4.13.4 | CSV results valid | Correct columns |
| 4.13.5 | No zombie processes | pgrep returns empty |
| 4.13.6 | Ctrl+C shutdown | Partial results saved |
| 4.13.7 | Full matrix (optional) | All 48 points complete |

### Definition of Done

- [ ] Full orchestration loop completes
- [ ] All qdiscs tested
- [ ] All flow counts tested
- [ ] Results exported in both formats
- [ ] No zombie processes
- [ ] Clean shutdown tested
- [ ] Log file updated with results summary

---

## Phase 4 Complete Checklist

Before marking Phase 4 complete, verify:

- [ ] Go module with all packages compiles
- [ ] Config loading with defaults
- [ ] Runner executes commands in namespaces
- [ ] All tool implementations parse output
- [ ] Test matrix generates correct combinations
- [ ] Qdisc controller switches all qdiscs
- [ ] Process manager handles lifecycle
- [ ] CPU telemetry collection works
- [ ] Results export to JSON and CSV
- [ ] Pre-flight validation passes
- [ ] Main orchestration loop runs to completion
- [ ] Nix flake builds binary
- [ ] Integration test passes
- [ ] Log file complete

---

## Design Reference Summary

From [phase-04-orchestrator.md](./phase-04-orchestrator.md):

**Key Patterns**:
- Single context from `signal.NotifyContext` in main
- Single waitgroup passed to all components
- Context as first argument to all functions
- Check `ctx.Done()` first in select statements
- `Setpgid` for process group cleanup

**Test Matrix**:
- 3 qdiscs × 4 flow counts × 4 tools = 48 test points
- Shuffle option to avoid thermal bias

**Success Criteria**:
- mq-cake spreads CPU load across cores
- cake shows single-core saturation
- No crashes during 10-minute tests

---

## Next Steps After Phase 4

1. Analyze results to prove mq-cake scalability
2. Generate comparison graphs
3. Document findings
4. Consider publishing results

---

## Appendix: Go Idioms Reference

### Context Pattern
```go
func DoWork(ctx context.Context, ...) error {
    select {
    case <-ctx.Done():
        return ctx.Err()
    default:
    }
    // ... work ...
}
```

### WaitGroup Pattern
```go
wg.Add(1)
go func() {
    defer wg.Done()
    // ... work ...
}()
```

### Process Cleanup
```go
c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
// Later:
syscall.Kill(-c.Process.Pid, syscall.SIGKILL)  // Negative PID = process group
```
