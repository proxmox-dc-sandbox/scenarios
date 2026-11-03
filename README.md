# scenarios

[![ci](https://github.com/proxmox-dc-sandbox/scenarios/actions/workflows/ci.yml/badge.svg)](https://github.com/proxmox-dc-sandbox/scenarios/actions/workflows/ci.yml)
[![security](https://github.com/proxmox-dc-sandbox/scenarios/actions/workflows/security.yml/badge.svg)](https://github.com/proxmox-dc-sandbox/scenarios/actions/workflows/security.yml)

Monorepo of **reproducible infrastructure scenarios** (Proxmox, SDN/EVPN,
BGP ...) driven by a Go orchestrator.

## Overview

```text
scenarios/
├── scenarios/                 the scenarios (one directory = one scenario)
│   ├── _template/             template to copy when creating a new scenario
│   └── proxmox-evpn-bgp-public-ip/   EVPN + BGP networking lab (MikroTik CHR)
│       └── tests/e2e/         post-deployment validation scripts
├── _fork-registry.md          who forked what, links to the forks
├── orchestrator/              the Go orchestrator (scaffold + tests)
├── docker/                    runner image + docker/run.sh lifecycle wrappers
└── README.md                  this file
```

## The orchestrator

Each scenario exposes a `scenario.yaml` manifest (name, description, typed
steps `terraform`/`ansible`/`sh`/`go`, dependencies, phases and environment
values). The Go tool in
[`orchestrator/`](orchestrator/README.md) reads it and executes the steps:

```shell
go build -o orchestrator/bin/orchestrator orchestrator/cmd/orchestrator

# From a scenario root:
orchestrator -scenario scenario.yaml -auto                # full run
orchestrator -scenario scenario.yaml -guided             # step by step
orchestrator -scenario scenario.yaml -resume              # resume after a crash
orchestrator -scenario scenario.yaml -phase chaos         # chaos phase only
orchestrator -scenario scenario.yaml -down                # full teardown (cleanup section)
orchestrator -scenario scenario.yaml -check               # validate manifest + order
```

Execution rules:

- **Topological sort** of the steps via `depends_on` (explicit error on
  cycles or unknown dependencies).
- **Phases**: `main` (default), `chaos`, `redteam` — only explicitly
  requested phases run.
- **Persistent state**: `.state/<scenario>.json` written after every
  transition with owner-only permissions; generated secrets and values
  published by steps are reused by later steps, `-resume` and `-down`.
  Per-step logs are in `logs/<scenario>/`.
- **Single configuration source**: scenario inputs come from `scenario.yaml`;
  the orchestrator does not read or generate `.env` files.
- **GitHub Actions CI**: the same binary runs headless (`-auto` is the default).

## Deploy from Docker (clean host)

Everything can run from a self-contained container (libvirt/KVM clients,
OpenTofu, Terragrunt, Proxmox auto-install tools, orchestrator binary). It
uses host networking and the host libvirt socket, so nothing is installed on
the machine:

```shell
docker/run.sh build      # build the tools image
docker/run.sh up         # install the scenario
docker/run.sh down       # tear it down (cleanup section)
```

See [`docker/README.md`](docker/README.md) for mounts, environment and
debugging (`docker/run.sh shell`).

## Scenario structure

| Element | Role |
|---------|------|
| `scenario.yaml` | Executable contract read by the orchestrator |
| `README.md` | Objective, context, scope, usage |
| `infra/` | IaC: tfvars, install scripts, terraform/ansible |
| `docs/architecture.md` | Diagram and technical decisions |
| `docs/constraints.md` | Constraints + nice-to-haves |
| `chaos/experiments.md` | Chaos experiment journal (optional) |
| `redteam/scope.md` | Authorized attack scope (optional) |
| `redteam/writeup.md` | Filled in after the fact, never before |

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full guide (new scenarios,
forks, code standards, CI, PR process), [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
and [`SECURITY.md`](SECURITY.md).

## License

MIT — see [`LICENSE`](LICENSE). By contributing you agree that your
contributions are licensed under the same terms.

## Status

- [x] Go orchestrator scaffold (build + green tests)
- [x] Monorepo structure: template, EVPN/BGP scenario migrated,
      fork registry
- [ ] CI child pipelines per scenario (waiting on scenario actual content)
