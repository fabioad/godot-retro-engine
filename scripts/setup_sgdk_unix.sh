#!/usr/bin/env bash
# Shared SGDK setup used by setup_sgdk_linux.sh and setup_sgdk_macos.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RETRO_SGDK_OUT="${RETRO_SGDK_OUT:-$ROOT/vendor/sgdk-unix}"
exec "$ROOT/ide/addons/retro_engine/setup/setup_sgdk_unix.sh" "$@"
