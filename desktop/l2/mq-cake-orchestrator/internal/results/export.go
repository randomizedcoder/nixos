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
		fmt.Printf("Wrote %s\n", baseName+".json")
	}

	if cfg.Format == "csv" || cfg.Format == "both" {
		if err := exportCSV(run, baseName+".csv"); err != nil {
			return err
		}
		fmt.Printf("Wrote %s\n", baseName+".csv")
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
	if err := w.Write([]string{
		"qdisc", "flow_count", "tool", "duration_s",
		"throughput_gbps", "latency_p50_ms", "latency_p99_ms",
		"packet_loss_pct", "retransmits",
	}); err != nil {
		return err
	}

	for _, r := range run.Results {
		if r.Result == nil {
			continue
		}
		if err := w.Write([]string{
			r.TestPoint.Qdisc,
			fmt.Sprintf("%d", r.TestPoint.FlowCount),
			r.TestPoint.Tool,
			fmt.Sprintf("%.0f", r.TestPoint.Duration.Seconds()),
			fmt.Sprintf("%.3f", r.Result.ThroughputGbps),
			fmt.Sprintf("%.2f", r.Result.LatencyP50Ms),
			fmt.Sprintf("%.2f", r.Result.LatencyP99Ms),
			fmt.Sprintf("%.2f", r.Result.PacketLossPct),
			fmt.Sprintf("%d", r.Result.Retransmits),
		}); err != nil {
			return err
		}
	}

	return nil
}
