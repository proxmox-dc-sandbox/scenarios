# Authorized scope (red team)

> This document defines what is **authorized** to attack in this scenario.
> It is mandatory before any `redteam` phase campaign. Anything not listed
> here is forbidden.

## Authorized targets

| Target | Address(es) | Allowed actions | Window |
|--------|-------------|------------------|--------|
| test VMs (`cloudbox3/4/5`) | `172.16.50.x`, `172.16.60.x` | Port scan, service fingerprinting, no data exfiltration | Lab window |
| Proxmox SDN/API surface | node `pve` | Read-only API audit, BGP session tests | Lab window |

## Rules

- No attack toward the outside of the lab (internet, other scenarios).
- RFC 5737 / synthetic ranges only; no real data, no real prefixes.
- Stop immediately if anything out of scope is touched by accident.
- The `writeup.md` file is filled in after the campaign, never before.

## Explicit exclusions

- Upstream network, MikroTik CHR management plane (unless separately agreed),
  other scenarios of the monorepo.
