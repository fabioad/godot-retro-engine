#!/usr/bin/env bash
# Headless SGDK validation: import the official image sample, build a real
# Mega Drive ROM through the IDE backend, probe it and check emulator support.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
SGDK_ROOT="${SGDK_ROOT:-/run/media/fabio/Dados/Fabio/sgdk211}"
OUT="$ROOT/validation/projects/sgdk_image"
WS="$ROOT/validation/workspace"
mkdir -p "$(dirname "$OUT")" "$WS"

if [ ! -x "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" ]; then
  echo "Run scripts/setup_sgdk_linux.sh first (or provide a native m68k-elf toolchain)." >&2
  exit 1
fi
source "$ROOT/vendor/sgdk-linux/env.sh"

if [ ! -d "$OUT" ]; then
  cp -a "$SGDK_ROOT/sample/basics/image" "$OUT"
  cat > "$OUT/Makefile" <<MAKEFILE
GDK = $SGDK_ROOT
include \$(GDK)/makefile.gen
MAKEFILE
fi

"$BIN" --headless --path "$ROOT/ide" --script res://tests/validate.gd -- \
  --workspace "$WS" --project "$OUT" --copy 0 --build 1 2>&1 | tee "$ROOT/validation/validate_sgdk.log"
cp "$ROOT/ide/validation/headless_report.json" "$ROOT/validation/headless_report_sgdk.json" 2>/dev/null || true
