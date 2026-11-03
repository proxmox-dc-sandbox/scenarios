# E2E tests

Post-deployment validation of the scenario, run **manually after a
completed install**. They are deliberately not `scenario.yaml` steps: a
failed install must fail the run before any validation is attempted.

Each script re-exports the persisted orchestrator environment from
`.state/proxmox-evpn-bgp-public-ip.json` (written by a successful run,
mode 0600) — variables already present in the environment win.

Prerequisite: the bastion tunnel must be up (re-run the `bastion-proxy`
step — or `docker/run.sh resume` — if it went down between the install
and the validation).

```bash
./test-zone-evpn.sh       # EVPN zone applied + running, vnet attached, subnet declared
./test-bgp.sh             # BGP session node<->CHR established (delegates to verify-bgp.sh)
./test-vm-joignable.sh    # every VM answers ICMP + sshd listens (TCP/22)
```

Chaos: `chaos/scripts/bgp-flap.sh` flaps FRR on the node and asserts the
recovery through `test-bgp.sh`.
