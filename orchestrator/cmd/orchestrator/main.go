// Command orchestrator runs a scenario in auto, guided or resume mode.
package main

import (
	"context"
	"fmt"
	"os"
	"strings"

	"pdcs/orchestrator/internal/manifest"
	"pdcs/orchestrator/internal/orchestrator"
)

type options struct {
	scenarioFile    string
	scenarioRoot    string
	phase           string
	auto            bool
	guided          bool
	resume          bool
	reset           bool
	check           bool
	continueOnError bool
	down            bool
}

func usage() {
	fmt.Print(`

usage: orchestrator [options]

Options:
  -scenario <path>      path to scenario.yaml (default: ./scenario.yaml)
  -root <dir>           scenario root override (default: manifest directory)
  -phase <phase>        phase to run: main (default) | chaos | redteam
  -auto                 run all steps of the phase without interaction (default)
  -guided               ask before each step: Enter=run, s=skip (optional only), q=quit
  -resume               skip steps already done/skipped, rerun failed/pending
  -reset                wipe .state/ and logs/ then run everything fresh
  -continue-on-error    keep going after a failed step (default: stop)
  -down                 run the manifest's cleanup section (full teardown)
  -h | -help            show this help

Environment:
  Variables are defined by the manifest 'env:' block. Generated secrets and
  values published by steps are stored privately in .state/<scenario>.json.
  ${VAR} / ${VAR:-default} in step args/env is interpolated from scenario state.
`)
}

func parseArgs(args []string) (*options, error) {
	opts := &options{scenarioFile: "scenario.yaml", phase: manifest.PhaseMain}
	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch arg {
		case "-scenario":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("missing value for -scenario")
			}
			i++
			opts.scenarioFile = args[i]
		case "-root":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("missing value for -root")
			}
			i++
			opts.scenarioRoot = args[i]
		case "-phase":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("missing value for -phase")
			}
			i++
			opts.phase = args[i]
		case "-auto":
			opts.auto = true
		case "-guided":
			opts.guided = true
		case "-resume":
			opts.resume = true
		case "-reset":
			opts.reset = true
		case "-check":
			opts.check = true
		case "-continue-on-error":
			opts.continueOnError = true
		case "-down":
			opts.down = true
		case "-h", "-help", "--help":
			usage()
			os.Exit(0)
		default:
			return nil, fmt.Errorf("unknown option %q", arg)
		}
	}
	if opts.auto && opts.guided {
		return nil, fmt.Errorf("-auto and -guided are mutually exclusive")
	}
	if opts.down && opts.phase != manifest.PhaseMain {
		return nil, fmt.Errorf("-down and -phase are mutually exclusive")
	}
	if !opts.auto && !opts.guided {
		opts.auto = true // CI-friendly default
	}
	return opts, nil
}

func run() error {
	opts, err := parseArgs(os.Args[1:])
	if err != nil {
		usage()
		return err
	}

	o, err := orchestrator.New(orchestrator.Config{
		ScenarioFile:    opts.scenarioFile,
		ScenarioRoot:    opts.scenarioRoot,
		Phase:           opts.phase,
		Auto:            opts.auto,
		Guided:          opts.guided,
		Resume:          opts.resume,
		Reset:           opts.reset,
		ContinueOnError: opts.continueOnError,
		Down:            opts.down,
		Check:           opts.check,
	})
	if err != nil {
		return err
	}

	if opts.check {
		// Validate the manifest and the execution order only; do not run.
		if opts.down {
			fmt.Printf("check: scenario %q is valid (%d cleanup steps, order resolved)\n",
				o.Name(), o.StepCount())
		} else {
			fmt.Printf("check: scenario %q is valid (%d steps, order resolved, %d cleanup steps)\n",
				o.Name(), o.StepCount(), o.CleanupCount())
		}
		if missing := o.MissingEnv(); len(missing) > 0 && !opts.down {
			fmt.Printf("check: warning: required environment variables not set: %s\n", strings.Join(missing, ", "))
		}
		return nil
	}

	if runErr := o.Run(context.Background()); runErr != nil {
		return runErr
	}
	return nil
}

func main() {
	if err := run(); err != nil {
		if err == orchestrator.ErrQuit {
			fmt.Println("Quit — execution state saved.")
			os.Exit(0)
		}
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
