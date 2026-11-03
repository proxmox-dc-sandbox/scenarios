package graph

import (
	"strings"
	"testing"

	"pdcs/orchestrator/internal/manifest"
)

func TestOrderSimpleChain(t *testing.T) {
	depSteps := []manifest.Step{
		{ID: "network", Type: manifest.TypeSh, Path: "n.sh"},
		{ID: "vms", Type: manifest.TypeSh, Path: "v.sh", DependsOn: []string{"network"}},
		{ID: "configure", Type: manifest.TypeSh, Path: "c.sh", DependsOn: []string{"vms"}},
	}
	order, err := Order(depSteps)
	if err != nil {
		t.Fatalf("Order() error = %v", err)
	}
	if len(order) != 3 {
		t.Fatalf("Order() len = %d, want 3", len(order))
	}
	if !posBefore(order, "network", "vms") || !posBefore(order, "vms", "configure") {
		t.Errorf("Order() = %v, deps not respected", order)
	}
}

func TestOrderIndependentFollowsDeclarationOrder(t *testing.T) {
	depSteps := []manifest.Step{
		{ID: "zeta", Type: manifest.TypeSh, Path: "z.sh"},
		{ID: "alpha", Type: manifest.TypeSh, Path: "a.sh"},
	}
	order, err := Order(depSteps)
	if err != nil {
		t.Fatalf("Order() error = %v", err)
	}
	if len(order) != 2 || order[0] != "zeta" || order[1] != "alpha" {
		t.Errorf("Order() = %v, want [zeta alpha] (declaration order preserved)", order)
	}
}

func TestOrderForkAndJoin(t *testing.T) {
	depSteps := []manifest.Step{
		{ID: "root", Type: manifest.TypeSh, Path: "root.sh"},
		{ID: "left", Type: manifest.TypeSh, Path: "left.sh", DependsOn: []string{"root"}},
		{ID: "right", Type: manifest.TypeSh, Path: "right.sh", DependsOn: []string{"root"}},
		{ID: "join", Type: manifest.TypeSh, Path: "join.sh", DependsOn: []string{"left", "right"}},
	}
	order, err := Order(depSteps)
	if err != nil {
		t.Fatalf("Order() error = %v", err)
	}
	if !posBefore(order, "root", "left") || !posBefore(order, "root", "right") ||
		!posBefore(order, "left", "join") || !posBefore(order, "right", "join") {
		t.Errorf("Order() = %v, fork/join edges violated", order)
	}
}

func TestOrderMissingDependency(t *testing.T) {
	depSteps := []manifest.Step{
		{ID: "a", Type: manifest.TypeSh, Path: "a.sh", DependsOn: []string{"ghost"}},
	}
	_, err := Order(depSteps)
	if err == nil {
		t.Fatal("Order() = nil error, want missing dependency error")
	}
	if !strings.Contains(err.Error(), "ghost") {
		t.Errorf("error = %q, want mention of ghost", err)
	}
}

func TestOrderCycle(t *testing.T) {
	depSteps := []manifest.Step{
		{ID: "a", Type: manifest.TypeSh, Path: "a.sh", DependsOn: []string{"b"}},
		{ID: "b", Type: manifest.TypeSh, Path: "b.sh", DependsOn: []string{"c"}},
		{ID: "c", Type: manifest.TypeSh, Path: "c.sh", DependsOn: []string{"a"}},
	}
	_, err := Order(depSteps)
	if err == nil {
		t.Fatal("Order() = nil error, want cycle error")
	}
	if !strings.Contains(strings.ToLower(err.Error()), "cycle") {
		t.Errorf("error = %q, want cycle mention", err)
	}
}

func TestOrderSelfCycle(t *testing.T) {
	depSteps := []manifest.Step{
		{ID: "a", Type: manifest.TypeSh, Path: "a.sh", DependsOn: []string{"a"}},
	}
	_, err := Order(depSteps)
	if err == nil {
		t.Fatal("Order() = nil error, want self-cycle error")
	}
}

func posBefore(order []string, before, after string) bool {
	pos := func(id string) int {
		for i, o := range order {
			if o == id {
				return i
			}
		}
		return -1
	}
	b, a := pos(before), pos(after)
	return b >= 0 && a >= 0 && b < a
}
