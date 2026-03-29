// internal/process/manager.go
package process

import (
	"context"
	"fmt"
	"strings"
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
	debug  bool
}

// NewManager creates a new process manager
func NewManager(r runner.Runner, wg *sync.WaitGroup, cfg *config.Config, debug bool) *Manager {
	return &Manager{
		runner: r,
		wg:     wg,
		cfg:    cfg,
		debug:  debug,
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
	serverCmd := tool.ServerCmd(port)
	clientCmd := tool.ClientCmd(m.cfg.Network.ServerIP, port, flows, m.cfg.Timing.PerToolDuration)

	if m.debug {
		fmt.Printf("  [DEBUG] Server: ip netns exec %s %s\n",
			m.cfg.Namespaces.Server, strings.Join(serverCmd, " "))
		fmt.Printf("  [DEBUG] Client: ip netns exec %s %s\n",
			m.cfg.Namespaces.Client, strings.Join(clientCmd, " "))
	}

	// Start server
	serverProc, err := m.runner.Start(
		toolCtx,
		m.cfg.Namespaces.Server,
		serverCmd,
	)
	if err != nil {
		return nil, fmt.Errorf("server start failed: %w", err)
	}

	// Ensure server cleanup on any exit
	defer func() {
		if serverProc != nil {
			serverProc.Kill()
		}
	}()

	// Watch for cancellation - kills server if context cancelled mid-run
	go func() {
		<-toolCtx.Done()
		if serverProc != nil {
			serverProc.Kill()
		}
	}()

	// Wait for server startup
	time.Sleep(m.cfg.Timing.ToolStartupDelay)

	// Run client
	output, err := m.runner.Run(
		toolCtx,
		m.cfg.Namespaces.Client,
		clientCmd,
	)
	if err != nil {
		return nil, fmt.Errorf("client failed: %w", err)
	}

	return tool.Parse(output, flows, m.cfg.Timing.PerToolDuration)
}
