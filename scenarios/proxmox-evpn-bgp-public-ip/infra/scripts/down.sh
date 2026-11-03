#!/usr/bin/env bash
# Tear the full scenario down through the Go orchestrator binary (-down).
# Cleanup steps run in the manifest's 'cleanup:' order and are idempotent;
# runtime credentials and outputs are reused from the install's private state.
# Usage: ./down.sh [extra orchestrator flags]   (e.g. -guided)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${SCENARIO_DIR}/../.." && pwd)"

ORCH="${ORCHESTRATOR_BIN:-${REPO_ROOT}/orchestrator/bin/orchestrator}"
if [[ ! -x "${ORCH}" ]]; then
  if command -v orchestrator >/dev/null 2>&1; then
    ORCH="$(command -v orchestrator)"
  else
    echo "[ERROR] orchestrator binary not found: ${ORCH}" >&2
    echo "[ERROR] build it first: make -C '${REPO_ROOT}' build" >&2
    exit 1
  fi
fi

exec "${ORCH}" -scenario "${SCENARIO_DIR}/scenario.yaml" -root "${SCENARIO_DIR}" -down -auto "$@"
