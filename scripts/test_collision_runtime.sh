#!/usr/bin/env bash
# Host hitstop/invulnerability logic + both SDK compilers for the generated
# collision runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
OUT="$ROOT/validation/collision_runtime"
rm -rf "$OUT"; mkdir -p "$OUT"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/collision_runtime_test.gd -- --dir "$OUT" | tee "$OUT/result.txt"
gcc -std=c99 -Wall -Wextra -I"$OUT" \
  "$ROOT/ide/tests/collision_logic/collision_logic_test.c" "$OUT/retro_collision.c" \
  -o "$OUT/host_test"
"$OUT/host_test" | tee "$OUT/logic.txt"
PVS="${PVSNESLIB_HOME:-/run/media/fabio/Dados/Fabio/pvsneslib-sdk-4.6}"
"$PVS/devkitsnes/bin/816-tcc" -c "$OUT/retro_collision.c" -o "$OUT/retro_collision.obj" -I"$OUT"
if [ -x "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" ]; then
  source "$ROOT/vendor/sgdk-linux/env.sh"
  GDK="${GDK:-/run/media/fabio/Dados/Fabio/sgdk211}" \
    "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" -m68000 -B"$GDK/bin" -nostdlib \
    -c "$OUT/retro_collision.c" -o "$OUT/retro_collision_md.o"
fi
echo "==> collision runtime logic and compilers PASS"
