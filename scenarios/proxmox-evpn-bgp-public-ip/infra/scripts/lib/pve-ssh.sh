#!/usr/bin/env bash
# SSH helpers for the Proxmox node (sourced, not executed).
#
# The node lives on the isolated private network: it is only reachable through
# the bastion (SSH jump). PVE_BASTION is published by the bastion-proxy step
# and supplied by the orchestrator to each subsequent step.
#
# Authentication: generated key (PROXMOX_VE_SSH_PRIVATE_KEY_PATH) or
# PVE_ROOT_PASSWORD via sshpass.

pve_ssh_init() {
  local key="${PROXMOX_VE_SSH_PRIVATE_KEY_PATH:-}"
  local bastion="${PVE_BASTION:-}"
  local bastion_user="${PVE_BASTION_USER}"
  local addr="${PROXMOX_NODE_ADDRESS}"
  local pve_user="${PROXMOX_VE_SSH_USERNAME}"

  PVE_SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
                -o ConnectTimeout=10 -o LogLevel=ERROR)

  local jump=()
  if [[ -n "${bastion}" ]]; then
    jump=(-o "ProxyCommand=ssh -i ${key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ${bastion_user}@${bastion}")
  fi

  if [[ -n "${key}" && -f "${key}" ]]; then
    PVE_SSH=(ssh -i "${key}" -o IdentitiesOnly=yes "${jump[@]}" "${PVE_SSH_OPTS[@]}" "${pve_user}@${addr}")
  elif [[ -n "${PVE_ROOT_PASSWORD:-}" ]] && command -v sshpass >/dev/null 2>&1; then
    PVE_SSH=(sshpass -p "${PVE_ROOT_PASSWORD}" ssh "${jump[@]}" "${PVE_SSH_OPTS[@]}" "${pve_user}@${addr}")
  else
    echo "error: no SSH authentication available (set PROXMOX_VE_SSH_PRIVATE_KEY_PATH or PVE_ROOT_PASSWORD)" >&2
    return 1
  fi
}

# pve_wait_ssh <timeout-seconds>
pve_wait_ssh() {
  local timeout="${1:-600}"
  local deadline=$(( $(date +%s) + timeout ))
  echo "==> Waiting for SSH on ${PROXMOX_VE_SSH_USERNAME}@${PROXMOX_NODE_ADDRESS} (up to ${timeout}s)"
  until "${PVE_SSH[@]}" true >/dev/null 2>&1; do
    if [[ "$(date +%s)" -ge "${deadline}" ]]; then
      echo "error: cannot reach the node over SSH after ${timeout}s" >&2
      return 1
    fi
    sleep 5
  done
}
