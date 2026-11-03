// Package runner executes the individual steps of a scenario.
//
// Every runner receives the absolute scenario root and an io.Writer where
// stdout/stderr are streamed (the orchestrator tees it into a log file and,
// in guided mode, replicates it to the terminal).
package runner

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"sort"
	"strings"

	"pdcs/orchestrator/internal/manifest"
)

// Runner executes a single step of a scenario.
type Runner interface {
	Run(ctx context.Context, step manifest.Step, scenarioRoot string, logw io.Writer) error
}

// Registry maps step types to their runner implementation.
type Registry map[manifest.StepType]Runner

// NewRegistry builds the runner registry for all supported step types.
func NewRegistry() Registry {
	return Registry{
		manifest.TypeTerraform:  &TerraformRunner{},
		manifest.TypeTerragrunt: &TerragruntRunner{},
		manifest.TypeAnsible:    &AnsibleRunner{},
		manifest.TypeSh:         &ShellRunner{},
		manifest.TypeGo:         &GoRunner{},
	}
}

// runCmd executes a command in the given working directory, streaming its
// output to logw. exec.Cmd.Dir is used instead of os.Chdir so that the
// process working directory is never mutated (thread-safe, parallel-ready).
// extraEnv, when non-nil, is appended to the inherited environment.
func runCmd(ctx context.Context, dir string, extraEnv map[string]string, logw io.Writer, name string, args ...string) error {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	cmd.Env = stepEnv(extraEnv)
	cmd.Stdout = logw
	cmd.Stderr = logw
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("command %q %v: %w", name, args, err)
	}
	return nil
}

// stepEnv returns the inherited environment with deterministic overrides.
// Scenario values replace host values rather than appearing as duplicate
// KEY=VALUE entries, which different libc implementations may resolve
// inconsistently. It returns nil when there is no override.
func stepEnv(extra map[string]string) []string {
	if len(extra) == 0 {
		return nil
	}
	values := make(map[string]string)
	for _, entry := range os.Environ() {
		key, value, ok := strings.Cut(entry, "=")
		if ok {
			values[key] = value
		}
	}
	for k, v := range extra {
		values[k] = v
	}
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	env := make([]string, 0, len(keys))
	for _, key := range keys {
		env = append(env, key+"="+values[key])
	}
	return env
}
