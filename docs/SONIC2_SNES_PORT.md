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
level/objects/EHZ_1.bin       -> 89 interactive objects:
                                 13 monitors, 14 springs, 3 star posts,
                                 1 goal signpost, 12 spike sets,
                                 11 Buzzers, 13 Mashers, 8 Coconuts,
                                 7 bridges, 7 EHZ platforms
art/nemesis/*.nem + mappings  -> original object art (Nemesis) and sprite mappings
art/nemesis + obj36/4B/5C/9D  -> spikes and badnik art/mappings
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
  contents, broken monitor frame and the original Sonic-head 1-up icon;
- star posts: activation by proximity, checkpoint stored for pit respawns and
  the star ball removed when active;
- goal signpost: idle Eggman face, proximity trigger, spin to the Sonic face
  and HUD timer stop at the end of the act;
- spikes: upright ceiling/floor spike sets, original y-flip orientation and
  hurt on contact;
- badniks: Buzz Bomber (hover/bob animation + fireball), Masher (original
  jump/gravity water cycle) and Coconuts (tree idle + thrown coconut), with
  stomp destruction (+100), explosion, contact damage and the original frames;
- hurt/death: hurt pose and knockback, ring scatter (up to 20 lost rings,
  collectible after a short delay), death pose and fall, lives counter,
  respawn at the last star post and reset of the act timer/rings;
- pit falls now count as deaths instead of teleporting back immediately;
- shield and invincibility stars drawn with the original art;
- lives counter shown at the bottom-left as SONIC + digit, and a GAME OVER
  screen with automatic restart when lives reach zero;
- spin dash: hold down + jump to charge, release down to launch, with the roll
  animation and a 40-frame rolling state;
- bridges and EHZ platforms: original bridge logs on level palette line 2,
  solid tops, and the level-art platform sprites;
- SNES SFX: ring, spring, jump, hurt, monitor and signpost samples through the
  PVSnesLib sound engine (synthesized placeholders; original SMPS music is
  still pending);
- ROM expanded to 1 MiB to leave room for audio and future modes.

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
          ring collected: SCORE 000010, RINGS 001; monitor break, spring
          launch, star post activation and goal signpost spin verified from
          controlled start positions; spikes hurt/death, ring scatter,
          badnik stomp (+100), death pose and checkpoint respawn verified
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
![Buzz Bomber](screenshots/sonic2_snes_port_buzzer.png)
![Spikes](screenshots/sonic2_snes_port_spikes.png)
![Stomp](screenshots/sonic2_snes_port_stomp.png)
![Ring loss](screenshots/sonic2_snes_port_ring_loss.png)
![Death](screenshots/sonic2_snes_port_death.png)
![Checkpoint respawn](screenshots/sonic2_snes_port_respawn.png)
![Buzz Bomber fireball](screenshots/sonic2_snes_port_buzzer_fire.png)
![Explosion](screenshots/sonic2_snes_port_explosion.png)
![Shield](screenshots/sonic2_snes_port_shield.png)
![Invincibility](screenshots/sonic2_snes_port_invincibility.png)
![1-up monitor](screenshots/sonic2_snes_port_1up.png)
![Lives HUD](screenshots/sonic2_snes_port_lives_hud.png)
![Spin dash](screenshots/sonic2_snes_port_spindash.png)
![Game over](screenshots/sonic2_snes_port_game_over.png)
![Bridge](screenshots/sonic2_snes_port_bridge.png)
![Platform](screenshots/sonic2_snes_port_platform.png)

The level, palette, sprite, camera and collision are the original Emerald Hill
Act 1 data; the colours are widened from Mega Drive 9-bit to SNES 15-bit. The
BG page window is updated when the camera crosses a 256-pixel page boundary.

## What is still missing (next phases)

1. **Slope velocity/loops.** Terrain Y snap is active, but horizontal speed is
   still plain inertia; `AnglePos` velocity rotation and `Sonic_SlopeResist`
   acceleration need the signed 16x16 path validated for every angle.
2. **Remaining objects.** Moving platforms, waterfalls and scenery still need
   their own importers and behaviors. Badnik AI is still approximate around
   ledges/turning points. Badniks respawn on death; broken monitors and used
   star posts intentionally remain in their state.
3. **HUD art/title card.** The layout is faithful, but the font is a compact
   5x7 OBJ font and the GAME OVER screen is text-only; the original HUD font,
   title card and act card are still missing.
4. **Death/game-over details.** The game-over state is a simple text screen;
   the original art/animation and the invincibility-kills-badniks behavior are
   still missing.
5. **Audio music.** SFX are in through the SNES sound engine, but the original
   SMPS music/DAC driver is not translated yet; the music is still silent.
6. **Tails, special stages, water, two-player mode, title/act cards, openings
   and ending.**

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
  in 22 groups and a 1 MiB ROM with ~529 KiB free.
- The object layer uses BG2 with a 32x32 screen-space map at VRAM 0x3800 and
  512 tiles of CHR at 0x4000; OBJ tiles moved to 0x6000. The map is copied to
  VRAM after `WaitForVBlank()` (RAM-to-VRAM DMA during active display is lost).
- The goal signpost is at x=10,816, so the level must stay at least 1,360 tiles
  wide; the port uses 1,376 tiles (43 pages).
- Sonic now uses 18 frames (idle/walk/run/roll/hurt/death), 384 OBJ tiles;
  rings use 32 and the HUD 39, for 455 of the 512 available OBJ tiles.
- The BG2 object atlas now includes monitor icons, spikes, badniks, shield,
  invincibility stars, explosion, bridge and platform frames (402 of 512 CHR
  tiles).
- The preview's injected controller events were not reliable in headless mode;
  the `--demo` build uses assignment (`pad = padsCurrent(0) | KEY_RIGHT`)
  because `pad |= KEY_RIGHT` did not reach the physics in that build.
