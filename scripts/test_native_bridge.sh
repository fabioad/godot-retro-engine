#!/usr/bin/env bash
# Godot-native scene/resource bridge: Sprite2D/AnimatedSprite2D -> RetroSprite/
# RetroAnimation, rendered scene -> SNES/MD tilemap, scene actor C table, and
# compilation with both SDK toolchains.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
OUT="$ROOT/validation/native_bridge"
rm -rf "$OUT"
mkdir -p "$OUT"

"$BIN" --headless --path "$ROOT/ide" --script res://tests/native_bridge_test.gd -- --dir "$OUT" \
  | tee "$OUT/result.txt"

NATIVE_DIR="$(grep '^NATIVE_DIR ' "$OUT/result.txt" | tail -1 | cut -d' ' -f2-)"
if [ -z "$NATIVE_DIR" ] || [ ! -d "$NATIVE_DIR" ]; then
  echo "native output directory not reported" >&2
  exit 1
fi

cat > "$NATIVE_DIR/test_scene.c" <<'C'
#include "hero_scene_scene.h"
#include "hero_scene_3d_profile.h"
int main(void) { return retro_native_actors[0].type + retro_3d_actors[0].type; }
C
PVS="${PVSNESLIB_HOME:-/run/media/fabio/Dados/Fabio/pvsneslib-sdk-4.6}"
"$PVS/devkitsnes/bin/816-tcc" -c "$NATIVE_DIR/test_scene.c" -o "$NATIVE_DIR/test_scene_snes.obj" -I"$NATIVE_DIR"

# UI/other-node/script port bundle header must also compile for the SNES.
cat > "$NATIVE_DIR/test_port.c" <<'C'
#include "hero_scene_port.h"
int main(void) {
  return retro_port_widgets[0].visible + retro_port_nodes[0].visible
      + retro_port_scripts[0].methods[0] + retro_port_actors[0].type;
}
C
"$PVS/devkitsnes/bin/816-tcc" -c "$NATIVE_DIR/test_port.c" -o "$NATIVE_DIR/test_port_snes.obj" -I"$NATIVE_DIR"
test -f "$NATIVE_DIR/scripts/native_bridge_test_script.gd"

cat > "$NATIVE_DIR/test_stage.asm" <<'ASM'
.MEMORYMAP
DEFAULTSLOT 0
SLOTSIZE $8000
SLOT 0 $8000
.ENDME
.ROMBANKSIZE $8000
.ROMBANKS 1
.INCLUDE "native_bg_stage.inc"
ASM
( cd "$NATIVE_DIR" && "$PVS/devkitsnes/bin/wla-65816" -o native_bg_stage.o test_stage.asm )
cat > "$NATIVE_DIR/test_tilemap.asm" <<'ASM'
.MEMORYMAP
DEFAULTSLOT 0
SLOTSIZE $8000
SLOT 0 $8000
.ENDME
.ROMBANKSIZE $8000
.ROMBANKS 1
.INCLUDE "ground_stage_stage.inc"
ASM
( cd "$NATIVE_DIR" && "$PVS/devkitsnes/bin/wla-65816" -o ground_stage.o test_tilemap.asm )

if [ -x "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" ]; then
  source "$ROOT/vendor/sgdk-linux/env.sh"
  cat > "$NATIVE_DIR/test_anim.c" <<'C'
#include "heroanim_anim.h"
int main(void) { return HEROANIM_IDLE_FRAMES[0].duration; }
C
  GDK="${GDK:-/run/media/fabio/Dados/Fabio/sgdk211}" \
    "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" -m68000 -B"$GDK/bin" -nostdlib \
    -I"$GDK/inc" -I"$NATIVE_DIR" -c "$NATIVE_DIR/test_anim.c" -o "$NATIVE_DIR/test_anim_md.o"
  cat > "$NATIVE_DIR/test_svp.c" <<'C'
#include "svp_profile.h"
int main(void) { return retro_3d_actors[0].type; }
C
  GDK="${GDK:-/run/media/fabio/Dados/Fabio/sgdk211}" \
    "$ROOT/vendor/sgdk-linux/bin/m68k-elf-gcc" -m68000 -B"$GDK/bin" -nostdlib \
    -I"$NATIVE_DIR" -c "$NATIVE_DIR/test_svp.c" -o "$NATIVE_DIR/test_svp_md.o"
fi

echo "==> native scene bridge and both SDK compilers PASS"
