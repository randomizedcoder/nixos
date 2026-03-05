// internal/runner/local.go
package runner

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os/exec"
	"syscall"
)

// LocalRunner executes commands via ip netns exec
type LocalRunner struct{}

// NewLocalRunner creates a new LocalRunner
func NewLocalRunner() *LocalRunner {
	return &LocalRunner{}
}

// Run executes a command in a namespace and waits for completion
func (r *LocalRunner) Run(ctx context.Context, namespace string, cmd []string) (string, error) {
	args := append([]string{"netns", "exec", namespace}, cmd...)
	c := exec.CommandContext(ctx, "ip", args...)

	// Set process group for clean termination
	c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	out, err := c.CombinedOutput()
	return string(out), err
}

// Start executes a command in background with real-time streaming output.
// Uses io.Pipe() to enable real-time reading of stdout/stderr as they are written.
func (r *LocalRunner) Start(ctx context.Context, namespace string, cmd []string) (Process, error) {
	args := append([]string{"netns", "exec", namespace}, cmd...)
	c := exec.CommandContext(ctx, "ip", args...)
	c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	// Create pipes for real-time streaming
	stdoutPR, stdoutPW := io.Pipe()
	stderrPR, stderrPW := io.Pipe()

	c.Stdout = stdoutPW
	c.Stderr = stderrPW

	if err := c.Start(); err != nil {
		stdoutPW.Close()
		stderrPW.Close()
		stdoutPR.Close()
		stderrPR.Close()
		return nil, fmt.Errorf("failed to start: %w", err)
	}

	proc := &localProcess{
		cmd:      c,
		stdoutPR: stdoutPR,
		stdoutPW: stdoutPW,
		stderrPR: stderrPR,
		stderrPW: stderrPW,
		done:     make(chan struct{}),
	}

	// Close write ends when process exits to unblock readers
	go func() {
		c.Wait()
		stdoutPW.Close()
		stderrPW.Close()
		close(proc.done)
	}()

	return proc, nil
}

// StartBuffered executes a command in background with buffered output.
// Uses bytes.Buffer for collecting output that is read after process completion.
// This is useful when you don't need real-time streaming.
func (r *LocalRunner) StartBuffered(ctx context.Context, namespace string, cmd []string) (Process, error) {
	args := append([]string{"netns", "exec", namespace}, cmd...)
	c := exec.CommandContext(ctx, "ip", args...)
	c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	var stdout, stderr bytes.Buffer
	c.Stdout = &stdout
	c.Stderr = &stderr

	if err := c.Start(); err != nil {
		return nil, fmt.Errorf("failed to start: %w", err)
	}

	return &bufferedProcess{
		cmd:    c,
		stdout: &stdout,
		stderr: &stderr,
	}, nil
}

// localProcess uses io.Pipe for real-time streaming output
type localProcess struct {
	cmd      *exec.Cmd
	stdoutPR *io.PipeReader
	stdoutPW *io.PipeWriter
	stderrPR *io.PipeReader
	stderrPW *io.PipeWriter
	done     chan struct{}
}

func (p *localProcess) Wait() error {
	<-p.done
	if p.cmd.ProcessState != nil && p.cmd.ProcessState.ExitCode() != 0 {
		return fmt.Errorf("process exited with code %d", p.cmd.ProcessState.ExitCode())
	}
	return nil
}

func (p *localProcess) Kill() error {
	if p.cmd.Process == nil {
		return nil
	}
	// Kill entire process group to prevent zombies
	return syscall.Kill(-p.cmd.Process.Pid, syscall.SIGKILL)
}

func (p *localProcess) Stdout() io.Reader {
	return p.stdoutPR
}

func (p *localProcess) Stderr() io.Reader {
	return p.stderrPR
}

func (p *localProcess) Pid() int {
	if p.cmd.Process == nil {
		return 0
	}
	return p.cmd.Process.Pid
}

// Done returns a channel that closes when the process exits
func (p *localProcess) Done() <-chan struct{} {
	return p.done
}

// bufferedProcess uses bytes.Buffer for output collection after completion
type bufferedProcess struct {
	cmd    *exec.Cmd
	stdout *bytes.Buffer
	stderr *bytes.Buffer
}

func (p *bufferedProcess) Wait() error {
	return p.cmd.Wait()
}

func (p *bufferedProcess) Kill() error {
	if p.cmd.Process == nil {
		return nil
	}
	return syscall.Kill(-p.cmd.Process.Pid, syscall.SIGKILL)
}

func (p *bufferedProcess) Stdout() io.Reader {
	return p.stdout
}

func (p *bufferedProcess) Stderr() io.Reader {
	return p.stderr
}

func (p *bufferedProcess) Pid() int {
	if p.cmd.Process == nil {
		return 0
	}
	return p.cmd.Process.Pid
}
