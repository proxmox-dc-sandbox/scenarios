package state

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, ".state", "demo.json")

	st := New("demo")
	st.SetEnvironment("API_TOKEN", "secret=value")
	st.Begin("network")
	if st.Status("network") != StatusRunning {
		t.Fatalf("Status() after Begin = %q, want running", st.Status("network"))
	}
	st.Finish("network", StatusDone, "")
	st.Finish("vms", StatusFailed, "boom: apply failed")
	if err := st.Save(path); err != nil {
		t.Fatalf("Save() error = %v", err)
	}

	got, err := Load("demo", path)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if got.Scenario != "demo" {
		t.Errorf("Scenario = %q, want demo", got.Scenario)
	}
	if got.Environment()["API_TOKEN"] != "secret=value" {
		t.Errorf("API_TOKEN = %q, want persisted value", got.Environment()["API_TOKEN"])
	}
	if got.Status("network") != StatusDone {
		t.Errorf("network status = %q, want done", got.Status("network"))
	}
	rec := got.Steps["vms"]
	if rec.Status != StatusFailed || rec.Error != "boom: apply failed" {
		t.Errorf("vms record = %+v, want failed with error", rec)
	}
	if got.Status("configure") != StatusPending {
		t.Errorf("unknown step status = %q, want pending", got.Status("configure"))
	}
}

func TestLoadMissingFileReturnsEmpty(t *testing.T) {
	st, err := Load("demo", filepath.Join(t.TempDir(), "nope.json"))
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if st.Scenario != "demo" || len(st.Steps) != 0 {
		t.Errorf("Load() missing = %+v, want empty state", st)
	}
}

func TestSkip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "s.json")
	st := New("demo")
	st.Skip("optional-step")
	if err := st.Save(path); err != nil {
		t.Fatalf("Save() error = %v", err)
	}
	got, err := Load("demo", path)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if got.Status("optional-step") != StatusSkipped {
		t.Errorf("status = %q, want skipped", got.Status("optional-step"))
	}
}

func TestSaveCreatesNestedDir(t *testing.T) {
	path := filepath.Join(t.TempDir(), "a", "b", "c.json")
	st := New("demo")
	st.Begin("x")
	if err := st.Save(path); err != nil {
		t.Fatalf("Save() into nested dir error = %v", err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Errorf("state file not created: %v", err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("Stat() state file error = %v", err)
	}
	if got := info.Mode().Perm(); got != 0o600 {
		t.Errorf("state mode = %o, want 600", got)
	}
}
