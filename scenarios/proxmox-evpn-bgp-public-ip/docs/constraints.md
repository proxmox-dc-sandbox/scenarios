# Constraints

- Disposable, isolated environment: no BGP session toward any network that
  is not explicitly planned.
- Synthetic data; documentation addresses (RFC 5737) in all examples.
- Versions: Proxmox VE 9.2, OpenTofu >= 1.8, bpg/proxmox provider >= 0.70
  (the actually tested version shall be recorded here).
- MikroTik CHR license: product terms apply.
- No secrets in the repository: tokens, passwords and keys are injected
  through the execution environment.
- Resource budget (CPU, RAM, disk) to be measured on the lab and recorded
  here.

---

# Nice-to-haves (optional improvements)

- Automate the nested lab bootstrap (KVM host setup) as a documented command.
- Add a smoke check job to the CI pipeline per scenario.
- Publish a step-by-step tutorial for bridging the nested EVPN zone to the
  upstream network.
- Ideas for future forks: IPv6-only variant, eBGP multihop with a second CHR,
  or a multi-node Proxmox cluster with the same EVPN design.
