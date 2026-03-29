// internal/matrix/testpoint.go
package matrix

import (
	"math/rand"
	"time"

	"github.com/randomizedcoder/mq-cake-orchestrator/internal/config"
)

// TestPoint represents a single test configuration
type TestPoint struct {
	Qdisc     string        `json:"qdisc"`
	FlowCount int           `json:"flow_count"`
	Tool      string        `json:"tool"`
	Duration  time.Duration `json:"duration"`
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
