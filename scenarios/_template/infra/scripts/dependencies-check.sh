#!/usr/bin/env bash
# dependencies-check — verify that every tool the scenario needs is available.
#
# TEMPLATE STUB: customize it for your scenario (list the binaries, check the
# hypervisor socket, verify any pinned module tag, ...), then remove this
# notice. It FAILS until you do: a silent pass would hide missing tools.
#
# Full implementation example: scenarios/proxmox-evpn-bgp-public-ip/
#   infra/scripts/dependencies-check.sh (tool list, /dev/kvm, libvirt,
#   pinned-module tag check).
set -euo pipefail

echo "TODO: implement the dependency checks of your scenario" >&2
exit 1
