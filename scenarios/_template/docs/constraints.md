# Constraints

> What the scenario must respect. Fill in, extend, or remove sections that do
> not apply.

## Resources

- Maximum vCPUs / RAM / disk usable (e.g. 4 vCPU, 8 GiB RAM, 50 GiB).
- Target storage: `local` (dir) and `local-lvm` (lvmthin) by default.

## Versions

- Proxmox VE >= 9.x.
- Images / templates pinned with their URLs (no floating latest).

## Network

- SDN zones: EVPN (public IP) or tagged VNet (private).
- DHCP ranges disjoint between the scenarios of the monorepo.

## Licenses

- Only components whose license allows lab usage (see each README).

---

# Nice-to-haves (optional improvements)

- Add a monitoring layer (Prometheus + Grafana).
- Add automated e2e tests for the objectives.
- Document a "cloud" fork (same scenario on another hypervisor).
- Variant ideas: duplicate the scenario and change the application stack.
