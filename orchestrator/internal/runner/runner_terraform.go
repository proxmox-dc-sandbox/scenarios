package runner

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"pdcs/orchestrator/internal/manifest"
)

// TerraformRunner provisions a directory with Terraform:
//   - `terraform init` when `.terraform/` is absent;
//   - `terraform apply -auto-approve`, adding `-var-file=terraform.tfvars`
//     when that file exists in the step directory.
type TerraformRunner struct{}

// Run implements Runner.
func (r *TerraformRunner) Run(ctx context.Context, step manifest.Step, scenarioRoot string, logw io.Writer) error {
	dir := filepath.Join(scenarioRoot, step.Path)
	if info, err := os.Stat(filepath.Join(dir, ".terraform")); err != nil || !info.IsDir() {
		if _, err := os.Stat(filepath.Join(dir, ".terraform")); err != nil {
			if err := runCmd(ctx, dir, step.Env, logw, "terraform", "init"); err != nil {
				return fmt.Errorf("terraform init: %w", err)
			}
		}
	}

	args := []string{"apply", "-auto-approve"}
	if _, err := os.Stat(filepath.Join(dir, "terraform.tfvars")); err == nil {
		args = append(args, "-var-file=terraform.tfvars")
	}
	args = append(args, step.Args...)
	if err := runCmd(ctx, dir, step.Env, logw, "terraform", args...); err != nil {
		return fmt.Errorf("terraform apply: %w", err)
	}
	return nil
}
