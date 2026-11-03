package runner

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"

	"pdcs/orchestrator/internal/manifest"
)

// ShellRunner executes a shell script directly. The script must be
// executable (the orchestrator refuses to fall back to shell invocation so
// that the manifest stays explicit).
type ShellRunner struct{}

// Run implements Runner.
func (r *ShellRunner) Run(ctx context.Context, step manifest.Step, scenarioRoot string, logw io.Writer) error {
	script := filepath.Join(scenarioRoot, step.Path)
	info, err := os.Stat(script)
	if err != nil {
		return fmt.Errorf("script %s: %w", script, err)
	}
	if info.Mode()&0o111 == 0 {
		return fmt.Errorf("script %s is not executable (run chmod +x)", script)
	}

	cmd := exec.CommandContext(ctx, script, step.Args...)
	cmd.Dir = filepath.Dir(script)
	cmd.Env = stepEnv(step.Env)
	cmd.Stdout = logw
	cmd.Stderr = logw
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("script %s: %w", script, err)
	}
	return nil
}
