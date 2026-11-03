#!/usr/bin/env bash
# Ensure the lab SSH key pair exists and publish its paths/keys to the orchestrator:
#
#   PROXMOX_VE_SSH_PRIVATE_KEY_PATH  private key used by the Proxmox provider
#                                    and the API-token step
#   LAB_VM_SSH_KEY                   public key injected into the VMs
#   PVE_SSH_PUBKEY                   public key installed on the Proxmox node
#                                    (answer file root-ssh-keys)
#
# Idempotent: an existing key is reused.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/env.sh"

SCENARIO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_KEY="${SCENARIO_ROOT}/.ssh/id_ed25519"

KEY_PATH="${PROXMOX_VE_SSH_PRIVATE_KEY_PATH:-${DEFAULT_KEY}}"

if [[ ! -f "${KEY_PATH}" ]]; then
  echo "[INFO] Generating SSH key pair: ${KEY_PATH}"
  mkdir -p "$(dirname "${KEY_PATH}")"
  chmod 700 "$(dirname "${KEY_PATH}")"
  ssh-keygen -q -t ed25519 -N "" -C "pdcs-lab" -f "${KEY_PATH}"
else
  echo "[OK] SSH key already present: ${KEY_PATH}"
fi

if [[ -f "${KEY_PATH}.pub" ]]; then
  PUBKEY="$(cat "${KEY_PATH}.pub")"
else
  PUBKEY="$(ssh-keygen -y -f "${KEY_PATH}")"
fi

set_env_var PROXMOX_VE_SSH_PRIVATE_KEY_PATH "${KEY_PATH}"
set_env_var LAB_VM_SSH_KEY "${PUBKEY}"
set_env_var PVE_SSH_PUBKEY "${PUBKEY}"

echo "[OK] SSH key ready; public key and private-key path published to the orchestrator"
