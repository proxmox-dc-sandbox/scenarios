#!/usr/bin/env bash
# bastion provisionner — create the bastion/jump VMs of the scenario.
#
# TEMPLATE STUB: implement it for your scenario. The credential-free
# pattern to follow:
#   1. copy vms.json.example to vms.json at run time,
#   2. interpolate ${LAB_VM_PASSWORD} / ${LAB_VM_SSH_KEY} from the
#      orchestrator-managed environment (never commit the rendered file —
#      it is gitignored),
#   3. create the VMs idempotently.
#
# Full implementation example: scenarios/proxmox-evpn-bgp-public-ip/
#   infra/scripts/bastion/provisionner.sh (renders vms.json.tpl).
set -euo pipefail

echo "TODO: implement the bastion VM creation" >&2
exit 1
