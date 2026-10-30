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

The Game Build dialog saves the selected mode and splash option in
`user://retro_engine.cfg` under `[game_build]`, so the next export starts with
the same configuration. When a built ROM is exported with **Export ROM...**,
its `export_profile.json` is copied next to the ROM as
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
