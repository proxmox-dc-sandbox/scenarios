package orchestrator

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"pdcs/orchestrator/internal/manifest"
	"pdcs/orchestrator/internal/state"
)

func TestStepsUseManifestValuesAndPersistPublishedOutputs(t *testing.T) {
	root := t.TempDir()
	t.Setenv("STATIC_VALUE", "host-value-must-not-win")
	writeTestScenario(t, root, `name: env-test
env:
  - name: STATIC_VALUE
    value: from-manifest
  - name: DYNAMIC_VALUE
steps:
  - id: publish
    type: sh
    path: publish.sh
    outputs: [DYNAMIC_VALUE]
  - id: consume
    type: sh
    path: consume.sh
    depends_on: [publish]
    requires_env: [DYNAMIC_VALUE]
cleanup:
  - id: cleanup
    type: sh
    path: cleanup.sh
    requires_env: [DYNAMIC_VALUE]
`)
	writeExecutable(t, filepath.Join(root, "publish.sh"), `#!/usr/bin/env bash
set -euo pipefail
printf '%s\0%s\0' DYNAMIC_VALUE 'created=by-step' >> "$PDCS_ENV_OUTPUT_FILE"
`)
	writeExecutable(t, filepath.Join(root, "consume.sh"), `#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s|%s' "$STATIC_VALUE" "$DYNAMIC_VALUE" "$PDCS_SCENARIO_ROOT" > "$PDCS_SCENARIO_ROOT/consumed"
`)
	writeExecutable(t, filepath.Join(root, "cleanup.sh"), `#!/usr/bin/env bash
set -euo pipefail
printf '%s' "$DYNAMIC_VALUE" > "$PDCS_SCENARIO_ROOT/cleaned-with"
`)

	o, err := New(Config{ScenarioFile: filepath.Join(root, "scenario.yaml"), ScenarioRoot: root})
	if err != nil {
		t.Fatalf("New(): %v", err)
	}
	if err := o.Run(context.Background()); err != nil {
		t.Fatalf("Run(): %v", err)
	}

	got, err := os.ReadFile(filepath.Join(root, "consumed"))
	if err != nil {
		t.Fatalf("read consumed values: %v", err)
	}
	want := "from-manifest|created=by-step|" + root
	if string(got) != want {
		t.Fatalf("step environment = %q, want %q", got, want)
	}

	st, err := state.Load("env-test", filepath.Join(root, ".state", "env-test.json"))
	if err != nil {
		t.Fatalf("load persisted state: %v", err)
	}
	if got := st.Environment()["DYNAMIC_VALUE"]; got != "created=by-step" {
		t.Fatalf("persisted DYNAMIC_VALUE = %q, want output value", got)
	}

	cleanup, err := New(Config{ScenarioFile: filepath.Join(root, "scenario.yaml"), ScenarioRoot: root, Down: true})
	if err != nil {
		t.Fatalf("New(-down): %v", err)
	}
	if err := cleanup.Run(context.Background()); err != nil {
		t.Fatalf("Run(-down): %v", err)
	}
	got, err = os.ReadFile(filepath.Join(root, "cleaned-with"))
	if err != nil {
		t.Fatalf("read cleanup value: %v", err)
	}
	if string(got) != "created=by-step" {
		t.Fatalf("cleanup received %q, want persisted output", got)
	}
}

func TestResolveEnvironmentUsesManifestStateAndScenarioRoot(t *testing.T) {
	root := t.TempDir()
	t.Setenv("STATIC_VALUE", "host-value-must-not-win")
	sc := &manifest.Scenario{Env: []manifest.EnvVar{
		{Name: "STATIC_VALUE", Value: "from-manifest"},
		{Name: "ISO_PATH", Value: "assets/proxmox.iso", Path: true},
		{Name: "GENERATED", Generate: true},
		{Name: "DYNAMIC", Required: false},
		{Name: "MISSING", Required: true},
	}}
	resolved, missing, generated, err := resolveEnvironment(sc, root, map[string]string{"DYNAMIC": "from-state"}, true)
	if err != nil {
		t.Fatalf("resolveEnvironment(): %v", err)
	}
	if resolved["STATIC_VALUE"] != "from-manifest" {
		t.Errorf("STATIC_VALUE = %q, want manifest value", resolved["STATIC_VALUE"])
	}
	if resolved["ISO_PATH"] != filepath.Join(root, "assets/proxmox.iso") {
		t.Errorf("ISO_PATH = %q, want scenario-rooted path", resolved["ISO_PATH"])
	}
	if resolved["DYNAMIC"] != "from-state" {
		t.Errorf("DYNAMIC = %q, want persisted output", resolved["DYNAMIC"])
	}
	if len(resolved["GENERATED"]) != 32 || generated["GENERATED"] != resolved["GENERATED"] {
		t.Errorf("generated secret was not returned for persistence")
	}
	if strings.Join(missing, ",") != "MISSING" {
		t.Errorf("missing = %v, want [MISSING]", missing)
	}
}

func TestGeneratedValuesPersistAndCheckDoesNotWriteState(t *testing.T) {
	root := t.TempDir()
	writeTestScenario(t, root, `name: generated-test
env:
  - name: SECRET
    generate: true
steps:
  - id: noop
    type: sh
    path: noop.sh
`)
	writeExecutable(t, filepath.Join(root, "noop.sh"), "#!/usr/bin/env bash\nexit 0\n")
	config := Config{ScenarioFile: filepath.Join(root, "scenario.yaml"), ScenarioRoot: root}
	first, err := New(config)
	if err != nil {
		t.Fatalf("New(): %v", err)
	}
	secret := first.env["SECRET"]
	if len(secret) != 32 {
		t.Fatalf("generated secret length = %d, want 32", len(secret))
	}
	second, err := New(config)
	if err != nil {
		t.Fatalf("New() after state save: %v", err)
	}
	if second.env["SECRET"] != secret {
		t.Fatal("generated secret changed when reloading scenario state")
	}

	checkRoot := t.TempDir()
	writeTestScenario(t, checkRoot, `name: check-test
env:
  - name: SECRET
    generate: true
steps:
  - id: noop
    type: sh
    path: noop.sh
`)
	check, err := New(Config{ScenarioFile: filepath.Join(checkRoot, "scenario.yaml"), ScenarioRoot: checkRoot, Check: true})
	if err != nil {
		t.Fatalf("New(-check): %v", err)
	}
	if check.env["SECRET"] != "" {
		t.Fatal("-check unexpectedly generated a secret")
	}
	if _, err := os.Stat(filepath.Join(checkRoot, ".state")); !os.IsNotExist(err) {
		t.Fatalf("-check created state artifacts: %v", err)
	}
}

func TestMissingRequiredValueStopsBeforeGeneratingSecrets(t *testing.T) {
	root := t.TempDir()
	writeTestScenario(t, root, `name: missing-test
env:
  - name: SECRET
    generate: true
  - name: REQUIRED_INPUT
    required: true
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
	if err := o.Run(context.Background()); err == nil || !strings.Contains(err.Error(), "REQUIRED_INPUT") {
		t.Fatalf("Run() error = %v, want missing REQUIRED_INPUT", err)
	}
	if o.env["SECRET"] != "" {
		t.Fatal("orchestrator generated a secret despite a missing required input")
	}
	if _, err := os.Stat(filepath.Join(root, ".state")); !os.IsNotExist(err) {
		t.Fatalf("missing input created state artifacts: %v", err)
	}
}

func TestMissingEnvReportsExternalStepInputsNotRuntimeOutputs(t *testing.T) {
	root := t.TempDir()
	writeTestScenario(t, root, `name: missing-check-test
env:
  - name: LICENSE_EMAIL
    required: true
  - name: DYNAMIC_OUTPUT
  - name: GENERATED_SECRET
    generate: true
steps:
  - id: discover
    type: sh
    path: discover.sh
    outputs: [DYNAMIC_OUTPUT]
  - id: configure
    type: sh
    path: configure.sh
    requires_env: [LICENSE_EMAIL, DYNAMIC_OUTPUT, GENERATED_SECRET]
`)
	o, err := New(Config{ScenarioFile: filepath.Join(root, "scenario.yaml"), ScenarioRoot: root, Check: true})
	if err != nil {
		t.Fatalf("New(-check): %v", err)
	}
	got := strings.Join(o.MissingEnv(), ",")
	if got != "LICENSE_EMAIL" {
		t.Fatalf("MissingEnv() = %q, want only the unprovided input", got)
	}
}

func writeTestScenario(t *testing.T, root, contents string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(root, "scenario.yaml"), []byte(contents), 0o600); err != nil {
		t.Fatalf("write scenario.yaml: %v", err)
	}
}

func writeExecutable(t *testing.T, path, contents string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(contents), 0o700); err != nil {
		t.Fatalf("write executable %s: %v", path, err)
	}
}
