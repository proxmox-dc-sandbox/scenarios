#!/usr/bin/env bash
# Verify that every tool required by the scenario is available, and that
# libvirt is reachable. Exits non-zero if anything is missing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MISSING=0

for tool in virsh virt-install qemu-img wget unzip jq python3 xorriso proxmox-auto-install-assistant curl terragrunt tofu git mkpasswd ssh-keygen sshpass sha256sum; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "[OK] ${tool} found"
  else
    echo "[ERROR] ${tool} missing - install it before running the scenario" >&2
    MISSING=1
  fi
done

if [[ ! -e /dev/kvm ]]; then
  echo "[ERROR] /dev/kvm missing - KVM (nested virtualization) is required for the Proxmox VE node" >&2
  MISSING=1
else
  echo "[OK] /dev/kvm available"
fi

if ! virsh --connect qemu:///system uri >/dev/null 2>&1; then
  echo "[ERROR] Cannot reach libvirt (qemu:///system). Is libvirtd running and is the user in the 'libvirt' group?" >&2
  MISSING=1
else
  echo "[OK] libvirt reachable (qemu:///system)"
fi

if [[ "$MISSING" -ne 0 ]]; then
  echo "[ERROR] Missing dependencies - fix the errors above first." >&2
  exit 1
fi

echo "[OK] All scenario dependencies are satisfied."
