#!/usr/bin/env bash
# Deploy the full scenario through the Go orchestrator binary.
#
# The binary resolves the manifest 'env:' block and runs every step in
# dependency order. Runtime values are kept in private scenario state.
# Usage: ./up.sh [extra orchestrator flags]   (e.g. -guided, -resume)
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

exec "${ORCH}" -scenario "${SCENARIO_DIR}/scenario.yaml" -root "${SCENARIO_DIR}" -auto "$@"
