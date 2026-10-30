#!/usr/bin/env bash
# Generate the visual state graph, compile its C runtime for both real SDKs,
# and execute the graph logic on the host.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
OUT="$ROOT/validation/state_graph_logic"
rm -rf "$OUT"; mkdir -p "$OUT/snes" "$OUT/md"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/generate_graph.gd -- \
  --platform snes --dir "$OUT/snes" | tee "$OUT/generate_snes.txt"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/generate_graph.gd -- \
  --platform megadrive --dir "$OUT/md" | tee "$OUT/generate_md.txt"

# Host logic test (the generated header is SDK-neutral).
gcc -std=c99 -Wall -Wextra -I"$OUT/snes" \
  "$ROOT/ide/tests/graph_logic/graph_logic_test.c" "$OUT/snes/retro_state_machine.c" \
  -o "$OUT/graph_logic_test"
"$OUT/graph_logic_test" | tee "$OUT/result.txt"

# Real SDK compilation.
PVS="${PVSNESLIB_HOME:-/run/media/fabio/Dados/Fabio/pvsneslib-sdk-4.6}"
"$PVS/devkitsnes/bin/816-tcc" -c "$OUT/snes/retro_state_machine.c" \
  -o "$OUT/snes/retro_state_machine.obj" -I"$OUT/snes"
if [ -x "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" ]; then
  source "$ROOT/vendor/sgdk-linux/env.sh"
  GDK="${GDK:-/run/media/fabio/Dados/Fabio/sgdk211}" \
    "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" -m68000 -B"$GDK/bin" -nostdlib \
    -c "$OUT/md/retro_state_machine.c" -o "$OUT/md/retro_state_machine.o"
fi
echo "==> graph runtime compiled and logic-tested"
