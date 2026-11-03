package runner

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"pdcs/orchestrator/internal/manifest"
)

// AnsibleRunner runs `ansible-playbook -i <inventory> <playbook>`.
//
// The inventory is resolved in this order:
//  1. the PDCS_ANSIBLE_INVENTORY environment variable;
//  2. <scenarioRoot>/inventory (default).
type AnsibleRunner struct{}

// Run implements Runner.
func (r *AnsibleRunner) Run(ctx context.Context, step manifest.Step, scenarioRoot string, logw io.Writer) error {
	inventory := os.Getenv("PDCS_ANSIBLE_INVENTORY")
	if inventory == "" {
		inventory = filepath.Join(scenarioRoot, "inventory")
	}
	if _, err := os.Stat(inventory); err != nil {
		return fmt.Errorf("ansible inventory %q not found (set PDCS_ANSIBLE_INVENTORY)", inventory)
	}

	playbook := filepath.Join(scenarioRoot, step.Path)
	if err := runCmd(ctx, scenarioRoot, step.Env, logw, "ansible-playbook", append([]string{"-i", inventory, playbook}, step.Args...)...); err != nil {
		return fmt.Errorf("ansible-playbook: %w", err)
	}
	return nil
}
