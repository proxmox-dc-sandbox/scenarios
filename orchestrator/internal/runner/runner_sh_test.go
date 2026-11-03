package runner

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"testing"

	"pdcs/orchestrator/internal/manifest"
)

func TestShellRunnerPassesArgsAndEnv(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "check.sh")
	content := `#!/usr/bin/env bash
set -euo pipefail
[ "$1" = "first arg" ]
[ "$2" = "--flag" ]
[ "${EXTRA_FROM_STEP:-}" = "42" ]
echo ok
`
	if err := os.WriteFile(script, []byte(content), 0o755); err != nil {
		t.Fatal(err)
	}

	step := manifest.Step{
		ID:   "check",
		Type: manifest.TypeSh,
		Path: "check.sh",
		Args: []string{"first arg", "--flag"},
		Env:  map[string]string{"EXTRA_FROM_STEP": "42"},
	}
	var out bytes.Buffer
	if err := (&ShellRunner{}).Run(context.Background(), step, dir, &out); err != nil {
		t.Fatalf("Run: %v\noutput: %s", err, out.String())
	}
	if got := out.String(); got != "ok\n" {
		t.Fatalf("unexpected output: %q", got)
	}
}
