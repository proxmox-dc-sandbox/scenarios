#!/usr/bin/env bash
# E2E: the EVPN zone is applied and running on the Proxmox cluster.
#
# Checks, strictly:
#   - the zone "cloud2" exists, is typed "evpn" and its state is "running";
#   - the vnet "pubvm" is declared and attached to the zone;
#   - the DHCP subnet is declared on the vnet.
#
# Standalone: sources the persisted scenario environment (see lib.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
# shellcheck disable=SC1091  # computed path (SCRIPT_DIR): exists at scenario runtime
. "${SCRIPT_DIR}/lib.sh"
# shellcheck source=../../../infra/scripts/lib/pve-ssh.sh
# shellcheck disable=SC1091  # computed path (SCRIPT_DIR): exists at scenario runtime
. "${SCRIPT_DIR}/../../infra/scripts/lib/pve-ssh.sh"

# Implementation names — see the correspondence table in docs/architecture.md
ZONE="cloud2"
VNET="pubvm"
SUBNET_CIDR="172.16.50.0/24"

log() { echo "==> $*"; }
die() { echo "error: $*" >&2; exit 1; }

load_scenario_env \
  PROXMOX_NODE_ADDRESS PROXMOX_VE_SSH_USERNAME PVE_BASTION_USER \
  PROXMOX_VE_SSH_PRIVATE_KEY_PATH PVE_ROOT_PASSWORD \
  || exit 1

pve_ssh_init || die "cannot build the SSH command to the node"

log "zone ${ZONE} (type evpn, state running)"
Z="$("${PVE_SSH[@]}" "pvesh get /cluster/sdn/zones/${ZONE} --output-format json")" \
  || die "pvesh cannot read zone ${ZONE} (is the SDN applied?)"
printf '%s' "${Z}" | jq -e --arg z "${ZONE}" \
  '.zone == $z and .type == "evpn" and .state == "running"' >/dev/null || {
  echo "error: zone ${ZONE} is not an applied, running EVPN zone:" >&2
  printf '%s\n' "${Z}" >&2
  exit 1
}

log "vnet ${VNET} attached to the zone"
V="$("${PVE_SSH[@]}" "pvesh get /cluster/sdn/vnets/${VNET} --output-format json")" \
  || die "pvesh cannot read vnet ${VNET}"
printf '%s' "${V}" | jq -e --arg z "${ZONE}" '.zone == $z' >/dev/null || {
  echo "error: vnet ${VNET} is not attached to zone ${ZONE}:" >&2
  printf '%s\n' "${V}" >&2
  exit 1
}

log "subnet ${SUBNET_CIDR} declared on ${VNET}"
S="$("${PVE_SSH[@]}" "pvesh get /cluster/sdn/vnets/${VNET}/subnets --output-format json")" \
  || die "pvesh cannot read the subnets of vnet ${VNET}"
printf '%s' "${S}" | jq -e --arg c "${SUBNET_CIDR}" 'any(.[]; .subnet == $c)' >/dev/null || {
  echo "error: subnet ${SUBNET_CIDR} is not declared on vnet ${VNET}:" >&2
  printf '%s\n' "${S}" >&2
  exit 1
}

log "OK: zone ${ZONE} running, vnet ${VNET} attached, subnet ${SUBNET_CIDR} present"
