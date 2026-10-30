#!/usr/bin/env bash
# Host-side logic test of the generated C state machine (no emulator needed).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
OUT="$ROOT/validation/state_machine_logic"
rm -rf "$OUT"
mkdir -p "$OUT/gen"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/generate_sm.gd -- \
  --platform snes --dir "$OUT/gen"
gcc -std=c99 -Wall -Wextra -I"$OUT/gen" -I"$ROOT/ide/tests/sm_logic" \
  "$ROOT/ide/tests/sm_logic/sm_logic_test.c" "$OUT/gen/retro_state_machine.c" \
  -o "$OUT/state_machine_test"
"$OUT/state_machine_test" | tee "$OUT/result.txt"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/sim_logic_test.gd 2>&1 | tee "$OUT/simulator_result.txt"
