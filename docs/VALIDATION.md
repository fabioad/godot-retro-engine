> Historical validation record from the original project layout. Migration
> checks are recorded separately in `docs/FORK_MIGRATION.md`.

# Validation report

Date: 2026-10-29  
Host: Linux x86_64, Intel Iris Xe, 37 GiB RAM, 12 threads  
Editor: Godot 4.7.2-stable + `retro_engine` module, custom build  
SDKs: PVSnesLib 4.6.0, SGDK 2.11  
Emulators detected: Mesen, bsnes, Snes9x (Flatpak), BlastEm, RetroArch

All tests ran on **copies** under `validation/projects/`. The original reference
trees were not edited by the importer or editor. Build outputs are produced by
the real `make`/SDK processes.

## 1. Module and editor startup

| Check | Result |
| --- | --- |
| Godot editor starts on Linux | PASS (`4.7.2.stable.custom_build`) |
| `RetroSDK.detect_all()` finds both SDKs | PASS |
| PVSnesLib probe | `4.6.0`, native Linux tools found, `ready=true` |
| SGDK probe | `SGDK 2.11`, `libmd.a` + `rescomp.jar`, Linux path detected |
| Editor plugin loads without parse/runtime errors | PASS (`SCRIPT ERROR` scan clean) |
| Retro workspace opens automatically | PASS |
| Auto-import configuration persisted | PASS (`user://retro_engine.cfg`) |

## 2. Import and conversion

| Project | Detection | Resources | Editable | Sprite conversion | Stage conversion |
| --- | --- | ---: | ---: | --- | --- |
| Daniel do Bolo's Adventure (`daniel_snes`) | SNES / WLA-DX | 93 | 68 | PASS | PASS |
| Side Arms (`sidearms/port`) | SNES / PVSnesLib | 269 | 106 | PASS | PASS |
| KOF '98 port (`kof98`) | SNES / PVSnesLib, target `pvsnes` | 3746 | 978 | PASS | PASS |
| SGDK image sample (`sgdk_image`) | Mega Drive / SGDK | 11 | 6 | PASS | (sample has no editable map) |

Editable means a real decoder and encoder exist. Read-only formats (SFF, AIR,
audio, archives) are counted separately and never shown as editable.

Working copies are written under `ide/workspaces` and receive a `.gdignore`
marker before any project file is copied. Godot's own importer therefore never
scans them, which matters because SNES toolchains emit binary `.obj` objects
that Godot would otherwise parse as Wavefront OBJ text (flooding the log with
`Unicode parsing error` lines and stalling the first scan). Legacy
Windows-1252/Latin-1 text files are decoded silently instead of raising one
UTF-8 warning per accented byte.

The importer detected:

- Daniel: raw WLA-DX Makefile, generated `src/gen/*.chr/.map/.pal`, 32×32
  row-major maps, 16-color palettes, 8×8 hardware tiles.
- Side Arms: `PVSNESLIB_HOME`/`snes_rules`, `.pic/.pal/.map`, **240×32
  column-major** maps (layout recovered from `stagedata.h` and the generator),
  8 palette banks.
- KOF: `Makefile.pvsnes` → build target `pvsnes`, 64×32 row-major stage maps,
  generated `*_pal.bin` companions for character CHR, 8 MiB ExHiROM ROM.
- SGDK: `$(GDK)/makefile.gen`, `.res` resources, 8×8 4bpp tiles and CRAM.

## 3. Real builds

| Project | Command path | Result | ROM |
| --- | --- | --- | --- |
| Daniel | WLA-DX `make`, WLA tools supplied by PVSnesLib | SUCCESS, exit 0 | `build/daniel.sfc`, 512 KiB, LoROM |
| Side Arms | PVSnesLib `make`, `PVSNESLIB_HOME` injected | SUCCESS, exit 0 | `sidearms.sfc`, 4 MiB, FastROM |
| KOF '98 | `make ... pvsnes`, PVSnesLib | SUCCESS, exit 0 | `kof98-snes.sfc`, 8 MiB, ExHiROM |
| SGDK image sample | SGDK `make`, GCC 13.2 m68k-elf via Wine + native host tools | SUCCESS, exit 0 | `out/rom.bin`, 128 KiB, SEGA header |

ROM probes:

```
daniel-blue.sfc -> snes LoROM title=DANIEL DO BOLO checksum_valid=true
kof98-snes.sfc  -> snes ExHiROM title=KOF98 SNESFEST checksum_valid=true
rom.bin (SGDK)  -> megadrive "SEGA" header title=SAMPLE PROGRAM
```

The initial ROM discovery bug that chose `build/msu_chr_late_staging/*.sfc`
over the canonical root ROM was found by this validation and fixed (score by
artifact type, staging penalty, then mtime).

## 4. Edit → export → rebuild → verify

Stage `src/gen/bg1.chr` was opened, one tile pixel was changed to palette index
1, exported as native CHR, then the project was cleaned and rebuilt entirely
through `RetroBuilder`:

```
ROM before edit:  6b6f681b52071ce4499bd5fc579f5317
ROM after edit:   ed02536b9e76b4a4b808abdaadde2f24
ROM restored:     6b6f681b52071ce4499bd5fc579f5317  (matches original)
```

This proves a visual resource edit reaches the linked ROM and that restoring
the asset restores the original image. It is the required vertical slice.

## 5. Resource compiler and emulator launch

- SGDK SPRITE export (indexed PNG + `.res`) compiled successfully with
  `rescomp.jar` (`exit 0`, `.s` and `.h` produced).
- SGDK TILESET/MAP/PALETTE export (tileset PNG + full-map PNG) compiled
  successfully with `rescomp.jar` (`exit 0`).
- Animation `.inc` (65816) and `.h` (SGDK) exports produced non-empty files.
- Mesen launched `daniel-blue.sfc` and stayed running until the test timeout
  (exit 124 means the GUI process was alive).
- BlastEm launched both `daniel-megadrive.bin` and the freshly built SGDK
  `out/rom.bin` and reported the SEGA header.
- Emulator detection and ROM probe now select the correct platform before
  choosing a frontend (the previous MD-as-SNES probe bug was fixed and
  re-tested).

## 6. Editor UI checks

The Retro workspace was launched with the built editor and captured from the
rendered viewport:

- `docs/screenshots/editor_sprite.png` – Daniel sprite sheet, 16-color palette,
  frames, origin, hitboxes and hardware monitor.
- `docs/screenshots/editor_stage.png` – decoded `ending.chr/.map/.pal` stage
  rendered at the SNES 256×224 viewport with tile picker and map metadata.
- `docs/screenshots/editor_animation.png` – fighting-game state list
  (IDLE/WALK/JUMP/CROUCH/ATTACK/HIT/BLOCK/SPECIAL/SUPER/THROW), timeline,
  60 Hz controls and export panel.
- `docs/screenshots/editor_inputs.png` – input mapper with 10 default actions,
  SNES/MD masks (`KEY_LEFT`, `BUTTON_LEFT`), state/next association, validation
  and state-machine preview.
- `docs/screenshots/editor_simulator.png` – editor-side state-machine simulator
  with action buttons, keyboard/gamepad capture, frame stepping and preview.
- `docs/screenshots/editor_graph.png` – GraphEdit state graph with nodes,
  connections, compound conditions, cooldown/priority and C generation.
- `docs/screenshots/editor_hitboxes.png` – per-frame hit/hurtbox timeline,
  box inspector, opponent collision preview and export controls.

The Input Mapping stage was also validated outside the UI: 10 default actions,
SNES `KEY_LEFT = 0x0200`, SGDK `BUTTON_A = 0x0040`, duplicate-mask warnings for
same-state conflicts, JSON round-trip, and three exported artifacts:

- the PVSnesLib C header compiled with `816-tcc`;
- the WLA-DX include assembled with `wla-65816`;
- the SGDK header compiled with the bundled GCC 13.2 `m68k-elf-gcc`.

The editor opens directly in the Retro workspace at 1600×1000. Short tab titles
and an adaptive three-column layout avoid clipping the hardware monitor on a
1024-pixel-wide editor window; very small windows still require resizing.

The Retro toolbar and the Game Build window include drawn minimize,
maximize/restore and close controls. Headless validation checks their presence
and icons:

```text
WINDOW_CONTROLS PASS buttons=3 icons=3 dialog=true
```

Screenshot: `docs/screenshots/editor_window_controls.png`. The controls are
appended to the Retro titlebar toolbar immediately after the **Executar** button,
because some shells (for example Noctalia) only expose a close button in the
native titlebar. Double-clicking an empty area of the editor titlebar or the
Retro workspace top bar toggles maximize/restore as well; the event is consumed
so shells that advertise but do not implement the native gesture still work.
When the compositor ignores a programmatic maximize request, the engine resizes
the `Window.size` (not just the DisplayServer surface) to the usable screen area
and restores the previous geometry on the next double-click. Using `Window.size`
is important: it updates the editor viewport, so the software fills the window
instead of leaving black margins.

## 7. Generated state machine + emulator execution

The optional C generator produced `retro_input.h`, `retro_state_machine.h` and
`retro_state_machine.c` from an 11-action map (including a priority-9 hold
combo with `SUPER -> IDLE` transition).

| Check | Result |
| --- | --- |
| Generated source compiles with PVSnesLib `816-tcc` | PASS (`retro_state_machine.obj`) |
| Generated source compiles with SGDK GCC 13.2 `m68k-elf-gcc` | PASS (`retro_state_machine.o`) |
| Host logic test: press vs hold, priority, state, next state, force state | PASS |
| PVSnesLib test project links generated code | PASS, `retro_sm_snes.sfc`, 256 KiB |
| SGDK test project links generated code | PASS, `out/rom.bin`, 128 KiB |
| Emulator execution smoke: six ROMs (Daniel, Side Arms, KOF, SGDK image, SNES SM, MD SM) | PASS, all processes alive after 4 s |

Emulator smoke used Mesen for SNES and BlastEm for Mega Drive. This proves the
ROMs load and the emulators stay running; it is not a frame-by-frame visual
comparison against hardware.

The generated state machine was driven by real console input reads in the test
ROMs (`padsCurrent`/`padsDown` on SNES and `JOY_readJoypad` + changed bits on
Mega Drive).

Animation durations are exported into `retro_state_durations[]`; the demo
`main.c` calls `retro_sm_tick()` every frame. The host logic test verifies that
a 2-frame `SUPER` action transitions back to `IDLE` automatically and that the
frame counter resets.

## 8. Editor state-machine simulation

`state_simulator.gd` implements the same priority/hold matcher in the editor.
It supports:

- action buttons plus keyboard/gamepad bindings from the Inputs editor;
- 60 Hz play, single-step and reset;
- current state, elapsed frame, duration, pending next state and input masks;
- automatic animation-duration transition and explicit animation-end button;
- animation preview using the loaded sprite/animation document.

Headless test `sim_logic_test.gd`:

```text
after step 1 state=SUPER frame=1 pending=IDLE
after step 2 state=IDLE frame=0
SIM_LOGIC PASS
```

Screenshot: `docs/screenshots/editor_simulator.png`.

## 9. Visual state graph runtime

`RetroStateGraph` compiles the graph to a standalone C runtime:

- node enum + duration table;
- condition table (`mask`, `mode = pressed/held/released`, sequence start/count/window);
- transition table (`from`, `to`, `cond_start`, `cond_count`, `op`, `cooldown`, `priority`, `auto`);
- 32-entry pressed/released history for MUGEN command sequences;
- `retro_sm_update()` edge-aware matcher;
- `retro_sm_tick()` cooldown decrement + duration auto transition;
- `retro_sm_animation_end()` explicit transition;
- `retro_sm_force_state()`, `retro_sm_state_name()`.

Validation:

| Check | Result |
| --- | --- |
| Graph with 10 states, 14 transitions validates | PASS |
| Compound ALL condition (attack pressed + left held) | PASS |
| Cooldown blocks retrigger, then releases after ticks | PASS |
| Auto transition after animation duration | PASS |
| MUGEN sequence (down, right, attack within 20 frames) | PASS |
| Generated C compiles with `816-tcc` | PASS |
| Generated C compiles with SGDK GCC 13.2 | PASS |
| Graph demo ROMs (SNES 256 KiB, MD 128 KiB) | PASS |
| Emulator smoke (8 ROMs including graph demos) | PASS, failures=0 |

The generated header is SDK-neutral (`retro_u8`/`retro_u16`/`retro_node` typedefs), so the
same runtime compiles for both consoles.

Screenshot: `docs/screenshots/editor_graph.png`.

## 10. Hitbox / hurtbox timeline

The animation hitbox editor was validated with two frames of `ATTACK`:

```text
boxes frame0=2
collision overlapping: hit=true  contacts=2
collision far:          hit=false contacts=0
export counts: SNES=3, SGDK=3
HITBOX LOGIC PASS
```

Exports:

- SNES `.inc` assembled with `wla-65816`;
- SGDK `.h` compiled with GCC 13.2.

The collision preview is connected to the Simulator tab: enabling **Follow
simulator** makes the player state/frame track the simulated state machine.
The canvas supports selecting and dragging boxes; the inspector edits
`x/y/w/h/type`; boxes are stored per animation frame.

## 11. MUGEN AIR/CNS and collision runtime

Real KOF '98 files were used:

```text
AIR actions=887 action=200 frames=5
import hit_boxes=1 hurt_boxes=10
CNS hitdefs=104
AIR round-trip/PASS
hitbox table count=11
AIR_CNS PASS
```

Validation:

| Check | Result |
| --- | --- |
| AIR parse (887 actions, defaults + explicit boxes) | PASS |
| AIR action 200 → animation state `ATTACK` | PASS |
| AIR export + reparse | PASS |
| CNS parse / HitDef properties | PASS (104 hitdefs) |
| Hitbox `.inc` assembled with `wla-65816` | PASS |
| Collision runtime host hitstop/invulnerability test | PASS |
| Collision runtime compiled with `816-tcc` | PASS |
| Collision runtime compiled with SGDK GCC 13.2 | PASS |
| Existing 8-ROM emulator smoke | PASS |

Collision runtime host assertions: hit damage 12, attacker hitstop 5, defender
hitstop 9, invulnerability 10, blocking path, health reduction and cooldown
decrement.

Screenshot: `docs/screenshots/editor_hitboxes.png` (updated with AIR/CNS import
and move-property controls).

## 12. Complete MUGEN import, command sequences and collision rules

Real KOF '98 CNS/AIR/CMD files were used end to end:

```text
PARSE ok=true states=259 actions=887 commands=71 state200_hitdef=11/13 hitstun=9 damage=7
IMPORT ok=true frames=5 hitboxes=1 hurtboxes=10
AUTOMAP ok=true mapped=257
IMPORT_ALL ok=true states=216 frames=1096 hitboxes=103 hurtboxes=1167 animation_states=219
GRAPH ok=true nodes=257 transitions=269 command=4 auto=265 sequences=7 moves=257 hitstop_moves=40 warnings=60
VALIDATE ok=true errors=0 warnings=0
MUGEN_IMPORT PASS
MUGEN_UI nodes=259 transitions=272 moves=259 batch=216 commands=71 animation_states=221
MUGEN_UI PASS
```

Validation:

| Check | Result |
| --- | --- |
| 259 `Statedef` records, 887 AIR actions, 71 `.cmd` definitions | PASS |
| Auto-map every unique state (257 unique numbers) | PASS |
| Batch import 216 states / 1096 frames / 103 hitboxes / 1167 hurtboxes | PASS |
| State 200 HitDef expression damage = 7, hitstop 11/13, hitstun 9 | PASS |
| Full fight graph: 257–259 nodes / 269–272 transitions | PASS |
| `.cmd` command sequences (QCF/HCB/DP/236236) in graph | PASS (7 sequence conditions) |
| Graph validation without MUGEN false-positive state warnings | PASS |
| Move profiles with hitstop/pushback/HitDef ID | PASS |
| 16-bit node/transition/state indices (>255) | PASS |
| Multi-hit ID gating + automatic BLOCK guard inference | PASS |
| MUGEN tab batch import → StateGraph + Hitbox editors | PASS |
| Generated state machine compiled with `816-tcc` | PASS |
| Generated state machine compiled with SGDK GCC 13.2 | PASS |
| Generated collision runtime compiled with both SDKs | PASS |

Command transitions come from real `command = "..."` triggers and `.cmd`
definitions. The graph has no node cap by default; `Max nodes = 0` imports all
mapped states. Variable/helper/random triggers remain reported as skipped (60
warnings in this character), not silently approximated.

Screenshot: `docs/screenshots/editor_mugen.png` (real KOF CNS/AIR/CMD parsed in
the MUGEN tab, 257 mapped states, batch import and command definitions).

## 13. Native Godot scene bridge and 3D reference profiles

`RetroNativeBridge` was exercised with synthetic Godot nodes and with the real
editor capture path.

Headless regression:

```text
NATIVE ok=true actors=5 assets=5
ASSET Hero type=1 asset=hero.png
ASSET HeroAnim type=2 asset=heroanim.retro_animation.json
ASSET Floor type=5
ASSET Cube3D type=3
ASSET Ground type=6
FILES hero_png=true hero_chr=true hero_anim=true scene_header=true scene_json=true
      superfx_header=true superfx_json=true
STAGE true tiles=2 map=8x8 checks={tilemap map/chr/json all true}
BAKE 8 checks={bake png/animation true}
CAPTURE2D 2 checks={capture map/chr true}
PROFILES superfx=superfx svp=svp svp_header=true
RESOURCES 52
NATIVE_BRIDGE PASS
==> native scene bridge and both SDK compilers PASS
```

Editor capture/bake:

```text
Native import complete
Scene: native3d
Actors: 2
3D bake: 8 frames
3D chip reference: Super FX / GSU (Star Fox reference)
```

Validation:

| Check | Result |
| --- | --- |
| `Sprite2D` + `AnimatedSprite2D` texture → sprite/animation assets | PASS |
| Animation atlas packing and per-frame durations | PASS |
| Rectangle collision → scene actor table | PASS |
| `MeshInstance3D` → 3D actor metadata | PASS |
| Rendered scene → 8x8 unique-tile SNES stage | PASS |
| Headless software 2D capture → SNES stage | PASS |
| Headless software 3D bake (triangle rasterizer) | PASS (8 frames) |
| Semantic TileMapLayer → RetroStage with flips | PASS |
| 3D scene duplicated, rotated and baked to 8-frame sprite sheet | PASS |
| Super FX profile header/JSON (Star Fox reference) | PASS |
| SVP profile header/JSON (Virtua Racing reference) | PASS |
| Scene/profile headers compiled with `816-tcc` | PASS |
| Scene/profile headers compiled with SGDK GCC 13.2 | PASS |
| Generated tilemap `.inc` assembled with `wla-65816` | PASS |
| Generated assets registered in the project resource list | PASS (52 resources) |
| `3D_HANDOFF.md` + `3d_handoff.json` for co-processor build path | PASS |

Screenshot: `docs/screenshots/editor_native.png` — 3D scene baked with the
Super FX / Star Fox profile, 224x192 capture and eight frames.

## 14. Game build options and Godot logo splash

Four generated builds were produced from the native scene and cross-converted
from the two source platforms:

```text
GEN native_snes     target=snes
GEN native_md       target=megadrive
GEN snes_to_md      target=megadrive
GEN md_to_snes      target=snes
GEN profile         snes-v1 / megadrive-v1 export_profile.json
GEN nosplash        snes/md assets.h RETRO_SPLASH 0
GAME_BUILD PASS

GAME_BUILD ROMS snes=262144/262144 md=131072/131072
SPLASH_VISUAL PASS snes center=(127.5,110.5) bbox=(38,15)-(217,206)
SPLASH_VISUAL PASS md center=(159.5,111.5) bbox=(70,16)-(249,207)
EMULATOR_SMOKE PASS native_snes.sfc
EMULATOR_SMOKE PASS md_to_snes.sfc
EMULATOR_SMOKE PASS rom.bin (native_md)
EMULATOR_SMOKE PASS rom.bin (snes_to_md)
EMULATOR_SMOKE RESULT failures=0
==> game build options and Godot logo splash PASS
```

| Check | Result |
| --- | --- |
| Native scene → SNES PVSnesLib ROM | PASS (256 KiB) |
| Native scene → Mega Drive SGDK ROM | PASS (128 KiB) |
| SNES project stage → Mega Drive ROM | PASS (128 KiB) |
| Mega Drive project stage → SNES ROM | PASS (256 KiB) |
| Optional Godot-logo splash compiled into both ROMs | PASS |
| Splash logo centered on black screen (RetroArch Snes9x/Genesis Plus GX) | PASS |
| "Game engine" subtitle preserved by median-cut palette | PASS |
| No stray OAM/BG map stripes around splash | PASS |
| SNES hardware brightness fade (no white flash/tearing) | PASS |
| SNES 64-tile BG packed as two 32x32 screens | PASS |
| Mega Drive packed-nibble tile format | PASS |
| Versioned SNES/Mega Drive export profiles persisted | PASS |
| `export_profile.json` written for every generated mode | PASS |
| Profile stored in `.retro/project.json` metadata | PASS |
| Splash disabled → `RETRO_SPLASH 0` and different ROM hashes | PASS |
| Generated ROMs launch in Mesen / BlastEm | PASS |
| Godot logo attribution documented | PASS |

Splash/no-splash SHA-256 values differed for both platforms, proving the
optional logo path is actually compiled, not just stored as metadata.

Visual regressions:

```text
docs/screenshots/splash_godot_snes.png
docs/screenshots/splash_godot_megadrive.png
```

Both show the complete Godot logo centered on a black screen. The generated
SNES code loads the splash with the display disabled and fades with the
hardware brightness register (`setFadeEffectEx`), which removes the white flash
and the palette-tearing bands seen with software CGRAM fades. It packs 64-tile
BG maps as two 32x32 screens and forces `REG_TM = 0x01` after loading so
uninitialised OAM/BG layers cannot draw stripes. The Mega Drive path clears BG_A and OAM
before drawing, stores tiles in SGDK's packed-nibble format and negates the
vertical scroll to center the plane. The showcase stage now covers the full
screen on both platforms instead of leaving a large empty backdrop with a small
block in the top-left.

## 15. Audio import, BGM/SFX conversion and MIDI ROM test

`scripts/test_audio.sh` imports the supplied MIDI:

```text
https://files.khinsider.com/midifiles/nes/super-mario-bros.-3/world-map-1-grass-land.mid
```

and builds both consoles with the converted BGM plus a synthesized jump SFX:

```text
AUDIO_BUILD PASS
AUDIO_BUILD GEN audio_snes ok=true bgm=worldmap sfx=1
AUDIO_BUILD GEN audio_md ok=true bgm=worldmap sfx=1
AUDIO_PREVIEW PASS snes_worldmap.wav rms=1184.0 peak=13555
AUDIO_PREVIEW PASS megadrive_worldmap.wav rms=2168.1 peak=9237
AUDIO_PREVIEW PASS snes_jump.wav rms=12535.9 peak=25951
AUDIO_PREVIEW PASS megadrive_jump.wav rms=12526.9 peak=25967
AUDIO_GM PASS duration=16.71s source=FluidR3_GM
AUDIO_YM2612 PASS writes=648
AUDIO_LONG_PCM PASS duration=16.71s
AUDIO_EMULATOR PASS snes_record.wav rms=1655.7 peak=9144
AUDIO_EMULATOR PASS md_record.wav rms=1441.2 peak=11851
AUDIO_BUILD ROMS snes=262144 md=131072 midi=2145
==> MIDI to SNES and Mega Drive audio PASS
```

| Check | Result |
| --- | --- |
| MIDI → FluidR3_GM full render → SNESMOD BRR soundbank | PASS |
| MIDI → YM2612 FM VGM → XGM2 Mega Drive music | PASS |
| Full GM FluidR3 MIDI render (>8 s) | PASS |
| Full-duration PCM BGM (>8 s, no 8 s cut) | PASS |
| WAV/MP3 → SNES BRR SFX | PASS |
| WAV/MP3 → Mega Drive XGM2 PCM SFX | PASS |
| Synthesized SFX parameters (wave/ADSR/slide/vibrato/noise/bitcrush) | PASS |
| SNES/MD device previews rendered | PASS |
| Real ROM emulator audio is non-silent | PASS |
| Audio editor creates and previews an asset | PASS |
| Stop cancels SNES/MD preview (including during conversion) | PASS |
| Double-click empty top bar maximizes/restores | PASS |

ROMs:

```text
validation/game_build/roms_para_testar/07_snes_music_mid.sfc
validation/game_build/roms_para_testar/08_megadrive_music_mid.bin
```

### Audio browser and raw project BGM regression

A real KOF98 project (3749 resources, 251 editable audio assets) was loaded to
reproduce project audio playback. Before the fix, selecting `01Ne.mid` and
pressing Preview built a temporary descriptor in `_on_selected`, but `_preview`
re-read the empty descriptor and fell back to the SFX synthesizer, playing a
0.22 s beep instead of the BGM. The preview now reuses the effective
descriptor and the kind/name/params fields:

```text
AUDIO_BROWSER ALL=251 BGM=63 SFX=188
AUDIO_BROWSER SEARCH 01Ne => 1 item
AUDIO_BROWSER play BGM 01Ne SNES length=189.49975s state=playing
AUDIO_BROWSER play BGM 01Ne MD   length=189.49980s state=playing
AUDIO_BROWSER previews separated under preview/snes and preview/megadrive
AUDIO_BROWSER stop => stream=null
```

```text
AUDIO_SFX_WAV add/preview/update/delete
  SNES preview 1.0s, Mega Drive preview 1.0s
  source WAV used instead of the SFX synthesizer
  Update SFX renamed the descriptor without changing its path
  Delete SFX removed the descriptor, imported source and previews
```

The Audio tab now has search and All/BGM/SFX filters, a localized `Play`
button and a `BGM / SFX` top-toolbar menu. Double-clicking an audio resource in
the left tree opens it and starts its preview. Generated previews for both
SNES and Mega Drive remain non-silent WAVs.

## 16. Fresh installation, missing SDKs and GitHub downloader

The workspace was launched with a temporary HOME containing no projects and no
SDK configuration. It opened with `(no project)` and clear SDK status, without
script errors. `MISSING_SDK PASS` verifies that invalid SDK paths produce
guidance from the Build panel instead of a crash or fake build.

The in-app **Download SDKs...** button was exercised against the official
GitHub assets:

```text
SDK_INSTALLED snes .../sdks/pvsneslib-4.6.0/pvsneslib
SDK_INSTALLED megadrive .../sdks/sgdk-2.11/SGDK-2.11
SNES found=true ready=true
MD found=true resource_ready=true
MISSING_SDK PASS
```

| Check | Result |
| --- | --- |
| App starts with no projects/SDKs | PASS (no crash) |
| Invalid SDK path shows guidance | PASS |
| PVSnesLib download/extract/probe | PASS |
| SGDK download/extract/probe | PASS |
| Downloaded SDKs auto-detected from user data | PASS |
| Missing m68k toolchain stays resource-only | PASS |

## 17. Embedded OS terminal

A `Terminal` main screen was added immediately after `Retro`. It embeds the MIT
GDTerm 1.0.2 extension (PTY + VT100), so it runs the real operating-system
shell instead of a command-output text box.

The GUI check shows both main screens (`Retro` and `Terminal`) and the terminal
header with tabs, `Terminals ▾`, `Aa`, `−` and `+`. The headless test starts a
real shell, executes a command through the PTY, then exercises tab creation,
switching, closing, the `+`/`−` buttons, the terminal menu and the font-size
controls:

```text
TERMINAL_EXTENSION class=true
TERMINAL_FIRST active=true tabs=1 focus=true
TERMINAL_SHELL marker=TERMINAL_OK
TERMINAL_ADD tabs=2 active=true focus=true
TERMINAL_FONT base=18 model=18
TERMINAL_FONT increase=20 second=20
TERMINAL_FONT decrease=16
TERMINAL_FONT menu=["Increase Font  (Ctrl+=)", "Decrease Font  (Ctrl+-)", "Reset Font  (Ctrl+0)", "", "Current: 18 px"]
TERMINAL_FONT shortcut=20
TERMINAL_SWITCH current=0 visible0=true visible1=false focus0=true
TERMINAL_RETURN current=1 visible1=true focus1=true
TERMINAL_CLOSE terms=1 tabs=1
TERMINAL_MENU ["New Terminal", "Close Current Terminal", "Terminals", "Terminal 1"]
TERMINAL_MENU_ACTIONS terms=2
TERMINAL_EMPTY terms=0 empty_visible=true
TERMINAL_TEST PASS
```

| Check | Result |
| --- | --- |
| Terminal main screen next to Retro | PASS (GUI screenshot) |
| GDTerm GDExtension load | PASS |
| Real shell through PTY + command execution | PASS |
| Multiple tabs, `+`, `−`, `Terminals ▾` | PASS |
| Font `Aa` menu, Ctrl shortcuts, live resize of all terminals | PASS |
| Font size persistence in `user://terminal.cfg` | PASS |
| Active tab fills the screen and receives keyboard focus | PASS |
| Re-selecting a terminal after switching away | PASS |
| Closing all terminals keeps the editor stable | PASS |

### Unicode and control strings

The bundled Linux GDTerm extension is rebuilt from a pinned revision with
`scripts/gdterm/control_strings.patch`. It consumes unsupported OSC/DCS/APC/
PM/SOS strings and unknown CSI requests completely, including when reads split
the escape sequence. This fixes OpenCode's OSC 66 probe leaking backslashes and
discarding the Unicode block logo.

```text
TERMINAL_CONTROL_STRINGS PASS (all read boundaries)
```

The OpenCode 2.2.2 TUI was launched inside the embedded terminal; the logo now
renders as the intended block letters instead of `\\` bars.

| Check | Result |
| --- | --- |
| OSC/DCS/APC/PM/SOS consumed at every read boundary | PASS |
| Unicode logo and symbols after control strings | PASS |
| OpenCode TUI inside the embedded terminal | PASS |

## 18. Native UI/node/script port bundle and InputMap import

The Native tab now exports a full port bundle in addition to sprites/tilemaps:
`<scene>_port.h`, `<scene>_port.json`, `<scene>_port.md` and copied
`scripts/*.gd`. It covers UI `Control` widgets, markers, bodies, collisions,
audio, animation, timers, lights, paths and attached scripts. **Import game
scene** uses `ProjectSettings.application/run/main_scene` (the Jogo/Game tab).

The regression scene includes `Label`, `Button`, `Marker2D`, `Area2D`, a real
GDScript and the existing sprites/3D/tilemap nodes. The generated port header is
compiled with both `816-tcc` and SGDK m68k GCC. Game Build copies the bundle to
the generated project's `port/` directory.

```text
PORT ok=true widgets=2 nodes=11 scripts=1 checks={ "json": true, "header": true, "markdown": true, "script_copy": true, "widgets": true, "nodes": true, "scripts": true, "header_text": true, "methods": true }
GAME_PORT { "ok": true, "header": true, "json": true, "porting_md": true, "scripts": true }
NATIVE_BRIDGE PASS
```

The Input Mapping editor imports Godot `InputMap` actions and events into the
SNES/Mega Drive masks, preserving existing state/next/hold/priority fields:

```text
INPUT_IMPORT left={ "id": "move_left", "snes": ["Left"], "md": ["Left"], "keys": ["A"], ... }
INPUT_IMPORT jump={ "id": "jump", "snes": ["A"], "md": ["A"], "gamepad": ["JOY_A"], ... }
INPUT_IMPORT start={ "id": "start", "snes": ["Start"], "md": ["Start"], "keys": ["Enter", ...], ... }
INPUT_IMPORT PASS
```

| Check | Result |
| --- | --- |
| UI widget manifest (`Control`, `Label`, `Button`, rects/text) | PASS |
| Other-node manifest (markers, areas, collisions, audio/animation metadata) | PASS |
| Script manifest + copied GDScript source | PASS |
| Port header compiles for SNES and Mega Drive | PASS |
| Game Build copies `port/` and `PORTING.md` | PASS |
| Godot `InputMap` import preserves state associations | PASS |
| Game scene import from `application/run/main_scene` | GUI workflow |

GDScript is exported as a reference manifest and copied source; it is not
transpiled to C. UI text/layout and gameplay scripts still need the manual port
described in `<scene>_port.md`.

## 19. New SNES and Mega Drive project templates

The top toolbar's **New Project...** creates a real starter project for either
target and imports it back into the IDE. The template includes a 16-colour
screen, editable `src/main.c`, `src/assets.c/.h`, `Makefile`, `art/` source
assets and `README.md`; the demo loop scrolls the background.

The regression creates both templates, verifies the generated/imported
resources, builds both ROMs with the real SDKs and checks the output:

```text
NEW_PROJECT snes checks={ "ok": true, "project": true, "main": true, "make": true, "readme": true, "animated": true, "build_system": true, "resources": true, "art": true }
NEW_PROJECT snes build_start=0 sdk=.../pvsneslib-sdk-4.6 system=pvsneslib
NEW_PROJECT snes build_ok=true rom=.../template_snes.sfc size=262144
NEW_PROJECT md checks={ "ok": true, "project": true, "main": true, "make": true, "readme": true, "animated": true, "build_system": true, "resources": true, "art": true }
NEW_PROJECT md build_start=0 sdk=.../sgdk211 system=sgdk
NEW_PROJECT md build_ok=true rom=.../out/rom.bin size=131072
NEW_PROJECT_TEST PASS
```

| Check | Result |
| --- | --- |
| SNES template generation and import | PASS |
| Mega Drive template generation and import | PASS |
| Editable C sources, Makefile, README and art assets | PASS |
| SNES ROM build (PVSnesLib) | PASS |
| Mega Drive ROM build (SGDK) | PASS |
| Template demo animation | PASS |

## 20. Project/platform coherence validation

The Build tab and Game Build dialog validate the active project against the
platform selector, mode, build system, SDK path, stored export/3D profiles and
the Game Build source mode. Blocking errors stop the build; non-fatal
incoherences are shown as warnings. The Build tab also offers **Use project
platform** to repair the selector.

```text
CHECK_VALID { "ok": true, "errors": [], "warnings": [], "target": "snes" }
CHECK_PLATFORM { "ok": false, "errors": ["Platform selector is Mega Drive, but the active project 'coherence_snes' is SNES. ..."] }
CHECK_MODE { "ok": false, "errors": ["Project mode 'h40' is not valid for SNES. Use mode1."] }
CHECK_SYSTEM { "ok": false, "errors": ["Project is marked SNES but uses SGDK (Mega Drive). ..."] }
CHECK_SDK { "ok": false, "errors": ["SDK path points to SGDK (Mega Drive), but the project is SNES: ..."] }
CHECK_PROFILE { "ok": true, "warnings": ["Stored export profile targets Mega Drive, but the project is SNES. ..."] }
CHECK_3D { "ok": true, "warnings": ["3D reference profile is SVP (Mega Drive), but the project is SNES. ..."] }
CHECK_BUILD_MODE { "ok": false, "errors": ["Project metadata build_mode 'native_megadrive' targets Mega Drive, but the project platform is SNES. ..."] }
CHECK_BUILD_PANEL blocked=true fix=snes
CHECK_GAME_BUILD_MODE error=Mode 'Mega Drive project → SNES' requires an active Mega Drive project. ... visible=true
PROJECT_CHECKS PASS
```

| Check | Result |
| --- | --- |
| Platform selector vs active project | BLOCKED |
| Project mode vs platform | BLOCKED + auto-fixed on project open |
| Build system vs platform | BLOCKED |
| SDK path vs project platform | BLOCKED |
| Export profile / 3D profile from the other platform | WARNING |
| `build_mode` metadata target mismatch | BLOCKED |
| Game Build source platform mode | BLOCKED with visible warning |
| **Use project platform** repair | PASS |

## 21. Retro UI localization

The Retro addon follows `TranslationServer.get_locale()` and ships all 40 Godot
4.7 editor locales in `locales.json` (467 keys each, plus English). The JSON is
loaded lazily by the small `i18n.gd`; technical terms are protected from
translation. The tests switch locales, check key parity/placeholders and
instantiate the New Project, Game Build and SDK Downloader dialogs.

```text
I18N pt_BR new_project=Novo Projeto... mode=Projeto SNES → Mega Drive
I18N_DIALOG_NEW create=Criar projeto build=Criar + Compilar
I18N_DIALOG_GAME mode=Jogo nativo → SNES generate=Gerar projeto
I18N_DIALOG_SDK title=Download de SDKs — GitHub
I18N en new_project=New Project... mode=SNES project → Mega Drive
I18N fallback fr_FR=fr cancel=Annuler xx=en
I18N_TEST PASS

I18N_LOCALE ar keys=429 sample=مشروع جديد...
I18N_LOCALE fr keys=429 sample=Nouveau projet...
I18N_LOCALE ja keys=429 sample=新しいプロジェクト...
I18N_LOCALE pt_BR keys=429 sample=Novo Projeto...
I18N_LOCALE zh_Hans keys=429 sample=新项目...
I18N_FALLBACK pt_PT -> pt_BR
I18N_FALLBACK fr_FR -> fr
I18N_FALLBACK de_DE -> de
I18N_FALLBACK es_MX -> es
I18N_FALLBACK zh_CN -> zh_Hans
I18N_FALLBACK zh_TW -> zh_Hant
I18N_FALLBACK en_GB -> en
I18N_COVERAGE_TEST PASS
```

The GUI check shows the main Retro workspace in Portuguese, French and Spanish:
Novo Projeto/Nouveau projet/Nuevo proyecto, Importar/Importer/Importar,
Recursos/Ressources/Recursos, Sprites/Stages protected as technical terms,
Build panel and hardware monitor translated, and the coherence warning localized.

| Area | Result |
| --- | --- |
| All 40 Godot editor locales present | PASS |
| 467 keys per locale + placeholder parity | PASS |
| pt-BR/pt-PT main workspace | PASS |
| French / Spanish main workspace | PASS (GUI) |
| English locale | PASS |
| Unsupported-locale fallback to English | PASS |
| Regional/script fallbacks (pt_PT, fr_FR, es_MX, zh_CN, zh_TW) | PASS |
| New Project dialog labels | PASS |
| Game Build dialog labels/modes | PASS |
| SDK Downloader title/status | PASS |
| Build panel + coherence alerts | PASS (visual + headless) |
| Terminal screen/menu/font controls | PASS (headless) |

## 22. SNES ROM mappings, sizes and MSU-1

`rom_profiles_test.gd` checks the pure mapping/size/suggestion logic and
`snes_rom_build_test.gd` generates and builds every supported profile with the
real PVSnesLib/WLA-DX toolchain, then inspects the ROM header, size byte,
checksum/complement and final 6 MiB trim.

```text
ROM_SUGGEST 262144 -> lorom_fast 2m PASS
ROM_SUGGEST 2097152 -> lorom_fast 16m PASS
ROM_SUGGEST 3145728 -> hirom_fast 32m PASS
ROM_SUGGEST 4194304 -> hirom_fast 32m PASS
ROM_SUGGEST 5242880 -> exhirom_fast 64m PASS
ROM_SUGGEST 8388608 -> exhirom_fast 64m PASS
ROM_PROFILE lorom_slow mode=32 size=2097152 banks=64 PASS
ROM_PROFILE lorom_fast mode=48 size=2097152 banks=64 PASS
ROM_PROFILE hirom_slow mode=33 size=2097152 banks=32 PASS
ROM_PROFILE hirom_fast mode=49 size=2097152 banks=32 PASS
ROM_PROFILE exhirom_fast mode=53 size=8388608 banks=128 PASS
ROM_PROFILE tales_phantasia mode=53 size=6291456 banks=96 PASS
ROM_PROFILE star_ocean mode=50 size=6291456 banks=96 PASS
ROM_AUTO_LARGE profile=exhirom_fast size=8388608 PASS
ROM_TALES fixed=6291456 trim=6291456 sram=3 PASS
ROM_STAR mode=50 warning=[game_build.rom_warn_sdd1] PASS
ROM_TOO_LARGE ok=false code=[game_build.rom_error_too_large] PASS
ROM_MSU1_EXHIROM warning=[game_build.rom_warn_msu1_exhirom] PASS
ROM_PROFILES_TEST PASS
```

Real generated ROMs:

```text
ROM_BUILD auto size=262144 mode=48 code=8 checksum=30648 header=true
ROM_BUILD lorom2 size=2097152 mode=48 code=11 checksum=30781 header=true
ROM_BUILD hirom4 size=4194304 mode=49 code=12 checksum=20854 header=true
ROM_BUILD exhirom8 size=8388608 mode=53 code=13 checksum=25327 header=true
ROM_BUILD tales6 size=6291456 mode=53 code=13 checksum=25135 header=true
ROM_BUILD star6 size=6291456 mode=50 code=13 checksum=21306 header=true
ROM_BUILD msu1 size=2097152 mode=48 code=11 checksum=61651 header=true msu=true
SNES_ROM_BUILD_TEST PASS
```

| Case | Expected | Result |
| --- | --- | --- |
| Automatic suggestion, small payload | LoROM FastROM, 2 Mbit | PASS |
| LoROM FastROM | mode `$30`, 2 MiB | PASS |
| HiROM FastROM | mode `$31`, 4 MiB | PASS |
| ExHiROM FastROM | mode `$35`, 8 MiB, header `$40FFC0` | PASS |
| Tales of Phantasia | mode `$35`, 6 MiB trimmed from 8 MiB | PASS |
| Star Ocean | mode `$32`, 6 MiB trimmed, S-DD1 warning | PASS |
| MSU-1 | base LoROM + empty `.msu` + `src/msu1.h` | PASS |
| Checksum/complement after trim | recomputed, field sum matches | PASS |

WLA-DX pads 6 MiB requests to 8 MiB; `GameBuild.finalize_rom()` trims to
`0x600000`, patches the Star Ocean mode byte to `$32` when required and
recomputes `checksum`/`complement`. Star Ocean is a header/layout preset only:
the S-DD1 decompressor and MMC bank switching of the real cartridge are not
implemented and are reported as a warning.

## 23. Known limitations confirmed by testing

- Native 3D is pre-rendered to sprites/tilemaps; there is no real-time 3D
  runtime for the base SNES/Mega Drive. The Super FX/SVP profiles and handoff
  documents are budget references; real GSU/SVP cartridge execution needs the
  external toolchains.
- The software headless 3D fallback renders flat-shaded triangles without
  textures, skeletal skinning or custom shaders. Editor GPU capture has higher
  fidelity.
- TileMapLayer semantic import covers `TileSetAtlasSource` atlas cells and flips;
  scene collection sources, transposed cells and advanced terrain/alternative
  tile semantics are not fully reconstructed.
- SFF/AIR assets remain read-only; audio assets use the BGM/SFX editor and
  real SNESMOD/XGM2 conversion instead of a visual timeline.
- Stage layers are stored/exported as metadata/duplicates; only the base map is
  painted in the current compositor.
- SGDK full builds on this host use the SDK's Windows GCC 13.2 under Wine plus
  native `sjasm`/`convsym`/`bintos`; this is automated by
  `scripts/setup_sgdk_linux.sh`. Dependency-file generation (`-MMD`) is skipped
  for Wine paths, so incremental C dependency tracking is coarser.
- `mac68k` is not shipped as source in SGDK 2.11; `.asm` sources that require it
  are not covered by the Wine setup. `.s`/C SGDK projects are covered.
- The 1024×951 window initially clipped the three-column workspace; the plugin
  now sets a 1600×1000 editor window and short tab titles, and the layout was
  re-checked at that size. Very small windows remain tight but usable.
- Preview is a hardware-aware reconstruction, not a PPU/VDP simulator. HDMA,
  raster effects, mid-frame palette changes and exact sprite-overflow behavior
  still require the emulator/hardware.
- The graph runtime is a polling state machine. Cooldown counts frames and is
  decremented by `retro_sm_tick()`; exact frame semantics depend on when the game
  calls update/tick around VBlank.
- Multiple graph transitions between the same two nodes share one visual edge
  in GraphEdit; the inspector's transition list exposes every condition set.
- Graph conditions reference Inputs actions by id. Renaming/deleting an action
  invalidates those conditions; validation reports it until corrected.
- Hitbox collision is still an AABB test. It now models hitstop, invulnerability,
  HitDef-ID multi-hit gating, basic pushback and automatic BLOCK/GUARD-state
  inference, but not clash, projectiles, rotation, hit-count limits or full
  MUGEN priority resolution. MUGEN/SNES hitboxes are axis-aligned, so rotation is
  intentionally out of scope.
- Hitbox coordinates are relative to the animation frame origin. Sprite-sheet
  frame splitting must be configured before box previews line up with art.
- Hitbox tables are flat per-box tables; the game must build the state/frame
  lookup or use the editor metadata.
- AIR import can be per-state or batch. The action→state mapping is generated
  automatically and remains editable; duplicate MUGEN state numbers collapse to
  one unique target name.
- MUGEN HitDef arithmetic/`ifelse`/`floor` expressions are evaluated with safe
  defaults (`var` = 0, `fvar` = 1, `Helper` = 0). Unknown functions or expressions
  are marked and fall back to 0; they are not a full MUGEN expression VM.
- The collision runtime exposes hitstop/invulnerability counters and checks, but
  the game loop must freeze animation/input while hitstop is active.
- Blocking is inferred for state names containing `BLOCK` or `GUARD`. The game
  can still override `RetroFighter.blocking` for custom guard logic.
- `.cmd` files are parsed into real command sequences (`~D, DF, F, x`, `x+y`,
  `/$F`, ...) and matched by the generated runtime. The SNES pad has three
  attack groups, so `x`/`a`, `y`/`b` and `z`/`c` collapse into attack A/B/C; a
  six-button command that distinguishes punch/kick still needs a custom input
  map.
- `ChangeState` targets are expanded as needed. The default is no node cap
  (`Max nodes = 0`); a positive cap is available for a smaller GraphEdit view.
  The generated runtime uses 16-bit node indices, so the full 250+ state
  character is valid.
- Batch import creates all mapped animation states in one pass. A per-state
  import is still available for selective work; both replace the target state's
  frames, never the original CNS/AIR files.
- Triggers using runtime variables, helpers, random values, enemy state or
  `VarSet`/`VarAdd` logic are skipped and reported; they are not approximated as
  always-true. Named commands are supported through `.cmd` sequences.
- HitDef expressions are evaluated with safe defaults, but the result is an
  estimate when the formula depends on runtime variables. The raw expression is
  preserved and the value remains editable in the Hitboxes tab.

## 24. Reproduce

```bash
scripts/bootstrap.sh
scripts/build_linux.sh
SGDK_ROOT=/path/to/sgdk211 scripts/setup_sgdk_linux.sh
source vendor/sgdk-linux/env.sh
BUILD=1 scripts/validate.sh
scripts/validate_sgdk.sh
scripts/build_state_machine_demos.sh
scripts/build_graph_demos.sh
scripts/test_state_machine_logic.sh
scripts/test_state_graph_logic.sh
scripts/test_hitboxes.sh
scripts/test_air_cns.sh
scripts/test_collision_runtime.sh
scripts/test_mugen_import.sh
scripts/test_native_bridge.sh
scripts/test_game_build.sh
scripts/smoke_emulators.sh
```

Headless report: `ide/validation/headless_report.json` (also copied by
`validation/headless_report.json` when using the harness output path).

## 25. Linux packages and cross-platform builds

### Linux packages

`scripts/package_linux.sh` builds a `.deb` and an `.rpm` from the current
`dist/linux` binary. Both contain the editor under `/opt/godot-retro-engine`,
the `ide` project, a `godot-retro-engine` launcher in `/usr/bin`, a desktop
entry and a scalable icon.

```text
dist/packages/godot-retro-engine_0.1.5_amd64.deb     71 MB
dist/packages/godot-retro-engine-0.1.5-1.x86_64.rpm  71 MB
dist/packages/SHA256SUMS
```

The launcher copies the IDE project to
`${XDG_DATA_HOME:-~/.local/share}/godot-retro-engine/ide` on first launch (and
after a package upgrade), preserving existing `workspaces/`; this keeps the
read-only `/opt` install working with Godot's `.godot` import cache. Package
`0.1.1` compares an IDE build stamp (`ide/.package_stamp`) instead of only the
semantic version, so rebuilding an unchanged version still refreshes the
user-data IDE copy. Both
packages were extracted and launched headless with a temporary data directory;
metadata, dependencies, desktop entry, icon and post-install cache hooks were
checked.

### Windows x86_64

Built on Linux with MinGW-w64 13.2 and Godot's D3D12/ANGLE build dependencies:

```text
dist/windows/GodotRetroEngine.exe          168 MB  PE32+ GUI
dist/windows/GodotRetroEngine.console.exe  184 KB  console stub
dist/windows/run.bat
dist/windows/ide/
```

The final build compiles `drivers/d3d12`, `gl_manager_windows_angle.cpp` and
copies `D3D12Core.dll`. WinRT is disabled because it requires the Windows SDK;
AccessKit is disabled when its SDK is absent. A Wine headless editor launch
completed without script/parse errors.

### macOS universal

Built on Linux with osxcross (macOS SDK 26.1) and ANGLE static libraries for
both architectures:

```text
dist/macos/GodotRetroEngine.app/Contents/MacOS/Godot  287 MB fat binary
dist/macos/run.sh
dist/macos/ide/
```

`lipo -info` reports `x86_64 arm64`; `LC_BUILD_VERSION` reports macOS 11.0
minimum. The osxcross build disables Metal (clang 18 cannot build the SDK 26.1
Metal C++ modules) and uses ANGLE/OpenGL for both slices. The module
`retro_engine` provides the small `___isPlatformVersionAtLeast` shim normally
supplied by Apple's `libclang_rt.osx.a`; `libxar`/`libtapi` are installed in
the osxcross container. The `.app` is unsigned because osxcross has no
`codesign`.

The cross-built `.app` cannot be executed on this Linux host; architecture,
bundle structure and load commands were validated with `lipo`/`otool`.

### SGDK Downloader automatic host-toolchain setup

The **Download SDKs...** dialog now runs the bundled `setup_sgdk_*` script
after extracting SGDK. The test installed the official `v2.11` source ZIP into
`user://sdks/sgdk-2.11`, called the downloader's `_install_archive()` path and
checked the probe before/after:

```text
BEFORE ready=false available=false
AFTER  ready=true  available=true
SGDK root/bin/m68k-elf-gcc, sjasm, convsym, bintos and env.sh present
```

The setup builds the host tools, writes the `m68k-elf-*` wrappers into the SDK
`bin/`, and updates the editor session's `PATH`. A regression test installed
the SDK under `.../Godot Retro Engine/...` (spaces in the path) and verified
that the downloader configures `.../godot-retro-engine/sdks/megadrive`, runs
the smoke test successfully and reports `ready=true`. The downloader passes
`--install-deps`: Linux installs Wine/Java/build tools via apt/dnf/pacman/zypper
with sudo or pkexec, macOS uses Homebrew for Wine/GNU make/Temurin JDK, and
Windows uses winget for Java. Missing dependencies are shown in the download
log with the manual command.

### BGM sequencer (0.1.6)

The BGM sequencer was validated headlessly with
`ide/tests/bgm_editor_test.gd` and the Python tools:

```text
BGM_EDITOR PASS
```

It covers: creating a song from the Audio tab, editing notes, saving the
`.retro_bgm.json` + MIDI source + descriptor, rendering and playing a real
SNES preview, reopening the saved song with a double click, importing the
saved MIDI back, importing a real KOF98 `.it` through `libopenmpt` (7 tracks,
1728 steps, 136.62 BPM fitted to the 189.7 s module length) and deleting the
descriptor/source/song/previews.

The IT → MIDI → target conversion was also checked directly:

```text
esaka.it import      0.1 s   bpm=136.62 steps=1728 tracks=7
esaka.mid export     0.3 s   25397 bytes
Mega Drive VGM      16.2 s   preview 188.14 s, 48050-byte VGM
SNES GM/IT/BRR      4.3 s   preview 188.14 s, 1506005-byte IT
```

Localization coverage now reports 521 keys for all 41 locales and
`I18N_COVERAGE_TEST PASS`.


### Resource categories (0.1.7)

Game sprites (`editor == "sprite"`) remain under **Sprites**. Generic
PNG/JPG/BMP/WebP images and unknown image files now appear under a separate
**Images** category. Double-clicking an image opens a read-only zoomed-to-fit
preview instead of treating it as a game sprite; **Open as Sprite** still
forces the sprite editor when needed.

```text
RESOURCE_CATEGORY PASS
```


### Real ROM preview via libretro (0.1.9)

The Preview tab no longer fakes a boot sequence. It executes the project's
built ROM in the installed libretro core (snes9x for SNES, genesis_plus_gx for
Mega Drive), streams real frames into the editor and injects the Inputs
editor's joypad commands. Pause, Step, +10 frames and Rewind (libretro save
states) operate on emulated frames.

```text
ROM_PREVIEW snes first=11 frozen=true stepped=true command=true log=true rewind=true texture=true stopped=true
ROM_PREVIEW megadrive first=11 frozen=true stepped=true command=true log=true rewind=true texture=true stopped=true
ROM_PREVIEW PASS
```

The KOF98 SNES ROM boots through its real "CHECKING MSU-1 SUPPORT" screen and
title; the SGDK platformer ROM runs its real gameplay. Both were exercised
through the same host/protocol used by the editor.

Command detection and screen-change pausing were checked on the real KOF98
boot:

```text
[00451] input start (mask 0x0008)
[00481] screen change after start at frame 481 (0.19)
[00481] pause ON
```

After a Start press the emulator keeps running until the real picture changes
significantly, then auto-pauses so the user can step/rewind through the actual
transition.


### On-screen pad (0.1.10)

The Preview tab now has a compact pad beside the log, using the same height so
the editor layout does not grow. The command/frame log is 72 px high, about 30%
shorter than before, and the pad sits to its right. It keeps the full SNES button count and swaps
labels with the active platform:

```text
SNES:       L X R / Y B A + START + SEL
Mega Drive: X Y Z / A B C + START + MODE
PAD_CONTROLS PASS
```

Buttons are 20-22 px with 7-9 px letters/icons. Press/release is sent to the
real libretro core; quick clicks are extended to two emulated frames so the
game always receives them. The same pad test also exercises the real SNES and
Mega Drive ROM previews with a Start press:

```text
ROM_PREVIEW ... button=true button_log=true ... PASS
```


### Real game audio (0.1.11)

The libretro helper now forwards the core's stereo PCM alongside the video
frames. The Preview tab plays it through an `AudioStreamGenerator`, and the
**Audio** checkbox enables/mutes it. Muting also tells the helper to stop
sending audio packets.

The real ROM test checks audio packets, mute and resume on both consoles:

```text
ROM_PREVIEW snes ... audio=true audio_off=true audio_on=true ... PASS
ROM_PREVIEW megadrive ... audio=true audio_off=true audio_on=true ... PASS
```

The pad layout still fits the narrow preview (minimum 686 px against a 705 px
tab) after adding the audio checkbox.


### Pad mask fix (0.1.12)

The on-screen pad and keyboard InputMap bridge were sending the libretro
button **index** instead of the button **mask**. Directions were therefore
combined with unrelated face/Select bits (Left used bits 1+2, Start used B+Y,
etc.). The tables now use `1 << button_id`, and tests assert the exact masks
for both consoles:

```text
SNES: LEFT=64 RIGHT=128 UP=16 DOWN=32
      A=256 B=1 X=512 Y=2 L=1024 R=2048 START=8 SELECT=4
MD:   LEFT=64 RIGHT=128 UP=16 DOWN=32
      A=2 B=1 C=256 X=1024 Y=512 Z=2048 START=8 MODE=4
PAD_CONTROLS PASS
```

The Mega Drive core is also initialized as a 6-button pad instead of the
default 3-button mode.


### New-project splash and Hello World (0.1.13)

New SNES and Mega Drive projects now boot with the existing Godot Engine
splash and then show a static Hello World screen. `src/main.c` starts with a
commented workflow block, and `src/assets.h` comments the `RETRO_SPLASH`
switch.

```text
NEW_PROJECT snes checks={ "splash": true, "workflow_comments": true,
  "main_splash": true, "assets_splash": true, ... } build_ok=true
NEW_PROJECT md   checks={ "splash": true, "workflow_comments": true,
  "main_splash": true, "assets_splash": true, ... } build_ok=true
NEW_PROJECT_TEST PASS
```

Captured from the real ROMs: Godot splash first, then the complete
`HELLO WORLD` screen on both SNES and Mega Drive.


### Terminal tab position (0.1.14)

The Terminal plugin now moves its main-screen button directly after **Script**.
It uses a deferred, retry-safe HBox reorder so the existing tab selection
callables keep working.

```text
TERMINAL_TAB_ORDER ["2D", "3D", "Script", "Terminal", "Game", "Asset Store", "Retro"]
TERMINAL_TEST PASS
```
