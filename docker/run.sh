#!/usr/bin/env bash
# Build and run the deployment tools container.
#
# The container runs with --network host and talks to the host libvirt daemon
# through its socket; the repository is mounted at the SAME absolute path so
# that scenario-local files and state work identically inside and outside the
# container. Nothing is installed on the host.
#
# Usage:
#   SCENARIO=<name> docker/run.sh <mode> [orchestrator flags]
#   docker/run.sh --scenario <name> <mode> [orchestrator flags]
#   docker/run.sh --scenario <name> shell [command...]
#
# Modes:
#   build    build the image
#   up       install (orchestrator -auto)
#   down     teardown (orchestrator -down)
#   resume   resume after a failure (orchestrator -auto -resume)
#   guided   step by step (orchestrator -guided)
#   check    validate the manifest (orchestrator -check)
#   shell    debug shell (bash) in the container
#
# Environment:
#   SCENARIO                     scenario name (or path) to mount/run
#   IMAGE                        image name (default: pdcs-scenarios-tools:latest)
#   DOCKER_BUILD_NETWORK_HOST    "true" to pass --network=host to docker build
#   DOCKER_BUILD_NO_CACHE        "true" to rebuild every image layer
#   DOCKER_BUILD_PULL            "true" to refresh Docker base images
#   EXTRA_MOUNTS                 extra host paths to mount at the same path
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE="${IMAGE:-pdcs-scenarios-tools:latest}"
SCENARIO="${SCENARIO:-}"
MODE=""
ORCH_EXTRA=()

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s | --scenario)
      [[ $# -ge 2 ]] || { echo "error: missing value for $1" >&2; exit 2; }
      SCENARIO="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$MODE" ]]; then
        MODE="$1"
      else
        ORCH_EXTRA+=("$1")
      fi
      shift
      ;;
  esac
done
MODE="${MODE:-up}"

# Optional host network for docker build (needed behind restrictive proxies).
BUILD_NET=()
if [[ "${DOCKER_BUILD_NETWORK_HOST:-false}" == "true" ]]; then
  BUILD_NET=(--network=host)
fi
BUILD_FLAGS=()
if [[ "${DOCKER_BUILD_NO_CACHE:-false}" == "true" ]]; then
  BUILD_FLAGS+=(--no-cache)
fi
if [[ "${DOCKER_BUILD_PULL:-false}" == "true" ]]; then
  BUILD_FLAGS+=(--pull)
fi

build_image() {
  docker build "${BUILD_NET[@]}" "${BUILD_FLAGS[@]}" \
    -f "${SCRIPT_DIR}/Dockerfile" -t "${IMAGE}" "${REPO_ROOT}"
}

if [[ "$MODE" == "build" ]]; then
  build_image
  exit 0
fi

case "$MODE" in
  up)     ORCH_ARGS=(-auto) ;;
  down)   ORCH_ARGS=(-down) ;;
  resume) ORCH_ARGS=(-auto -resume) ;;
  guided) ORCH_ARGS=(-guided) ;;
  check)  ORCH_ARGS=(-check) ;;
  shell)  ORCH_ARGS=() ;;
  *)
    echo "error: unknown mode '$MODE' (build|up|down|resume|guided|check|shell)" >&2
    exit 2
    ;;
esac

if [[ -z "$SCENARIO" ]]; then
  echo "error: no scenario specified (SCENARIO=<name> or --scenario <name>)" >&2
  echo "available scenarios:" >&2
  find "${REPO_ROOT}/scenarios" -maxdepth 2 -name scenario.yaml -printf '%h\n' |
    xargs -n1 basename | grep -v '^_' | sed 's/^/  - /' >&2 || true
  exit 2
fi

if [[ "$SCENARIO" == */* ]]; then
  SCENARIO_DIR="$SCENARIO"
  [[ "$SCENARIO_DIR" = /* ]] || SCENARIO_DIR="${REPO_ROOT}/${SCENARIO_DIR}"
else
  SCENARIO_DIR="${REPO_ROOT}/scenarios/${SCENARIO}"
fi
SCENARIO_DIR="$(cd "$SCENARIO_DIR" && pwd)" ||
  { echo "error: scenario directory not found: $SCENARIO" >&2; exit 2; }
[[ -f "${SCENARIO_DIR}/scenario.yaml" ]] ||
  { echo "error: ${SCENARIO_DIR}/scenario.yaml not found" >&2; exit 2; }

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "[INFO] Image ${IMAGE} not found, building it ..."
  build_image
fi

# A TTY is only attached when one is available (CI-friendly).
TTY_FLAGS=(-i)
[[ -t 0 && -t 1 ]] && TTY_FLAGS=(-it)

# ssh-keygen (and other tools) call getpwuid(): the container must know the
# host UID. Build passwd/group files = image entries + the current user.
PASSWD_TMP="$(mktemp)"
GROUP_TMP="$(mktemp)"
trap 'rm -f "${PASSWD_TMP}" "${GROUP_TMP}"' EXIT
docker run --rm --entrypoint cat "${IMAGE}" /etc/passwd >"${PASSWD_TMP}"
docker run --rm --entrypoint cat "${IMAGE}" /etc/group >"${GROUP_TMP}"
echo "$(id -un 2>/dev/null || echo user):x:$(id -u):$(id -g):container user:/tmp:/bin/bash" >>"${PASSWD_TMP}"
echo "$(id -gn 2>/dev/null || echo user):x:$(id -g):" >>"${GROUP_TMP}"
chmod 644 "${PASSWD_TMP}" "${GROUP_TMP}"

MOUNTS=(-v "${REPO_ROOT}:${REPO_ROOT}"
        -v "${PASSWD_TMP}:/etc/passwd:ro"
        -v "${GROUP_TMP}:/etc/group:ro")
  [[ -e /var/run/libvirt ]] && MOUNTS+=(-v /var/run/libvirt:/var/run/libvirt)
  [[ -e /dev/kvm ]] && MOUNTS+=(-v /dev/kvm:/dev/kvm)
  for path in ${EXTRA_MOUNTS:-}; do
    MOUNTS+=(-v "${path}:${path}")
  done

# Run as the host user so files created in the mounted repo (runtime assets,
# state, logs, Terragrunt caches) stay owned by the user. libvirt group access
# is granted through the socket's group; HOME uses a writable scratch dir.
USER_FLAGS=(--user "$(id -u):$(id -g)")
LIBVIRT_SOCK="/var/run/libvirt/libvirt-sock"
[[ -S "${LIBVIRT_SOCK}" ]] && USER_FLAGS+=(--group-add "$(stat -c %g "${LIBVIRT_SOCK}")")
DOCKER_ENV=(-e "HOME=/tmp")

# Note: VM_HOST_ID (last octet of the reserved IP) was removed with the DHCP
# reservation code; the MAC address in scenario.yaml carries the reservation.

if [[ "$MODE" == "shell" ]]; then
  exec docker run --rm "${TTY_FLAGS[@]}" --network host \
    "${USER_FLAGS[@]}" "${MOUNTS[@]}" "${DOCKER_ENV[@]}" \
    -w "${REPO_ROOT}" --entrypoint bash "${IMAGE}" "${ORCH_EXTRA[@]}"
fi

exec docker run --rm "${TTY_FLAGS[@]}" --network host \
  "${USER_FLAGS[@]}" "${MOUNTS[@]}" "${DOCKER_ENV[@]}" \
  -w "${REPO_ROOT}" "${IMAGE}" \
  -scenario "${SCENARIO_DIR}/scenario.yaml" -root "${SCENARIO_DIR}" \
  "${ORCH_ARGS[@]}" "${ORCH_EXTRA[@]}"
