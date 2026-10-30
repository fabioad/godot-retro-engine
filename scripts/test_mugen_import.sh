#!/usr/bin/env bash
# Stage 8: real MUGEN CNS/AIR state parsing, assisted mapping, automatic
# fight-graph generation, generated collision move profiles, and both native
# SDK compilers.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
OUT="$ROOT/validation/mugen_import"
rm -rf "$OUT"
mkdir -p "$OUT"

"$BIN" --headless --path "$ROOT/ide" --script res://tests/mugen_test.gd -- --dir "$OUT" \
  | tee "$OUT/result.txt"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/mugen_ui_test.gd \
  | tee "$OUT/ui.txt"

PVS="${PVSNESLIB_HOME:-/run/media/fabio/Dados/Fabio/pvsneslib-sdk-4.6}"
"$PVS/devkitsnes/bin/816-tcc" -c "$OUT/retro_state_machine.c" \
  -o "$OUT/retro_state_machine.obj" -I"$OUT"
"$PVS/devkitsnes/bin/816-tcc" -c "$OUT/retro_collision.c" \
  -o "$OUT/retro_collision.obj" -I"$OUT"

if [ -x "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" ]; then
  source "$ROOT/vendor/sgdk-linux/env.sh"
  GDK="${GDK:-/run/media/fabio/Dados/Fabio/sgdk211}" \
    "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" -m68000 -B"$GDK/bin" -nostdlib \
    -c "$OUT/md/retro_state_machine.c" -o "$OUT/md/retro_state_machine.o"
  GDK="${GDK:-/run/media/fabio/Dados/Fabio/sgdk211}" \
    "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" -m68000 -B"$GDK/bin" -nostdlib \
    -c "$OUT/md/retro_collision.c" -o "$OUT/md/retro_collision.o"
fi

echo "==> MUGEN import, fight graph and both SDK compilers PASS"
