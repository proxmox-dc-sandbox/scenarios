// Package graph resolves the execution order of scenario steps.
//
// It performs a topological sort (Kahn's algorithm) over the `depends_on`
// edges and fails fast on unknown dependencies or cycles.
package graph

import (
	"fmt"
	"sort"
	"strings"

	"pdcs/orchestrator/internal/manifest"
)

// Order returns the step IDs in a dependency-respecting execution order.
//
// Steps that are ready at the same time run in their declaration order (the
// order they appear in the manifest), so that a scenario written
// sequentially behaves as expected even without explicit `depends_on`.
//
// It returns an error when a step references an unknown dependency ID or
// when the dependency graph contains a cycle.
func Order(steps []manifest.Step) ([]string, error) {
	byID := make(map[string]manifest.Step, len(steps))
	declIdx := make(map[string]int, len(steps))
	ids := make([]string, 0, len(steps))
	for i, st := range steps {
		byID[st.ID] = st
		declIdx[st.ID] = i
		ids = append(ids, st.ID)
	}

	// Edge validation: every depends_on entry must exist.
	for id, st := range byID {
		for _, dep := range st.DependsOn {
			if _, ok := byID[dep]; !ok {
				return nil, fmt.Errorf("step %q depends on unknown step %q", id, dep)
			}
		}
	}

	// Kahn's algorithm; the ready queue always stays in declaration order so
	// independent steps run the way the author wrote them.
	indegree := make(map[string]int, len(byID))
	dependents := make(map[string][]string, len(byID))
	for id := range byID {
		indegree[id] = 0
	}
	for _, st := range steps {
		for _, dep := range st.DependsOn {
			indegree[st.ID]++
			dependents[dep] = append(dependents[dep], st.ID)
		}
	}
	for _, deps := range dependents {
		sort.Slice(deps, func(a, b int) bool { return declIdx[deps[a]] < declIdx[deps[b]] })
	}

	ready := make([]string, 0, len(byID))
	for _, id := range ids {
		if indegree[id] == 0 {
			ready = append(ready, id)
		}
	}
	sort.Slice(ready, func(a, b int) bool { return declIdx[ready[a]] < declIdx[ready[b]] })

	order := make([]string, 0, len(byID))
	for len(ready) > 0 {
		id := ready[0]
		ready = ready[1:]
		order = append(order, id)
		for _, dep := range dependents[id] {
			indegree[dep]--
			if indegree[dep] == 0 {
				ready = append(ready, dep)
			}
		}
		sort.Slice(ready, func(a, b int) bool { return declIdx[ready[a]] < declIdx[ready[b]] })
	}

	if len(order) != len(byID) {
		var inCycle []string
		for _, id := range ids {
			if indegree[id] > 0 {
				inCycle = append(inCycle, id)
			}
		}
		return nil, fmt.Errorf("dependency cycle detected involving: %s", strings.Join(inCycle, ", "))
	}

	return order, nil
}
