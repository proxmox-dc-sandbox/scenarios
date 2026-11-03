# orchestrator

Go orchestrator for multi-tool scenarios: it reads a `scenario.yaml` manifest
per scenario and executes the steps (`terraform` / `ansible` / `sh` / `go`)
in order, either automatically or in guided mode. Designed to run as-is in a
GitLab CI pipeline (`-auto` is the default).

## Build & test

```shell
go build -o bin/orchestrator ./cmd/orchestrator
go test ./...        # unit tests: manifest, toposort, state
go vet ./...
```

From the repo root, `make build`, `make test`, `make check` (build + vet +
tests + validation of every scenario) do the same.

## Manifest (`scenario.yaml`)

```yaml
name: replica-bank
description: "Replica of a banking stack for tests and training"
env:
  - name: LAB_VM_PASSWORD
    required: true
    description: "Set value in scenario.yaml before deployment"
  - name: KVM_STORE_DIR
    value: ".runtime/kvm"
    path: true
steps:
  - id: network
    type: terraform
    path: infra/network
    description: "Provisions VLAN + SDN network"
  - id: vms
    type: terraform
    path: infra/vms
    depends_on: [network]
    description: "Creates the Proxmox VMs"
  - id: configure
    type: ansible
    path: infra/ansible/site.yml
    depends_on: [vms]
    description: "Installs Fineract, Keycloak, Postgres"
  - id: seed-data
    type: sh
    path: infra/scripts/seed.sh
    depends_on: [configure]
    optional: true
cleanup:
  - id: destroy-vms
    type: sh
    path: infra/scripts/down.sh
    description: "Removes what the scenario created (-down)"
```

Step fields: `id` (required, unique), `type` (`terraform|terragrunt|ansible|sh|go`),
`path` (required), `args` (extra CLI arguments), `env` (extra variables for
that step only), `requires_env` (variables that must be set when the step
runs), `outputs` (declared variables a step publishes), `depends_on` (ids),
`phase` (`main` default | `chaos` | `redteam`), `optional`, `description`.

Scenario fields: `name`, `description`, `env` (declared variables), `steps`
(install/run) and optional `cleanup` (teardown, run with `-down`).

### Environment and runtime values

The manifest `env:` block is the sole source of scenario configuration:

- `value:` is the configured value and is not overridden by the host process
  environment;
- `path: true` resolves relative values from the scenario root;
- `required: true` makes the run fail before the first step if the manifest
  has no value and no earlier persisted step output supplies it;
- `generate: true` asks Go to generate a random secret once and persist it;
- `.env` files are not read or created.

Steps may declare `outputs: [VAR, ...]`. A shell step publishes them by
appending NUL-delimited name/value pairs to the orchestrator-provided
`PDCS_ENV_OUTPUT_FILE` (the scenario helper `infra/scripts/lib/env.sh`
provides `set_env_var NAME VALUE`). The orchestrator verifies that every
output was declared in both the manifest and the producing step, then stores
it in `.state/<scenario>.json` and injects it into later steps. This supports
generated keys, discovered addresses and API tokens without scripts editing
configuration files.

`requires_env: [VAR, ...]` is checked right before a step runs, after its
dependencies, so it is appropriate for outputs produced during the run. A
missing late value stops the run with a clear error; fix the producing step
and use `-resume`.

`${VAR}` and `${VAR:-default}` in step `args` and `env` are interpolated from
the current manifest/state environment. The orchestrator passes that complete
scenario environment to each child process on every step.

## Execution modes

### `-auto` (default)

Runs all the steps of the selected phase, in topological order, without
interaction — CI-friendly.

```shell
orchestrator -scenario scenario.yaml -auto
```

### `-guided`

Before each step: `id`, `type`, `description`, then a prompt:

- `Enter` -> run the step;
- `s` (only when `optional: true`) -> skip the step;
- `q` -> quit cleanly (state is saved before exiting).

stdout/stderr is also streamed live to the terminal.

```shell
orchestrator -scenario scenario.yaml -guided
```

### `-phase`

Only processes the steps of the requested phase (`main` by default —
`chaos` and `redteam` must be explicitly requested). A step whose dependency
is not `done` stops with an explicit message (run the `main` phase first).

```shell
orchestrator -scenario scenario.yaml -phase chaos -continue-on-error
orchestrator -scenario scenario.yaml -phase redteam
```

### `-resume`

Reads `.state/<scenario>.json` and resumes after the last `done` step,
without re-running what already succeeded. `failed`/`pending` steps are
re-run.

```shell
orchestrator -scenario scenario.yaml -resume
```

### `-reset`

Wipes `.state/` and `logs/` for the scenario, then runs everything fresh.
Use it when you want to guarantee a clean run from step 1 (equivalent to
deleting the state file yourself, but explicit and crash-safe).

```shell
orchestrator -scenario scenario.yaml -reset
```

### `-check`

Validates the manifest and resolves the execution order without running
anything (used by the CI pipeline and `make check`).

```shell
orchestrator -scenario scenario.yaml -check
```

### `-down`

Runs the manifest `cleanup:` section instead of `steps:` (full teardown),
in declaration/dependency order. Required inputs are not enforced up front;
the orchestrator reuses generated secrets and step outputs from install state.
State and logs use a separate suffix (`<scenario>-cleanup.json`,
`logs/<scenario>-cleanup/`), so teardown never interferes with install status.

```shell
orchestrator -scenario scenario.yaml -down            # teardown
orchestrator -scenario scenario.yaml -down -guided    # confirm each step
```

### Other options

- `-root <dir>`: overrides the scenario root directory (default: the
  manifest directory).
- `-continue-on-error`: a failed non-optional step does not stop the run
  (default: stop).

## Runner behavior

- **terraform**: `terraform init` when `.terraform/` is missing, then
  `terraform apply -auto-approve` (+ `-var-file=terraform.tfvars` if it
  exists).
- **terragrunt**: `terragrunt run --all <action> --non-interactive` from
  the step directory (a client root with `root.hcl` and one directory per
  unit). The action defaults to `apply`; a first argument naming an action
  (`destroy`, `plan`, `validate`, ...) selects another one - a cleanup step
  is just `args: ["destroy"]`. Units run in dependency order (reverse order
  for destroy).
- **ansible**: `ansible-playbook -i <inventory> <playbook>`; inventory via
  `PDCS_ANSIBLE_INVENTORY` or `<root>/inventory`.
- **sh**: the script must be executable (`chmod +x`); `args` are passed
  as CLI arguments and step `env` is added to its environment.
- **go**: a precompiled binary in `<path>/bin/` if present, otherwise
  `go run .`; `args` and step `env` are forwarded.

No `os.Chdir()`: the working directory is set via `exec.Cmd.Dir`
(thread-safe, parallel-friendly).

## Persistent state

`.state/<scenario>.json`:

```json
{
  "scenario": "replica-bank",
  "env": {"LAB_VM_PASSWORD": "<private>"},
  "steps": {
    "network": {"status": "done", "started_at": "...", "finished_at": "..."},
    "vms": {"status": "failed", "error": "..."},
    "configure": {"status": "pending"}
  }
}
```

Statuses: `pending | running | done | failed | skipped`. Runtime values and
step statuses are written atomically after transitions. Because state may
contain credentials, `.state/` and its files are owner-only and gitignored.

## Logs

- `logs/<scenario>/<step-id>.log`: stdout/stderr per step (created if absent).
- In `-guided` mode, a live summary is also printed on the terminal.

## Error handling

- **non-optional** failed step -> abort (except `-continue-on-error`).
- **optional** failed step -> log the failure, keep going.
- A final summary is always printed: done / failed / skipped / not run.

## Example

```shell
# From the monorepo root:
make build
cd orchestrator/examples/hello-scenario && ../../bin/orchestrator -auto
cd ../../scenarios/replica-bank && ../../bin/orchestrator -auto
```

## Project layout

```text
orchestrator/
├── cmd/orchestrator/main.go
├── internal/
│   ├── manifest/        YAML parsing + validation (+ tests)
│   ├── graph/           toposort + cycle detection (+ tests)
│   ├── state/           private persistent JSON state (+ tests)
│   ├── runner/          Runner interface + terraform/ansible/sh/go runners
│   └── orchestrator/    main loop: auto/guided/resume/phase
├── examples/hello-scenario/
├── go.mod
└── README.md
```
