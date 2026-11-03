package runner

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"pdcs/orchestrator/internal/manifest"
)

func TestTerragruntRunnerDefaultsToApply(t *testing.T) {
	dir := t.TempDir()
	tgDir := filepath.Join(dir, "terragrunt")
	if err := os.MkdirAll(tgDir, 0o755); err != nil {
		t.Fatal(err)
	}
	argsFile := filepath.Join(dir, "args.txt")
	installFakeTerragrunt(t, argsFile)

	step := manifest.Step{ID: "tg", Type: manifest.TypeTerragrunt, Path: "terragrunt"}
	var out bytes.Buffer
	if err := (&TerragruntRunner{}).Run(context.Background(), step, dir, &out); err != nil {
		t.Fatalf("Run: %v\noutput: %s", err, out.String())
	}
	assertArgs(t, argsFile, "run --all apply --non-interactive")
}

func TestTerragruntRunnerDestroyAction(t *testing.T) {
	dir := t.TempDir()
	tgDir := filepath.Join(dir, "terragrunt")
	if err := os.MkdirAll(tgDir, 0o755); err != nil {
		t.Fatal(err)
	}
	argsFile := filepath.Join(dir, "args.txt")
	installFakeTerragrunt(t, argsFile)

	step := manifest.Step{ID: "tg-down", Type: manifest.TypeTerragrunt, Path: "terragrunt", Args: []string{"destroy"}}
	var out bytes.Buffer
	if err := (&TerragruntRunner{}).Run(context.Background(), step, dir, &out); err != nil {
		t.Fatalf("Run: %v\noutput: %s", err, out.String())
	}
	assertArgs(t, argsFile, "run --all destroy --non-interactive")
}

func installFakeTerragrunt(t *testing.T, argsFile string) {
	t.Helper()
	binDir := t.TempDir()
	script := "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> \"" + argsFile + "\"\n"
	if err := os.WriteFile(filepath.Join(binDir, "terragrunt"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", binDir+string(os.PathListSeparator)+os.Getenv("PATH"))
}

func assertArgs(t *testing.T, argsFile, want string) {
	t.Helper()
	data, err := os.ReadFile(argsFile)
	if err != nil {
		t.Fatalf("read args: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if got := lines[len(lines)-1]; got != want {
		t.Fatalf("terragrunt args = %q, want %q", got, want)
	}
}
