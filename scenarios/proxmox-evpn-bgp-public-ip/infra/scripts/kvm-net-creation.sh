#!/usr/bin/env bash
# Define/start/stop the KVM libvirt networks used by the scenario.
# Idempotent: re-running never fails on already-defined or already-active
# networks (they are detected and skipped instead).
# Usage: kvm-net-creation.sh {start|stop|delete|status}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL_DIR="${SCRIPT_DIR}/../templates/kvm-network"
VIRSH="virsh --connect qemu:///system"

declare -a NETS=(
  "pdcs-public-network:${TPL_DIR}/pdcs-public_network.xml"
  "pdcs-private-network:${TPL_DIR}/pdcs-private_network.xml"
)

usage() { echo "Usage: $0 {start|stop|delete|status}" >&2; exit 1; }

net_exists() { $VIRSH net-info "$1" >/dev/null 2>&1; }

net_active() {
  net_exists "$1" &&
    [[ "$($VIRSH net-info "$1" | awk '/^Active:/{print $2}')" == "yes" ]]
}

ACTION="${1:-start}"

case "$ACTION" in
  start | create)
    for entry in "${NETS[@]}"; do
      name="${entry%%:*}"
      xml="${entry#*:}"
      if net_exists "$name"; then
        echo "[OK] Network ${name} already defined, skipping definition."
      else
        echo "[INFO] Defining network ${name} from ${xml}"
        $VIRSH net-define "$xml"
      fi
      if net_active "$name"; then
        echo "[OK] Network ${name} already active."
      else
        echo "[INFO] Starting network ${name}"
        $VIRSH net-start "$name"
      fi
      $VIRSH net-autostart "$name" >/dev/null
    done
    echo "[OK] Networks ready."
    ;;

  stop | delete | clean)
    for entry in "${NETS[@]}"; do
      name="${entry%%:*}"
      if net_active "$name"; then
        echo "[INFO] Destroying active network ${name}"
        $VIRSH net-destroy "$name"
      fi
      if net_exists "$name"; then
        echo "[INFO] Undefining network ${name}"
        $VIRSH net-undefine "$name"
      else
        echo "[OK] Network ${name} already absent."
      fi
    done
    echo "[OK] Networks removed."
    ;;

  status)
    for entry in "${NETS[@]}"; do
      name="${entry%%:*}"
      if net_active "$name"; then
        echo "[OK] ${name}: active"
      elif net_exists "$name"; then
        echo "[WARN] ${name}: defined but inactive"
      else
        echo "[WARN] ${name}: not defined"
      fi
    done
    ;;

  *)
    usage
    ;;
esac
