package orchestrator

import (
	"testing"

	"pdcs/orchestrator/internal/manifest"
)

func TestMissingForStep(t *testing.T) {
	t.Setenv("SET_VAR", "value")
	t.Setenv("EMPTY_VAR", "")

	o := &Orchestrator{env: map[string]string{"SET_VAR": "value", "EMPTY_VAR": ""}}
	step := manifest.Step{RequiresEnv: []string{"SET_VAR", "EMPTY_VAR", "NEVER_SET"}}
	missing := o.missingForStep(step)

	if len(missing) != 2 || missing[0] != "EMPTY_VAR" || missing[1] != "NEVER_SET" {
		t.Fatalf("missing = %v, want [EMPTY_VAR NEVER_SET]", missing)
	}
}
