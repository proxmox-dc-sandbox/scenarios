#!/usr/bin/env bash
# Download the MikroTik CHR image, convert it to qcow2 and boot the
# "mikrotik-bgp" VM on the scenario networks.
# Idempotent: skips download/convert/creation when already done, and never
# hangs on the interactive "replace file?" unzip prompt (-o overwrites).
# The following mikrotik-config step activates the p-unlimited license from
# the account credentials supplied in scenario.yaml.
# Usage: mikrotik-router.sh {start|delete}
set -euo pipefail

VERSION="7.25"
ZIP_URL="https://download.mikrotik.com/routeros/${VERSION}/chr-${VERSION}.img.zip"

STORE_DIR="${KVM_STORE_DIR}"
IMAGE_DIR="${STORE_DIR}/mikrotik"
ZIP_FILE="${IMAGE_DIR}/chr-${VERSION}.img.zip"
IMG_FILE="${IMAGE_DIR}/chr-${VERSION}.img"
DISK_FILE="${STORE_DIR}/mikrotik-bgp.qcow2"
VM_NAME="mikrotik-bgp"
VIRSH="virsh --connect qemu:///system"

mkdir -p "${IMAGE_DIR}"

vm_exists() { $VIRSH dominfo "${VM_NAME}" >/dev/null 2>&1; }
vm_running() {
  vm_exists &&
    [[ "$($VIRSH domstate "${VM_NAME}" | awk '{print $1}')" == "running" ]]
}

ACTION="${1:-start}"

case "$ACTION" in
  start)
    if vm_exists; then
      echo "[OK] VM ${VM_NAME} already defined."
      if ! vm_running; then
        echo "[INFO] Starting VM ${VM_NAME}"
        $VIRSH start "${VM_NAME}"
      fi
      exit 0
    fi

    if [[ -f "${ZIP_FILE}" ]]; then
      echo "[OK] CHR image already downloaded: ${ZIP_FILE}"
    else
      echo "[INFO] Downloading MikroTik CHR ${VERSION} ..."
      wget -q --show-progress -O "${ZIP_FILE}" "${ZIP_URL}"
    fi

    echo "[INFO] Converting image to qcow2 ..."
    unzip -o -q "${ZIP_FILE}" -d "${IMAGE_DIR}"
    rm -f "${DISK_FILE}"
    qemu-img convert -f raw -O qcow2 "${IMG_FILE}" "${DISK_FILE}"
    chown libvirt-qemu:kvm "${DISK_FILE}" 2>/dev/null || true
    chmod 666 "${DISK_FILE}" 2>/dev/null || true

    echo "[INFO] Creating VM ${VM_NAME}"
    virt-install \
      --name "${VM_NAME}" \
      --memory 1024 \
      --vcpus 1 \
      --os-variant generic \
      --disk path="${DISK_FILE}",bus=virtio \
      --import \
      --network network=pdcs-public-network,model=virtio,mac=52:54:00:00:00:aa \
      --network network=pdcs-private-network,model=virtio,mac=52:54:00:00:00:ab \
      --graphics vnc,listen=0.0.0.0 \
      --noautoconsole
    echo "[OK] VM ${VM_NAME} created. License activation runs in the mikrotik-config step."
    ;;

  delete)
    if vm_exists; then
      echo "[INFO] Destroying VM ${VM_NAME}"
      $VIRSH destroy "${VM_NAME}" 2>/dev/null || true
      $VIRSH undefine "${VM_NAME}" --remove-all-storage 2>/dev/null ||
        $VIRSH undefine "${VM_NAME}"
    else
      echo "[OK] VM ${VM_NAME} already absent."
    fi
    rm -f "${DISK_FILE}"
    echo "[OK] MikroTik cleaned."
    ;;

  *)
    echo "Usage: $0 {start|delete}" >&2
    exit 1
    ;;
esac
