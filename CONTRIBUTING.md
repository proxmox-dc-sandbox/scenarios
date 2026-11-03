# Contributing

Thanks for your interest in the pdcs scenarios monorepo! This guide explains how to
add scenarios, improve the orchestrator, and get your change merged.

## Table of contents

- [Code of conduct](#code-of-conduct)
- [Project layout](#project-layout)
- [Development setup](#development-setup)
- [Adding a scenario](#adding-a-scenario)
- [Forking a scenario](#forking-a-scenario)
- [Improving the orchestrator](#improving-the-orchestrator)
- [Branching and commit conventions](#branching-and-commit-conventions)
- [Pull request process](#pull-request-process)
- [Releases](#releases)
- [CI](#ci)
- [Reporting issues](#reporting-issues)

## Code of conduct

By participating you agree to [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).
Be respectful, constructive, and inclusive.

## Project layout

```text
scenarios/         one directory per scenario (copy of _template + content)
_fork-registry.md  mandatory declaration of every fork
orchestrator/      Go module: cmd/, internal/{manifest,graph,state,runner,orchestrator}
                  and examples/hello-scenario (shell-only, for smoke tests)
```

## Development setup

Requirements: Go >= 1.26, git. Terraform/Ansible are only needed to run the
corresponding step types (the `examples/hello-scenario` runs shell-only).

```shell
make build        # build the orchestrator binary
make test         # go test ./...
make vet          # go vet ./...
make fmt          # gofmt -l check
make lint         # shellcheck every scenario script (vendored legacy excluded)
make security     # gitleaks over the full history (project config)
make check        # build + vet + tests + verify every scenario.yaml
```

### pre-commit hooks

The repository ships a pre-commit configuration mirroring the CI checks
(formatting, shellcheck, gitleaks, gofmt):

```shell
pip install pre-commit
pre-commit install          # from now on, every commit runs the hooks
pre-commit run --all-files  # one-shot full validation
```

The `gitleaks` hook expects the `gitleaks` binary on `PATH` (see
`.github/workflows/security.yml` for the pinned install); without it the
hook reports a failure, not a silent pass.

## Adding a scenario

1. Copy the template:

   ```shell
   cp -r scenarios/_template scenarios/<my-scenario>
   ```

2. Fill in every file:

   - `scenario.yaml` — manifest (`name`, `description`, `steps` with
     `id`, `type`, `path`, optional `depends_on`/`phase`/`optional`).
     Keep the step ids stable: they are written into `.state/` and used by
     `-resume`.
   - `README.md` — objective, context, scope, usage.
   - `docs/architecture.md` and `docs/constraints.md`.
   - `chaos/experiments.md` and `redteam/scope.md` (+ `redteam/writeup.md`
     only after a campaign).

3. Make the steps actually runnable:

   - the template ships **documented stubs** under `infra/scripts/` that
     fail loudly (`exit 1`): implement each one for your scenario (every
     stub points to a full implementation example in
     `scenarios/proxmox-evpn-bgp-public-ip/`); implementations live in
     the scenarios, never back in the template,
   - add executable scripts under `infra/scripts/` (`chmod +x`),
   - wire real Terraform/Ansible layers under `infra/`,
   - reference them by path in `scenario.yaml`.

4. Declare the fork if you derived it from another scenario (see below).

5. Run the checks and open a pull request.

### Rules for scenario content

- Use synthetic data; documentation ranges (RFC 5737) in all examples.
- No secrets in the repository: keys, tokens and passwords are injected
  through the execution environment.
- Modules consumed through Terragrunt are pinned to an immutable tag defined
  once in the scenario's `root.hcl` (`core_modules_repo` /
  `core_modules_version`); bump it deliberately after reviewing the modules
  `CHANGELOG.md`, never consume a floating branch.
- `redteam/writeup.md` is filled in after the fact, never before.
- Keep the DHCP/IP ranges disjoint from the other scenarios.

## Forking a scenario

1. Copy the parent scenario: `cp -r scenarios/<parent> scenarios/<new>`.
2. Add a row in `_fork-registry.md` (`parent`, link, status).
3. Document the differences (stack, objective, constraints) in the new
   `README.md` / `docs/constraints.md`.
4. Back-porting improvements to the parent (or to `_template`) is
   encouraged and appreciated.

## Improving the orchestrator

- Keep the package layout: `internal/manifest`, `internal/graph`,
  `internal/state`, `internal/runner`, `internal/orchestrator`.
- Code is idiomatic Go, explicit error handling, no `panic` except truly
  unrecoverable cases.
- **Never use `os.Chdir()`** — step working dirs go through
  `exec.Cmd.Dir` (thread-safe, parallel-ready).
- Add/adapt unit tests for any behavior change (`go test ./...`).
- No unnecessary external dependencies (stdlib first; YAML parsing is the
  one allowed dependency in this project).

## Branching and commit conventions

- Work on a dedicated branch: `feature/<topic>` (or `fix/<topic>`),
  never commit directly on `main`/`master`.
- Commit messages use conventional-style prefixes:

  ```
  feat: ...    (new feature, new scenario)
  fix: ...     (bug fix)
  docs: ...    (documentation)
  test: ...    (tests)
  security: ... (security fix)
  chore: ...   (tooling, CI, refactoring)
  ```

- Keep commits focused; reference the issue/pull request number when relevant.

## Pull request process

1. Push your branch and open a pull request against `main`.
2. The pull request template (`.github/PULL_REQUEST_TEMPLATE.md`) covers:
   objective, changes, tests run, and any breaking change.
3. CI must pass (build, vet, tests, scenario manifest checks).
4. Reviewers check: no secrets, docs updated, tests meaningful, no
   platform-specific chdir/state pollution.

## Releases

Releases follow [Semantic Versioning](https://semver.org/) and are
immutable, annotated tags created on `main` **after the change is merged
and the checks are green**. Release candidates are tagged `vX.Y.Z-rcN`
(e.g. `v1.0.0-rc1`); the stable `vX.Y.Z` follows once a candidate is
validated on a real deployment. Each release adds a section to
[CHANGELOG.md](CHANGELOG.md) (Keep a Changelog format), moving items out
of `Unreleased`.

The orchestrator step contract is part of the compatibility surface: step
`id`s are persisted in `.state/` and consumed by `-resume`, and the state
file format is reused by `-down`. Any change to those requires a major
version bump and a migration note in the release.

```shell
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

## CI

The pipelines (see `.github/workflows/`) run on `main` and pull requests:

- `ci.yml` — `orchestrator` job: build + vet + unit tests of the Go module;
  `manifests` job: validates every `scenario.yaml` (including the
  orchestrator examples) with `orchestrator -scenario <path> -check`.
- `security.yml` — `gitleaks` job: secret scan over the full history
  (rules in `.gitleaks.toml`); `shellcheck` job: lint of every shell
  script (vendored legacy copies excluded, see the workflow).

To trigger a local validation:

```shell
make check

# same security checks as CI:
gitleaks detect --source . --config .gitleaks.toml --verbose --redact
# shellcheck: see the loop in .github/workflows/security.yml
```

## Reporting issues

Use the project issue tracker with one of the templates (Bug report /
Feature request / Scenario proposal). Include: version/commit, environment,
expected vs actual behavior, and logs if relevant. For security issues, see
[`SECURITY.md`](SECURITY.md) (private disclosure preferred).
