// internal/process/scaler.go
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

// Instance represents a running tool instance
type Instance struct {
	Tool    string
	Port    int
	Flows   int
	Server  runner.Process
	started time.Time
}

// ToolScaler manages multiple instances of load generation tools
type ToolScaler struct {
	mu        sync.Mutex
	runner    runner.Runner
	cfg       *config.Config
	ports     *PortAllocator
	instances map[string][]*Instance // tool name -> running instances
	toolMap   map[string]tools.Tool  // tool name -> tool implementation
	debug     bool
}

// NewToolScaler creates a new tool scaler
func NewToolScaler(r runner.Runner, cfg *config.Config, debug bool) *ToolScaler {
	return &ToolScaler{
		runner:    r,
		cfg:       cfg,
		ports:     NewPortAllocator(),
		instances: make(map[string][]*Instance),
		toolMap: map[string]tools.Tool{
			"iperf2":   tools.NewIperf2(),
			"iperf3":   tools.NewIperf3(),
			"flent":    tools.NewFlent(cfg.Output.ResultsDir),
			"crusader": tools.NewCrusader(),
			"wrk":      tools.NewWrk("100k"),
			"dnsperf":  tools.NewDNSPerf(""),
			"fping":    tools.NewFping(),
		},
		debug: debug,
	}
}

// FlowsPerInstance returns the max flows per instance for a tool
func (ts *ToolScaler) FlowsPerInstance(tool string) int {
	switch tool {
	case "iperf2":
		return 100 // iperf2 handles 100 flows per -P flag reasonably well
	case "iperf3":
		return 100 // iperf3 practical limit around 128 parallel streams
	case "wrk":
		return 100 // wrk: 100 connections per instance for better load distribution
	case "dnsperf":
		return 20 // dnsperf: 20 concurrent queries per instance
	case "flent", "crusader":
		return 1 // These run as single instances with fixed flows
	default:
		return ts.cfg.Stress.FlowsPerInstance
	}
}

// IsClientOnly returns true for tools where we only need one server
// and scale by spawning multiple client instances
// - wrk/dnsperf: server (nginx/pdns) is external
// - iperf2: single server can handle multiple concurrent clients
// - fping: uses ICMP, kernel handles echo replies (no server)
func (ts *ToolScaler) IsClientOnly(tool string) bool {
	switch tool {
	case "wrk", "dnsperf", "iperf2", "fping":
		return true
	default:
		// iperf3: can only handle one client at a time, needs multiple servers
		return false
	}
}

// IsFixedInstance returns true for tools that run a single instance
// with fixed flow count (no scaling)
func (ts *ToolScaler) IsFixedInstance(tool string) bool {
	switch tool {
	case "flent", "crusader", "fping":
		return true
	default:
		return false
	}
}

// CurrentFlows returns the total flows currently running for a tool
func (ts *ToolScaler) CurrentFlows(tool string) int {
	ts.mu.Lock()
	defer ts.mu.Unlock()

	total := 0
	for _, inst := range ts.instances[tool] {
		total += inst.Flows
	}
	return total
}

// InstanceCount returns the number of running instances for a tool
func (ts *ToolScaler) InstanceCount(tool string) int {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	return len(ts.instances[tool])
}

// ScaleTo adjusts the flow count for a tool, spawning/killing instances as needed
func (ts *ToolScaler) ScaleTo(ctx context.Context, tool string, targetFlows int) error {
	// Check context first
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	ts.mu.Lock()
	defer ts.mu.Unlock()

	// Fixed instance tools (flent, crusader): no scaling
	if ts.IsFixedInstance(tool) {
		return nil
	}

	currentFlows := 0
	for _, inst := range ts.instances[tool] {
		currentFlows += inst.Flows
	}

	if targetFlows == currentFlows {
		return nil
	}

	if targetFlows > currentFlows {
		// Scale up - spawn additional instances
		needed := targetFlows - currentFlows
		return ts.spawnInstances(ctx, tool, needed)
	}

	// Scale down - kill excess instances
	excess := currentFlows - targetFlows
	return ts.killInstances(tool, excess)
}

// spawnInstances creates new tool instances to handle the specified flows
func (ts *ToolScaler) spawnInstances(ctx context.Context, tool string, flows int) error {
	t, ok := ts.toolMap[tool]
	if !ok {
		return fmt.Errorf("unknown tool: %s", tool)
	}

	flowsPerInstance := ts.FlowsPerInstance(tool)
	numInstances := (flows + flowsPerInstance - 1) / flowsPerInstance

	clientOnly := ts.IsClientOnly(tool)

	// Determine the server port
	// - For client-only tools with no existing instances, we may need to start one server
	// - For iperf2: start server on first instance, then just add clients
	// - For wrk/dnsperf: server is external (nginx/pdns already running)
	existingInstances := ts.instances[tool]
	var serverPort int

	if len(existingInstances) > 0 {
		// Use existing server's port for all new instances
		serverPort = existingInstances[0].Port
	} else if clientOnly && ts.needsServerStart(tool) {
		// iperf2: start one server on first spawn
		var err error
		serverPort, err = ts.ports.Allocate(tool)
		if err != nil {
			return fmt.Errorf("port allocation failed: %w", err)
		}

		serverCmd := t.ServerCmd(serverPort)
		if ts.debug {
			fmt.Printf("  [SCALER] Starting %s server on port %d\n", tool, serverPort)
		}

		server, err := ts.runner.Start(ctx, ts.cfg.Namespaces.Server, serverCmd)
		if err != nil {
			ts.ports.Release(tool, serverPort)
			return fmt.Errorf("failed to start %s server on port %d: %w", tool, serverPort, err)
		}

		// First instance holds the server reference
		inst := &Instance{
			Tool:    tool,
			Port:    serverPort,
			Flows:   min(flowsPerInstance, flows),
			Server:  server,
			started: time.Now(),
		}
		ts.instances[tool] = append(ts.instances[tool], inst)
		numInstances--
		flows -= inst.Flows
	} else if clientOnly {
		// wrk/dnsperf: external server, use default port
		serverPort = t.DefaultPort()
	}

	// Spawn remaining instances (client-only for clientOnly tools)
	for i := 0; i < numInstances; i++ {
		instanceFlows := min(flowsPerInstance, flows-(i*flowsPerInstance))
		if instanceFlows <= 0 {
			break
		}

		var port int
		var server runner.Process

		if clientOnly {
			// Additional clients connect to the same server
			port = serverPort
			if ts.debug {
				fmt.Printf("  [SCALER] Adding %s client instance (flows: %d, port: %d)\n", tool, instanceFlows, port)
			}
		} else {
			// iperf3: each instance needs its own server
			var err error
			port, err = ts.ports.Allocate(tool)
			if err != nil {
				return fmt.Errorf("port allocation failed: %w", err)
			}

			serverCmd := t.ServerCmd(port)
			if ts.debug {
				fmt.Printf("  [SCALER] Starting %s server on port %d (flows: %d)\n", tool, port, instanceFlows)
			}

			server, err = ts.runner.Start(ctx, ts.cfg.Namespaces.Server, serverCmd)
			if err != nil {
				ts.ports.Release(tool, port)
				return fmt.Errorf("failed to start %s server on port %d: %w", tool, port, err)
			}
		}

		inst := &Instance{
			Tool:    tool,
			Port:    port,
			Flows:   instanceFlows,
			Server:  server,
			started: time.Now(),
		}
		ts.instances[tool] = append(ts.instances[tool], inst)
	}

	return nil
}

// needsServerStart returns true for client-only tools that need us to start a server
// (as opposed to external servers like nginx/pdns)
func (ts *ToolScaler) needsServerStart(tool string) bool {
	switch tool {
	case "iperf2":
		return true // We start the iperf2 server
	case "wrk", "dnsperf":
		return false // nginx/pdns started externally
	default:
		return false
	}
}

// killInstances stops enough instances to reduce flows by the specified amount
func (ts *ToolScaler) killInstances(tool string, flowsToRemove int) error {
	instances := ts.instances[tool]
	if len(instances) == 0 {
		return nil
	}

	// Calculate target flows after removal
	currentFlows := 0
	for _, inst := range instances {
		currentFlows += inst.Flows
	}
	targetFlows := currentFlows - flowsToRemove
	if targetFlows < 0 {
		targetFlows = 0
	}

	// Keep instances until we reach target, kill the rest
	var remaining []*Instance
	flowsKept := 0
	for _, inst := range instances {
		if flowsKept < targetFlows {
			remaining = append(remaining, inst)
			flowsKept += inst.Flows
		} else {
			// Kill this instance
			if inst.Server != nil {
				inst.Server.Kill()
				// Release port if this instance had a server
				ts.ports.Release(tool, inst.Port)
			}
		}
	}
	ts.instances[tool] = remaining

	return nil
}

// StartTool starts a tool with the specified number of flows
func (ts *ToolScaler) StartTool(ctx context.Context, tool string, flows int) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()

	// Clear any existing instances first
	for _, inst := range ts.instances[tool] {
		if inst.Server != nil {
			inst.Server.Kill()
			// Release port if this instance had a server
			ts.ports.Release(tool, inst.Port)
		}
	}
	ts.instances[tool] = nil

	return ts.spawnInstances(ctx, tool, flows)
}

// StopTool stops all instances of a tool
func (ts *ToolScaler) StopTool(tool string) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()

	for _, inst := range ts.instances[tool] {
		if inst.Server != nil {
			inst.Server.Kill()
			// Release port if this instance had a server
			ts.ports.Release(tool, inst.Port)
		}
	}
	ts.instances[tool] = nil
	return nil
}

// StopAll stops all running tool instances
func (ts *ToolScaler) StopAll() {
	ts.mu.Lock()
	defer ts.mu.Unlock()

	for tool, instances := range ts.instances {
		for _, inst := range instances {
			if inst.Server != nil {
				inst.Server.Kill()
				// Release port if this instance had a server
				// (includes iperf2 which is clientOnly but allocates 1 port)
				ts.ports.Release(tool, inst.Port)
			}
		}
	}
	ts.instances = make(map[string][]*Instance)
}

// GetInstances returns a copy of the current instances for a tool
func (ts *ToolScaler) GetInstances(tool string) []Instance {
	ts.mu.Lock()
	defer ts.mu.Unlock()

	result := make([]Instance, len(ts.instances[tool]))
	for i, inst := range ts.instances[tool] {
		result[i] = *inst
	}
	return result
}

// RunClients runs client commands for all instances of a tool
// Returns combined output from all clients
func (ts *ToolScaler) RunClients(ctx context.Context, tool string, duration time.Duration) ([]string, error) {
	ts.mu.Lock()
	instances := make([]*Instance, len(ts.instances[tool]))
	copy(instances, ts.instances[tool])
	ts.mu.Unlock()

	t, ok := ts.toolMap[tool]
	if !ok {
		return nil, fmt.Errorf("unknown tool: %s", tool)
	}

	var wg sync.WaitGroup
	outputs := make([]string, len(instances))
	errors := make([]error, len(instances))

	for i, inst := range instances {
		wg.Add(1)
		go func(idx int, inst *Instance) {
			defer wg.Done()

			clientCmd := t.ClientCmd(ts.cfg.Network.ServerIP, inst.Port, inst.Flows, duration)
			output, err := ts.runner.Run(ctx, ts.cfg.Namespaces.Client, clientCmd)
			outputs[idx] = output
			errors[idx] = err
		}(i, inst)
	}

	wg.Wait()

	// Check for errors
	for i, err := range errors {
		if err != nil {
			return outputs, fmt.Errorf("instance %d failed: %w", i, err)
		}
	}

	return outputs, nil
}
