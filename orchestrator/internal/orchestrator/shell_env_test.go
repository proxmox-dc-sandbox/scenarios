package orchestrator

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
)

func TestShellExportsEscapesAndSorts(t *testing.T) {
	env := map[string]string{
		"B":      "b",
		"A":      "a",
		"QUOTED": "it's",
		"EMPTY":  "",
	}
	got := ShellExports(env)
	want := "export A='a'\nexport B='b'\nexport EMPTY=''\nexport QUOTED='it'\\''s'\n"
	if got != want {
		t.Fatalf("ShellExports() = %q, want %q", got, want)
	}
}

func TestShellEnvironmentIncludesScenarioContext(t *testing.T) {
	root := t.TempDir()
	writeTestScenario(t, root, `name: shell-env-test
env:
  - name: STATIC_VALUE
    value: from-manifest
steps:
  - id: noop
    type: sh
    path: noop.sh
`)
	writeExecutable(t, filepath.Join(root, "noop.sh"), "#!/usr/bin/env bash\nexit 0\n")

	o, err := New(Config{ScenarioFile: filepath.Join(root, "scenario.yaml"), ScenarioRoot: root})
	if err != nil {
		t.Fatalf("New(): %v", err)
	}

	env := o.ShellEnvironment()
	if env["STATIC_VALUE"] != "from-manifest" {
		t.Errorf("STATIC_VALUE = %q, want manifest value", env["STATIC_VALUE"])
	}
	if env["PDCS_SCENARIO_ROOT"] != root {
		t.Errorf("PDCS_SCENARIO_ROOT = %q, want %q", env["PDCS_SCENARIO_ROOT"], root)
	}
	if env["PDCS_SCENARIO_NAME"] != "shell-env-test" {
		t.Errorf("PDCS_SCENARIO_NAME = %q, want shell-env-test", env["PDCS_SCENARIO_NAME"])
	}

	exports := ShellExports(env)
	for _, want := range []string{
		"export STATIC_VALUE='from-manifest'",
		"export PDCS_SCENARIO_ROOT='" + root + "'",
		"export PDCS_SCENARIO_NAME='shell-env-test'",
	} {
		if !strings.Contains(exports, want) {
			t.Errorf("ShellExports() missing %q in:\n%s", want, exports)
		}
	}
}

func TestShellEnvironmentSeesPersistedStepOutputs(t *testing.T) {
	root := t.TempDir()
	writeTestScenario(t, root, `name: shell-env-output-test
env:
  - name: DYNAMIC_VALUE
steps:
  - id: publish
    type: sh
    path: publish.sh
    outputs: [DYNAMIC_VALUE]
`)
	writeExecutable(t, filepath.Join(root, "publish.sh"), `#!/usr/bin/env bash
set -euo pipefail
printf '%s\0%s\0' DYNAMIC_VALUE 'created=by-step' >> "$PDCS_ENV_OUTPUT_FILE"
`)

	o, err := New(Config{ScenarioFile: filepath.Join(root, "scenario.yaml"), ScenarioRoot: root})
	if err != nil {
		t.Fatalf("New(): %v", err)
	}
	if err := o.Run(context.Background()); err != nil {
		t.Fatalf("Run(): %v", err)
	}

	reloaded, err := New(Config{ScenarioFile: filepath.Join(root, "scenario.yaml"), ScenarioRoot: root})
	if err != nil {
		t.Fatalf("New() after run: %v", err)
	}
	if got := reloaded.ShellEnvironment()["DYNAMIC_VALUE"]; got != "created=by-step" {
		t.Fatalf("shell env DYNAMIC_VALUE = %q, want persisted step output", got)
	}
	if !strings.Contains(ShellExports(reloaded.ShellEnvironment()), "export DYNAMIC_VALUE='created=by-step'") {
		t.Fatal("ShellExports() missing the persisted step output")
	}
}
