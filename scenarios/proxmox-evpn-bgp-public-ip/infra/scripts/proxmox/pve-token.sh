#!/usr/bin/env bash
# Create a Proxmox VE API token and publish it to the orchestrator.
#
# The node lives on the isolated private network: SSH goes through the bastion
# (PVE_BASTION, published by the bastion-proxy step). The orchestrator passes
# the token to the Terragrunt step without restarting the run.
#
# Idempotent: the stored token is checked against the node and reused when
# valid; otherwise it is recreated.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../lib/env.sh"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../lib/pve-ssh.sh"

NODE_ADDRESS="${PROXMOX_NODE_ADDRESS}"
TOKEN_ID="${PVE_TOKEN_ID}"
WAIT="${PVE_SSH_WAIT}"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

ENDPOINT="${PROXMOX_VE_ENDPOINT}"

# A stored token may be stale (node reinstalled, token revoked): check it
# against the node before skipping.
if [[ -n "${PROXMOX_VE_API_TOKEN:-}" ]]; then
  code="$(curl -ks -o /dev/null -w '%{http_code}' --max-time 5 \
    -H "Authorization: PVEAPIToken=${PROXMOX_VE_API_TOKEN}" \
    "${ENDPOINT%/}/api2/json/version" || true)"
  case "${code}" in
    2*)
      log "existing API token is valid on ${NODE_ADDRESS} - skipping token creation"
      set_env_var PROXMOX_VE_API_TOKEN "${PROXMOX_VE_API_TOKEN}"
      exit 0
      ;;
    *)
      log "stored API token is not valid on ${NODE_ADDRESS} (HTTP ${code}) - recreating it"
      ;;
  esac
fi

pve_ssh_init || die "cannot build the SSH command to the node"
pve_wait_ssh "${WAIT}" || die "node unreachable over SSH (check the bastion proxy, then re-run with -resume)"

log "Creating API token ${TOKEN_ID} for root@pam on ${NODE_ADDRESS}"
"${PVE_SSH[@]}" "pveum user token remove root@pam '${TOKEN_ID}'" >/dev/null 2>&1 || true
OUT="$("${PVE_SSH[@]}" "pveum user token add root@pam '${TOKEN_ID}' --privsep 0 --output-format json")" \
  || die "pveum user token add failed on the node"

TOKEN_VALUE="$(printf '%s' "${OUT}" | jq -r '.value // empty')"
[[ -n "${TOKEN_VALUE}" ]] || die "cannot parse the token value from pveum output: ${OUT}"

set_env_var PROXMOX_VE_API_TOKEN "root@pam!${TOKEN_ID}=${TOKEN_VALUE}"
log "API token published to the orchestrator"
