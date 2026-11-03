#!/usr/bin/env bash
# Verify the plain BGP session between the Proxmox node (SDN BGP controller,
# AS 64512) and the MikroTik CHR (eBGP AS 65001).
#
# Checks, strictly:
#   - the SDN BGP controller exists on the Proxmox cluster;
#   - the FRR IPv4 peer state is "Established" (vtysh JSON);
#   - the CHR session is established.
# The EVPN controller is not involved in this peering.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../lib/pve-ssh.sh"

TIMEOUT="${BGP_WAIT}"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

CHR_IP="${CHR_PUBLIC_IP:-}"
NODE="${PROXMOX_NODE_ADDRESS}"
PEER="${BGP_PEER}"
[[ -n "${CHR_IP}" ]] || die "CHR_PUBLIC_IP is not set (mikrotik-config step)"

RSH=(sshpass -p '' ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o ConnectTimeout=10 -o PreferredAuthentications=password
     -o PubkeyAuthentication=no "admin@${CHR_IP}")

pve_ssh_init || die "cannot build the SSH command to the node"

log "Checking the SDN BGP controller"
if ! "${PVE_SSH[@]}" "pvesh get /cluster/sdn/controllers --output-format json" |
    jq -e 'any(.[]; .type == "bgp")' >/dev/null; then
  die "no BGP controller (type 'bgp') on the Proxmox cluster"
fi

deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
  CHR_OUT="$("${RSH[@]}" '/routing bgp session print detail' 2>&1 || true)"
  NODE_JSON="$("${PVE_SSH[@]}" "vtysh -c 'show bgp summary json'" 2>/dev/null || true)"
  FRR_STATE="$(printf '%s' "${NODE_JSON}" | jq -r --arg n "${PEER}" '(.ipv4Unicast.peers[$n].state // .peers[$n].state) // empty' 2>/dev/null || true)"
  FRR_RCD="$(printf '%s' "${NODE_JSON}" | jq -r --arg n "${PEER}" '(.ipv4Unicast.peers[$n].pfxRcd // .peers[$n].pfxRcd) // 0' 2>/dev/null || true)"
  FRR_SNT="$(printf '%s' "${NODE_JSON}" | jq -r --arg n "${PEER}" '(.ipv4Unicast.peers[$n].pfxSnt // .peers[$n].pfxSnt) // 0' 2>/dev/null || true)"

  CHR_UP=0
  if printf '%s' "${CHR_OUT}" | grep -q 'ESTABLISHED' &&
     printf '%s' "${CHR_OUT}" | grep -q '10.10.0.23'; then
    CHR_UP=1
  fi

  if [[ "${FRR_STATE}" == "Established" && "${CHR_UP}" -eq 1 ]]; then
    log "Proxmox node ${NODE}: FRR BGP peer ${PEER} state = ${FRR_STATE} (prefixes received: ${FRR_RCD}, sent: ${FRR_SNT})"
    log "MikroTik CHR ${CHR_IP}: BGP session established"
    printf '%s\n' "${CHR_OUT}" | grep -aE 'name=|remote\.address|uptime' || true
    log "BGP session is up"
    exit 0
  fi

  if [[ "$(date +%s)" -ge "${deadline}" ]]; then
    echo "--- FRR IPv4 summary (node ${NODE}) ---" >&2
    printf '%s\n' "${NODE_JSON}" >&2
    echo "--- CHR BGP session ---" >&2
    printf '%s\n' "${CHR_OUT}" >&2
    die "BGP session is not established after ${TIMEOUT}s"
  fi
  sleep 10
done
