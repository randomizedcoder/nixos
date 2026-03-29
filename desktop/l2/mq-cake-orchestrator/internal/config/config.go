// internal/config/config.go
package config

import (
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Namespaces NamespaceConfig `yaml:"namespaces"`
	Interfaces InterfaceConfig `yaml:"interfaces"`
	Network    NetworkConfig   `yaml:"network"`
	Tools      []string        `yaml:"tools"`
	Matrix     MatrixConfig    `yaml:"matrix"`
	Timing     TimingConfig    `yaml:"timing"`
	Telemetry  TelemetryConfig `yaml:"telemetry"`
	Preflight  PreflightConfig `yaml:"preflight"`
	Output     OutputConfig    `yaml:"output"`
	Stress     StressConfig    `yaml:"stress"`
	Netem      NetemConfig     `yaml:"netem"`
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

// ToolFlowConfig defines flow ramping parameters for each tool
type ToolFlowConfig struct {
	Name      string `yaml:"name"`      // Tool name (iperf2, iperf3, wrk, dnsperf, flent, crusader)
	Start     int    `yaml:"start"`     // Starting flow/connection count
	Increment int    `yaml:"increment"` // How many flows to add each step
	Max       int    `yaml:"max"`       // Stop incrementing at this level
}

// StressConfig configures concurrent stress testing with flow ramping
type StressConfig struct {
	Enabled        bool             `yaml:"enabled"`
	Tools          []ToolFlowConfig `yaml:"tools"`
	StepDuration   time.Duration    `yaml:"step_duration"`   // Hold each flow level for this long
	StabilizeDelay time.Duration    `yaml:"stabilize_delay"` // Wait after incrementing before measuring

	// Breaking point detection thresholds
	MaxLatencyP99Ms      float64 `yaml:"max_latency_p99_ms"`      // Stop if P99 exceeds this (default: 500ms)
	MaxPacketLossPct     float64 `yaml:"max_packet_loss_pct"`     // Stop if loss exceeds this (default: 5%)
	MaxCPUPct            float64 `yaml:"max_cpu_pct"`             // Stop if any core exceeds this (default: 95%)
	MinThroughputPct     float64 `yaml:"min_throughput_pct"`      // Stop if throughput drops below this % of baseline (default: 50%)
	MetricsPort          int     `yaml:"metrics_port"`            // Prometheus metrics port (default: 2112)
	FlowsPerInstance     int     `yaml:"flows_per_instance"`      // Max flows per tool instance (default: 100)
}

// NetemConfig configures netem latency injection on load generators
type NetemConfig struct {
	Enabled bool `yaml:"enabled"`
	Latency int  `yaml:"latency"` // Base delay in ms (default: 30)
	Jitter  int  `yaml:"jitter"`  // Delay variation in ms (default: 3, 10% of latency)
	Limit   int  `yaml:"limit"`   // Queue size in packets (default: 100000)
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
	if cfg.Output.Format == "" {
		cfg.Output.Format = "both"
	}
	if cfg.Telemetry.CPUSampleInterval == 0 {
		cfg.Telemetry.CPUSampleInterval = 1 * time.Second
	}

	// Stress test defaults
	if cfg.Stress.StepDuration == 0 {
		cfg.Stress.StepDuration = 60 * time.Second
	}
	if cfg.Stress.StabilizeDelay == 0 {
		cfg.Stress.StabilizeDelay = 5 * time.Second
	}
	if cfg.Stress.MaxLatencyP99Ms == 0 {
		cfg.Stress.MaxLatencyP99Ms = 500
	}
	if cfg.Stress.MaxPacketLossPct == 0 {
		cfg.Stress.MaxPacketLossPct = 5
	}
	if cfg.Stress.MaxCPUPct == 0 {
		cfg.Stress.MaxCPUPct = 95
	}
	if cfg.Stress.MinThroughputPct == 0 {
		cfg.Stress.MinThroughputPct = 50
	}
	if cfg.Stress.MetricsPort == 0 {
		cfg.Stress.MetricsPort = 2112
	}
	if cfg.Stress.FlowsPerInstance == 0 {
		cfg.Stress.FlowsPerInstance = 100
	}

	// Netem defaults
	if cfg.Netem.Latency == 0 {
		cfg.Netem.Latency = 30
	}
	if cfg.Netem.Jitter == 0 {
		cfg.Netem.Jitter = 3
	}
	if cfg.Netem.Limit == 0 {
		cfg.Netem.Limit = 100000
	}

	return &cfg, nil
}
