# Authorized scope (red team)

> This document defines what is **authorized** to attack in this scenario.
> It is mandatory before any `redteam` phase campaign. Anything not listed
> here is forbidden.

## Authorized targets

| Target | Address(es) | Allowed actions | Window |
|--------|-------------|------------------|--------|
| ...    | ...         | ...              | ...    |

## Rules

- No attack beyond the lab (internet, other scenarios).
- No exfiltration of real data: demo data only.
- Stop immediately if anything out of scope is touched by accident.
- The `writeup.md` file is filled in after the campaign, never before.

## Explicit exclusions

- Lab host machine, shared storage, other scenarios of the monorepo.
