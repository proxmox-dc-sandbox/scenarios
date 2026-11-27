#!/usr/bin/env bash
# Prepare a fresh Proxmox VE node for day-to-day use and testing:
#   - install dnsmasq (local DNS/DHCP/IPAM for guests and test scripts);
#   - install and enable FRR (BGP/OSPF routing for routing tests);
#   - disable the Proxmox enterprise repositories and enable the
#     pve-no-subscription repository instead, so apt keeps working on an
#     unlicensed node. Controlled by PVE_DISABLE_ENTERPRISE (true|false or
#     yes|no, case-insensitive; anything other than true/yes keeps the stock
#     enterprise repositories untouched).
#   - enable the "snippets" content type on the local storage (cloud-init
#     snippets for the guests of the test scripts).
#
# The node is directly reachable over SSH (PROXMOX_NODE_ADDRESS). Idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../lib/pve-ssh.sh"

WAIT="${PVE_SSH_WAIT}"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

# Accept true|yes (case-insensitive) as the "enabled" value.
disable_enterprise() {
  case "${PVE_DISABLE_ENTERPRISE:-}" in
    true | True | TRUE | yes | Yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

pve_ssh_init || die "cannot build the SSH command to the node"
pve_wait_ssh "${WAIT}" || die "node unreachable over SSH"

if disable_enterprise; then
  log "Disabling the Proxmox enterprise repositories (PVE_DISABLE_ENTERPRISE=${PVE_DISABLE_ENTERPRISE})"
  # A fresh Proxmox VE 9 install ships deb822 *.sources files; older releases
  # use *.list. Comment out the active lines of both formats (kept for
  # traceability) and enable the pve-no-subscription repository.
  # shellcheck disable=SC2016  # remote shell: expand these variables on the node
  "${PVE_SSH[@]}" '
set -e
for f in /etc/apt/sources.list.d/pve-enterprise.sources \
         /etc/apt/sources.list.d/ceph.sources \
         /etc/apt/sources.list.d/pve-enterprise.list \
         /etc/apt/sources.list.d/ceph.list; do
  if [ -f "$f" ]; then
    sed -i "s/^\([^#]\)/# \1/" "$f"
  fi
done
printf "%s\n" "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list
' || die "cannot enable the pve-no-subscription repository"
else
  log "Keeping the Proxmox enterprise repositories enabled (PVE_DISABLE_ENTERPRISE=${PVE_DISABLE_ENTERPRISE:-})"
fi

log "Installing dnsmasq (DNS/DHCP/IPAM) and FRR (routing)"
"${PVE_SSH[@]}" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq; apt-get install -y -qq dnsmasq frr" \
  || die "cannot install dnsmasq/frr on the node"
"${PVE_SSH[@]}" "systemctl enable --now frr >/dev/null 2>&1 || true"

log "Ensuring 'snippets' content on the local storage"
"${PVE_SSH[@]}" "pvesm set local --content backup,iso,vztmpl,import,snippets" \
  || die "cannot update the local storage content"

log "Node preparation complete:"
"${PVE_SSH[@]}" "dpkg-query -W -f='\${Package} \${Version}\n' dnsmasq frr; pvesm status"