# Import compatibility matrix

This matrix is generated from the actual importer rules in
`modules/retro_engine/retro_importer.cpp`. A resource is marked
`editable` only when the IDE has a real decoder and encoder for it.

| Extension | Kind | Visual editor | Editable | Notes |
| --- | --- | --- | --- | --- |
| `.png` | image | Sprite or Stage | yes | Palette read from PNG `PLTE`/`tRNS`; indexed PNG export preserves index order. Companion `.map` is required for stage mode. |
| `.bmp` | image | Sprite or Stage | yes | Decoded by Godot; palette inferred by nearest-color extraction. |
| `.webp`, `.jpg` | image | Sprite | yes | Lossy sources are imported as pixels; use PNG for pixel art. |
| `.chr` | SNES/MD planar tiles | Sprite or Stage | yes | 2/4/8 bpp, 8x8 or 16x16 tiles. Companion `.pal` and `.map` auto-discovered. |
| `.pic` | PVSnesLib gfx4snes tile blob | Stage | yes | Treated as raw planar tile data (usually 4bpp). Companion `.pal`/`.map` auto-discovered. |
| `.pal` | CGRAM (SNES) / CRAM (MD) | Palette | yes | SNES 15-bit BGR555 little-endian; MD 9-bit 0BGR big-endian. |
| `.map` | SNES tilemap / MD nametable | Stage | yes | 16-bit entries; map width inferred (32/64); adjustable in the Stage editor. |
| `.res` | SGDK resource script | Code/Resources | yes (text) | Compiled by `rescomp.jar` as part of the real build. The IDE does not fake its output. |
| `.sff` | MUGEN sprite bank | Animation (read-only) | no | Recognized; the project's own SFF converter remains authoritative. Generated `.chr/.pal/.inc` files are editable. |
| `.air` | MUGEN animation data | Animation (read-only) | no | Text can be opened in the code editor; no visual SFF/AIR timeline conversion. |
| `.c`, `.h`, `.cpp`, `.hpp` | C/C++ source | Code | yes | Indexed for functions/includes; save creates a timestamped backup. |
| `.asm`, `.s`, `.inc` | assembly source | Code | yes | Indexed for labels; save creates a backup. |
| `.mid` | MIDI | Audio | yes | Imported as BGM; converted with FluidR3_GM to IT/SNESMOD for SNES and to a YM2612 FM VGM/XGM2 for Mega Drive. |
| `.it` | Impulse Tracker | Audio | yes | SNES passes it to `smconv`; Mega Drive renders it to an XGM2 PCM loop. |
| `.wav`, `.mp3` | samples/music | Audio | yes | SFX become BRR (SNES) or XGM2 PCM (MD); BGM becomes a looped sample. |
| `.vgm`, `.xgm`, `.xgm2` | chip music | Audio | no | Recognized; the SDK converter remains authoritative. |
| `.brr` | SNES sample | Audio | no | Recognized; use WAV/SFX synthesis for new samples. |
| `.spc` | SPC snapshot/driver | Audio | no | Recognized. |
| `.msu` | MSU-1 data | Audio | no | Recognized. |
| `.json` | data | none | no | Metadata only. |
| `.sfc`, `.smc`, `.md`, `.gen` | ROM | ROM probe | no | Header/checksum/platform inspection. |
| `.zip`, `.7z`, `.rar` | archive | none | no | Ignored by scan. |
| `.bin`, `.o`, `.obj` | binary | none | no | Ignored unless part of a recognized resource pair. |

## Working copies and Godot's importer

Imported projects are copied (by default) to `<ide>/workspaces/<name>`, inside
the IDE's own Godot project. `RetroImporter` writes a `.gdignore` marker into
the working copy before copying any files, and the IDE keeps one at the
workspace root as well. The plugin reads project files through absolute paths,
so this does not change how assets are loaded.

The marker matters for native build outputs: Godot ships a Wavefront OBJ
importer that claims every `.obj` file. SNES toolchains (WLA-DX, `816-tcc`)
emit binary `.obj` objects with the same extension, so Godot would otherwise
parse multi-megabyte binaries as text, print hundreds of `Unicode parsing
error` lines and stall the first filesystem scan. With `.gdignore` in place the
editor never touches those files.

## Build system detection

1. A `Makefile.pvsnes` file forces `pvsneslib` and target `pvsnes`.
2. Makefile text containing `PVSNESLIB_HOME` or `snes_rules` → `pvsneslib`.
3. Makefile text containing `wla-65816`, `wlalink`, `wla-spc700` → `wla-dx`.
4. Makefile text containing `makefile.gen`, `genesis.h`, `$(GDK)` or `SGDK` → `sgdk`.
5. A `hdr.asm`/`linkfile` plus `.sfc` layout → SNES.
6. Otherwise → `generic` Make.

Platform hints from the UI override auto-detection when needed.

## SNES resource layout observed in reference projects

- **Daniel do Bolo's Adventure** (`daniel_snes`): raw WLA-DX assembly, PNG masters in `assets/`, generated `src/gen/*.chr`, `*.map`, `*.pal`; 16x16 background tiles, 4bpp sprites. Imported as `wla-dx`.
- **Side Arms** (`sidearms_pc_engine_snes/port`): PVSnesLib C + assembly, `.png` masters converted to `.pic/.pal/.map` by `gfx4snes`, `.asm` includes the binaries. Imported as `pvsneslib`.
- **KOF '98 port** (`kof98_port_snes`): PVSnesLib C + assembly; `Makefile.pvsnes` target; generated `build/gen_fight/*.chr`, `*_pal.bin`, metasprite `.inc`, SFF/AIR sources. Imported as `pvsneslib` with target `pvsnes`.

## Mega Drive resources

- SGDK `.res` lines (`SPRITE`, `TILESET`, `MAP`, `PALETTE`, `IMAGE`, `XGM`, `WAV`, `BIN`) are parsed only as text; the real `rescomp.jar` performs compilation.
- Tiles are 8x8, 4bpp, interleaved planes; palettes are 4x16 CRAM entries; nametable words are big-endian.
- `SPRITE` exports write an indexed PNG plus a `.res` line compatible with the SGDK resource compiler, without rewriting unrelated lines.
- Stage exports write a tileset PNG and a full rendered map PNG, then emit
  native `TILESET`/`MAP`/`PALETTE` lines. `rescomp` builds the VDP nametable from
  the map image; the IDE does not fabricate a nametable binary. Images are
  quantized to 64 colors for CRAM when needed.

## Input map files

The editor stores its visual input map in `.retro/editor/input_map.json`. It is
never injected into source files. Explicit exports produce:

- `retro_input.h` — PVSnesLib C header with `KEY_*` masks, state enum and
  `RetroInputAction` table.
- `retro_input.inc` — WLA-DX table with `.dw` masks and `.db` state/next/flags/priority.
- `retro_input_md.h` — SGDK header with `BUTTON_*` masks and the same state table.

All masks were compiled/assembled against the real SDK headers during
validation.

The optional **State machine C** action additionally writes:

- `retro_state_machine.h` — `retro_sm_init/update/tick/state/animation_end/last_action/force_state/frame`;
- `retro_state_machine.c` — polling matcher using `RETRO_INPUT_FLAG_HOLD`,
  priority ordering, target state, pending next state and animation-duration
  auto transitions.

The **Visual state graph** export writes the same standalone runtime names, but
from a graph model:

- node enum + duration table;
- `RetroCondition { mask, mode }`, where mode is pressed/held/released;
- `RetroTransition { from, to, cond_start, cond_count, op, cooldown, priority, auto_transition }`;
- edge-aware `retro_sm_update()`, cooldown/decrement + duration auto transition
  in `retro_sm_tick()`, and explicit `retro_sm_animation_end()`.

Both generated headers are SDK-neutral (`retro_u8`/`retro_u16`/`retro_node`), so the graph
runtime compiles for PVSnesLib and SGDK without SDK-specific includes.

Both the SNES and SGDK variants compile against their respective SDK; the
generated C source is SDK-neutral except for the `u8`/`u16` typedefs supplied by
`<snes.h>`/`<genesis.h>`.

## Hitbox tables

`RetroAnimation` exports per-frame collision data independently of animation
frames:

- SNES `.inc`: flat table rows `state, frame, type` followed by `x, y, w, h`;
  type `0` is hurtbox and `1` is hitbox.
- SGDK `.h`: `RetroHitbox { state, frame, type, x, y, w, h }` with
  `RETRO_HITBOX_HIT`/`RETRO_HITBOX_HURT`.

Boxes are stored relative to the animation frame origin. The collision preview
is an AABB test between one character's hitboxes and the other's hurtboxes (in
both directions).

## MUGEN AIR/CNS

- `.air` is parsed as text: actions, frame lines, `Clsn1`/`Clsn2` defaults and
  per-frame boxes, offsets, duration and flips.
- Import is explicit: the user selects an AIR action and a target animation
  state. That state's frame list is replaced with the AIR action frames.
- Export writes a valid AIR action with `Clsn1`/`Clsn2` blocks from the current
  animation state.
- `.cns` HitDefs are parsed for `state`, `damage`, `pausetime`,
  `guard.pausetime`, `ground.hittime`, `air.hittime`, `ground.velocity`,
  `guardflag`, `hitflag`, `attr`, `animtype`, `priority` and `ID`.
- HitDef arithmetic/`ifelse`/`floor` expressions are evaluated.
  `var(...)`/`Helper(...)` use 0 and `fvar(...)` uses 1 as safe defaults; the raw
  expression is kept for review. Unknown functions fall back to 0 and are marked
  in `damage_error`.

## MUGEN states and fight graph

`RetroMugenImport::parse_states(cns, air)` reads every `[Statedef N]` and
associates:

- `anim` (the action used by the state) and the first `ChangeAnim`;
- `[State N, ChangeState]` blocks with their target `value` and triggers;
- `[State N, HitDef]` blocks, including parsed damage, hitstop, hitstun,
  blockstun, guard/hit flags and priority;
- AIR action, frame count, hitbox/hurtbox counts and total duration.

`import_state(cns, air, N, animation, target_state)` replaces the frames of one
explicit animation state with the AIR action of state N. No automatic state
renaming occurs.

`auto_map_states(parsed)` maps every unique `Statedef` to a project state name
(`IDLE`, `WALK`, `WIN_181`, `ATTACK_250`, ...). `import_mapped_states()` imports
all mapped AIR actions in one pass and sets looping for idle/walk/crouch/jump/
block states.

`parse_commands(cmd)` reads `[Command]` blocks and compiles sequences:

- direction tokens `U/D/F/B` and diagonals `DF/DB/UF/UB`;
- buttons `x/y/z/a/b/c` mapped to attack A/B/C;
- `~`/`/` release, `$`/`>` hold, repeated prefixes such as `/$F`;
- simultaneous tokens such as `x+y` become one sequence step;
- the `time` field becomes the runtime sequence window.

`build_fight_graph(parsed, mapping, input, max_nodes = 0, commands)` produces a
`RetroStateGraph` plus move profiles:

- every mapped state becomes a node by default (`max_nodes = 0`); a positive
  value is an optional editable-graph cap;
- `ChangeState` targets are added as needed;
- `.cmd` named commands become sequence conditions; simple button commands fall
  back to direct input actions;
- `AnimTime`/`AnimElem` triggers become auto transitions;
- duplicate edges and self-transitions are removed;
- unmapped variable/helper/random triggers are skipped and reported as warnings.

The graph metadata contains `source = "mugen"`, so validation does not report
every generated state as missing from the animation list. The generated runtime
uses 16-bit node/transition indices, so 250+ node graphs are valid.

## Native Godot scenes and 3D references

The Native tab imports the **currently edited Godot scene**, or the project's
Jogo/Game main scene via **Import game scene**, without modifying the source:

- `Sprite2D`/`Sprite3D`/`TextureRect` → `RetroSprite` + PNG/`.chr`/`.pal`/`.inc`/SGDK `.res`;
- `AnimatedSprite2D`/`AnimatedSprite3D` → packed atlas + `RetroAnimation` + native frame tables;
- `Control`/`Label`/`Button`/`Panel`/`TextureRect`/`ItemList`/`OptionButton`/`TabContainer`/`ProgressBar` → UI widget manifest (rect, text, font size, colors, items/tabs, script);
- `Marker2D`, `Area2D`, bodies, collision shapes/polygons, raycasts, audio/animation/timer/light/path/line/polygon/canvas nodes → generic node manifest;
- attached GDScript/C# scripts → script manifest (class/base, exports, constants, methods, signals) + copied source under `scripts/`;
- `Camera2D`/`Camera3D`, rectangle collisions and `MeshInstance3D` bounds → `*_scene.h/.json` actor table;
- `TileMapLayer` + `TileSetAtlasSource` → semantic `RetroStage` (atlas tiles, flips, map);
- rendered 2D/3D view → `RetroStage` tilemap (GPU or software fallback);
- 3D view from several angles → packed sprite sheet + `TURN` animation.

The UI/node/script data is written to `<scene>_port.h/.json/.md`. Game Build
copies this bundle into the generated console project under `port/`. Scripts are
ported manually; they are not transpiled to C.

Captures use a script-stripped duplicate of the scene. Headless capture uses a
software renderer for 2D canvas items and flat-shaded 3D triangles; the editor
GPU capture remains higher fidelity.

`superfx` and `svp` profiles are references for 3D budgets:

- Super FX / Star Fox: MARIO Chip 1 / GSU-1, 10.74 MHz, 8 Mbit ROM, 256 Kbit
  work RAM, 224x192 4bpp frame buffer, ~20 fps target.
- SVP / Virtua Racing: SSP160x DSP, 23 MHz, 2 MB ROM, 128 KB DRAM, 2 KB IRAM,
  ~600 polygons/frame at 15 fps, 16 colours.

They generate `*_3d_profile.h/.json` with the scene dimensions, bake frame count,
target fps, palette/tile budgets and `RetroNativeActor` table, plus a
`3D_HANDOFF.md`/JSON that documents the base-console assets and the external
GSU/SVP toolchain path. They are budget references, not GSU/SVP execution or
cartridge build support. See
`docs/NATIVE_BRIDGE.md` for the full workflow.

## Generated game builds

**Game Build...** in the Build tab supports native→SNES, native→Mega Drive,
SNES→Mega Drive and Mega Drive→SNES. It selects a stage from the last native
import or from the active project's stage resources, retargets tilemap words and
exports a minimal PVSnesLib/SGDK project. The optional **Godot logo fade in/out**
converts the same Godot splash image to a 16-colour tilemap and fades it on a
black screen before the game stage. See `docs/GAME_BUILD.md`.

## Deliberately unsupported automatic conversions

- Arbitrary C → visual scene graph.
- SFF/AIR → visual animation, without the project's converter.
- Audio audition/editing.
- Cycle-accurate PPU/VDP behaviour in preview.
- Debugger memory/breakpoints over emulator-specific private protocols.
