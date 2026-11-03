#!/usr/bin/env bash
# Simulated failure: exits non-zero (run with -phase chaos -continue-on-error).
set -euo pipefail
echo "chaos: killing simulated postgres..."
sleep 1
echo "boom: postgres is down (expected failure for -continue-on-error demo)"
exit 42
