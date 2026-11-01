# Sonic 2 → SNES port (experimental vertical slice)

This is the first runnable slice of the Sonic 2 engine reimplemented for the
SNES. It is **not** a binary translation of the 68000 code and it is not yet a
complete game; it is the playable core that proves the data path and the
runtime on real SNES/PVSnesLib.

## What is implemented

`tools/sonic2_snes_port.py` reads a Sonic 2 disassembly and generates a
PVSnesLib C project with:

```text
level/layout/EHZ_1.kos        -> 64x64-tile playable slice at world (0, 512)
mappings/128x128/EHZ_HTZ.kos  -> chunk table used by both rendering and collision
mappings/16x16/EHZ.kos        -> 16x16 block table
art/kosinski/EHZ_HTZ.kos      -> 136 used BG tiles, remapped, SNES 4bpp
art/palettes/EHZ.bin          -> palette lines 1-3 + backdrop line 0
collision/EHZ and HTZ ...     -> primary/secondary collision indexes (768 B each)
collision/Collision array ... -> vertical/horizontal heightmaps (4096 B each)
collision/Curve ...           -> angle map (256 B)
misc/sinewave.bin             -> 256-entry sin/cos table
.retro/generated/sprites/common_sonic.png
                              -> 22 frames (idle/walk/run/roll/skid/duck),
                                 117 deduplicated 16x16 pieces
```

The runtime is C on the SNES side:

- camera with horizontal/vertical clamps (`512x512` slice);
- Sonic ground acceleration/deceleration/top speed;
- jump with slope-direction velocity and jump-height cut;
- gravity, air control and air drag;
- original heightmap collision for floors/ceilings during airborne movement
  (`FindFloor`/`FindFloor2` port);
- original 16x16-block collision index and heightmap data;
- sprite frames packed as SNES OBJ tiles with the correct 16x16 layout
  (`n`, `n+1`, `n+16`, `n+17`);
- animations selected from speed/air state (idle/walk/run/roll).

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
ROM:      524,288 bytes (512 KiB), LoROM FastROM
build:    exit 0
preview:  walk at frame 90, jump at 135, landing at 260
```

![Walk](screenshots/sonic2_snes_port_walk.png)
![Jump](screenshots/sonic2_snes_port_jump.png)
![Land](screenshots/sonic2_snes_port_land.png)

The level, palette, sprite and camera are the original Emerald Hill Act 1 data;
the colours are widened from Mega Drive 9-bit to SNES 15-bit.

## What is still missing (next phases)

1. **Ground heightmap snap / slopes.** The first slice keeps a fixed standing
   Y and uses the heightmap only while airborne. The full `AnglePos`/slope
   rotation logic needs the 16-bit C stack/ABI issue solved and must be
   re-enabled. Walking up/down slopes and loops are not faithful yet.
2. **Walls.** `FindWall`/`FindWall2` are ported but disabled in this slice while
   the collision signs are validated.
3. **Full level streaming.** The slice is 64x64 tiles (512x512 px). The full
   EHZ Act 1 is 128x32 chunks (2048x4096 px); a 64x64/64x32 BG window must be
   streamed as the camera moves.
4. **Rings, objects, badniks, springs, monitors, starposts and the goal.**
   Ring/object lists and their behavior are not imported yet.
5. **HUD** (score/time/rings/lives) and the title/act card.
6. **Audio.** The SMPS music and DAC driver are not translated; the current
   ROM is silent.
7. **Tails, spin dash, special stages, water, two-player mode.**

## Notes for the next implementation

- `816-tcc` has 2-byte `long`; use pixel + 8-bit subpixel accumulators (or
  `long long`, 4 bytes) instead of 16.16 `long`.
- `oamSet` ids are **byte offsets** (`sprite * 4`), not sprite indices.
- A 16x16 SNES OBJ uses tiles `n, n+1, n+16, n+17`; packing them as `n..n+3`
  produces a fragmented sprite.
- Calling the separate `angle_pos()` from `ground_move()` froze in testing;
  inlining the snap or using the flat-ground slice avoided it. This is the main
  ABI/stack item to solve before restoring full slope collision.
- The preview's injected controller events were not reliable in headless mode;
  the `--demo` build uses assignment (`pad = padsCurrent(0) | KEY_RIGHT`)
  because `pad |= KEY_RIGHT` did not reach the physics in that build.
