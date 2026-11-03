#!/bin/bash
set -euo pipefail
# Source the shared VM library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # computed path (SCRIPT_DIR): exists at scenario runtime
source "${SCRIPT_DIR}/../virsh_strator/virsh_strator.sh"

# JSON file local to this project
JSON_FILE="${2:-${SCRIPT_DIR}/vms.json}"

# Action: default "up" if not provided
ACTION="${1:-up}"

# Render vms.json from the template: no credential is ever committed.
TPL_FILE="${SCRIPT_DIR}/vms.json.tpl"
if [[ "${ACTION}" == "down" && -f "${JSON_FILE}" &&
      ( -z "${LAB_VM_PASSWORD:-}" || -z "${LAB_VM_SSH_KEY:-}" ) ]]; then
  # Teardown only needs hostnames/disk paths: reuse the existing file.
  echo "[INFO] Reusing existing ${JSON_FILE} (teardown does not need credentials)."
elif [[ -f "${TPL_FILE}" ]]; then
  if [[ -z "${LAB_VM_PASSWORD:-}" || -z "${LAB_VM_SSH_KEY:-}" ]]; then
    echo "[ERROR] LAB_VM_PASSWORD and LAB_VM_SSH_KEY must be exported to render ${TPL_FILE}" >&2
    exit 1
  fi
  if command -v envsubst >/dev/null 2>&1; then
    envsubst < "${TPL_FILE}" > "${JSON_FILE}"
  else
    python3 - "${TPL_FILE}" "${JSON_FILE}" <<'PY'
import os, re, sys
tpl, out = sys.argv[1], sys.argv[2]
text = open(tpl).read()
text = re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}",
              lambda m: os.environ.get(m.group(1), m.group(0)), text)
open(out, "w").write(text)
PY
  fi
  echo "[INFO] Rendered $(basename "${JSON_FILE}") from template."
elif [[ ! -f "${JSON_FILE}" ]]; then
  echo "[ERROR] Neither ${TPL_FILE} nor ${JSON_FILE} is available." >&2
  exit 1
fi

# Specific actions for project goes here
function scripts() {
    echo "[INFO] Executing project-specific scripts (none defined)."
}

if [[ "$ACTION" == "down" ]]; then
  echo "[INFO] Deleting all VMs defined in $JSON_FILE ..."
  jq -c '.[]' "$JSON_FILE" | while read -r vm; do
    [[ "$(echo "$vm" | jq -r '.type // "vm"')" == "vm" ]] || continue
    vm_name=$(echo "$vm" | jq -r '.hostname')
    disk_dir=$(echo "$vm" | jq -r '.disk_dir // empty')
    echo "[INFO] Destroying VM: $vm_name"
    delete_vm "$vm_name" "${disk_dir:-$LIBVIRT_IMAGE_DIR}"
  done
  echo "[INFO] All VMs deleted."

  echo "[INFO] Deleting all networks defined in $JSON_FILE ..."
  jq -c '.[]' "$JSON_FILE" | while read -r vm; do
    [[ "$(echo "$vm" | jq -r '.type // "vm"')" == "network" ]] || continue
    name=$(echo "$vm" | jq -r '.name')
    delete_network "$name"
  done
  echo "[INFO] All networks deleted."
  exit 0
fi

if [[ "$ACTION" == "up" ]]; then
  # Call main steps
  pull_base_image

  echo "[INFO] Creating all networks defined in $JSON_FILE ..."
  jq -c '.[]' "$JSON_FILE" | while read -r vm; do
    [[ "$(echo "$vm" | jq -r '.type // "vm"')" == "network" ]] || continue
    name=$(echo "$vm" | jq -r '.name')
    bridge=$(echo "$vm" | jq -r '.bridge // empty')
    mode=$(echo "$vm" | jq -r '.mode // "nat"')
    ip=$(echo "$vm" | jq -r '.ip')
    netmask=$(echo "$vm" | jq -r '.netmask // empty')
    dhcp_start=$(echo "$vm" | jq -r '.dhcp_start // empty')
    dhcp_end=$(echo "$vm" | jq -r '.dhcp_end // empty')
    create_network "$name" "$bridge" "$mode" "$ip" "$netmask" "$dhcp_start" "$dhcp_end"
  done
  echo "[INFO] All networks created."

  jq -c '.[]' "$JSON_FILE" | while read -r vm; do
    [[ "$(echo "$vm" | jq -r '.type // "vm"')" == "vm" ]] || continue
    vm_name=$(echo "$vm" | jq -r '.hostname')
    ram=$(echo "$vm" | jq -r '.ram')
    vcpus=$(echo "$vm" | jq -r '.vcpus')
    disk_size=$(echo "$vm" | jq -r '.disk_size')
    user=$(echo "$vm" | jq -r '.user_name')
    passwd=$(echo "$vm" | jq -r '.password')
    ssh_key=$(echo "$vm" | jq -r '.ssh_pub_key')
    networks=$(echo "$vm" | jq -c '.networks[]' 2>/dev/null || true)
    iso_path=$(echo "$vm" | jq -r '.iso_path // empty')
    disk_dir=$(echo "$vm" | jq -r '.disk_dir // empty')
    os_variant=$(echo "$vm" | jq -r '.os_variant // empty')

    disk_dir="${disk_dir:-$LIBVIRT_IMAGE_DIR}"

    create_vm_dir "$vm_name" "$disk_dir"

    if [[ -z "$iso_path" ]]; then
      generate_cloud_init "$vm_name" "$user" "$passwd" "$ssh_key" "$disk_dir" "$networks"
    fi
    create_vm "$vm_name" "$ram" "$vcpus" "$disk_size" "$networks" "$iso_path" "$disk_dir" "$os_variant"
  done

  echo "[INFO] All VMs created."
  scripts
  exit 0
fi

if [[ "$ACTION" == "ip" ]]; then
  echo "[INFO] Showing IPs of all VMs defined in $JSON_FILE ..."
  jq -c '.[]' "$JSON_FILE" | while read -r vm; do
    vm_name=$(echo "$vm" | jq -r '.hostname')
    echo "[INFO] Showing if for VM: $vm_name"
    get_ip_addr "$vm_name"
  done
  exit 0
fi

if [[ "$ACTION" == "stop" ]]; then
  echo "[INFO] Stoping VMs defined in $JSON_FILE ..."
  jq -c '.[]' "$JSON_FILE" | while read -r vm; do
    vm_name=$(echo "$vm" | jq -r '.hostname')
    echo "[INFO] Stoping VM: $vm_name"
    stop_vm "$vm_name"
  done
  exit 0
fi


if [[ "$ACTION" == "start" ]]; then
  echo "[INFO] Starting VMs defined in $JSON_FILE ..."
  jq -c '.[]' "$JSON_FILE" | while read -r vm; do
    vm_name=$(echo "$vm" | jq -r '.hostname')
    echo "[INFO] Starting VM: $vm_name"
    start_vm "$vm_name"
  done
  exit 0
fi

echo "[ERROR] Unknown action: $ACTION"
echo "Usage: $0 {up|down|ip|stop|start}"
exit 1
