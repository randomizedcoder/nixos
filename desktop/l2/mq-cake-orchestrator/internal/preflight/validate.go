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
	namespaces := []string{v.cfg.Namespaces.Client, v.cfg.Namespaces.Server, v.cfg.Namespaces.DUT}
	for _, ns := range namespaces {
		_, err := v.runner.Run(ctx, ns, []string{"true"})
		if err != nil {
			return fmt.Errorf("namespace %s not accessible: %w", ns, err)
		}
	}
	return nil
}

func (v *Validator) checkInterfaces(ctx context.Context) error {
	interfaces := []string{v.cfg.Interfaces.DUTIngress, v.cfg.Interfaces.DUTEgress}
	for _, iface := range interfaces {
		cmd := []string{"ip", "link", "show", iface}
		_, err := v.runner.Run(ctx, v.cfg.Namespaces.DUT, cmd)
		if err != nil {
			return fmt.Errorf("interface %s not found: %w", iface, err)
		}
	}
	return nil
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

// GetBaselineRTT returns the measured baseline RTT
func (v *Validator) GetBaselineRTT() float64 {
	return v.BaselineRTT
}
