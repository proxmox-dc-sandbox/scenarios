#!/usr/bin/env bash
# E2E: the plain BGP session node<->CHR is established and only planned
# prefixes circulate.
#
# Delegates to infra/scripts/mikrotik/verify-bgp.sh — the single source of
# truth for the BGP checks (SDN controller present, FRR vtysh JSON peer
# state "Established", CHR session established). This wrapper only makes the
# test runnable standalone by sourcing the persisted scenario environment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
# shellcheck disable=SC1091  # computed path (SCRIPT_DIR): exists at scenario runtime
. "${SCRIPT_DIR}/lib.sh"

VERIFY="${SCRIPT_DIR}/../../infra/scripts/mikrotik/verify-bgp.sh"
if [[ ! -f "${VERIFY}" ]]; then
  echo "error: ${VERIFY} not found" >&2
  exit 1
fi

load_scenario_env \
  CHR_PUBLIC_IP BGP_PEER BGP_WAIT \
  PROXMOX_NODE_ADDRESS PROXMOX_VE_SSH_USERNAME PVE_BASTION_USER \
  PROXMOX_VE_SSH_PRIVATE_KEY_PATH PVE_ROOT_PASSWORD \
  || exit 1

echo "==> e2e bgp: delegating to infra/scripts/mikrotik/verify-bgp.sh"
exec "${VERIFY}"
