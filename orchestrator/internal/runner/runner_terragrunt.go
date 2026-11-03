package runner

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"pdcs/orchestrator/internal/manifest"
)

// TerragruntRunner runs a Terragrunt client project:
//
//	terragrunt run --all <action> --non-interactive
//
// from the step directory (the client root containing root.hcl and one
// directory per unit). The action defaults to "apply"; a first step argument
// naming a Terragrunt action (destroy, plan, validate, ...) selects another
// one, so a cleanup step is simply `args: ["destroy"]`.
//
// Terragrunt runs the units in dependency order (and in reverse order for
// destroy) and appends -auto-approve automatically with `run --all`.
type TerragruntRunner struct{}

// Run implements Runner.
func (r *TerragruntRunner) Run(ctx context.Context, step manifest.Step, scenarioRoot string, logw io.Writer) error {
	dir := filepath.Join(scenarioRoot, step.Path)
	if info, err := os.Stat(dir); err != nil || !info.IsDir() {
		return fmt.Errorf("terragrunt directory %s not found", dir)
	}

	action := "apply"
	extra := step.Args
	if len(extra) > 0 && isTerragruntAction(extra[0]) {
		action = extra[0]
		extra = extra[1:]
	}

	// Keep the OpenTofu provider packages in the scenario (not in the
	// ephemeral container HOME), so interrupted runs and cache resets do
	// not lose them.
	cacheDir := filepath.Join(scenarioRoot, ".terraform-plugin-cache")
	if err := os.MkdirAll(cacheDir, 0o755); err != nil {
		return fmt.Errorf("create provider cache: %w", err)
	}
	env := make(map[string]string, len(step.Env)+1)
	for k, v := range step.Env {
		env[k] = v
	}
	if _, ok := env["TF_PLUGIN_CACHE_DIR"]; !ok {
		env["TF_PLUGIN_CACHE_DIR"] = cacheDir
	}

	args := []string{"run", "--all", action, "--non-interactive"}
	args = append(args, extra...)
	if err := runCmd(ctx, dir, env, logw, "terragrunt", args...); err != nil {
		return fmt.Errorf("terragrunt %s: %w", action, err)
	}
	return nil
}

func isTerragruntAction(s string) bool {
	switch s {
	case "apply", "destroy", "plan", "validate", "init", "refresh", "output", "fmt":
		return true
	}
	return false
}
