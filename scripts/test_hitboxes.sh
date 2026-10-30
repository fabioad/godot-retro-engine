#!/usr/bin/env bash
# Generate hit/hurtbox tables, verify collision math, and compile the tables
# with both SDK toolchains.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
OUT="$ROOT/validation/hitboxes"
rm -rf "$OUT"; mkdir -p "$OUT"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/hitbox_test.gd -- --dir "$OUT" | tee "$OUT/result.txt"

cat > "$OUT/test_hit.asm" <<'ASM'
.MEMORYMAP
DEFAULTSLOT 0
SLOTSIZE $8000
SLOT 0 $8000
.ENDME
.ROMBANKSIZE $8000
.ROMBANKS 1
.INCLUDE "hit.inc"
ASM
PVS="${PVSNESLIB_HOME:-/run/media/fabio/Dados/Fabio/pvsneslib-sdk-4.6}"
( cd "$OUT" && "$PVS/devkitsnes/bin/wla-65816" -o test_hit.o test_hit.asm )

if [ -x "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" ]; then
  cat > "$OUT/test_hit.c" <<'C'
#include <genesis.h>
#include "hit.h"
int main(bool hard) { return retro_hitboxes[0].type; }
C
  source "$ROOT/vendor/sgdk-linux/env.sh"
  GDK="${GDK:-/run/media/fabio/Dados/Fabio/sgdk211}" \
    "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" -m68000 -B"$GDK/bin" -nostdlib \
    -I"$GDK/inc" -I"$GDK/res" -I"$OUT" -c "$OUT/test_hit.c" -o "$OUT/test_hit.o"
fi
echo "==> hitbox tables compiled"
