#!/usr/bin/env bash
# Prepare SGDK 2.11 for macOS.
#
# Uses SGDK's Windows m68k-elf GCC 13.2 through Wine and builds sjasm,
# convsym and bintos natively. Requires GNU make (gmake) for SGDK's makefiles.
#
# Usage:
#   SGDK_ROOT=$HOME/sgdk211 scripts/setup_sgdk_macos.sh
#   source vendor/sgdk-macos/env.sh
#   scripts/run_linux.sh
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/setup_sgdk_unix.sh" macos "$@"
