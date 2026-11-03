// Package orchestrator drives the execution of a scenario: topological
// ordering, phase filtering, guided/auto/resume modes, per-step logs and a
// final summary.
package orchestrator

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"pdcs/orchestrator/internal/graph"
	"pdcs/orchestrator/internal/manifest"
	"pdcs/orchestrator/internal/runner"
	"pdcs/orchestrator/internal/state"
)

// Config carries the CLI options for a run.
type Config struct {
	ScenarioFile    string // path to scenario.yaml
	ScenarioRoot    string // optional override; defaults to the manifest dir
	Phase           string // "main" (default) | "chaos" | "redteam"
	Auto            bool
	Guided          bool
	Resume          bool
	Reset           bool // wipe the persisted state (and logs) before running
	ContinueOnError bool // when false, a failed non-optional step stops the run
	Down            bool // run the manifest's cleanup steps (teardown)
	Check           bool // validate only; do not generate or persist runtime values
}

// ErrQuit is returned when the user quits a guided run; state is already saved.
var ErrQuit = errors.New("quit requested by user")

// Orchestrator is the execution engine of a scenario.
type Orchestrator struct {
	cfg        Config
	sc         *manifest.Scenario
	order      []string
	byID       map[string]manifest.Step
	st         *state.State
	root       string
	stateFile  string
	logDir     string
	runner     runner.Registry
	steps      []manifest.Step
	missingEnv []string
	env        map[string]string
}

// New loads the manifest, resolves the execution order and restores the
// persisted state. Runtime state/log directories are created for normal runs.
func New(cfg Config) (*Orchestrator, error) {
	if cfg.Phase == "" {
		cfg.Phase = manifest.PhaseMain
	}
	sc, err := manifest.Load(cfg.ScenarioFile)
	if err != nil {
		return nil, err
	}

	stepsList := sc.Steps
	suffix := ""
	if cfg.Down {
		if len(sc.Cleanup) == 0 {
			return nil, fmt.Errorf("scenario %q has no cleanup section (nothing to tear down)", sc.Name)
		}
		stepsList = sc.Cleanup
		suffix = "-cleanup"
	}

	order, err := graph.Order(stepsList)
	if err != nil {
		return nil, fmt.Errorf("order resolution: %w", err)
	}

	root := cfg.ScenarioRoot
	if root == "" {
		root = filepath.Dir(cfg.ScenarioFile)
	}
	root, err = filepath.Abs(root)
	if err != nil {
		return nil, fmt.Errorf("resolve scenario root: %w", err)
	}

	stateFile := filepath.Join(root, ".state", sc.Name+suffix+".json")
	logDir := filepath.Join(root, "logs", sc.Name+suffix)

	if cfg.Reset && !cfg.Check {
		// Force a full fresh run: drop the persisted state and the per-step
		// logs before loading (the state file would otherwise be restored).
		if err := os.Remove(stateFile); err != nil && !errors.Is(err, os.ErrNotExist) {
			return nil, fmt.Errorf("reset state %q: %w", stateFile, err)
		}
		if err := os.RemoveAll(logDir); err != nil {
			return nil, fmt.Errorf("reset logs %q: %w", logDir, err)
		}
	}

	st := state.New(sc.Name)
	persistedEnv := map[string]string{}
	if !cfg.Check {
		if cfg.Down {
			// Cleanup has a separate status file, but uses runtime outputs and
			// generated credentials from the successful install run.
			installState, err := state.Load(sc.Name, filepath.Join(root, ".state", sc.Name+".json"))
			if err != nil {
				return nil, err
			}
			for name, value := range installState.Environment() {
				persistedEnv[name] = value
			}
		}
		var err error
		st, err = state.Load(sc.Name, stateFile)
		if err != nil {
			return nil, err
		}
		for name, value := range st.Environment() {
			persistedEnv[name] = value
		}
	}

	resolved, missing, _, err := resolveEnvironment(sc, root, persistedEnv, false)
	if err != nil {
		return nil, err
	}
	generated := map[string]string{}
	if !cfg.Down && !cfg.Check && len(missing) == 0 {
		resolved, missing, generated, err = resolveEnvironment(sc, root, persistedEnv, true)
		if err != nil {
			return nil, err
		}
	}
	for name, value := range generated {
		st.SetEnvironment(name, value)
	}
	if len(generated) > 0 && !cfg.Check {
		if err := st.Save(stateFile); err != nil {
			return nil, err
		}
	}

	byID := make(map[string]manifest.Step, len(stepsList))
	for _, s := range stepsList {
		byID[s.ID] = s
	}

	o := &Orchestrator{
		cfg:        cfg,
		sc:         sc,
		order:      order,
		byID:       byID,
		st:         st,
		root:       root,
		stateFile:  stateFile,
		runner:     runner.NewRegistry(),
		logDir:     logDir,
		steps:      stepsList,
		missingEnv: missing,
		env:        resolved,
	}
	if !cfg.Check {
		if err := os.MkdirAll(o.logDir, 0o755); err != nil {
			return nil, fmt.Errorf("create log dir: %w", err)
		}
	}
	return o, nil
}

var envNamePattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

// resolveEnvironment builds the scenario-owned environment from manifest
// values and persisted outputs. Generated secrets are written to state so a
// resume or teardown sees the same values without a separate .env file.
func resolveEnvironment(sc *manifest.Scenario, root string, persisted map[string]string, generate bool) (map[string]string, []string, map[string]string, error) {
	resolved := make(map[string]string, len(sc.Env))
	generated := make(map[string]string)
	var missing []string

	for _, declaration := range sc.Env {
		value := declaration.Value
		if value != "" {
			value = manifest.Expand(value, resolved)
			if declaration.Path {
				if !filepath.IsAbs(value) {
					value = filepath.Join(root, value)
				}
				abs, err := filepath.Abs(value)
				if err != nil {
					return nil, nil, nil, fmt.Errorf("resolve path env %q: %w", declaration.Name, err)
				}
				value = abs
			}
		} else if persistedValue, ok := persisted[declaration.Name]; ok {
			value = persistedValue
		} else if declaration.Generate && generate {
			secret, err := randomSecret()
			if err != nil {
				return nil, nil, nil, err
			}
			value = secret
			generated[declaration.Name] = secret
		}

		if value == "" && declaration.Required && !declaration.Generate {
			missing = append(missing, declaration.Name)
		}
		resolved[declaration.Name] = value
	}
	return resolved, missing, generated, nil
}

func randomSecret() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("generate scenario secret: %w", err)
	}
	return hex.EncodeToString(buf), nil
}

func cloneStep(step manifest.Step) manifest.Step {
	step.Args = append([]string(nil), step.Args...)
	step.Outputs = append([]string(nil), step.Outputs...)
	if step.Env != nil {
		step.Env = cloneEnvironment(step.Env)
	}
	return step
}

func cloneEnvironment(source map[string]string) map[string]string {
	copy := make(map[string]string, len(source))
	for name, value := range source {
		copy[name] = value
	}
	return copy
}

func outputFile() (string, func(), error) {
	f, err := os.CreateTemp("", "pdcs-env-output-*")
	if err != nil {
		return "", nil, fmt.Errorf("create step environment output: %w", err)
	}
	path := f.Name()
	if err := f.Chmod(0o600); err != nil {
		_ = f.Close()
		_ = os.Remove(path)
		return "", nil, fmt.Errorf("protect step environment output: %w", err)
	}
	if err := f.Close(); err != nil {
		_ = os.Remove(path)
		return "", nil, fmt.Errorf("close step environment output: %w", err)
	}
	return path, func() { _ = os.Remove(path) }, nil
}

func readStepOutputs(path string, declared []string) (map[string]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read step environment outputs: %w", err)
	}
	outputs := make(map[string]string, len(declared))
	allowed := make(map[string]bool, len(declared))
	for _, name := range declared {
		allowed[name] = true
	}
	if len(data) == 0 {
		if len(declared) > 0 {
			return nil, fmt.Errorf("step did not publish declared environment outputs: %s", strings.Join(declared, ", "))
		}
		return outputs, nil
	}

	parts := bytes.Split(data, []byte{0})
	if len(parts) > 0 && len(parts[len(parts)-1]) == 0 {
		parts = parts[:len(parts)-1]
	}
	if len(parts)%2 != 0 {
		return nil, errors.New("step environment output is malformed (expected NUL-delimited name/value pairs)")
	}
	for i := 0; i < len(parts); i += 2 {
		name, value := string(parts[i]), string(parts[i+1])
		if !envNamePattern.MatchString(name) {
			return nil, fmt.Errorf("step published invalid environment name %q", name)
		}
		if !allowed[name] {
			return nil, fmt.Errorf("step published undeclared environment output %q", name)
		}
		if _, exists := outputs[name]; exists {
			return nil, fmt.Errorf("step published environment output %q more than once", name)
		}
		if value == "" {
			return nil, fmt.Errorf("step published empty environment output %q", name)
		}
		outputs[name] = value
	}
	for _, name := range declared {
		if _, ok := outputs[name]; !ok {
			return nil, fmt.Errorf("step did not publish declared environment output %q", name)
		}
	}
	return outputs, nil
}

// Name returns the scenario name (used by -check).
func (o *Orchestrator) Name() string { return o.sc.Name }

// StepCount returns the number of steps (used by -check).
func (o *Orchestrator) StepCount() int { return len(o.steps) }

// CleanupCount returns the number of cleanup steps (used by -check).
func (o *Orchestrator) CleanupCount() int { return len(o.sc.Cleanup) }

// MissingEnv returns required inputs not present in the manifest/state and not
// produced by any step. Generated runtime outputs are not reported as missing.
func (o *Orchestrator) MissingEnv() []string {
	missing := make(map[string]bool, len(o.missingEnv))
	for _, name := range o.missingEnv {
		missing[name] = true
	}
	produced := make(map[string]bool)
	generated := make(map[string]bool)
	for _, declaration := range o.sc.Env {
		generated[declaration.Name] = declaration.Generate
	}
	steps := append(append([]manifest.Step{}, o.sc.Steps...), o.sc.Cleanup...)
	for _, step := range steps {
		for _, name := range step.Outputs {
			produced[name] = true
		}
	}
	for _, step := range steps {
		for _, name := range step.RequiresEnv {
			if o.env[name] == "" && !produced[name] && !generated[name] {
				missing[name] = true
			}
		}
	}
	result := make([]string, 0, len(missing))
	for name := range missing {
		result = append(result, name)
	}
	sort.Strings(result)
	return result
}

// Run executes the steps of the selected phase (or the cleanup steps in
// down mode) and prints a final summary.
func (o *Orchestrator) Run(ctx context.Context) error {
	if len(o.missingEnv) > 0 && !o.cfg.Down {
		return fmt.Errorf("missing required scenario values: %s (set 'value:' in scenario.yaml)",
			strings.Join(o.missingEnv, ", "))
	}

	var done, failed, skipped, notRun int

	mode := "auto"
	switch {
	case o.cfg.Guided:
		mode = "guided"
	case o.cfg.Resume:
		mode = "resume"
	}
	phase := o.cfg.Phase
	if o.cfg.Down {
		phase = "cleanup"
	}
	fmt.Printf("scenario=%q phase=%s mode=%s state=%s\n", o.sc.Name, phase, mode, o.stateFile)

	for _, id := range o.order {
		step := cloneStep(o.byID[id])
		if !o.cfg.Down && step.ManagementPhase() != o.cfg.Phase {
			continue // steps of other phases are only run when requested
		}
		if o.cfg.Resume && (o.st.Status(id) == state.StatusDone || o.st.Status(id) == state.StatusSkipped) {
			continue
		}

		if err := o.checkDependencies(step); err != nil {
			err = fmt.Errorf("step %q: %w", id, err)
			if o.cfg.ContinueOnError {
				o.st.Finish(id, state.StatusFailed, err.Error())
				if saveErr := o.st.Save(o.stateFile); saveErr != nil {
					return fmt.Errorf("persist state after dependency failure: %w", saveErr)
				}
				failed++
				fmt.Printf("  [SKIP] %s (%v)\n", id, err)
				continue
			}
			fmt.Printf("  [ERROR] %s: %v\n", id, err)
			return err
		}

		// Environment requirements are checked right before the step runs,
		// not up front: some values only exist after earlier steps publish them.
		if len(step.RequiresEnv) > 0 {
			if missing := o.missingForStep(step); len(missing) > 0 {
				err := fmt.Errorf("step %q: missing scenario values: %s (set inputs in scenario.yaml or fix the producing step, then re-run with -resume)",
					id, strings.Join(missing, ", "))
				if o.cfg.ContinueOnError {
					o.st.Finish(id, state.StatusFailed, err.Error())
					if saveErr := o.st.Save(o.stateFile); saveErr != nil {
						return fmt.Errorf("persist state after missing environment: %w", saveErr)
					}
					failed++
					fmt.Printf("  [SKIP] %s (%v)\n", id, err)
					continue
				}
				fmt.Printf("  [ERROR] %s: %v\n", id, err)
				return err
			}
		}

		manifest.ExpandStep(&step, o.env)

		if o.cfg.Guided {
			action, err := o.prompt(step)
			if err != nil {
				return err
			}
			switch action {
			case "skip":
				o.st.Skip(id)
				if err := o.st.Save(o.stateFile); err != nil {
					return fmt.Errorf("persist skipped step %q: %w", id, err)
				}
				skipped++
				continue
			case "quit":
				if err := o.st.Save(o.stateFile); err != nil {
					return fmt.Errorf("persist state before quit: %w", err)
				}
				return ErrQuit
			}
		}

		fmt.Printf("==> step %s (%s): %s\n", step.ID, step.Type, step.Description)
		r, ok := o.runner[step.Type]
		if !ok {
			return fmt.Errorf("step %q: no runner for type %q", step.ID, step.Type)
		}

		o.st.Begin(id)
		if err := o.st.Save(o.stateFile); err != nil {
			return fmt.Errorf("persist running state for step %q: %w", id, err)
		}

		logw, closeFn, err := o.stepLogWriter(step)
		if err != nil {
			return fmt.Errorf("step %q: %w", id, err)
		}

		logCli := logw
		if o.cfg.Guided {
			logCli = io.MultiWriter(logw, os.Stdout)
		}

		outputsPath, removeOutputs, err := outputFile()
		if err != nil {
			closeFn()
			return fmt.Errorf("step %q: %w", id, err)
		}
		step.Env = cloneEnvironment(o.env)
		for name, value := range o.byID[id].Env {
			step.Env[name] = manifest.Expand(value, o.env)
		}
		step.Env["PDCS_SCENARIO_ROOT"] = o.root
		step.Env["PDCS_ENV_OUTPUT_FILE"] = outputsPath

		runErr := r.Run(ctx, step, o.root, logCli)
		closeFn()
		if runErr == nil {
			outputs, outputErr := readStepOutputs(outputsPath, step.Outputs)
			if outputErr != nil {
				runErr = outputErr
			} else {
				for name, value := range outputs {
					o.env[name] = value
					o.st.SetEnvironment(name, value)
				}
			}
		}
		removeOutputs()

		if runErr != nil {
			o.st.Finish(id, state.StatusFailed, runErr.Error())
			if saveErr := o.st.Save(o.stateFile); saveErr != nil {
				return fmt.Errorf("step %q failed (%v) and state could not be persisted: %w", id, runErr, saveErr)
			}
			failed++
			fmt.Printf("  [FAILED] %s: %v (log: %s/%s.log)\n", id, runErr, o.logDir, id)
			if !step.Optional && !o.cfg.ContinueOnError {
				return runErr
			}
			continue
		}

		o.st.Finish(id, state.StatusDone, "")
		if err := o.st.Save(o.stateFile); err != nil {
			return fmt.Errorf("persist completed step %q and its environment outputs: %w", id, err)
		}
		done++
		fmt.Printf("  [OK] %s\n", id)
	}

	notRun = o.unexecutedSteps()
	o.printSummary(done, failed, skipped, notRun)
	return nil
}

// missingForStep returns the step's required environment variables that are
// not set at execution time.
func (o *Orchestrator) missingForStep(step manifest.Step) []string {
	var missing []string
	for _, name := range step.RequiresEnv {
		if o.env[name] == "" {
			missing = append(missing, name)
		}
	}
	return missing
}

// checkDependencies ensures every dependency of a step is already done.
func (o *Orchestrator) checkDependencies(step manifest.Step) error {
	for _, dep := range step.DependsOn {
		switch o.st.Status(dep) {
		case state.StatusDone:
			continue
		case state.StatusSkipped:
			continue
		default:
			return fmt.Errorf("dependency %q is not done (status %q); run its phase first or resume after it succeeds",
				dep, o.st.Status(dep))
		}
	}
	return nil
}

// prompt asks the user what to do with the step in guided mode.
//   - Enter: run
//   - s: skip (optional steps only)
//   - q: quit now (state is saved by the caller)
func (o *Orchestrator) prompt(step manifest.Step) (string, error) {
	reader := bufio.NewReader(os.Stdin)
	for {
		msg := fmt.Sprintf("Step %q [%s] %s (Enter=run", step.ID, step.Type, step.Description)
		if step.Optional {
			msg += ", s=skip"
		}
		msg += ", q=quit) > "
		fmt.Print(msg)
		line, err := reader.ReadString('\n')
		if err != nil && line == "" {
			return "", err
		}
		switch strings.TrimSpace(line) {
		case "":
			return "run", nil
		case "s", "S":
			if !step.Optional {
				fmt.Println("This step is not optional, it cannot be skipped.")
				continue
			}
			return "skip", nil
		case "q", "Q":
			return "quit", nil
		default:
			fmt.Println("Accepted inputs: Enter (run), s (skip, optional only), q (quit).")
		}
	}
}

// stepLogWriter opens (creating it if needed) the per-step log file.
func (o *Orchestrator) stepLogWriter(step manifest.Step) (io.Writer, func(), error) {
	f, err := os.Create(filepath.Join(o.logDir, step.ID+".log"))
	if err != nil {
		return nil, nil, fmt.Errorf("open log: %w", err)
	}
	return f, func() { _ = f.Close() }, nil
}

// unexecutedSteps counts the steps of the selected phase that are still pending.
func (o *Orchestrator) unexecutedSteps() int {
	n := 0
	for _, id := range o.order {
		if !o.cfg.Down && o.byID[id].ManagementPhase() != o.cfg.Phase {
			continue
		}
		if o.st.Status(id) == state.StatusPending {
			n++
		}
	}
	return n
}

// printSummary emits the final run summary.
func (o *Orchestrator) printSummary(done, failed, skipped, notRun int) {
	phase := o.cfg.Phase
	if o.cfg.Down {
		phase = "cleanup"
	}
	fmt.Println("----------------------------------------")
	fmt.Printf("Summary : %d done, %d failed, %d skipped, %d not run (phase=%s)\n",
		done, failed, skipped, notRun, phase)
	if o.cfg.Resume {
		fmt.Printf("Resumed run of scenario %q. full state: %s\n", o.sc.Name, o.stateFile)
	}
}
