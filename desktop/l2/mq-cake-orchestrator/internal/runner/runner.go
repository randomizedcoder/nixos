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
