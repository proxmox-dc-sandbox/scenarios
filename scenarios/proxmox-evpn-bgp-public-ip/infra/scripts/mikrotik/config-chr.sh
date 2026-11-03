#!/usr/bin/env bash
# Configure the MikroTik CHR over SSH (RouterOS), from the scenario:
#   - WAN on the public network (DHCP from the KVM NAT network)
#   - LAN 10.10.0.1/24 on the private network (gateway/DNS of the PVE node)
#   - NAT masquerade, DNS cache, firewall rules, BGP peering with the node
#
# The router is reached through its public (DHCP) address. Idempotent: the
# configuration is skipped when the LAN address is already present.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../lib/env.sh"

CONFIG_RSC="${SCRIPT_DIR}/config.rsc"
CHR_MAC="${CHR_WAN_MAC}"
WAIT="${CHR_WAIT}"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

command -v sshpass >/dev/null 2>&1 || die "missing command: sshpass"

find_chr_ip() {
  virsh --connect qemu:///system net-dhcp-leases pdcs-public-network 2>/dev/null |
    awk -v mac="${CHR_MAC}" '$3 == mac {split($5, a, "/"); print a[1]}' | tail -n1
}

log "Waiting for the MikroTik CHR public address (up to ${WAIT}s)"
CHR_IP="${CHR_PUBLIC_IP:-}"
deadline=$(( $(date +%s) + WAIT ))
while :; do
  [[ -z "${CHR_IP}" ]] && CHR_IP="$(find_chr_ip)"
  if [[ -n "${CHR_IP}" ]] && sshpass -p '' ssh -T \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no "admin@${CHR_IP}" /system/identity/print >/dev/null 2>&1; then
    break
  fi
  [[ "$(date +%s)" -lt "${deadline}" ]] || die "cannot reach the CHR over SSH (public IP: ${CHR_IP:-none})"
  sleep 5
done
log "CHR reachable at ${CHR_IP}"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o ConnectTimeout=10 -o PreferredAuthentications=password
          -o PubkeyAuthentication=no)
RSH=(sshpass -p '' ssh -T "${SSH_OPTS[@]}" "admin@${CHR_IP}")

# Escape a value for RouterOS double-quoted string syntax.
ros_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//\$/\\$}
  printf '%s' "${value}"
}

activate_unlimited_license() {
  local license_state email password renew_cmd attempt
  license_state="$("${RSH[@]}" '/system license print' 2>/dev/null || true)"
  if printf '%s\n' "${license_state}" | grep -qE 'level:[[:space:]]*p-unlimited'; then
    log "CHR license is already p-unlimited"
    return 0
  fi

  [[ -n "${MIKROTIK_LICENSE_EMAIL:-}" ]] || die "MIKROTIK_LICENSE_EMAIL must be set in scenario.yaml"
  [[ -n "${MIKROTIK_LICENSE_PASSWORD:-}" ]] || die "MIKROTIK_LICENSE_PASSWORD must be set in scenario.yaml"
  [[ "${MIKROTIK_LICENSE_EMAIL}" != *$'\n'* && "${MIKROTIK_LICENSE_EMAIL}" != *$'\r'* ]] ||
    die "MIKROTIK_LICENSE_EMAIL contains unsupported control characters"
  [[ "${MIKROTIK_LICENSE_PASSWORD}" != *$'\n'* && "${MIKROTIK_LICENSE_PASSWORD}" != *$'\r'* ]] ||
    die "MIKROTIK_LICENSE_PASSWORD contains unsupported control characters"

  email="$(ros_escape "${MIKROTIK_LICENSE_EMAIL}")"
  password="$(ros_escape "${MIKROTIK_LICENSE_PASSWORD}")"
  renew_cmd="/system license renew account=\"${email}\" password=\"${password}\" level=p-unlimited"

  log "Activating the CHR p-unlimited license"
  for attempt in 1 2 3; do
    "${RSH[@]}" "${renew_cmd}" >/dev/null 2>&1 || true
    license_state="$("${RSH[@]}" '/system license print' 2>/dev/null || true)"
    if printf '%s\n' "${license_state}" | grep -qE 'level:[[:space:]]*p-unlimited'; then
      log "CHR license confirmed at p-unlimited"
      return 0
    fi
    [[ "${attempt}" -lt 3 ]] && sleep 3
  done

  printf '%s\n' "${license_state}" | grep -E 'level|nlevel' >&2 || true
  die "CHR license activation did not reach p-unlimited; verify the account and Internet access"
}

activate_unlimited_license

# The configuration is complete when the BGP connection exists.
BGP_COUNT=$("${RSH[@]}" ':put [:len [/routing bgp connection find where name="BGP-PROXMOX"]]' | tr -d '\r')

if [[ "$BGP_COUNT" -gt 0 ]]; then
  log "CHR already configured (BGP-PROXMOX present) - skipping"
else
  log "Uploading $(basename "${CONFIG_RSC}") and importing it"
  sshpass -p '' scp -O "${SSH_OPTS[@]}" "${CONFIG_RSC}" "admin@${CHR_IP}:" >/dev/null \
    || die "cannot upload the RouterOS configuration"
  IMPORT_OUT="$("${RSH[@]}" '/import file-name=config.rsc' 2>&1 || true)"
  printf '%s\n' "${IMPORT_OUT}"
  if printf '%s' "${IMPORT_OUT}" | grep -qiE 'script error|failure|error'; then
    die "RouterOS configuration import reported errors"
  fi
fi

# Verify the end state instead of trusting the import exit code.
for check in "10.10.0.1/24" "BGP-PROXMOX"; do
  if [[ -z "$("${RSH[@]}" "/ip address print where address=${check}" 2>/dev/null)" &&
        -z "$("${RSH[@]}" "/routing bgp connection print where name=${check}" 2>/dev/null)" ]]; then
    die "CHR configuration incomplete (${check} missing)"
  fi
done
if [[ -z "$("${RSH[@]}" '/ip firewall nat print where comment="NAT - Masquerade LAN"' 2>/dev/null)" ]]; then
  die "CHR configuration incomplete (LAN NAT rule missing)"
fi

if [[ -z "$("${RSH[@]}" '/ip firewall filter print where comment="ACCEPT - DNS from LAN"' 2>/dev/null)" ]]; then
  die "CHR configuration incomplete (DNS firewall rule missing)"
fi

set_env_var CHR_PUBLIC_IP "${CHR_IP}"

log "CHR state:"
"${RSH[@]}" '/ip address print; /ip route print where dst-address=0.0.0.0/0' || true
