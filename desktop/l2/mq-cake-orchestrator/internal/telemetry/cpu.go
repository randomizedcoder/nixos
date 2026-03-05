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
	Timestamp time.Time   `json:"timestamp"`
	PerCore   []CoreStats `json:"per_core"`
	Total     CoreStats   `json:"total"`
}

// CoreStats holds per-core CPU counters
type CoreStats struct {
	Core   int    `json:"core"`
	User   uint64 `json:"user"`
	System uint64 `json:"system"`
	Idle   uint64 `json:"idle"`
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

// CalculateUsage computes CPU usage percentage between two samples
func CalculateUsage(prev, curr *CoreStats) float64 {
	prevTotal := prev.User + prev.System + prev.Idle
	currTotal := curr.User + curr.System + curr.Idle

	totalDiff := float64(currTotal - prevTotal)
	if totalDiff == 0 {
		return 0
	}

	idleDiff := float64(curr.Idle - prev.Idle)
	return 100 * (1 - idleDiff/totalDiff)
}
