#!/usr/bin/env bash
# E2E: the test VMs answer on their addresses.
#
# For every VM of the scenario (see the correspondence table in
# docs/architecture.md), checks from the Proxmox node — through the bastion
# jump — that the VM answers ICMP and that sshd is listening (TCP/22).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
# shellcheck disable=SC1091  # computed path (SCRIPT_DIR): exists at scenario runtime
. "${SCRIPT_DIR}/lib.sh"
# shellcheck source=../../../infra/scripts/lib/pve-ssh.sh
# shellcheck disable=SC1091  # computed path (SCRIPT_DIR): exists at scenario runtime
. "${SCRIPT_DIR}/../../infra/scripts/lib/pve-ssh.sh"

# name ip — implementation values, see docs/architecture.md
VMS=(
  "cloudbox3 172.16.50.26"
  "cloudbox4 172.16.50.16"
  "cloudbox5 172.16.60.16"
)

log() { echo "==> $*"; }
die() { echo "error: $*" >&2; exit 1; }

load_scenario_env \
  PROXMOX_NODE_ADDRESS PROXMOX_VE_SSH_USERNAME PVE_BASTION_USER \
  PROXMOX_VE_SSH_PRIVATE_KEY_PATH PVE_ROOT_PASSWORD \
  || exit 1

pve_ssh_init || die "cannot build the SSH command to the node"

failed=0
while read -r name ip; do
  log "VM ${name} (${ip}): ICMP"
  if ! "${PVE_SSH[@]}" "ping -c1 -W3 ${ip}" >/dev/null 2>&1; then
    echo "error: ${name} (${ip}) does not answer ICMP from the node" >&2
    failed=1
    continue
  fi
  log "VM ${name} (${ip}): sshd (TCP/22)"
  if ! "${PVE_SSH[@]}" "timeout 3 bash -c '</dev/tcp/${ip}/22>'" >/dev/null 2>&1; then
    echo "error: sshd does not listen on ${name} (${ip}:22)" >&2
    failed=1
    continue
  fi
  echo "OK: ${name} (${ip})"
done < <(printf '%s\n' "${VMS[@]}")

if [[ "${failed}" -ne 0 ]]; then
  die "some VMs are not reachable (diagnostics above)"
fi
log "OK: all VMs answer ICMP and sshd is listening"
