// Package manifest parses and validates scenario manifests (scenario.yaml).
package manifest

import (
	"errors"
	"fmt"
	"os"
	"regexp"
	"strings"

	"gopkg.in/yaml.v3"
)

// StepType enumerates the accepted step kinds.
type StepType string

const (
	TypeTerraform  StepType = "terraform"
	TypeTerragrunt StepType = "terragrunt"
	TypeAnsible    StepType = "ansible"
	TypeSh         StepType = "sh"
	TypeGo         StepType = "go"
)

// Phase enumerates the accepted execution phases.
const (
	PhaseMain    = "main"
	PhaseChaos   = "chaos"
	PhaseRedteam = "redteam"
)

var (
	validEnvName = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)
	validTypes   = map[StepType]bool{
		TypeTerraform:  true,
		TypeTerragrunt: true,
		TypeAnsible:    true,
		TypeSh:         true,
		TypeGo:         true,
	}
	validPhases = map[string]bool{
		PhaseMain:    true,
		PhaseChaos:   true,
		PhaseRedteam: true,
	}
)

// Step describes a single executable unit of a scenario.
type Step struct {
	ID          string            `yaml:"id"`
	Type        StepType          `yaml:"type"`
	Path        string            `yaml:"path"`
	Args        []string          `yaml:"args,omitempty"`
	Env         map[string]string `yaml:"env,omitempty"`
	RequiresEnv []string          `yaml:"requires_env,omitempty"`
	Outputs     []string          `yaml:"outputs,omitempty"`
	DependsOn   []string          `yaml:"depends_on,omitempty"`
	Phase       string            `yaml:"phase,omitempty"`
	Optional    bool              `yaml:"optional,omitempty"`
	Description string            `yaml:"description,omitempty"`
}

// EnvVar declares an environment variable owned by the scenario manifest.
// Value is the configured source of truth; Generate asks the orchestrator to
// create and persist a secret in scenario state; Path makes relative values
// relative to the scenario root. Required fails before the first step when a
// value that must be supplied by a prior step is still missing.
type EnvVar struct {
	Name        string `yaml:"name"`
	Value       string `yaml:"value,omitempty"`
	Required    bool   `yaml:"required,omitempty"`
	Generate    bool   `yaml:"generate,omitempty"`
	Path        bool   `yaml:"path,omitempty"`
	Description string `yaml:"description,omitempty"`
}

// ManagementPhase returns the effective phase of the step ("main" when unset).
func (s Step) ManagementPhase() string {
	if s.Phase == "" {
		return PhaseMain
	}
	return s.Phase
}

// Scenario is the root object of a scenario manifest.
type Scenario struct {
	Name        string   `yaml:"name"`
	Description string   `yaml:"description,omitempty"`
	Env         []EnvVar `yaml:"env,omitempty"`
	Steps       []Step   `yaml:"steps"`
	// Cleanup lists the teardown steps, run with -down. They run in
	// declaration order (unless depends_on says otherwise).
	Cleanup []Step `yaml:"cleanup,omitempty"`
}

// Load reads and parses a scenario manifest from disk.
func Load(path string) (*Scenario, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("scenario manifest: %w", err)
	}
	sc, err := Parse(data)
	if err != nil {
		return nil, fmt.Errorf("scenario manifest %q: %w", path, err)
	}
	return sc, nil
}

// Parse parses and validates raw YAML content.
func Parse(data []byte) (*Scenario, error) {
	var sc Scenario
	if err := yaml.Unmarshal(data, &sc); err != nil {
		return nil, fmt.Errorf("invalid YAML: %w", err)
	}
	if err := sc.Validate(); err != nil {
		return nil, err
	}
	return &sc, nil
}

// Validate checks the structural rules of the manifest.
func (s *Scenario) Validate() error {
	if strings.TrimSpace(s.Name) == "" {
		return errors.New("field 'name' is required")
	}
	if len(s.Steps) == 0 {
		return fmt.Errorf("scenario %q: at least one step is required", s.Name)
	}

	envSeen := make(map[string]bool, len(s.Env))
	envByName := make(map[string]EnvVar, len(s.Env))
	for i, e := range s.Env {
		if strings.TrimSpace(e.Name) == "" {
			return fmt.Errorf("scenario %q: env entry #%d is missing required field 'name'", s.Name, i+1)
		}
		if !validEnvName.MatchString(e.Name) {
			return fmt.Errorf("scenario %q: env variable %q is not a valid environment name", s.Name, e.Name)
		}
		if e.Name == "PDCS_ENV_OUTPUT_FILE" || e.Name == "PDCS_SCENARIO_ROOT" {
			return fmt.Errorf("scenario %q: env variable %q is reserved for the orchestrator", s.Name, e.Name)
		}
		if envSeen[e.Name] {
			return fmt.Errorf("scenario %q: duplicate env variable %q", s.Name, e.Name)
		}
		envSeen[e.Name] = true
		envByName[e.Name] = e
		if e.Generate && e.Value != "" {
			return fmt.Errorf("scenario %q: env variable %q cannot set both 'value' and 'generate'", s.Name, e.Name)
		}
	}

	seen := make(map[string]bool, len(s.Steps)+len(s.Cleanup))
	for i, st := range s.Steps {
		if err := validateStep(s.Name, i, st); err != nil {
			return err
		}
		if seen[st.ID] {
			return fmt.Errorf("scenario %q: duplicate step id %q", s.Name, st.ID)
		}
		seen[st.ID] = true
	}
	for i, st := range s.Cleanup {
		if err := validateStep(s.Name, i, st); err != nil {
			return fmt.Errorf("cleanup: %w", err)
		}
		if seen[st.ID] {
			return fmt.Errorf("scenario %q: duplicate step id %q (steps and cleanup share the same id space)", s.Name, st.ID)
		}
		seen[st.ID] = true
	}

	for _, st := range append(append([]Step{}, s.Steps...), s.Cleanup...) {
		for _, name := range st.RequiresEnv {
			if !envSeen[name] {
				return fmt.Errorf("scenario %q: step %q requires env %q which is not declared in the 'env:' block", s.Name, st.ID, name)
			}
		}
		outputsSeen := make(map[string]bool, len(st.Outputs))
		for _, name := range st.Outputs {
			if outputsSeen[name] {
				return fmt.Errorf("scenario %q: step %q declares output %q more than once", s.Name, st.ID, name)
			}
			outputsSeen[name] = true
			e, ok := envByName[name]
			if !ok {
				return fmt.Errorf("scenario %q: step %q outputs env %q which is not declared in the 'env:' block", s.Name, st.ID, name)
			}
			if e.Value != "" || e.Generate {
				return fmt.Errorf("scenario %q: step %q cannot output env %q because it has a manifest value or is generated", s.Name, st.ID, name)
			}
		}
	}
	return nil
}

func validateStep(scenarioName string, index int, st Step) error {
	if strings.TrimSpace(st.ID) == "" {
		return fmt.Errorf("scenario %q: step #%d is missing required field 'id'", scenarioName, index+1)
	}
	if !validTypes[st.Type] {
		return fmt.Errorf("scenario %q: step %q has invalid type %q (expected terraform|terragrunt|ansible|sh|go)", scenarioName, st.ID, st.Type)
	}
	if strings.TrimSpace(st.Path) == "" {
		return fmt.Errorf("scenario %q: step %q is missing required field 'path'", scenarioName, st.ID)
	}
	if st.Phase != "" && !validPhases[st.Phase] {
		return fmt.Errorf("scenario %q: step %q has invalid phase %q (expected main|chaos|redteam)", scenarioName, st.ID, st.Phase)
	}
	return nil
}
