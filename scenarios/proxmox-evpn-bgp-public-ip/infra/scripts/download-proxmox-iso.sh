#!/usr/bin/env bash
# Download and verify the Proxmox VE ISO at the scenario-local path declared
# in scenario.yaml. The repository bind mount makes it available in Docker.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

[[ -n "${PVE_ISO:-}" ]] || die "PVE_ISO is not configured in scenario.yaml"
[[ -n "${PVE_ISO_URL:-}" ]] || die "PVE_ISO_URL is not configured in scenario.yaml"
[[ "${PVE_ISO_SHA256:-}" =~ ^[[:xdigit:]]{64}$ ]] || die "PVE_ISO_SHA256 must be a 64-character SHA-256 value"
[[ "${PVE_ISO_URL}" == https://* ]] || die "PVE_ISO_URL must use HTTPS"

SCENARIO_ROOT="${PDCS_SCENARIO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
case "${PVE_ISO}" in
  "${SCENARIO_ROOT}"/*) ;;
  *) die "PVE_ISO must resolve inside the scenario directory for portable Docker access" ;;
esac

mkdir -p "$(dirname "${PVE_ISO}")"
verify_iso() {
  local actual
  actual="$(sha256sum "${1}" | cut -d ' ' -f1)"
  [[ "${actual,,}" == "${PVE_ISO_SHA256,,}" ]]
}

if [[ -s "${PVE_ISO}" ]]; then
  if verify_iso "${PVE_ISO}"; then
    log "Verified cached Proxmox VE ISO: ${PVE_ISO}"
    exit 0
  fi
  die "existing ISO checksum mismatch at ${PVE_ISO}; remove it before retrying"
fi

PARTIAL="${PVE_ISO}.part"
log "Downloading Proxmox VE ISO from ${PVE_ISO_URL}"
wget --tries=3 --timeout=30 --continue --output-document="${PARTIAL}" "${PVE_ISO_URL}" ||
  die "ISO download failed; the partial file is retained for a -resume retry"
if ! verify_iso "${PARTIAL}"; then
  rm -f "${PARTIAL}"
  die "downloaded ISO checksum mismatch (expected ${PVE_ISO_SHA256})"
fi
mv "${PARTIAL}" "${PVE_ISO}"
log "Downloaded and verified Proxmox VE ISO: ${PVE_ISO}"
