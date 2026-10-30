#!/usr/bin/env bash
# Import a real MIDI file, convert it to SNES IT/SNESMOD and Mega Drive
# VGM/PSG, build both ROMs, render device previews and record emulator audio.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
OUT="$ROOT/validation/audio"
PVS="${PVSNESLIB_HOME:-/run/media/fabio/Dados/Fabio/pvsneslib-sdk-4.6}"
SGDK="${GDK:-/run/media/fabio/Dados/Fabio/sgdk211}"
URL="https://files.khinsider.com/midifiles/nes/super-mario-bros.-3/world-map-1-grass-land.mid"
MIDI="$OUT/world-map-1-grass-land.mid"
mkdir -p "$OUT"
if [ ! -s "$MIDI" ]; then
  curl -L --max-time 90 -o "$MIDI" "$URL"
fi
test -s "$MIDI"
export PVSNESLIB_HOME="$PVS"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/audio_editor_test.gd | tee "$OUT/editor.txt"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/audio_build_test.gd -- \
  --dir "$OUT/build" --midi "$MIDI" | tee "$OUT/generate.txt"

PVSNESLIB_HOME="$PVS" make -C "$OUT/build/audio_snes" -j4 > "$OUT/audio_snes.build.log" 2>&1
test -f "$OUT/build/audio_snes/audio_snes.sfc"
source "$ROOT/vendor/sgdk-linux/env.sh"
GDK="$SGDK" make -C "$OUT/build/audio_md" -j1 LIBGCC="$SGDK/lib/libgcc.a" > "$OUT/audio_md.build.log" 2>&1
test -f "$OUT/build/audio_md/out/rom.bin"

mkdir -p "$OUT/preview" "$OUT/roms" "$ROOT/validation/game_build/roms_para_testar"
cp "$OUT/build/audio_snes/audio/worldmap_preview.wav" "$OUT/preview/snes_worldmap.wav"
cp "$OUT/build/audio_md/res/worldmap_preview.wav" "$OUT/preview/megadrive_worldmap.wav"
cp "$OUT/build/audio_snes/audio/jump.wav" "$OUT/preview/snes_jump.wav"
cp "$OUT/build/audio_md/res/jump.wav" "$OUT/preview/megadrive_jump.wav"
cp "$OUT/build/audio_snes/audio_snes.sfc" "$OUT/roms/audio_snes_mid.sfc"
cp "$OUT/build/audio_md/out/rom.bin" "$OUT/roms/audio_megadrive_mid.bin"
cp "$OUT/build/audio_snes/audio_snes.sfc" "$ROOT/validation/game_build/roms_para_testar/07_snes_music_mid.sfc"
cp "$OUT/build/audio_md/out/rom.bin" "$ROOT/validation/game_build/roms_para_testar/08_megadrive_music_mid.bin"

python3 - "$OUT" <<'PYAUDIO'
import sys, wave, struct, math, pathlib
out = pathlib.Path(sys.argv[1])
for name in ["snes_worldmap.wav", "megadrive_worldmap.wav", "snes_jump.wav", "megadrive_jump.wav"]:
    p = out / "preview" / name
    assert p.exists() and p.stat().st_size > 100, f"missing preview {p}"
    w = wave.open(str(p), "rb")
    raw = w.readframes(w.getnframes())
    vals = struct.unpack("<" + "h" * (len(raw) // 2), raw)
    rms = math.sqrt(sum(v * v for v in vals) / max(1, len(vals)))
    peak = max((abs(v) for v in vals), default=0)
    assert rms > 50 and peak > 200, f"preview is silent: {name} rms={rms} peak={peak}"
    print(f"AUDIO_PREVIEW PASS {name} rms={rms:.1f} peak={peak}")
PYAUDIO

# Verify the previously documented limitations are actually fixed: full GM
# render, real YM2612 FM traffic, and no 8-second PCM cut.
python3 - "$OUT" "$ROOT" <<'PYLONG'
import sys, pathlib, struct, wave, subprocess
out = pathlib.Path(sys.argv[1]); root = pathlib.Path(sys.argv[2])
gm = out / "build/audio_snes/audio/worldmap_gm.wav"
w = wave.open(str(gm), "rb"); gm_dur = w.getnframes() / w.getframerate()
assert gm_dur > 8.0, f"GM render was cut: {gm_dur}"
print(f"AUDIO_GM PASS duration={gm_dur:.2f}s source=FluidR3_GM")

vgm = out / "build/audio_md/res/worldmap.vgm"
data = vgm.read_bytes()
pos = 0x34 + struct.unpack_from("<I", data, 0x34)[0]
ym_writes = 0
while pos < len(data):
    cmd = data[pos]; pos += 1
    if cmd in (0x52, 0x53):
        ym_writes += 1; pos += 2
    elif cmd == 0x50:
        pos += 1
    elif cmd == 0x61:
        pos += 2
    elif cmd in (0x62, 0x63):
        pass
    elif cmd == 0x66:
        break
    else:
        break
assert ym_writes > 100, f"no YM2612 FM traffic: {ym_writes}"
print(f"AUDIO_YM2612 PASS writes={ym_writes}")

tmp = out / "preview/full_pcm"
subprocess.run([sys.executable, str(root / "ide/addons/retro_engine/tools/retro_audio_tool.py"),
    "convert", "--input", str(gm), "--out-dir", str(tmp), "--name", "full",
    "--kind", "bgm", "--target", "megadrive"], check=True,
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
pw = wave.open(str(tmp / "full.wav"), "rb"); pcm_dur = pw.getnframes() / pw.getframerate()
assert pcm_dur > 8.0, f"PCM BGM was cut: {pcm_dur}"
print(f"AUDIO_LONG_PCM PASS duration={pcm_dur:.2f}s")
PYLONG

SNES_CORE="$HOME/.config/retroarch/cores/snes9x_libretro.so"
MD_CORE="$HOME/.var/app/org.libretro.RetroArch/config/retroarch/cores/genesis_plus_gx_libretro.so"
if [ -n "${DISPLAY:-}" ] && command -v retroarch >/dev/null 2>&1 \
    && [ -f "$SNES_CORE" ] && [ -f "$MD_CORE" ]; then
  rm -f "$OUT/snes.mkv" "$OUT/md.mkv" "$OUT/snes_record.wav" "$OUT/md_record.wav"
  timeout 45 retroarch -L "$SNES_CORE" -r "$OUT/snes.mkv" --max-frames 360 \
    "$OUT/build/audio_snes/audio_snes.sfc" > "$OUT/record_snes.log" 2>&1
  timeout 45 retroarch -L "$MD_CORE" -r "$OUT/md.mkv" --max-frames 360 \
    "$OUT/build/audio_md/out/rom.bin" > "$OUT/record_md.log" 2>&1
  ffmpeg -y -loglevel error -i "$OUT/snes.mkv" -map 0:a -ac 1 -ar 44100 "$OUT/snes_record.wav"
  ffmpeg -y -loglevel error -i "$OUT/md.mkv" -map 0:a -ac 1 -ar 44100 "$OUT/md_record.wav"
  python3 - "$OUT" <<'PYREC'
import sys, wave, struct, math, pathlib
out = pathlib.Path(sys.argv[1])
for name in ["snes_record.wav", "md_record.wav"]:
    w = wave.open(str(out / name), "rb")
    raw = w.readframes(w.getnframes())
    vals = struct.unpack("<" + "h" * (len(raw) // 2), raw)
    rms = math.sqrt(sum(v * v for v in vals) / max(1, len(vals)))
    peak = max((abs(v) for v in vals), default=0)
    assert rms > 100 and peak > 500, f"emulator audio is silent: {name} rms={rms} peak={peak}"
    print(f"AUDIO_EMULATOR PASS {name} rms={rms:.1f} peak={peak}")
PYREC
else
  echo "AUDIO_EMULATOR SKIP (RetroArch/cores/display unavailable)"
fi

printf 'AUDIO_BUILD ROMS snes=%s md=%s midi=%s\n' \
  "$(stat -c%s "$OUT/roms/audio_snes_mid.sfc")" \
  "$(stat -c%s "$OUT/roms/audio_megadrive_mid.bin")" \
  "$(stat -c%s "$MIDI")" | tee "$OUT/roms.txt"
echo "==> MIDI to SNES and Mega Drive audio PASS"
