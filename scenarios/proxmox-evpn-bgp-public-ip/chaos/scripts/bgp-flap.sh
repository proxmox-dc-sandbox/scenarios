#!/usr/bin/env bash
# Chaos: flap the BGP sessions of the node (FRR restart drops both the CHR
# peering and the EVPN fabric), then assert the recovery through the e2e
# BGP test.
#
# Run with: orchestrator -scenario scenario.yaml -phase chaos -continue-on-error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../infra/scripts/lib/pve-ssh.sh
# shellcheck disable=SC1091  # computed path (SCRIPT_DIR): exists at scenario runtime
. "${SCRIPT_DIR}/../../infra/scripts/lib/pve-ssh.sh"

FLAP_WAIT="${BGP_FLAP_WAIT:-30}"
VERIFY="${SCRIPT_DIR}/../../tests/e2e/test-bgp.sh"

log() { echo "[chaos] $*"; }
die() { echo "error: $*" >&2; exit 1; }

if [[ ! -f "${VERIFY}" ]]; then
  die "${VERIFY} not found"
fi

pve_ssh_init || die "cannot build the SSH command to the node"

log "restarting frr on the node (session flap)"
"${PVE_SSH[@]}" "systemctl restart frr"

log "waiting ${FLAP_WAIT}s before verification"
sleep "${FLAP_WAIT}"

log "verifying recovery (delegating to tests/e2e/test-bgp.sh)"
exec "${VERIFY}"
