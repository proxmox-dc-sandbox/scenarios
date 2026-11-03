package manifest

import (
	"regexp"
)

// envRef matches ${VAR} and ${VAR:-default} references.
var envRef = regexp.MustCompile(`\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}`)

// Expand replaces ${VAR} / ${VAR:-default} references using only scenario
// values already resolved by the orchestrator. The process environment is
// deliberately not a second configuration source.
func Expand(value string, resolved map[string]string) string {
	return envRef.ReplaceAllStringFunc(value, func(ref string) string {
		m := envRef.FindStringSubmatch(ref)
		name, def := m[1], m[2]
		if v, ok := resolved[name]; ok && v != "" {
			return v
		}
		return def
	})
}

// ExpandStep applies Expand to the step arguments and step-level environment.
func ExpandStep(st *Step, resolved map[string]string) {
	for i := range st.Args {
		st.Args[i] = Expand(st.Args[i], resolved)
	}
	for k, v := range st.Env {
		st.Env[k] = Expand(v, resolved)
	}
}
