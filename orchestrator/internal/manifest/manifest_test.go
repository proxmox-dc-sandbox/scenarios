package manifest

import "testing"

func TestParseValid(t *testing.T) {
	data := []byte(`
name: replica-bank
description: "Test"
steps:
  - id: network
    type: terraform
    path: infra/network
  - id: vms
    type: terraform
    path: infra/vms
    depends_on: [network]
  - id: configure
    type: ansible
    path: infra/ansible/site.yml
    depends_on: [vms]
    optional: true
    description: "Installe la stack"
  - id: seed
    type: sh
    path: infra/scripts/seed.sh
    phase: chaos
  - id: recon
    type: go
    path: redteam/recon
    phase: redteam
`)

	sc, err := Parse(data)
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}
	if sc.Name != "replica-bank" {
		t.Errorf("Name = %q, want replica-bank", sc.Name)
	}
	if len(sc.Steps) != 5 {
		t.Fatalf("got %d steps, want 5", len(sc.Steps))
	}
	if sc.Steps[0].ManagementPhase() != "main" {
		t.Errorf("step 0 default phase = %q, want main", sc.Steps[0].ManagementPhase())
	}
	if sc.Steps[3].ManagementPhase() != "chaos" {
		t.Errorf("step 3 phase = %q, want chaos", sc.Steps[3].ManagementPhase())
	}
	if !sc.Steps[2].Optional {
		t.Error("step 2 should be optional")
	}
}

func TestParseInvalidYAML(t *testing.T) {
	data := []byte("name: [broken\n  steps: 1\n")
	if _, err := Parse(data); err == nil {
		t.Fatal("Parse() = nil error, want YAML parse error")
	}
}

func TestParseMissingName(t *testing.T) {
	data := []byte("steps:\n  - id: a\n    type: sh\n    path: x.sh\n")
	if _, err := Parse(data); err == nil {
		t.Fatal("Parse() = nil error, want missing name error")
	}
}

func TestParseNoSteps(t *testing.T) {
	data := []byte("name: empty-ish\n")
	if _, err := Parse(data); err == nil {
		t.Fatal("Parse() = nil error, want at least one step error")
	}
}

func TestParseInvalidType(t *testing.T) {
	data := []byte("name: t\nsteps:\n  - id: a\n    type: make\n    path: x\n")
	if _, err := Parse(data); err == nil {
		t.Fatal("Parse() = nil error, want invalid type error")
	}
}

func TestParseMissingPath(t *testing.T) {
	data := []byte("name: t\nsteps:\n  - id: a\n    type: sh\n")
	if _, err := Parse(data); err == nil {
		t.Fatal("Parse() = nil error, want missing path error")
	}
}

func TestParseDuplicateID(t *testing.T) {
	data := []byte("name: t\nsteps:\n  - id: a\n    type: sh\n    path: x\n  - id: a\n    type: sh\n    path: y\n")
	if _, err := Parse(data); err == nil {
		t.Fatal("Parse() = nil error, want duplicate id error")
	}
}

func TestParseInvalidPhase(t *testing.T) {
	data := []byte("name: t\nsteps:\n  - id: a\n    type: sh\n    path: x\n    phase: deploy\n")
	if _, err := Parse(data); err == nil {
		t.Fatal("Parse() = nil error, want invalid phase error")
	}
}
