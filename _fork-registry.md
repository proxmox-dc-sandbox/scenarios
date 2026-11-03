# _fork-registry — Fork registry

> Every scenario derived from another one must be declared here: this is the
> traceability contract of the monorepo. A fork inherits the parent scenario,
> declares its differences, and points to where it is maintained.

## How to declare a fork

1. Copy the scenario: `cp -r scenarios/<parent> scenarios/<new>`.
2. Add a row to the table below.
3. If the fork lives somewhere else, put the repository link.
4. Fill in `README.md` and `docs/`; only write `redteam/writeup.md` after
   the fact.

## Registry

| Scenario | Fork of | Repository / link | Status | Notes |
|----------|---------|-------------------|--------|-------|
| `scenarios/proxmox-evpn-bgp-public-ip` | — (root) | [local](./scenarios/proxmox-evpn-bgp-public-ip/) | active | EVPN + BGP lab with MikroTik CHR (migrated to the current template) |
| `scenarios/_template` | — | [local](./scenarios/_template/) | — | Template — never derive from it directly; always copy it and declare the fork here |

## Rules

- A scenario without an entry here does not officially exist.
- Any fork must stay within the scope defined by its `redteam/scope.md`.
- Removing a scenario first requires removing its own row here (and those
  of any forks of it).
