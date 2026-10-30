#!/usr/bin/env bash
# Prepare SGDK 2.11 for linux.
# The implementation is bundled with the addon so the SDK Downloader can run it too.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RETRO_SGDK_OUT="${RETRO_SGDK_OUT:-$ROOT/vendor/sgdk-linux}"
export RETRO_SGDK_TEST="${RETRO_SGDK_TEST:-$RETRO_SGDK_OUT/test}"
exec "$ROOT/ide/addons/retro_engine/setup/setup_sgdk_linux.sh" "$@"
