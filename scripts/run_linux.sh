#!/usr/bin/env bash
# Launch the built IDE.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
if [ ! -x "$BIN" ]; then
  echo "Build first: scripts/build_linux.sh" >&2
  exit 1
fi
# Full Mega Drive builds need the Wine-wrapped SGDK m68k-elf toolchain.
if [ -f "$ROOT/vendor/sgdk-linux/env.sh" ]; then
  . "$ROOT/vendor/sgdk-linux/env.sh"
fi
exec "$BIN" --editor --path "$ROOT/ide" "$@"
