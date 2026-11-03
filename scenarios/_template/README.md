# _template — Scenario template

> Purpose: template to copy when creating a new scenario in the monorepo.
> Copy the directory (`cp -r scenarios/_template scenarios/<my-scenario>`),
> then fill in every section. Do not edit this template for a specific case:
> create a fork instead (see `_fork-registry.md`).

## Objective

Describe in 2-3 sentences the goal of the scenario: which system is
replicated, for which purpose (test, training, demo, red team), and what
result the scenario must produce (e.g. "a VM answers on its public IP").

## Context

- Target platform: Proxmox VE (VM / LXC), SDN EVPN network, etc.
- Tooling: the monorepo orchestrator (Go) with `terraform`, `ansible`, `sh`
  or `go` steps.
- Life cycle: `orchestrator -auto` deploys; execution state is persisted in
  `.state/` and logs in `logs/<scenario>/`.

## Scope

- **Included**: what the scenario covers.
- **Excluded**: what is explicitly out of scope (and why).

## Quick start

```shell
# From the scenario root
orchestrator -scenario scenario.yaml -auto          # deploy the main phase
orchestrator -scenario scenario.yaml -guided        # step by step
orchestrator -scenario scenario.yaml -resume        # resume without re-running
orchestrator -scenario scenario.yaml -phase chaos   # chaos phase only
```

## Directory contents

| Element | Role |
|---------|------|
| `scenario.yaml` | Executable contract read by the orchestrator (steps, dependencies, phases) |
| `infra/` | IaC: tfvars, install scripts, terraform/ansible |
| `docs/architecture.md` | Architecture diagram and technical decisions |
| `docs/constraints.md` | Imposed constraints + nice-to-haves |
| `chaos/experiments.md` | Chaos experiment journal (optional) |
| `redteam/scope.md` | Authorized attack scope (optional) |
| `redteam/writeup.md` | Filled in AFTER the fact, never before |

## Rules

- **The template is minimal**: every script under `infra/scripts/` is a
  documented stub that fails loudly (`exit 1`) until you implement it for
  your scenario. Implementations live in the scenarios, not in the
  template — a shared implementation would be copied and diverge (that is
  how the previous vendored copies rotted). Each stub points to a full
  implementation example in `scenarios/proxmox-evpn-bgp-public-ip/`.
- Never commit secrets (keys, tokens): the root `.gitignore` excludes them.
  Credentials reach the scripts through the orchestrator-managed environment
  only: `infra/scripts/bastion/vms.json.example` is copied to `vms.json`
  with `${LAB_VM_PASSWORD}` / `${LAB_VM_SSH_KEY}` interpolated at runtime,
  and the rendered `vms.json` is gitignored. Terragrunt units read the same
  values with `get_env()` — see `scenario.yaml` (`env:`, `outputs:`,
  `requires_env:`) for how they are declared, generated and checked.
- `redteam/writeup.md` is only filled in after an authorized campaign.
- Any scenario derived from another one must be declared in
  `_fork-registry.md`.
