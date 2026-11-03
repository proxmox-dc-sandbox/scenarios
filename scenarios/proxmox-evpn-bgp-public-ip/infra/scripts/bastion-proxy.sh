#!/usr/bin/env bash
# Start the SSH proxy to the isolated 10.10.0.0/24 network through the bastion.
#
# The private network has no host address: the Proxmox node is only reachable
# through the bastion. This step:
#   - discovers the bastion public (DHCP) address on pdcs-public-network;
#   - starts `ssh -L 127.0.0.1:8443:<node>:8006` (Proxmox API) and
#     `ssh -D 127.0.0.1:1080` (SOCKS, used by the provider SSH for snippets);
#   - publishes PVE_BASTION, PROXMOX_VE_ENDPOINT and PROXMOX_VE_SSH_SOCKS5 to
#     the orchestrator so later steps receive them in their environment.
#
# Idempotent: an already running proxy is reused. Runs in the same container
# as the orchestrator (host network), so the port forwards are local.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/env.sh"

BASTION_MAC="${BASTION_PUBLIC_MAC}"
BASTION_USER="${PVE_BASTION_USER}"
NODE_ADDRESS="${PROXMOX_NODE_ADDRESS}"
SOCKS_PORT="${BASTION_SOCKS_PORT}"
API_PORT="${BASTION_API_PORT}"
WAIT="${BASTION_WAIT}"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

KEY="${PROXMOX_VE_SSH_PRIVATE_KEY_PATH}"
[[ -n "${KEY}" && -f "${KEY}" ]] || die "missing SSH key: run the ssh-keygen step first"
command -v ssh >/dev/null 2>&1 || die "missing command: ssh"

find_bastion_ip() {
  virsh --connect qemu:///system net-dhcp-leases pdcs-public-network 2>/dev/null |
    awk -v mac="${BASTION_MAC}" '$3 == mac {split($5, a, "/"); print a[1]}' | tail -n1
}

log "Waiting for the bastion public address (up to ${WAIT}s)"
BASTION_IP="${PVE_BASTION}"
deadline=$(( $(date +%s) + WAIT ))
while :; do
  [[ -z "${BASTION_IP}" ]] && BASTION_IP="$(find_bastion_ip)"
  if [[ -n "${BASTION_IP}" ]] && ssh -i "${KEY}" -o IdentitiesOnly=yes \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 -o BatchMode=yes "${BASTION_USER}@${BASTION_IP}" true >/dev/null 2>&1; then
    break
  fi
  [[ "$(date +%s)" -lt "${deadline}" ]] || die "cannot SSH into the bastion (public IP: ${BASTION_IP:-none})"
  sleep 5
done
log "Bastion reachable at ${BASTION_IP} (user ${BASTION_USER})"

proxy_running() {
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "(^|:)${1}$"
}

if proxy_running "${SOCKS_PORT}" && proxy_running "${API_PORT}"; then
  log "SSH proxy already running (SOCKS ${SOCKS_PORT}, API ${API_PORT})"
else
  log "Starting SSH proxy: SOCKS 127.0.0.1:${SOCKS_PORT}, API 127.0.0.1:${API_PORT} -> ${NODE_ADDRESS}:8006"
  ssh -i "${KEY}" -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
    -f -N -D "127.0.0.1:${SOCKS_PORT}" \
    -L "127.0.0.1:${API_PORT}:${NODE_ADDRESS}:8006" \
    "${BASTION_USER}@${BASTION_IP}"
fi

set_env_var PVE_BASTION "${BASTION_IP}"
set_env_var PROXMOX_VE_ENDPOINT "https://127.0.0.1:${API_PORT}"
set_env_var PROXMOX_VE_SSH_SOCKS5 "127.0.0.1:${SOCKS_PORT}"

log "Tunnel ready (API https://127.0.0.1:${API_PORT}, SOCKS 127.0.0.1:${SOCKS_PORT} via ${BASTION_IP})"
