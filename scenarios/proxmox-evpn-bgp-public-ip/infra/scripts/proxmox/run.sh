#!/usr/bin/env bash
#
# Create (or destroy) an unattended Proxmox VE VM on a local libvirt/KVM host.
#
# Usage:
#   ./run.sh /path/to/proxmox-ve.iso [answer.toml]   create and start the VM
#   ./run.sh --destroy                               remove the VM and what was created for it
#
# Optional environment variables (defaults in brackets):
#   VM_NAME [pve]            VM name
#   VM_POOL [default]        libvirt storage pool (created if missing)
#   VM_NETWORK [default]     libvirt network
#   VM_MAC [52:54:00:00:00:43]  MAC address, bound to the reserved IP
#   VM_MEMORY [4096]         memory in MiB
#   VM_VCPUS [4]             number of vCPUs
#   VM_DISK_GB [30]          disk size in GiB
#   VM_WAIT [30]             maximum duration of the installation, in minutes
#   API_WAIT [10]            maximum wait for the Proxmox API, in minutes
#   PROXMOX_VE_ENDPOINT      Proxmox API endpoint polled once the VM is up

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export LIBVIRT_DEFAULT_URI=qemu:///system

VM=${VM_NAME}
POOL=${VM_POOL}
NET=${VM_NETWORK}
MAC=${VM_MAC}
MEMORY=${VM_MEMORY}
VCPUS=${VM_VCPUS}
DISK_GB=${VM_DISK_GB}
WAIT=${VM_WAIT}
ISO_VOL="$VM-auto.iso"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

need() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing command: $cmd"
  done
}

# Render ${VAR} / ${VAR:-default} placeholders of an answer file template.
render_template() {
  local tpl=$1 out=$2
  command -v python3 >/dev/null 2>&1 || die "missing command: python3 (needed to render $tpl)"
  python3 - "$tpl" "$out" <<'PYEOF'
import os, re, sys
tpl, out = sys.argv[1], sys.argv[2]
ref = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}")
def repl(m):
    return os.environ.get(m.group(1)) or (m.group(2) or "")
open(out, "w").write(ref.sub(repl, open(tpl).read()))
PYEOF
}

destroy() {
  need virsh
  log "Removing VM '$VM'"
  virsh destroy "$VM" >/dev/null 2>&1 || true
  virsh undefine "$VM" --remove-all-storage --nvram >/dev/null 2>&1 \
    || virsh undefine "$VM" --remove-all-storage >/dev/null 2>&1 || true
  virsh vol-delete "$ISO_VOL" --pool "$POOL" >/dev/null 2>&1 || true
  log "Done"
}

if [ "${1:-}" = "--destroy" ]; then
  destroy
  exit 0
fi

ISO_SRC=${1:-${PVE_ISO}}
ANSWER_SRC=${2:-${SCRIPT_DIR}/pve.toml.tpl}

need virsh virt-install proxmox-auto-install-assistant xorriso
[ -e /dev/kvm ] || die "/dev/kvm not found: KVM is not available on this host"
virsh uri >/dev/null 2>&1 || die "cannot connect to libvirt: is your user in the 'libvirt' group?"

# Idempotent: an existing VM means the installation is already done.
if virsh dominfo "$VM" >/dev/null 2>&1; then
  log "VM '$VM' already exists - skipping installation (use '$0 --destroy' to remove it)"
  exit 0
fi

[ -n "$ISO_SRC" ] || die "usage: $0 /path/to/proxmox-ve.iso [answer.toml|answer.toml.tpl] | --destroy (or set PVE_ISO)"
[ -f "$ISO_SRC" ] || die "ISO not found: $ISO_SRC"
[ -f "$ANSWER_SRC" ] || die "answer file not found: $ANSWER_SRC"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

ANSWER=$ANSWER_SRC
case "$ANSWER_SRC" in
  *.tpl)
    export PVE_SSH_PUBKEY
    [ -n "$PVE_SSH_PUBKEY" ] || die "PVE_SSH_PUBKEY (or LAB_VM_SSH_KEY) is required: the node must accept the generated SSH key (run the ssh-keygen step)"
    ANSWER="$WORK/answer.toml"
    render_template "$ANSWER_SRC" "$ANSWER"
    ;;
esac

# Storage pool: create it if missing, start it if inactive
if ! virsh pool-info "$POOL" >/dev/null 2>&1; then
  log "Creating storage pool '$POOL'"
  virsh pool-define-as "$POOL" dir --target "/var/lib/libvirt/images/$POOL" >/dev/null
  virsh pool-build "$POOL" >/dev/null
  virsh pool-autostart "$POOL" >/dev/null
fi
if [ "$(virsh pool-info "$POOL" | awk '/^State:/{print $2}')" != "running" ]; then
  virsh pool-start "$POOL" >/dev/null
fi

# Network: make sure it is running
virsh net-info "$NET" >/dev/null 2>&1 || die "libvirt network '$NET' does not exist"
if [ "$(virsh net-info "$NET" | awk '/^Active:/{print $2}')" != "yes" ]; then
  log "Starting network '$NET'"
  virsh net-start "$NET" >/dev/null
fi

# prepare-iso writes a temporary copy next to the source ISO: use a writable
# copy when the source directory is read-only (ro mount, NFS, ...).
ISO_INPUT="$ISO_SRC"
if [ ! -w "$(dirname "$ISO_SRC")" ]; then
  log "Copying the ISO to a writable location"
  ISO_INPUT="$WORK/source.iso"
  cp "$ISO_SRC" "$ISO_INPUT"
fi

# Build the ISO with the answer file
log "Preparing the ISO"
proxmox-auto-install-assistant prepare-iso "$ISO_INPUT" \
  --fetch-from iso --answer-file "$ANSWER" --output "$WORK/$ISO_VOL"

# Upload it to the storage pool (no sudo needed, and QEMU can read it)
log "Uploading the ISO to pool '$POOL'"
virsh vol-delete "$ISO_VOL" --pool "$POOL" >/dev/null 2>&1 || true
virsh vol-create-as "$POOL" "$ISO_VOL" "$(stat -c%s "$WORK/$ISO_VOL")" --format raw >/dev/null
virsh vol-upload --pool "$POOL" "$ISO_VOL" "$WORK/$ISO_VOL"

# Create the VM; libvirt creates the disk in the pool.
# virt-install waits until the unattended installation is finished.
log "Installing Proxmox VE (up to $WAIT minutes)"
virt-install --name "$VM" --memory "$MEMORY" --vcpus "$VCPUS" \
  --cpu host-passthrough --os-variant debian13 \
  --disk pool="$POOL",size="$DISK_GB",bus=virtio,format=qcow2 \
  --cdrom "$(virsh vol-path --pool "$POOL" "$ISO_VOL")" \
  --network network="$NET",model=virtio,mac="$MAC" \
  --graphics vnc,listen=127.0.0.1 \
  --noautoconsole --wait "$WAIT"

# virt-install may restart the VM itself once the installation is complete.
# Start it only if it is not already running.
log "Making sure the VM is running"
for _ in $(seq 1 30); do
  state=$(virsh domstate "$VM")
  [ "$state" = "running" ] && break
  if [ "$state" = "shut off" ]; then
    virsh start "$VM" >/dev/null
    break
  fi
  sleep 2
done

# Wait for the Proxmox API to answer so that Terragrunt can run right after.
if [ -n "${PROXMOX_VE_ENDPOINT:-}" ]; then
  API_WAIT="${API_WAIT:-10}"
  log "Waiting for the Proxmox VE API at $PROXMOX_VE_ENDPOINT (up to ${API_WAIT} min)"
  deadline=$(( $(date +%s) + API_WAIT * 60 ))
  while :; do
    code=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 5 \
      "$PROXMOX_VE_ENDPOINT/api2/json/version" || true)
    case "$code" in
      2*|401|403) break ;;
    esac
    if [ "$(date +%s)" -ge "$deadline" ]; then
      die "Proxmox VE API not reachable at $PROXMOX_VE_ENDPOINT after ${API_WAIT} min (check PROXMOX_VE_ENDPOINT / VM_NETWORK, then re-run with -resume)"
    fi
    sleep 10
  done
  log "Proxmox VE API is answering (HTTP $code)"
else
  log "PROXMOX_VE_ENDPOINT not set - skipping the API readiness check"
fi

log "VM created. Check if all is ok with virsh command"
