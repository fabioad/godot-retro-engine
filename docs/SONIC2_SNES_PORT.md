# Sonic 2 → SNES port (experimental full-level slice)

This is the first runnable slice of the Sonic 2 engine reimplemented for the
SNES. It is **not** a binary translation of the 68000 code and it is not yet a
complete game; it is the playable core that proves the data path and the
runtime on real SNES/PVSnesLib.

## What is implemented

`tools/sonic2_snes_port.py` reads a Sonic 2 disassembly and generates a
PVSnesLib C project with:

```text
level/layout/EHZ_1.kos        -> full EHZ Act 1 (11,008 x 1,024 px, includes the goal signpost)
mappings/128x128/EHZ_HTZ.kos  -> full chunk table (256 chunks) for render + collision
mappings/16x16/EHZ.kos        -> 16x16 block table
art/kosinski/EHZ_HTZ.kos      -> 634 used BG tiles, remapped, SNES 4bpp
BG pages                       -> 43 x 4 pages of 32x32 tiles, streamed into a 64x64 window
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
level/objects/EHZ_1.bin       -> springs, monitors, star posts and the goal signpost
art/nemesis/*.nem + mappings  -> original object art (Nemesis) and sprite mappings
```

The runtime is C on the SNES side:

- camera over the full level with 43x4 page streaming into a 64x64 SNES BG;
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
  (layout faithful; the original HUD art/font is still pending);
- original object layer on BG2 (16-colour object palette, priority above the
  level background) with the original Nemesis art and sprite mappings;
- springs: vertical/horizontal/diagonal launch with the original yellow/red
  strengths and bounce animation;
- monitors: solid top, spin-jump break, ring/shoes/shield/invincibility/1-up
  contents, broken monitor frame (the 1-up icon still needs its extra art);
- star posts: activation by proximity, checkpoint stored for pit respawns and
  the star ball removed when active;
- goal signpost: idle Eggman face, proximity trigger, spin to the Sonic face
  and HUD timer stop at the end of the act.

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
          fall reset to the checkpoint at 700; ring collected: SCORE 000010,
          RINGS 001; monitor break, spring launch, star post activation and
          goal signpost spin verified from controlled start positions
```

![Full-level start](screenshots/sonic2_snes_port_full_start.png)
![Pit](screenshots/sonic2_snes_port_full_pit.png)
![Fall reset](screenshots/sonic2_snes_port_full_reset.png)
![HUD](screenshots/sonic2_snes_port_hud.png)
![Ring collected](screenshots/sonic2_snes_port_ring_collect.png)
![Objects: monitor](screenshots/sonic2_snes_port_monitor.png)
![Monitor break](screenshots/sonic2_snes_port_monitor_break.png)
![Spring launch](screenshots/sonic2_snes_port_spring.png)
![Star post checkpoint](screenshots/sonic2_snes_port_starpost.png)
![Goal signpost](screenshots/sonic2_snes_port_signpost.png)

The level, palette, sprite, camera and collision are the original Emerald Hill
Act 1 data; the colours are widened from Mega Drive 9-bit to SNES 15-bit. The
BG page window is updated when the camera crosses a 256-pixel page boundary.

## What is still missing (next phases)

1. **Slope velocity/loops.** Terrain Y snap is active, but horizontal speed is
   still plain inertia; `AnglePos` velocity rotation and `Sonic_SlopeResist`
   acceleration need the signed 16x16 path validated for every angle.
2. **Remaining objects.** Badniks (Buzzer, Masher, Coconuts), spikes, bridges,
   moving platforms, waterfalls and scenery still need their own importers and
   behaviors; object respawn state (broken monitors, used star posts) is not
   persisted across deaths yet.
3. **HUD art/lives/title card.** The layout is faithful, but the font is a
   compact 5x7 OBJ font; lives and the title/act card are missing.
4. **Hurt/death/lives.** Spikes, badniks and the Robotnik monitor have no damage
   path yet. Pit falls respawn at the last star post, but there is no hurt or
   death animation and no ring loss.
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
- BG page groups are 16 KiB assembly sections (8 pages each); 172 pages fit
  in 22 groups and 512 KiB with ~50 KiB free.
- The object layer uses BG2 with a 32x32 screen-space map at VRAM 0x3800 and
  512 tiles of CHR at 0x4000; OBJ tiles moved to 0x6000. The map is copied to
  VRAM after `WaitForVBlank()` (RAM-to-VRAM DMA during active display is lost).
- The goal signpost is at x=10,816, so the level must stay at least 1,360 tiles
  wide; the port uses 1,376 tiles (43 pages).
- The preview's injected controller events were not reliable in headless mode;
  the `--demo` build uses assignment (`pad = padsCurrent(0) | KEY_RIGHT`)
  because `pad |= KEY_RIGHT` did not reach the physics in that build.
