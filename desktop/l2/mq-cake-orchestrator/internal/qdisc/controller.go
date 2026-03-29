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
	runner       runner.Runner
	cfg          *config.Config
	currentQdisc string
	debug        bool
}

// NewController creates a new qdisc controller
func NewController(r runner.Runner, cfg *config.Config, debug bool) *Controller {
	return &Controller{
		runner: r,
		cfg:    cfg,
		debug:  debug,
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
			nativeCmd := []string{
				"tc", "qdisc", "replace", "dev", iface, "root", "cake_mq",
				"bandwidth", c.cfg.Network.Bandwidth,
				"diffserv4", "nat", "wash", "split-gso",
			}
			if c.debug {
				fmt.Printf("  [DEBUG] Qdisc: ip netns exec %s %s\n",
					c.cfg.Namespaces.DUT, strings.Join(nativeCmd, " "))
			}
			_, err := c.runner.Run(ctx, c.cfg.Namespaces.DUT, nativeCmd)
			if err != nil {
				// Fallback to mq + cake per-queue
				if err := c.setMQFallback(ctx, iface); err != nil {
					return err
				}
				continue
			}
			continue

		default:
			return fmt.Errorf("unknown qdisc: %s", qdisc)
		}

		if c.debug {
			fmt.Printf("  [DEBUG] Qdisc: ip netns exec %s %s\n",
				c.cfg.Namespaces.DUT, strings.Join(cmd, " "))
		}
		if _, err := c.runner.Run(ctx, c.cfg.Namespaces.DUT, cmd); err != nil {
			return fmt.Errorf("failed to set %s on %s: %w", qdisc, iface, err)
		}
	}

	c.currentQdisc = qdisc
	return nil
}

func (c *Controller) setMQFallback(ctx context.Context, iface string) error {
	// Set mq as root with handle 1:
	mqCmd := []string{"tc", "qdisc", "replace", "dev", iface, "root", "handle", "1:", "mq"}
	if c.debug {
		fmt.Printf("  [DEBUG] MQ fallback: ip netns exec %s %s\n",
			c.cfg.Namespaces.DUT, strings.Join(mqCmd, " "))
	}
	if _, err := c.runner.Run(ctx, c.cfg.Namespaces.DUT, mqCmd); err != nil {
		return fmt.Errorf("mq fallback failed: %w", err)
	}

	// Get number of TX queues by counting tx-* directories in /sys/class/net/<iface>/queues/
	numQueues := c.getTxQueueCount(ctx, iface)
	if numQueues == 0 {
		numQueues = 64 // Fallback to high number, errors will be ignored
	}
	if c.debug {
		fmt.Printf("  [DEBUG] %s has %d TX queues\n", iface, numQueues)
	}

	// Add cake to each queue
	for i := 1; i <= numQueues; i++ {
		cakeCmd := []string{
			"tc", "qdisc", "replace", "dev", iface,
			"parent", fmt.Sprintf("1:%d", i),
			"cake", "bandwidth", c.cfg.Network.Bandwidth,
			"diffserv4", "nat", "wash", "split-gso",
		}
		if c.debug {
			fmt.Printf("  [DEBUG] MQ queue %d: ip netns exec %s %s\n",
				i, c.cfg.Namespaces.DUT, strings.Join(cakeCmd, " "))
		}
		if _, err := c.runner.Run(ctx, c.cfg.Namespaces.DUT, cakeCmd); err != nil {
			// Not all queues may exist, ignore errors
			continue
		}
	}

	return nil
}

// getTxQueueCount returns the number of TX queues for an interface
func (c *Controller) getTxQueueCount(ctx context.Context, iface string) int {
	// Count tx-* directories in /sys/class/net/<iface>/queues/
	cmd := []string{"sh", "-c", fmt.Sprintf("ls -d /sys/class/net/%s/queues/tx-* 2>/dev/null | wc -l", iface)}
	out, err := c.runner.Run(ctx, c.cfg.Namespaces.DUT, cmd)
	if err != nil {
		return 0
	}

	var count int
	fmt.Sscanf(strings.TrimSpace(out), "%d", &count)
	return count
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

// ParseDrops extracts drop count from qdisc stats
func ParseDrops(stats string) int64 {
	// Example: "Sent 12345 bytes 100 pkt (dropped 5, overlimits 0 requeues 0)"
	if idx := strings.Index(stats, "dropped "); idx != -1 {
		var drops int64
		fmt.Sscanf(stats[idx:], "dropped %d", &drops)
		return drops
	}
	return 0
}
