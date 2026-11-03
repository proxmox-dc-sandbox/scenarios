#!/usr/bin/env bash
# Shared helpers for the e2e tests (sourced, not executed).
#
# The tests run standalone after a completed scenario install: the
# orchestrator environment of the run is persisted in
# .state/proxmox-evpn-bgp-public-ip.json (mode 0600, "env" map) and this
# helper re-exports it on demand. Variables already present in the
# environment always win (manual override).
# shellcheck shell=bash

# load_scenario_env VAR... — export each VAR from the persisted scenario
# state when it is not already set; fails with an explicit list when some
# variable cannot be resolved.
load_scenario_env() {
  local lib_dir state_file var val missing=()
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  state_file="${SCENARIO_STATE_FILE:-${lib_dir}/../../.state/proxmox-evpn-bgp-public-ip.json}"

  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      if [[ -f "${state_file}" ]]; then
        val="$(jq -r --arg k "${var}" '.env[$k] // empty' "${state_file}" 2>/dev/null || true)"
        if [[ -n "${val}" ]]; then
          printf -v "${var}" '%s' "${val}"
          export "${var?}"
        fi
      fi
      if [[ -z "${!var:-}" ]]; then
        missing+=("${var}")
      fi
    fi
  done

  if ((${#missing[@]})); then
    echo "error: missing environment variables: ${missing[*]}" >&2
    if [[ ! -f "${state_file}" ]]; then
      echo "  (no persisted state at ${state_file}: run a completed scenario install first)" >&2
    else
      echo "  (present in neither the environment nor the persisted state)" >&2
    fi
    return 1
  fi
}
