# Architecture

## Why a fork plus a module

Godot already provides the editor shell, docks, theme, file dialogs, text editor,
scene tree, inspector patterns and a stable C++ extension mechanism. Rebuilding
those would add risk without adding console capability. The fork therefore
changes the engine only in the places that need native access:

```
core/, editor/, scene/, ...         upstream 4.7.2-stable (repository root)
modules/retro_engine/      our C++ module (built directly into the fork)
ide/addons/retro_engine/           editor workspace (GDScript)
```

The module is registered at scene level, so identical functionality is
available in the editor, headless validation and future CLI tools.

## Module classes

| Class | Responsibility |
| --- | --- |
| `RetroSDK` | PVSnesLib/SGDK probing, toolchain readiness, console limits, emulator candidate discovery |
| `RetroProject` | serialisable project metadata, working path, resources, sources, associations |
| `RetroImporter` | Makefile/SDK detection, resource classification, isolated working copies |
| `RetroGraphics` | SNES/MD planar tile codecs, BGR555/RGB333 palettes, tilemaps, indexed PNG I/O, palette extraction |
| `RetroSprite` | sprite document, frames/hitboxes, SNES and SGDK export |
| `RetroStage` | tile map document, rendering, layers, collisions, SNES and SGDK export |
| `RetroAnimation` | state/frame timelines, per-frame hit/hurtboxes, AABB collision test, hitbox tables, `.inc` and C header export |
| `RetroInputMap` | console button masks, action list, hold/priority, state/next associations, PVSnesLib/WLA-DX/SGDK exports, optional C state-machine generator |
| `RetroStateGraph` | visual state graph, compound conditions, cooldown/priority, animation-duration auto transitions, standalone C runtime generator |
| `RetroHitboxIO` | MUGEN AIR/CNS parsing, AIR action import/export, hitbox/hurtbox exchange |
| `RetroCollisionRuntime` | move profiles, generated hitbox tables, AABB hit/block checks, hitstop and invulnerability runtime |
| `RetroMugenImport` | Statedef/ChangeAnim/ChangeState/HitDef parsing, automatic state mapping, batch AIR import, .cmd sequence compilation, fight-graph generation |
| `RetroNativeBridge` | Godot Image/Texture/2D/3D scene capture -> RetroSprite, RetroAnimation, RetroStage, scene C table, UI/node/script port bundle and Super FX/SVP reference manifests |
| `GameBuild` | native/cross-platform SNES/MD project generation, C asset tables, native port bundle copy, optional Godot-logo fade splash, audio resource integration |
| `ProjectTemplates` | new buildable/runnable SNES (PVSnesLib) and Mega Drive (SGDK) starter projects with a 16-colour demo screen, editable sources and art assets |
| `ProjectChecks` | pre-build coherence checks for selected platform, project platform/mode, build system, SDK path, export/3D profiles and Game Build source mode |
| `I18n` | editor-locale translations for the Retro UI (pt-BR/pt-PT + English fallback), with structured check messages |
| `AudioPipeline` | Python-backed real audio conversion: MIDI/IT/WAV/MP3 -> IT/SNESMOD, VGM/PSG/XGM2, BRR and PCM SFX; previews |
| `AudioEditor` | BGM/SFX import, SFX synth parameters, device preview and project asset persistence |
| `RetroBuilder` | threaded real `make` execution, log streaming, diagnostics, ROM discovery |
| `RetroEmulator` | emulator detection/launch, ROM header probe, debug flag capability |
| `RetroCodeIndex` | C function / assembly label index and code↔asset associations |
| `RetroHardware` | static resource estimation and limit checks |

## Data flow

### Import
```
directory
  -> detect_build_files()
  -> _detect_platform()       PVSnesLib | WLA-DX | SGDK | generic
  -> scan resources
       -> classify editable/read-only
       -> companion .pal/.map discovery
       -> PNG dimensions/palette metadata
  -> copy selected resources/sources to working copy
  -> .retro/project.json
```

No source file is rewritten by import.

### Editor animation and stage previews

The **Anim** tab renders a console-shaped preview driven by the real animation
document: `RetroAnimation.sample(state, time)` selects the frame, while
`RetroSprite.render_frame()` crops the exact sprite region. The preview
auto-plays at 60 Hz, follows the timeline playhead, shows hitboxes/origin and
falls back to cycling the sprite sheet when a state has no frames yet
(clearly labelled). **Frames from sprite** turns the current sprite frames
into animation frames without re-importing art.

The **Cen** tab plays the same stage data used by export:
`StageCanvas` renders the base map plus every visible authored layer with its
own parallax factor (`layer_scroll(index)`), clamps scroll to the world size,
and overlays the selected animation/sprite. **Animate scroll** drives the
preview from the stage `scroll` speed (or the px/s control), looping at the
world edge without mutating the document. Painting pauses playback so tile
editing stays stable.

### Conversion
```
PNG / .chr / .pic / .pal / .map
  -> RetroGraphics decode (planar / palette / tilemap)
  -> editable Image + PackedColorArray + map bytes
  -> user edits
  -> RetroGraphics encode
  -> .chr .pal .map / indexed PNG / .res
```

The SDK converters remain authoritative for formats they own (for example
`gfx4snes` produces `.pic` from a PNG in the PVSnesLib workflow, and
`rescomp.jar` compiles SGDK `.res` files). The IDE writes source assets in the
same shapes those tools consume; it does not replace the SDK linker.

### Build
```
RetroProject
  -> RetroBuilder (thread)
  -> env PVSNESLIB_HOME=... | GDK=...
  -> cd working_copy && make -f build_file target -jN
  -> streamed stdout/stderr
  -> diagnostics + ROM discovery + size
  -> .retro/project.json update
```

### State machine generation
```
RetroInputMap (actions + animation states)
  -> retro_input.h        masks + RetroInputAction table
  -> retro_state_machine.h API
  -> retro_state_machine.c priority/hold matcher + pending transition
  -> game calls retro_sm_update() + retro_sm_tick() each frame
  -> retro_sm_tick() applies animation-duration transitions
  -> game may call retro_sm_animation_end() for an explicit transition
```

The editor State Simulator mirrors this matcher for keyboard/gamepad-driven
preview without compiling a ROM.

The **Preview** tab executes the project's actual built ROM in a libretro
core. `tools/libretro_preview.py` is a thin frontend over the installed
snes9x/bsnes or genesis_plus_gx core: it streams the real emulator frames to
`rom_preview.gd`, accepts joypad presses derived from the Inputs editor and
exposes pause, single-frame step, +10 frames and save-state rewind. There is
no scripted boot or fake title screen: the first frame is whatever the ROM's
own reset vector and boot code produce. Building the project is required, and
the real emulator remains the source of truth.

Real preview requirements are the same as the existing Python audio tools plus
an installed libretro core:

- `python3` with `numpy`;
- `snes9x_libretro.so` or `bsnes_libretro.so` for SNES;
- `genesis_plus_gx_libretro.so`, `picodrive_libretro.so` or
  `blastem_libretro.so` for Mega Drive.

The editor searches the standard RetroArch core directories (including the
Flatpak path and `retroarch.cfg`'s `libretro_directory`). The helper also
streams the core's PCM audio over the same socket; the Preview tab feeds it to
an `AudioStreamGenerator`, and the **Audio** checkbox mutes the real game sound
without stopping emulation. The focus remains the real video, input, pause,
frame step and rewind behavior.

A compact on-screen pad sits beside the Preview log so the layout does not
grow. It always shows the full action set (D-pad, six face/shoulder buttons and
Start plus Select/Mode), but relabels the buttons for the active console:
SNES uses L/X/R and Y/B/A with Select; Mega Drive uses X/Y/Z and A/B/C with
Mode. Press/release events are injected into the running libretro core, and
quick taps are held for at least two emulated frames so they are never lost.

The Hitbox Timeline editor stores `hitboxes[]` per animation frame. Each box has
`rect` + `type` (`hit`/`hurt`). AIR import replaces the frames of a explicitly
chosen animation state with the selected AIR action; CNS HitDefs are applied to
the selected state as move properties. The collision preview calls
`RetroAnimation.collision_test()` with two state/frame/position triples and draws
the intersecting world-space rectangles. The timeline can follow the Simulator
tab state/frame so the displayed boxes are the boxes the runtime state machine
would expose.

**Game Build...** in the Build tab calls `game_build.gd`. It selects a stage
from the last native import or from the active project's stage resources,
retargets the tilemap words for the target console, emits a minimal PVSnesLib or
SGDK project, and lets `RetroBuilder` build the real ROM. Four modes are
supported: native→SNES, native→Mega Drive, SNES→Mega Drive, Mega Drive→SNES.
The optional splash converts the Godot logo to a 16-colour tilemap and fades the
palette in/out before the game stage. Generated builds live under `builds/` and
never modify the source project.

The Native tab (`native_bridge.gd`) traverses the scene currently open in the
Godot editor, or the project's `application/run/main_scene` via **Import game
scene**. `Sprite2D`/`Sprite3D`/`TextureRect` textures become `RetroSprite`
documents, `AnimatedSprite2D`/`AnimatedSprite3D` frames are packed into an atlas
and exported as `RetroAnimation`, and camera/collision/mesh nodes contribute to
a generated `RetroNativeActor` scene table. It also exports a portable
`<scene>_port.h/.json/.md` bundle with UI widget rects/text, other scene nodes,
script metadata and copied script sources. Generated files are written under
`native/<scene>/` inside the retro project and registered as normal project
resources; Game Build copies the port bundle into `port/`.

`RetroNativeBridge.import_stage_image()` quantizes a rendered view to 16 colours,
extracts unique 8x8 tiles, builds a `RetroStage` and writes SNES `.chr/.pal/.map`
plus SGDK PNG/`.res` assets. `TileMapLayer` is also converted semantically from
`TileSetAtlasSource` cells (atlas regions and flips) into a `RetroStage`. The
editor uses a `SubViewport` to render a copy of a 2D or 3D scene; **Bake 3D
sprite** rotates the copy and captures a frame sequence into a sprite sheet. The
copy has scripts removed and processing disabled. In headless runs, or when the
viewport has no image, a software renderer draws 2D canvas items or triangle
meshes with a depth buffer. Neither operation modifies the source scene.

3D profiles (`superfx` and `svp`) store Star Fox / Virtua Racing reference
budgets (clock, ROM/RAM, frame buffer, target fps, palette and tile/frame
budgets) and generate `*_3d_profile.h/.json`, plus a `3D_HANDOFF.md`/JSON that
lists the generated base-console assets and the external GSU/SVP toolchain path.
They deliberately do not emulate the GSU or SVP DSP: the output is a pre-rendered
2D asset set for the base console, with the profile acting as a design budget and
metadata source.

The MUGEN tab (`mugen_editor.gd`) parses a `.cns` + `.air` pair through
`RetroMugenImport`. `parse_states()` returns one record per `Statedef` with its
`ChangeAnim`, `ChangeState`, `HitDef` blocks, AIR action/frame/hitbox counts and
a suggested target state. The mapping table is editable and persisted to
`.retro/editor/mugen_mapping.json`.

`auto_map_states()` maps every unique `Statedef` to a unique project state
name. `import_mapped_states()` batch-creates/updates those animation states from
their AIR actions and chooses looping for idle/walk/crouch/jump/block states.

`build_fight_graph()` creates nodes for all mapped states when `max_nodes = 0`
(the default); a positive limit is still available for a smaller GraphEdit
view. `ChangeState` targets are added as needed. `.cmd` files are parsed into
named command definitions; multi-step motions (`QCF_x`, `236236AC`, ...) become
sequence conditions that the generated runtime matches against a 32-entry input
history. Simple button commands (`holdx`, `~x`, `x/a/y/b/z/c`) fall back to direct
input actions. `AnimTime`/`AnimElem` triggers become duration-based auto
transitions. The resulting graph replaces the StateGraph tab, and `moves[]`
updates the collision runtime move profiles. Unsupported variable/helper/random
triggers are reported as warnings instead of silently dropped.

The generated state-machine runtime uses `retro_node` (`unsigned short`) for
nodes and transitions, so a full 250+ state character no longer wraps around the
old 8-bit limit. Sequence matching keeps the last 32 input events and enforces
the `.cmd` `time` window.

The collision runtime generator combines the animation hitbox tables with move
profiles (`damage`, hitstop, hitstun, blockstun, invuln, guard, priority, HitDef
ID, pushback). The generated C API exposes `retro_col_check()` and
`retro_col_apply()`; hitstop and invulnerability countdowns are decremented by
`retro_col_tick()`. States whose names contain `BLOCK`/`GUARD` are inferred as
guard states, repeated hits with the same non-zero HitDef ID are rejected, and
pushback is applied away from the attacker. Collision state/box indices are
16-bit.

The visual graph backend (`RetroStateGraph`) generates a second, standalone
runtime with condition tables, cooldown counters and `pressed`/`held`/`released`
semantics. Graph nodes are states; edges carry ALL/ANY condition sets and an
optional auto transition driven by the node's animation duration.
The generated files are separate from the game's existing `main.c` and scene
code. No automatic source rewrite is performed.

### Run
```
ROM -> RetroEmulator.probe_rom()
    -> platform detection
    -> emulator candidates for that platform
    -> create_process(executable, args)
```

## Threading model

`RetroBuilder` is a `Node` with a `Thread`. Signals are connected by the UI with
`CONNECT_DEFERRED`, marshalling log lines and the final result onto the main
thread. `cancel()` kills the real process. Destruction waits for the thread.

## Preservation rules

1. Import copies by default. The source path is recorded for traceability.
2. Editor-only files live under `.retro/`.
3. Editing source in the Code panel writes a timestamped backup under
   `.retro/backups/` before saving.
4. Export operations write new files; replacing project files is an explicit
   user action (usually by exporting into the project's asset directory).
5. Read-only formats are never advertised as editable.

## Platform abstraction

Console differences are in data and limits, not duplicated editors:

- Tile codecs and palette formats are parameters (`megadrive` boolean).
- `RetroHardware`/`RetroSDK.get_limits()` provide mode, layer, color, sprite and
  VRAM rules.
- Build command construction branches only on `build_system` and env var.
- The UI mode selector reconfigures limits and labels.

## Adding a platform backend

1. Add probe + limits in `retro_sdk.cpp`.
2. Add codec parameters in `retro_graphics.cpp` if the tile format differs.
3. Add build env/target handling in `retro_builder.cpp`.
4. Add emulator candidates in `retro_sdk.cpp`.
5. Extend `RetroHardware` checks and the mode selector.
6. Map new console buttons in `RetroInputMap` (`KEY_*`/`BUTTON_*`) and mirror
   them in the Inputs editor.
No editor widget has to be duplicated.
