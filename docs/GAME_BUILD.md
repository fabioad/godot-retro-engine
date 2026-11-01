# Generated game builds

> To create a fresh starter project instead of converting existing assets, use
> **New Project...** — see `docs/NEW_PROJECT.md`.

The **Build** tab exposes **Game Build...** with four real build modes:

| Mode | Source | Output |
| --- | --- | --- |
| Native game → SNES | Last native stage from `.retro/editor/native_links.json`, or an explicit native stage | PVSnesLib project + `.sfc` |
| Native game → Mega Drive | Same native stage, converted to Mega Drive tiles/palette/map | SGDK project + `out/rom.bin` |
| SNES project → Mega Drive | Stage/CHR/MAP/PAL resources from the active project | SGDK project + `out/rom.bin` |
| Mega Drive project → SNES | Stage/CHR/MAP/PAL resources from the active project | PVSnesLib project + `.sfc` |

Generated projects are written under the active retro project's `builds/`
directory and are ordinary PVSnesLib/SGDK projects. They contain:

```text
builds/<name>/
  Makefile
  src/main.c
  src/assets.c
  src/assets.h
  PORTING.md
  port/<scene>_port.h
  port/<scene>_port.json
  port/<scene>_port.md
  port/scripts/*.gd
  .retro/project.json
```

The `port/` bundle is copied from the last native import: UI widget rects/text,
other nodes (markers, bodies, collisions, audio, animation, lights), scripts
and the porting checklist travel with the generated ROM project. It is a port
manifest, not a runtime interpreter; GDScript is copied as reference and is not
transpiled.

## Coherence checks

The Build tab and Game Build dialog refuse incoherent combinations:

- platform selector (SNES/Mega Drive) differs from the active project;
- project mode is not valid for its platform (`mode1` on MD, `h40` on SNES);
- build system and platform disagree (`sgdk` on a SNES project, `pvsneslib`/WLA-DX on MD);
- SDK path points to the other platform's SDK;
- project metadata `build_mode` targets the other platform;
- Game Build mode `SNES project → Mega Drive` / `Mega Drive project → SNES` is used with the wrong source platform.

Stored export profiles and 3D reference profiles from the other platform are
reported as warnings. The Build tab shows the errors/warnings inline and offers
**Use project platform** when the selector differs. **Generate project** still
works when the target SDK is missing; **Generate + Build** is blocked with a
clear SDK message.

The game screen displays the converted stage as a background. The native
capture/import path already bakes sprites into that stage; the generated project
is a real, runnable console build, not a mock. The native port bundle adds the
UI/node/script mapping data for the manual gameplay port.

The Input Mapping editor also imports Godot's own `InputMap` actions/events into
the SNES and Mega Drive masks, preserving existing state associations.

## SNES ROM mapping, size and MSU-1

The Game Build dialog exposes a real SNES ROM configuration row (SNES targets
only):

```text
ROM mapping: Auto (best fit) | LoROM (SlowROM) | LoROM FastROM |
             HiROM (SlowROM) | HiROM FastROM | ExHiROM FastROM (8 MiB) |
             Tales of Phantasia (ExHiROM FastROM 48 Mbit) |
             Star Ocean (S-DD1 48 Mbit)
ROM size:    Auto (recommended) | 2/4/8/16/32/48/64 Mbit
MSU-1:       optional companion .msu file + audio/data driver
```

| Profile | Header mode | Max ROM | Header notes |
| --- | --- | --- | --- |
| LoROM SlowROM | `$20` | 4 MiB | 32 KiB banks, `CARTRIDGETYPE $00` |
| LoROM FastROM | `$30` | 4 MiB | fast access in banks `$80-$FF` |
| HiROM SlowROM | `$21` | 4 MiB | 64 KiB banks |
| HiROM FastROM | `$31` | 4 MiB | fast HiROM |
| ExHiROM FastROM | `$35` | 8 MiB | custom `hdr.asm`, `.EXHIROM`, header at `$40FFC0` |
| Tales of Phantasia | `$35` | 6 MiB | ExHiROM FastROM, SRAM 8 KiB, header size `$0D` |
| Star Ocean | `$32` | 6 MiB | S-DD1 header/layout, SRAM 8 KiB; compression/MMC not included |
| MSU-1 | base `$30`/`$31` | base ROM | empty `.msu`, `src/msu1.h`, registers `$2000-$2007` |

The header size byte has no standard 48 Mbit value; both 48 Mbit (6 MiB) and
64 Mbit (8 MiB) use `$0D`, matching Tales of Phantasia and Star Ocean. WLA-DX
pads a requested 6 MiB image to 8 MiB, so the generated project stores
`rom_trim_bytes` and `GameBuild.finalize_rom()` trims the ROM back to
`0x600000`, patches the Star Ocean mode byte to `$32`, and recomputes the SNES
checksum/complement.

The automatic suggestion uses the estimated generated payload:

| Estimated payload | Suggested profile | Suggested size |
| --- | --- | --- |
| up to 2 MiB | LoROM FastROM | smallest fitting 2/4/8/16 Mbit |
| > 2 MiB to 4 MiB | HiROM FastROM | 32 Mbit |
| > 4 MiB to 8 MiB | ExHiROM FastROM | 64 Mbit |
| > 8 MiB | HiROM FastROM + MSU-1 | 32 Mbit base + `.msu` data |

The estimate is computed from the converted stage tiles/palette/map, the splash
and the project audio sources. `RomProfiles.suggest()` is pure and can be
tested without a toolchain; `GameBuild.generate()` accepts a `rom_settings`
dictionary:

```gdscript
{"profile": "auto", "size_id": "auto", "msu1": false}
```

It writes the matching `HIROM`, `FASTROM`, `ROMSIZE`, `ROMBANKS`, `SRAMSIZE`,
`CARTRIDGETYPE` and `AUTOHDR` values to the generated Makefile, plus a custom
`hdr.asm` for ExHiROM/Tales/Star Ocean. The selected profile, size, header mode
and banks are stored in `export_profile.json` and in the project metadata.

`Star Ocean` is a header/layout preset. S-DD1 decompression and the MMC bank
switching used by the real cartridge are external coprocessor features and are
not implemented by this engine; the dialog and build log show that warning.

MSU-1 is an enhancement, not a separate mapping: the base ROM remains
LoROM/HiROM, an empty `<rom>.msu` companion is written, and `src/msu1.h` exposes
status/seek/track/volume/control helpers. PCM tracks are supplied by the user
as `<rom>-1.pcm`, `<rom>-2.pcm`, ... next to the ROM.

## Godot logo splash

The **Godot logo fade in/out** checkbox includes the same Godot Engine splash
image used by this application:

```text
ide/addons/retro_engine/assets/godot_splash.png
```

The logo is resized/quantized and converted to the target palette/tilemap. In
the generated ROM:

1. the screen starts black;
2. the logo palette fades in;
3. the logo is held centered on screen;
4. the logo fades out to black;
5. the game background appears.

The generated SNES background uses BG1 only (`REG_TM = 0x01`), clears the
tilemap to a reserved blank tile, and writes 16/32-tile rows with the correct
stride. This prevents uninitialised OAM/BG layers and map padding from appearing
as stripes around the centered logo. The Mega Drive path clears the BG_A plane
and OAM before drawing the converted logo/stage.

SNES fades CGRAM entries with `setPaletteColor`; Mega Drive fades CRAM entries
with `PAL_setColor`. The checkbox controls whether the splash assets and code are
compiled into the ROM. With the splash disabled, the generated `assets.h`
contains `#define RETRO_SPLASH 0` and no splash arrays.

The logo is CC BY 4.0; see `LICENSE-NOTICE.md`.

## Persisted export profiles

The validated SNES and Mega Drive settings live in
`ide/addons/retro_engine/export_profiles.gd` as versioned profiles
(`snes-v1` and `megadrive-v1`). `GameBuild.generate()` reads tile size, bpp,
palette size, tile budget, BG mode, splash canvas, fade timing, scroll direction
and tile encoding from these profiles instead of duplicating magic numbers.

Every generated game project contains an `export_profile.json` with those
settings plus the actual map/splash sizes, SDK path/version and ROM path. The
same dictionary is stored in `.retro/project.json` under
`metadata.export_profile`.

| Setting | SNES (`snes-v1`) | Mega Drive (`megadrive-v1`) |
| --- | --- | --- |
| Tile encoding | `snes-planar` | `packed-nibbles` |
| BG mode / layer | `mode1` / `BG1` | `h40` / `BG_A` |
| Tile budget | 1024 | 2048 |
| Map layout | two 32x32 screens | linear |
| Map upload | DMA | DMA |
| Splash fade | hardware brightness, 2 frames/level | 15-step palette, 1 frame/level |
| Splash scroll | x negative, y negative | x positive, y negative |
| Clear before draw | BG1 only, `REG_TM=0x01` | clear `BG_A` + sprites |

The Game Build dialog saves the selected mode, splash option, ROM mapping, ROM
size and MSU-1 flag in `user://retro_engine.cfg` under `[game_build]`, so the
next export starts with the same configuration. When a built ROM is exported
with **Export ROM...**, its `export_profile.json` is copied next to the ROM as
`<rom>.profile.json`.

`ide/tests/game_build_test.gd` asserts that every generated mode writes a
profile with the expected version/encoding and that the project metadata keeps
it.

## Audio

Game Build also consumes audio resources created by the **Audio** tab. SNES
MIDI BGM is rendered with FluidR3_GM and packed into a full-duration IT/SNESMOD
soundbank. Mega Drive MIDI BGM is converted to a YM2612 FM VGM and compiled as
XGM2. `.it`/MP3/WAV BGM uses XGM2 PCM. SFX use BRR (`spcSetSoundEntry`) on SNES
and `XGM2_playPCM` on Mega Drive.
See `docs/AUDIO.md` for formats, synthesis parameters, previews and limits.

```bash
scripts/test_audio.sh
```

The test imports the requested Super Mario Bros. 3 world-map MIDI, converts it
for both consoles, builds both ROMs and records the emulator audio.

## Reproduce

```bash
scripts/test_game_build.sh
```

The test generates all four modes, builds all four ROMs, builds a no-splash
variant, verifies that splash/no-splash ROM hashes differ, launches the
generated ROMs in Mesen/BlastEm when a display is available, and copies the
test ROMs to `validation/game_build/roms_para_testar/`. When RetroArch is
available it also takes SNES (Snes9x) and Mega Drive (Genesis Plus GX)
screenshots and asserts that the logo is centered on a black screen.

Visual regressions:

```text
docs/screenshots/splash_godot_snes.png
docs/screenshots/splash_godot_megadrive.png
```

Both show the complete Godot logo (including the "Game engine" subtitle)
centered on a black screen. The automated check reports:

```text
SPLASH_VISUAL PASS snes center=(127.5,110.5) bbox=(38,15)-(217,206)
SPLASH_VISUAL PASS md center=(159.5,111.5) bbox=(70,16)-(249,207)
```

The logo is cropped to its visible area and fitted into a 192x192 black canvas
before palette reduction, so the logo content is roughly twice as large as the
old 85x91 version and the subtitle stays sharp. A median-cut palette keeps the
few subtitle tiles that survive the 16-colour SNES/Mega Drive budget. SNES
uses BG1 only (`REG_TM = 0x01`), a reserved blank tile, and loads the splash
with the display disabled. The fade uses PVSnesLib's hardware brightness fade
(`setFadeEffectEx(FADE_IN/FADE_OUT, 2)`), so CGRAM is never rewritten during
active display; this removes both the white flash and the horizontal
tearing/banding of the software palette fade. SNES 64-tile-wide BG maps are
packed as two 32x32 screens instead of 64 contiguous words per row. Mega Drive
tiles use SGDK's packed-nibble format (two pixels per byte, high nibble is the left
pixel) and the vertical scroll is negated because a positive Mega Drive VScroll
moves the plane up. The generated showcase stage fills the full visible screen,
so no empty backdrop remains after the splash.

## Large ROMs and mappers (0.1.37)

### SNES

The existing profiles cover LoROM/HiROM up to 4 MiB, ExHiROM up to 8 MiB,
Tales of Phantasia (ExHiROM 48 Mbit), Star Ocean (S-DD1 48 Mbit) and the
KOF98/SD2SNES MKII preset (ExHiROM 8 MiB + MSU-1).

| Preset | Header | Image | Notes |
| --- | --- | --- | --- |
| Tales of Phantasia | `$35` ExHiROM FastROM | 6 MiB trimmed | 64 KiB banks, checksum fixed |
| Star Ocean | `$32` S-DD1 FastROM | 6 MiB trimmed | S-DD1 decompressor/MMC is not embedded |
| KOF98 / SD2SNES MKII | `$35` ExHiROM FastROM | 8 MiB | keep the matching `.msu` companion |

The build pads WLA-DX output to 8 MiB and `finalize_rom()` trims 6 MiB
presets, patches the S-DD1 mode when requested and recomputes the SNES
checksum. `GameBuild.validate_rom()` reports mapping, title, checksum,
MSU-1 companion size and SD2SNES readiness.

### Mega Drive

| Profile | Capacity | Mapper |
| --- | --- | --- |
| `md_linear` | up to 4 MiB | no mapper |
| `md_ssf2` | 8 MiB | SSF2, 8 x 512 KiB segments, `$A130F1-$A130FF` |
| `md_ssf2_ext` | above 8 MiB | extended SSF2 / flashcart |
| `md_pier_solar` | 8 MiB | Pier Solar mapper |
| `md_custom_16` / `md_custom_32` | 16 / 32 MiB | hardware-specific custom mapper |
| `md_mega_cd` | hundreds of MiB | Mega-CD image (export only) |
| `md_msu_md` | 8 MiB base | MSU-MD / MD+ companion |

Generated Mega Drive projects override SGDK's `padROM` target with the
selected `-sizealign` and checksum. Mapper profiles also emit
`src/mapper_ssf2.c/.h` or `src/mapper_profile.h`; the game must switch banks
explicitly. `md_mega_cd` is rejected by the ordinary SGDK build because it
needs a Mega-CD image builder.

Sizes above 8 MiB are not universal Mega Drive formats: they depend on the
mapper and the cartridge/flashcart hardware.

## Cross-platform stage export and Sonic 2 import (0.1.38)

`megadrive_snes` can now export a Sonic 2 disassembly project even though it
contains no `RetroStage` resource. `sonic_stage_import.gd` decodes the original
Kosinski streams:

```text
level/layout/EHZ_1.kos       128x16 chunk layout (FG rows at +$100)
mappings/128x128/EHZ_HTZ.kos chunk -> 8x8 block map
mappings/16x16/EHZ.kos       block -> 2x2 tiles
art/kosinski/EHZ_HTZ.kos     914 packed 4bpp tiles
art/palettes/EHZ.bin         3 level palette lines
```

The Mega Drive block/tile words are preserved (tile index, palette line, H/V
flip, priority) and the stage is cropped to the screen shown at the act's start
position. The importer supports EHZ, MTZ, ARZ, CNZ, CPZ, OOZ, MCZ, WFZ, SCZ and
DEZ when the corresponding files are present.

Because `816-tcc` emits one `.db` line per array, large SNES assets are now
emitted as binary blobs plus a WLA module:

```text
src/assets_tiles.bin, src/assets_pal.bin, src/assets_map.bin
src/assets_data.asm   (.incbin + .export, one section per blob)
src/sfx_data.asm      (converted BRR samples)
```

`assets.c` only declares the sizes. This avoids the 100 KiB tcc line split and
WLA parse errors on large tilesets.

The exporter remains a stage exporter: game logic, physics, sprites, HUD,
parallax layers, objects and the original sound driver are not translated.
Mega Drive colours are widened from 9-bit to SNES 15-bit while keeping the
palette indices unchanged.
