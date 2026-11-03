package runner

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"pdcs/orchestrator/internal/manifest"
)

// GoRunner executes a Go step:
//   - a precompiled binary found in <step.Path>/bin/ (any executable file) is
//     preferred when present;
//   - otherwise `go run .` is used with <step.Path> as working directory.
type GoRunner struct{}

// Run implements Runner.
func (r *GoRunner) Run(ctx context.Context, step manifest.Step, scenarioRoot string, logw io.Writer) error {
	dir := filepath.Join(scenarioRoot, step.Path)

	binDir := filepath.Join(dir, "bin")
	if entries, err := os.ReadDir(binDir); err == nil {
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			info, err := e.Info()
			if err == nil && info.Mode()&0o111 != 0 {
				binary := filepath.Join(binDir, e.Name())
				if err := runCmd(ctx, dir, step.Env, logw, binary, step.Args...); err != nil {
					return fmt.Errorf("go binary %s: %w", e.Name(), err)
				}
				return nil
			}
		}
	}

	if err := runCmd(ctx, dir, step.Env, logw, "go", append([]string{"run", "."}, step.Args...)...); err != nil {
		return fmt.Errorf("go run: %w", err)
	}
	return nil
}
