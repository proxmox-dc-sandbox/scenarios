#!/usr/bin/env bash
# Prepare a fresh Proxmox VE node for the Terragrunt client:
#   - enable the "snippets" content type on the local directory storage, which
#     the compute layer needs for cloud-init snippets (a default PVE install
#     only has backup,iso,vztmpl,import).
#
# Reachable only through the bastion (PVE_BASTION). Idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../lib/pve-ssh.sh"

WAIT="${PVE_SSH_WAIT}"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

pve_ssh_init || die "cannot build the SSH command to the node"
pve_wait_ssh "${WAIT}" || die "node unreachable over SSH"

# The EVPN controller (FRR) requires the frr package on the node.
if ! "${PVE_SSH[@]}" "command -v vtysh >/dev/null 2>&1"; then
  log "Installing FRR on the node (EVPN controller)"
  "${PVE_SSH[@]}" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq || true; apt-get install -y -qq frr" \
    || die "cannot install frr on the node"
fi
"${PVE_SSH[@]}" "systemctl enable --now frr >/dev/null 2>&1 || true"

log "Ensuring 'snippets' content on the local storage"
"${PVE_SSH[@]}" "pvesm set local --content backup,iso,vztmpl,import,snippets" \
  || die "cannot update the local storage content"

log "Storage state:"
"${PVE_SSH[@]}" "pvesm status"

# Prevent terragrunt to failed
git config --global --add safe.directory "$SCRIPT_DIR/../../../../../pdcs-core-tf-modules/.git"
