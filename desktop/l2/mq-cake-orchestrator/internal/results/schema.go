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
