# Security

The scenarios are designed for a **private laboratory** and synthetic data.
Never publish a secret, customer data, or an address that could reach an
environment that is not meant to be public.

## Reporting a vulnerability

Do **not** publish a secret or exploitation details in a public issue or
pull request. Use the private reporting channel of the repository host
(GitHub **Private Vulnerability Reporting**: "Report a vulnerability" in
the "Security" tab of the repository). Report includes: affected component,
version/commit, description of the vulnerability, and (if possible) a
minimal reproduction.

## Secrets

- API tokens, passwords and private keys: environment variables or a
  secrets manager. Never committed.
- Examples (`infra/`, `docs/`, target files) only contain fictitious values;
  a committed SSH key is a placeholder or a **public** key.
- An OpenTofu state can contain secrets: it is handled by the runtime
  platform, out of the repository, restricted and backed up.
- A committed secret must be revoked and rotated; merely deleting it from
  the current branch is not enough.
- The repo has secret-exclusion rules in `.gitignore` and an **automated
  secret scan runs in CI** (gitleaks, full history — rules and the
  historical-incident allowlist in `.gitleaks.toml`). Treat any
  secret-looking value as a signal to stop and check.

## Historical incident (2026-11, TASK-01)

Before the policy above was fully applied, lab credentials were committed:
the compute-unit VM password and the scenario-template bastion password,
plus a personal SSH public key. They are **treated as compromised and must
never be reused anywhere**, even though they only ever reached synthetic
lab environments.

The values were removed from the working tree and replaced by the
orchestrator-generated mechanism (`generate: true` / `get_env`), documented
in the scenario READMEs (`get_env()` in the Terragrunt units, rendered
`vms.json` from the gitignored template).

The git history of the private repository still contains them: **no
history rewrite will be performed** — before the project is pushed to any
public host, it will be re-initialized as a **fresh git repository**, so
the public history starts clean. The committed values are considered
compromised and must never be reused anywhere.

## Deployments

A deployment runs on an isolated, authorized target, after a plan review.
`infra/scripts/down.sh` and the chaos steps are destructive and explicit:
their effects are documented in the scenario.

## Red-team phases

`redteam/scope.md` defines the authorized attack surface and must be
approved before any campaign. `redteam/writeup.md` is filled in after the
fact and must never contain real credentials.

## Supported versions

Security fixes are applied on `main` and backported on request; the
orchestrator only tracks the latest stable Go release.
