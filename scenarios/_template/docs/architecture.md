# Architecture

> To be filled in: architecture diagram of the scenario (ASCII block or
> Mermaid), technical decisions, network topology, data flows.

## Diagram

```text
+---------------+      +---------------------------+
| orchestrator  | -->  | steps (terraform/ansible/sh/go) |
+---------------+      +---------------------------+
```

## Technical decisions

- Hypervisor: Proxmox VE (SDN EVPN for the network).
- Provisioning: `terraform` steps (infra layer) + `ansible` (configuration).
- State: `.state/<scenario>.json` (resume via `-resume`).

## Network topology

| Zone | CIDR | Role |
|------|------|------|
| ...  | ...  | ...  |

## Flows

1. `preflight` validates the prerequisites.
2. `provision` creates the resources.
3. `configure` installs the applications.
4. `seed-data` loads the demo data (optional).
