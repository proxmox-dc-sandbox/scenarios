#!/usr/bin/env bash
# Fail before creating lab resources if the required account values are absent.
set -euo pipefail

[[ -n "${MIKROTIK_LICENSE_EMAIL:-}" ]] || {
  echo "error: set MIKROTIK_LICENSE_EMAIL in scenario.yaml" >&2
  exit 1
}
[[ -n "${MIKROTIK_LICENSE_PASSWORD:-}" ]] || {
  echo "error: set MIKROTIK_LICENSE_PASSWORD in scenario.yaml" >&2
  exit 1
}

echo "[OK] MikroTik license account values are configured"
