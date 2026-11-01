# Sonic 2 → SNES port (experimental full-level slice)

This is the first runnable slice of the Sonic 2 engine reimplemented for the
SNES. It is **not** a binary translation of the 68000 code and it is not yet a
complete game; it is the playable core that proves the data path and the
runtime on real SNES/PVSnesLib.

## What is implemented

`tools/sonic2_snes_port.py` reads a Sonic 2 disassembly and generates a
PVSnesLib C project with:

```text
level/layout/EHZ_1.kos        -> full EHZ Act 1 (10,656 x 1,024 px)
mappings/128x128/EHZ_HTZ.kos  -> full chunk table (256 chunks) for render + collision
mappings/16x16/EHZ.kos        -> 16x16 block table
art/kosinski/EHZ_HTZ.kos      -> 634 used BG tiles, remapped, SNES 4bpp
BG pages                       -> 42 x 4 pages of 32x32 tiles, streamed into a 64x64 window
art/palettes/EHZ.bin          -> palette lines 1-3 + backdrop line 0
collision/EHZ and HTZ ...     -> primary/secondary collision indexes (768 B each)
collision/Collision array ... -> vertical/horizontal heightmaps (4096 B each)
collision/Curve ...           -> angle map (256 B)
misc/sinewave.bin             -> 256-entry sin/cos table
.retro/generated/sprites/common_sonic.png
                              -> 16 frames (idle/walk/run/roll),
                                 82 deduplicated 16x16 pieces
.retro/generated/sprites/common_ring.png
                              -> 4 ring animation frames, 16x16 OBJ pieces
level/rings/EHZ_1.bin         -> 226 ring positions expanded from the row/col list
```

The runtime is C on the SNES side:

- camera over the full level with 42x4 page streaming into a 64x64 SNES BG;
- Sonic ground acceleration/deceleration/top speed;
- terrain Y snap with the original heightmap/step logic (slope speed is still
  applied as horizontal inertia; slope rotation is the next physics item);
- jump with slope-direction velocity and jump-height cut;
- gravity, air control and air drag;
- original heightmap collision for floors/ceilings during airborne movement
  (`FindFloor`/`FindFloor2` port);
- `FindWall`/`FindWall2` wall collision enabled on the start terrain;
- original 16x16-block collision index and heightmap data;
- sprite frames packed as SNES OBJ tiles with the correct 16x16 layout
  (`n`, `n+1`, `n+16`, `n+17`);
- animations selected from speed/air state (idle/walk/run/roll);
- all 226 Act 1 rings: original art/animation, collection overlap, score +10,
  RINGS counter;
- SCORE/TIME/RINGS HUD drawn as 8x8 OBJ glyphs from a compact 5x7 font
  (layout faithful; the original HUD art/font is still pending).

## Build and run

```bash
python3 tools/sonic2_snes_port.py \
  /path/to/s2disasm /tmp/sonic_port [--demo]

cd /tmp/sonic_port
PVSNESLIB_HOME=/path/to/pvsneslib make -j4
# -> sonic_port.sfc
```

`--demo` forces right and a jump for automated screenshots. Without it the ROM
reads the real controller with `padsCurrent(0)`.

## Verified result

```text
ROM:      524,288 bytes (512 KiB), LoROM FastROM, checksum OK
build:    exit 0; Game Build integration builds the same ROM
preview:  start at frame 90; walk/jump at 90/135; pit/fall at 240/480;
          fall reset back to start at 700; ring collected: SCORE 000010,
          RINGS 001
```

![Full-level start](screenshots/sonic2_snes_port_full_start.png)
![Pit](screenshots/sonic2_snes_port_full_pit.png)
![Fall reset](screenshots/sonic2_snes_port_full_reset.png)
![HUD](screenshots/sonic2_snes_port_hud.png)
![Ring collected](screenshots/sonic2_snes_port_ring_collect.png)

The level, palette, sprite, camera and collision are the original Emerald Hill
Act 1 data; the colours are widened from Mega Drive 9-bit to SNES 15-bit. The
BG page window is updated when the camera crosses a 256-pixel page boundary.

## What is still missing (next phases)

1. **Slope velocity/loops.** Terrain Y snap is active, but horizontal speed is
   still plain inertia; `AnglePos` velocity rotation and `Sonic_SlopeResist`
   acceleration need the signed 16x16 path validated for every angle.
2. **Objects, badniks, springs, monitors, starposts and the goal.** The object
   lists and their behavior are not imported yet (rings are).
3. **HUD art/lives/title card.** The layout is faithful, but the font is a
   compact 5x7 OBJ font; lives and the title/act card are missing.
4. **Death animation/lives.** Falling into a pit currently respawns immediately
   at the start; there is no hurt/death state yet.
5. **Audio.** The SMPS music, ring sound and DAC driver are not translated; the
   current ROM is silent.
6. **Tails, spin dash, special stages, water, two-player mode, openings and
   ending.**

## Notes for the next implementation

- `816-tcc` has 2-byte `long`; use pixel + 8-bit subpixel accumulators (or
  `long long`, 4 bytes) instead of 16.16 `long`.
- `oamSet` ids are **byte offsets** (`sprite * 4`), not sprite indices.
- A 16x16 SNES OBJ uses tiles `n, n+1, n+16, n+17`; packing them as `n..n+3`
  produces a fragmented sprite.
- The 816-tcc signed `*` path froze on negative slope values; `mul88()` uses
  shifts/adds for the jump and slope math. The ground snap itself is inlined
  (no separate `AnglePos` call) to avoid the same ABI/stack symptom.
- BG page groups are 16 KiB assembly sections (8 pages each); 168 pages fit
  in 21 groups and 512 KiB with ~77 KiB free.
- The preview's injected controller events were not reliable in headless mode;
  the `--demo` build uses assignment (`pad = padsCurrent(0) | KEY_RIGHT`)
  because `pad |= KEY_RIGHT` did not reach the physics in that build.
