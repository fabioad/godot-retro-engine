#!/usr/bin/env bash
# Process-level emulator execution smoke test. Requires GUI/X11 (DISPLAY).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
if [ -z "${DISPLAY:-}" ]; then
  echo "SKIP: no DISPLAY (GUI emulator launch requires a display)."
  exit 0
fi
ROMS=()
for f in \
  "$ROOT/validation/projects/daniel_snes/build/daniel.sfc" \
  "$ROOT/validation/projects/sidearms/port/sidearms.sfc" \
  "$ROOT/validation/projects/kof98/kof98-snes.sfc" \
  "$ROOT/validation/projects/sgdk_image/out/rom.bin" \
  "$ROOT/validation/projects/retro_sm_snes/retro_sm_snes.sfc" \
  "$ROOT/validation/projects/retro_sm_md/out/rom.bin" \
  "$ROOT/validation/projects/retro_graph_snes/retro_sm_snes.sfc" \
  "$ROOT/validation/projects/retro_graph_md/out/rom.bin"; do
  [ -f "$f" ] && ROMS+=(--rom "$f")
done
if [ ${#ROMS[@]} -eq 0 ]; then
  echo "No built ROMs found; run scripts/validate.sh and build the state-machine projects first." >&2
  exit 1
fi
"$BIN" --headless --path "$ROOT/ide" --script res://tests/emulator_smoke.gd -- "${ROMS[@]}" 2>&1 | tee "$ROOT/validation/emulator_smoke.log"
