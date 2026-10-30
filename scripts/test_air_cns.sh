#!/usr/bin/env bash
# Real KOF AIR/CNS import, AIR round-trip, hitbox tables and collision runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
OUT="$ROOT/validation/air_cns"
rm -rf "$OUT"; mkdir -p "$OUT"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/air_test.gd -- --dir "$OUT" | tee "$OUT/result.txt"

cat > "$OUT/test_hit.asm" <<'ASM'
.MEMORYMAP
DEFAULTSLOT 0
SLOTSIZE $8000
SLOT 0 $8000
.ENDME
.ROMBANKSIZE $8000
.ROMBANKS 1
.INCLUDE "iori_hitboxes.inc"
ASM
PVS="${PVSNESLIB_HOME:-/run/media/fabio/Dados/Fabio/pvsneslib-sdk-4.6}"
( cd "$OUT" && "$PVS/devkitsnes/bin/wla-65816" -o iori_hitboxes.o test_hit.asm )

if [ -x "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" ]; then
  source "$ROOT/vendor/sgdk-linux/env.sh"
  GDK="${GDK:-/run/media/fabio/Dados/Fabio/sgdk211}" \
    "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" -m68000 -B"$GDK/bin" -nostdlib \
    -c "$OUT/md/retro_collision.c" -o "$OUT/md/retro_collision.o"
fi
echo "==> AIR/CNS import and collision runtime PASS"
