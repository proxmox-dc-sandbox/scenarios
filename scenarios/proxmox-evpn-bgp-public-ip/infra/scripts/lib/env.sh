#!/usr/bin/env bash
# Helpers for the deployment scripts (sourced, not executed).

# set_env_var <key> <value>
# Publish a runtime value back to the Go orchestrator. Values are written as
# NUL-delimited name/value pairs so spaces, equals signs and newlines survive
# without shell parsing or a second .env configuration file.
set_env_var() {
  local key=${1:-} value=${2:-}
  [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
    echo "error: invalid environment output name: ${key}" >&2
    return 1
  }
  [[ -n "${PDCS_ENV_OUTPUT_FILE:-}" ]] || {
    echo "error: PDCS_ENV_OUTPUT_FILE was not provided by the orchestrator" >&2
    return 1
  }
  printf '%s\0%s\0' "${key}" "${value}" >>"${PDCS_ENV_OUTPUT_FILE}"
  export "${key}=${value}"
}
