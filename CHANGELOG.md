# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> Note: the published (GitHub) history will start fresh — see `SECURITY.md`,
> "Historical incident". The private pre-publication history and its tags
> (`v0.01`, `v1.0.0-rc1`) are kept for traceability only.

## [Unreleased]

### Added

- pre-commit configuration mirroring the CI checks (trailing whitespace,
  end-of-file, yaml, shellcheck, gitleaks, gofmt) + install documentation
  in CONTRIBUTING.
- Makefile `lint` (shellcheck) and `security` (gitleaks) targets.
- README: GitHub Actions badges (placeholder slug, TODO(publication)) and a
  complete overview diagram (docker/, tests/e2e/, cleaning/).
- Real e2e validation of the flagship scenario (previously `exit 1`
  stubs): `test-zone-evpn.sh` (EVPN zone applied/running, vnet attached,
  subnet declared), `test-bgp.sh` (delegates to the single source of
  truth `verify-bgp.sh`), `test-vm-joignable.sh` (every VM answers ICMP
  + sshd TCP/22, from the node through the bastion jump). A shared
  `tests/e2e/lib.sh` re-exports the persisted scenario environment so
  each test runs standalone after a completed install.
- Chaos `bgp-flap.sh` implemented: restarts FRR on the node (session
  flap) and asserts the recovery through the e2e BGP test.
- Scenario README: "Post-deployment validation" section.
- CI (GitHub Actions): `security` workflow — gitleaks (pinned 8.30.1) over
  the full history with `.gitleaks.toml` (default rules + a rule failing on
  the credentials compromised in the 2026-10 incident, allowlisted for the
  five historical commits) and ShellCheck on every script; `ci` workflow —
  port of the historical `.gitlab-ci.yml` (orchestrator go build/vet/test +
  manifest validation loop).

### Changed

- Cloud-init template header comments translated to English; the working
  tree is now English-only outside `cleaning/` (internal historical
  artifacts).
- Three-layer Terragrunt layout, aligned with the modules repository:
  the `02-sdn-zone` unit is merged into `01-foundation` (the zone input
  moves to `sdn_zones`) and the units are renumbered
  `01-foundation / 02-networking / 03-compute`. The zone/controller
  destroy ordering now lives in the foundation module itself
  (`depends_on`, modules v1.0.0-rc3) instead of a separate state; the
  `proxmox-zone-deprovisioning` cleanup step is gone and the teardown
  chain is compute -> networking -> foundation.
- Modules consumed at `v1.0.0-rc3` (pinned in `root.hcl`).
- **Migration note (v1.0.0-rc2 -> rc3)**: the step id
  `proxmox-zone-deprovisioning` disappears from the manifest — a fresh
  install cycle is expected with this restructure; also run once on the
  lab host: `git -C pdcs-core-tf-modules fetch --tags` and
  `rm -rf infra/terragrunt/*/.terragrunt-cache`.
- Go module renamed `pdcs/scenarios/orchestrator` ->
  `pdcs/orchestrator` (all imports updated).
- README title/labels now use the repository name (was
  `scenarios-monorepo`); same in CONTRIBUTING and the Makefile header.
- `.gitignore`: dead legacy entries removed (`thekey`, `info.md`,
  `answer-*.toml`, `lab_user`, `*testkey*`, the scenario `virsh_strator/
  misc/*.pub` — zero history each, verified); comments translated to
  English.
- Scenario `docs/storage.md` translated to English, with neutral example
  paths (was machine-specific `ozlab_data`).
- Scenario docs resynchronized with the real implementation: zone
  `cloud2` (was `cloud`), VMs `cloudbox3/4/5` with both subnets (was
  `demo-vm-01/02`), node `pve` (was `pve-01`), provisioning in
  `infra/terragrunt/` (was `infra/terraform/`), plain BGP peering
  attributed to `bgpchr` (was wrongly on the EVPN controller). Added the
  logical-name -> implementation correspondence table with the "code
  wins" rule.
- Removed the stale empty `infra/terraform/` and `infra/ansible/`
  placeholder layers (provisioning lives in `infra/terragrunt/`, guest
  configuration in cloud-init).
- The scenario template is **minimal**: the divergent vendored
  implementations it carried (virsh_strator.sh with a machine-specific
  path, bastion/kvm/mikrotik scripts, lab_user.pub fixture, KVM network
  XML copies identical to the reference scenario's) are removed;
  `infra/scripts/` now ships documented stubs that fail loudly until
  implemented, each pointing to a full example in the reference scenario.
  Rule documented in the template README and CONTRIBUTING (implementations
  live in the scenarios, never in the template).
- Modules consumed at `v1.0.0-rc2` (pinned in `root.hcl`). The two
  client-side `generate` workarounds are gone: the plain BGP controller
  ("bgpchr") is a native `sdn_controllers` input (`type = "bgp"`) and
  `zones_config` comes from the sdn-zone module output.
- `.gitlab-ci.yml` removed (GitLab syntax never executed on the Gitea
  host); SECURITY.md: secret scan is now automated, not "planned".

### Removed

- The `replica-bank` scenario (not realized yet; will be reintroduced with
  its own history when it carries a real deployment).

### Fixed

- ShellCheck findings on the critical-path scripts, idempotence preserved:
  `proxmox/run.sh` waits `API_WAIT` minutes with the documented `10`
  default (was a no-op self-assignment); dead `PVE_SSH_PUBKEY`
  self-assignment removed; dead `HOST_ID`/`VM_HOST_ID` plumbing removed
  (run.sh + docker/run.sh); `node-prep.sh` quotes the safe.directory path.

## [1.0.0-rc1] - 2026-11-03

First release candidate: public-ready cut with credentials fully generated
at runtime, MIT license and GitHub governance. The stable `v1.0.0` follows
once the candidate is validated on a real deployment.

### Security

- Removed every hardcoded credential: the compute-unit VM password and SSH
  key now come from the orchestrator environment (`generate: true`,
  `get_env()`), and the bastion `vms.json` is rendered from
  placeholder-only templates. The previously committed lab credentials are
  documented as compromised in `SECURITY.md`.
- `scenario.yaml`: the terragrunt provisioning and compute-deprovisioning
  steps now declare `LAB_VM_PASSWORD`/`LAB_VM_SSH_KEY` in `requires_env`,
  so a missing value fails early with an actionable message.

### Added

- MIT `LICENSE`; GitHub issue templates and pull-request template
  (converted from the GitLab ones); private vulnerability reporting
  documented in `SECURITY.md`.
- Documentation of how secrets reach the Terragrunt units and the rendered
  `vms.json` (scenario and template READMEs).
- `CHANGELOG.md` (this file).

### Changed

- Working artifacts (session journals, automation test notes, raw prompts)
  moved to `cleaning/`, out of the project documentation path.

## [0.01] - 2026-11-02

Historical, pre-CHANGELOG tag (non-SemVer name kept for traceability).

### Added

- Go orchestrator: `scenario.yaml` executable contract, topological step
  ordering, persistent private state (`.state/`), resume/cleanup modes,
  per-step logs, unit tests.
- Scenario monorepo: `_template`, `replica-bank` (shell simulation),
  `proxmox-evpn-bgp-public-ip` (Proxmox VE + MikroTik CHR BGP/EVPN lab),
  `_fork-registry.md`.
- Docker tools image (orchestrator, OpenTofu, Terragrunt, Proxmox
  auto-install tooling) and `docker/run.sh` lifecycle wrappers.
