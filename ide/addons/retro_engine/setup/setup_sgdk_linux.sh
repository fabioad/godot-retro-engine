#!/usr/bin/env bash
# Prepare SGDK 2.11 for Linux.
#
# Uses SGDK's Windows m68k-elf GCC 13.2 through Wine and builds sjasm,
# convsym and bintos natively.
#
# Usage:
#   SGDK_ROOT=/path/to/sgdk211 scripts/setup_sgdk_linux.sh
#   source vendor/sgdk-linux/env.sh
#   scripts/run_linux.sh
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/setup_sgdk_unix.sh" linux "$@"
