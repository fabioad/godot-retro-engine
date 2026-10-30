#!/usr/bin/env bash
# Generate real native/cross-platform SNES and Mega Drive games, build them,
# and verify the optional Godot logo splash changes the ROM.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
OUT="$ROOT/validation/game_build"
PVS="${PVSNESLIB_HOME:-/run/media/fabio/Dados/Fabio/pvsneslib-sdk-4.6}"
SGDK="${GDK:-/run/media/fabio/Dados/Fabio/sgdk211}"
rm -rf "$OUT"
mkdir -p "$OUT"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/game_build_test.gd -- --dir "$OUT" \
  | tee "$OUT/generate.txt"

for name in native_snes md_to_snes native_snes_nosplash; do
  PVSNESLIB_HOME="$PVS" make -C "$OUT/$name" -j4 > "$OUT/$name.build.log" 2>&1
  test -f "$OUT/$name/$name.sfc"
done
source "$ROOT/vendor/sgdk-linux/env.sh"
for name in native_md snes_to_md native_md_nosplash; do
  GDK="$SGDK" make -C "$OUT/$name" -j1 LIBGCC="$SGDK/lib/libgcc.a" > "$OUT/$name.build.log" 2>&1
  test -f "$OUT/$name/out/rom.bin"
done
splash_snes=$(sha256sum "$OUT/native_snes/native_snes.sfc" | cut -d' ' -f1)
plain_snes=$(sha256sum "$OUT/native_snes_nosplash/native_snes_nosplash.sfc" | cut -d' ' -f1)
splash_md=$(sha256sum "$OUT/native_md/out/rom.bin" | cut -d' ' -f1)
plain_md=$(sha256sum "$OUT/native_md_nosplash/out/rom.bin" | cut -d' ' -f1)
[ "$splash_snes" != "$plain_snes" ]
[ "$splash_md" != "$plain_md" ]
grep -aq "SEGA" "$OUT/native_md/out/rom.bin"
mkdir -p "$OUT/roms_para_testar"
cp "$OUT/native_snes/native_snes.sfc" "$OUT/roms_para_testar/01_snes_native_com_splash.sfc"
cp "$OUT/native_md/out/rom.bin" "$OUT/roms_para_testar/02_megadrive_native_com_splash.bin"
cp "$OUT/md_to_snes/md_to_snes.sfc" "$OUT/roms_para_testar/03_snes_convertido_do_md_com_splash.sfc"
cp "$OUT/snes_to_md/out/rom.bin" "$OUT/roms_para_testar/04_megadrive_convertido_do_snes_com_splash.bin"
cp "$OUT/native_snes_nosplash/native_snes_nosplash.sfc" "$OUT/roms_para_testar/05_snes_native_sem_splash.sfc"
cp "$OUT/native_md_nosplash/out/rom.bin" "$OUT/roms_para_testar/06_megadrive_native_sem_splash.bin"

printf 'GAME_BUILD ROMS snes=%s/%s md=%s/%s\n' \
  "$(stat -c%s "$OUT/native_snes/native_snes.sfc")" \
  "$(stat -c%s "$OUT/md_to_snes/md_to_snes.sfc")" \
  "$(stat -c%s "$OUT/native_md/out/rom.bin")" \
  "$(stat -c%s "$OUT/snes_to_md/out/rom.bin")" | tee "$OUT/roms.txt"
SNES_CORE="$HOME/.config/retroarch/cores/snes9x_libretro.so"
MD_CORE="$HOME/.var/app/org.libretro.RetroArch/config/retroarch/cores/genesis_plus_gx_libretro.so"
splash_checked=0
if [ -n "${DISPLAY:-}" ] && command -v retroarch >/dev/null 2>&1 \
    && [ -f "$SNES_CORE" ] && [ -f "$MD_CORE" ] \
    && python3 -c 'from PIL import Image' 2>/dev/null; then
  rm -f /tmp/retro_splash_snes.png /tmp/retro_splash_md.png
  timeout 40 retroarch -L "$SNES_CORE" --max-frames 70 --max-frames-ss \
    --max-frames-ss-path=/tmp/retro_splash_snes.png \
    "$OUT/native_snes/native_snes.sfc" > "$OUT/splash_snes.log" 2>&1
  timeout 40 retroarch -L "$MD_CORE" --max-frames 70 --max-frames-ss \
    --max-frames-ss-path=/tmp/retro_splash_md.png \
    "$OUT/native_md/out/rom.bin" > "$OUT/splash_md.log" 2>&1
  cp /tmp/retro_splash_snes.png "$OUT/splash_check_snes.png"
  cp /tmp/retro_splash_md.png "$OUT/splash_check_md.png"
  python3 - "$OUT/splash_check_snes.png" snes "$OUT/splash_check_md.png" md <<'PYSPLASH'
import sys
from PIL import Image

def check(path, platform):
    im = Image.open(path).convert('RGB')
    w, h = im.size
    px = im.load()
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        r, g, b = px[x, y]
        assert r + g + b <= 24, f'{platform}: corner {x},{y} is not black'
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if r + g + b > 30:
                xs.append(x); ys.append(y)
    assert xs and ys, f'{platform}: splash logo is missing'
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    expected_cx = 127.5 if platform == 'snes' else 159.5
    assert abs(cx - expected_cx) <= 12, f'{platform}: logo horizontal center {cx} is not centered'
    assert abs(cy - 112) <= 12, f'{platform}: logo vertical center {cy} is not centered'
    assert 20 <= (max(xs) - min(xs)) <= 220, f'{platform}: logo width is implausible'
    assert 20 <= (max(ys) - min(ys)) <= 220, f'{platform}: logo height is implausible'
    print(f'SPLASH_VISUAL PASS {platform} center=({cx:.1f},{cy:.1f}) bbox=({min(xs)},{min(ys)})-({max(xs)},{max(ys)})')

check(sys.argv[1], sys.argv[2])
check(sys.argv[3], sys.argv[4])
PYSPLASH
  splash_checked=1
elif command -v mesen >/dev/null 2>&1 && python3 -c 'from PIL import Image' 2>/dev/null; then
  timeout 30 mesen --testrunner "$OUT/native_snes/native_snes.sfc" "$ROOT/ide/tests/mesen_splash.lua" > "$OUT/mesen_splash.log" 2>&1
  cp /tmp/retro_splash_check.png "$OUT/splash_check_snes.png"
  python3 - "$OUT/splash_check_snes.png" <<'PYSPLASH'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
px = im.load()
for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
    r, g, b = px[x, y]
    assert r + g + b <= 24, f'corner {x},{y} is not black'
xs, ys = [], []
for y in range(h):
    for x in range(w):
        r, g, b = px[x, y]
        if r + g + b > 30:
            xs.append(x); ys.append(y)
assert xs and ys, 'splash logo is missing'
cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
assert 120 <= cx <= 136, f'logo horizontal center {cx} is not centered'
assert 100 <= cy <= 124, f'logo vertical center {cy} is not centered'
assert 20 <= (max(xs) - min(xs)) <= 220, 'logo width is implausible'
assert 20 <= (max(ys) - min(ys)) <= 220, 'logo height is implausible'
print(f'SPLASH_VISUAL PASS snes center=({cx:.1f},{cy:.1f}) bbox=({min(xs)},{min(ys)})-({max(xs)},{max(ys)})')
PYSPLASH
  splash_checked=1
fi
[ "$splash_checked" = 1 ] || echo "SPLASH_VISUAL SKIP (no RetroArch/Mesen+display)"
if [ -n "${DISPLAY:-}" ]; then
  "$BIN" --headless --path "$ROOT/ide" --script res://tests/emulator_smoke.gd -- \
    --rom "$OUT/native_snes/native_snes.sfc" \
    --rom "$OUT/md_to_snes/md_to_snes.sfc" \
    --rom "$OUT/native_md/out/rom.bin" \
    --rom "$OUT/snes_to_md/out/rom.bin" | tee "$OUT/emulator_smoke.txt"
fi
echo "==> game build options and Godot logo splash PASS"
