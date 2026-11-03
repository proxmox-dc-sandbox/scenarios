package manifest

import (
	"testing"
)

func TestParseEnvArgsAndCleanup(t *testing.T) {
	sc, err := Parse([]byte(`
name: demo
env:
  - name: REQUIRED_VAR
    required: true
  - name: CONFIGURED_VAR
    value: hello
  - name: DYNAMIC_VAR
steps:
  - id: install
    type: sh
    path: install.sh
    args: ["${REQUIRED_VAR}", "--mode=${MODE:-fast}"]
    env:
      EXTRA: "${CONFIGURED_VAR}"
  - id: publish
    type: sh
    path: publish.sh
    outputs: [DYNAMIC_VAR]
cleanup:
  - id: uninstall
    type: sh
    path: uninstall.sh
    args: ["--destroy"]
`))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(sc.Env) != 3 || len(sc.Cleanup) != 1 {
		t.Fatalf("unexpected manifest: %#v", sc)
	}
	if got := sc.Steps[0].Args[0]; got != "${REQUIRED_VAR}" {
		t.Fatalf("args not preserved: %q", got)
	}
	if got := sc.Steps[0].Env["EXTRA"]; got != "${CONFIGURED_VAR}" {
		t.Fatalf("step env not preserved: %q", got)
	}
	if got := sc.Env[1].Value; got != "hello" {
		t.Fatalf("configured env value = %q, want hello", got)
	}
	if got := sc.Cleanup[0].Args[0]; got != "--destroy" {
		t.Fatalf("cleanup args not parsed: %q", got)
	}
}

func TestValidateEnv(t *testing.T) {
	tests := map[string]string{
		"empty name":                            "name: x\nenv:\n  - name: ''\nsteps:\n  - id: a\n    type: sh\n    path: a.sh\n",
		"duplicate env":                         "name: x\nenv:\n  - name: A\n  - name: A\nsteps:\n  - id: a\n    type: sh\n    path: a.sh\n",
		"duplicate id across steps and cleanup": "name: x\nsteps:\n  - id: a\n    type: sh\n    path: a.sh\ncleanup:\n  - id: a\n    type: sh\n    path: b.sh\n",
		"invalid cleanup step":                  "name: x\nsteps:\n  - id: a\n    type: sh\n    path: a.sh\ncleanup:\n  - id: b\n    type: nope\n    path: b.sh\n",
	}
	for name, yaml := range tests {
		if _, err := Parse([]byte(yaml)); err == nil {
			t.Fatalf("%s: expected a validation error", name)
		}
	}
}

func TestScenarioWithoutCleanupIsValid(t *testing.T) {
	if _, err := Parse([]byte("name: x\nsteps:\n  - id: a\n    type: sh\n    path: a.sh\n")); err != nil {
		t.Fatalf("Parse: %v", err)
	}
}

func TestExpand(t *testing.T) {
	t.Setenv("FROM_OS", "must-not-leak")
	resolved := map[string]string{"FROM_SCENARIO": "scenario-value"}
	cases := map[string]string{
		"${FROM_SCENARIO}":          "scenario-value",
		"${FROM_OS}":                "",
		"${UNKNOWN:-default}":       "default",
		"${UNKNOWN}":                "",
		"prefix-${FROM_SCENARIO}-s": "prefix-scenario-value-s",
		"no-ref":                    "no-ref",
	}
	for in, want := range cases {
		if got := Expand(in, resolved); got != want {
			t.Fatalf("Expand(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestValidateStepOutputs(t *testing.T) {
	valid := "name: x\nenv:\n  - name: GENERATED\nsteps:\n  - id: a\n    type: sh\n    path: a.sh\n    outputs: [GENERATED]\n"
	if _, err := Parse([]byte(valid)); err != nil {
		t.Fatalf("valid output rejected: %v", err)
	}
	invalid := []string{
		"name: x\nsteps:\n  - id: a\n    type: sh\n    path: a.sh\n    outputs: [UNKNOWN]\n",
		"name: x\nenv:\n  - name: STATIC\n    value: configured\nsteps:\n  - id: a\n    type: sh\n    path: a.sh\n    outputs: [STATIC]\n",
		"name: x\nenv:\n  - name: BOTH\n    value: configured\n    generate: true\nsteps:\n  - id: a\n    type: sh\n    path: a.sh\n",
	}
	for _, yaml := range invalid {
		if _, err := Parse([]byte(yaml)); err == nil {
			t.Errorf("expected invalid output/value declaration to fail: %s", yaml)
		}
	}
}

func TestRequiresEnvMustBeDeclared(t *testing.T) {
	declared := "name: x\nenv:\n  - name: FOO\nsteps:\n  - id: a\n    type: sh\n    path: a.sh\n    requires_env: [FOO]\n"
	if _, err := Parse([]byte(declared)); err != nil {
		t.Fatalf("declared variable rejected: %v", err)
	}
	undeclared := "name: x\nsteps:\n  - id: a\n    type: sh\n    path: a.sh\n    requires_env: [NOPE]\n"
	if _, err := Parse([]byte(undeclared)); err == nil {
		t.Fatal("expected an error for an undeclared requires_env variable")
	}
}

func TestRequiresEnvAllowedInCleanup(t *testing.T) {
	yaml := "name: x\nenv:\n  - name: FOO\nsteps:\n  - id: a\n    type: sh\n    path: a.sh\ncleanup:\n  - id: b\n    type: sh\n    path: b.sh\n    requires_env: [FOO]\n"
	if _, err := Parse([]byte(yaml)); err != nil {
		t.Fatalf("cleanup requires_env rejected: %v", err)
	}
}
