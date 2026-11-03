#!/usr/bin/env bash
# Reset the scenario to its initial state: full teardown then redeploy,
# both through the Go orchestrator binary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/down.sh"
"${SCRIPT_DIR}/up.sh"
