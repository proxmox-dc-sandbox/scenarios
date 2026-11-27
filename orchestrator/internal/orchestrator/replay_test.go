package orchestrator

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"pdcs/orchestrator/internal/state"
)

func TestReplayRunsOnlyTheRequestedStep(t *testing.T) {
	root := t.TempDir()
	writeTestScenario(t, root, `name: replay-test
env:
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
`)
	counter := filepath.Join(root, "counter")
	writeExecutable(t, filepath.Join(root, "publish.sh"), fmt.Sprintf(`#!/usr/bin/env bash
set -euo pipefail
n=0
[[ -f %q ]] && n=$(cat %q)
n=$((n + 1))
printf '%%s' "$n" > %q
printf 'DYNAMIC_VALUE\0v%%d\0' "$n" >> "$PDCS_ENV_OUTPUT_FILE"
`, counter, counter, counter))
	writeExecutable(t, filepath.Join(root, "consume.sh"), `#!/usr/bin/env bash
set -euo pipefail
printf '%s' "$DYNAMIC_VALUE" > "$PDCS_SCENARIO_ROOT/consumed"
`)

	o, err := New(Config{ScenarioFile: filepath.Join(root, "scenario.yaml"), ScenarioRoot: root})
	if err != nil {
		t.Fatalf("New(): %v", err)
	}
	if err := o.Run(context.Background()); err != nil {
		t.Fatalf("Run(): %v", err)
	}

	consumed, err := os.ReadFile(filepath.Join(root, "consumed"))
	if err != nil {
		t.Fatalf("read consumed: %v", err)
	}
	if string(consumed) != "v1" {
		t.Fatalf("first run consumed = %q, want v1", consumed)
	}

	// Replay only the producing step: it must re-run (and re-publish its
	// outputs) without touching the already done consumer.
	replay, err := New(Config{ScenarioFile: filepath.Join(root, "scenario.yaml"), ScenarioRoot: root, Replay: "publish"})
	if err != nil {
		t.Fatalf("New(-replay): %v", err)
	}
	if err := replay.Run(context.Background()); err != nil {
		t.Fatalf("Run(-replay): %v", err)
	}

	got, err := os.ReadFile(counter)
	if err != nil {
		t.Fatalf("read counter: %v", err)
	}
	if string(got) != "2" {
		t.Fatalf("replayed step ran %s times, want 2 (only the requested step)", got)
	}

	consumed, err = os.ReadFile(filepath.Join(root, "consumed"))
	if err != nil {
		t.Fatalf("read consumed after replay: %v", err)
	}
	if string(consumed) != "v1" {
		t.Fatalf("consumer was re-run by replay (consumed = %q, want v1)", consumed)
	}

	st, err := state.Load("replay-test", filepath.Join(root, ".state", "replay-test.json"))
	if err != nil {
		t.Fatalf("load persisted state: %v", err)
	}
	if got := st.Environment()["DYNAMIC_VALUE"]; got != "v2" {
		t.Fatalf("persisted DYNAMIC_VALUE = %q, want the replayed output v2", got)
	}
	if got := st.Status("consume"); got != state.StatusDone {
		t.Fatalf("consume status after replay = %q, want done (untouched)", got)
	}
	if got := st.Status("publish"); got != state.StatusDone {
		t.Fatalf("publish status after replay = %q, want done", got)
	}
}

func TestReplayRequiresDoneDependencies(t *testing.T) {
	root := t.TempDir()
	writeTestScenario(t, root, `name: replay-deps-test
env:
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
`)
	writeExecutable(t, filepath.Join(root, "publish.sh"), "#!/usr/bin/env bash\nexit 0\n")
	writeExecutable(t, filepath.Join(root, "consume.sh"), "#!/usr/bin/env bash\nexit 0\n")

	// The dependency has never run: replay must refuse to run the step.
	replay, err := New(Config{ScenarioFile: filepath.Join(root, "scenario.yaml"), ScenarioRoot: root, Replay: "consume"})
	if err != nil {
		t.Fatalf("New(-replay): %v", err)
	}
	err = replay.Run(context.Background())
	if err == nil || !strings.Contains(err.Error(), "dependency") {
		t.Fatalf("Run(-replay) error = %v, want a dependency error", err)
	}
}

func TestReplayUnknownStepFailsAtLoad(t *testing.T) {
	root := t.TempDir()
	writeTestScenario(t, root, `name: replay-unknown-test
steps:
  - id: noop
    type: sh
    path: noop.sh
`)
	writeExecutable(t, filepath.Join(root, "noop.sh"), "#!/usr/bin/env bash\nexit 0\n")

	_, err := New(Config{ScenarioFile: filepath.Join(root, "scenario.yaml"), ScenarioRoot: root, Replay: "does-not-exist"})
	if err == nil || !strings.Contains(err.Error(), "does not exist") {
		t.Fatalf("New(-replay) error = %v, want unknown step error", err)
	}
}
