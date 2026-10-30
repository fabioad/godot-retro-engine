# Native Godot → SNES / Mega Drive bridge

The `Native` tab turns ordinary Godot scenes and resources into retro assets. It
does not replace the Godot editor: sprites, animations, 2D/3D scenes, UI scenes,
scripts and the project main scene are authored with the normal Godot tools,
then converted into the files consumed by the PVSnesLib / SGDK projects.

## What is imported

| Godot node/resource | Retro output |
| --- | --- |
| `Sprite2D`, `Sprite3D`, `TextureRect` | `RetroSprite` + PNG, `.chr`, `.pal`, `.inc`, SGDK `.res` |
| `AnimatedSprite2D`, `AnimatedSprite3D` | Packed sprite atlas + `RetroAnimation` state/frame table + `.inc`/`.h` |
| `Camera2D`, `Camera3D` | actor/Camera metadata in `*_scene.h/.json` |
| `CollisionShape2D` (rectangle), `CollisionPolygon2D` | collision bounds in the scene actor table |
| `MeshInstance3D` | 3D actor bounds; source for 3D baking |
| `TileMapLayer` | semantic `RetroStage` from TileSetAtlasSource cells (tile atlas, flips, map) plus bounds metadata |

Atlas textures are cropped through `AtlasTexture.region`. Animated sprite
frames with different sizes are packed into a regular cell grid.

## Full port bundle — UI, other nodes, scripts and game scene

The Native tab has a **Game scene** row. It defaults to
`ProjectSettings.application/run/main_scene` (the scene used by Godot's
Jogo/Game tab); **Use current** fills it from the scene currently open, and
**Import game scene** opens that scene and runs the full export. The three
**Port bundle** checkboxes control the exported layers:

- **UI layout** — every `Control` widget with its global rect, type, text,
  font size, colors, texture, items/tabs and script;
- **Other nodes** — markers/spawns, bodies, areas, collision shapes and
  polygons, raycasts, audio players, animation players, timers, lights, paths,
  lines, polygons and canvas layers;
- **Scripts** — every attached GDScript/C# source path, class/base type,
  exported properties, constants, methods and signals. The source file is
  copied to `<scene>/scripts/` as a reference; it is **not transpiled**.

The import writes a portable bundle next to the generated sprites/tilemaps:

```text
native/<scene>/
  <scene>_port.h      # C structs/arrays for actors, widgets, nodes and scripts
  <scene>_port.json   # full manifest for tools and future re-import
  <scene>_port.md     # human-readable port report + checklist
  scripts/*.gd        # copied GDScript references (opt-in via the Scripts checkbox)
```

Paths in the manifest are relative to the retro project where possible, so the
bundle can be copied with the game build. The header is plain C with
`RETRO_PORT_*` count macros and `RetroPortActor`, `RetroPortWidget`,
`RetroPortNode` and `RetroPortScript` tables. It compiles with both `816-tcc`
and the SGDK m68k GCC. Scripts are a porting aid, not a GDScript-to-C compiler.

**Game Build...** copies the latest bundle into the generated project:

```text
builds/<name>/
  PORTING.md
  port/<scene>_port.h
  port/<scene>_port.json
  port/<scene>_port.md
  port/scripts/*.gd
```

## Godot InputMap import

The Input Mapping editor has an **Import Godot InputMap** button. It merges the
project's `InputMap` actions into the retro input map:

- directions (`ui_left`, `move_left`, `_left`, ...) → console Left/Right/Up/Down;
- jump/fire/attack/guard/throw/shoulder/start/select names → the matching SNES
  and Mega Drive buttons;
- `ui_accept` updates the existing `start` action, `ui_cancel` updates `select`;
- keyboard and joypad events are copied into the IDE/test bindings;
- existing state, next-state, hold and priority associations are preserved.

## Capture and 3D baking

- **Capture background** renders a copy of the open 2D or 3D scene in a
  `SubViewport` and converts the image into a console tilemap. In headless runs,
  or when the viewport cannot provide an image, a software fallback renders
  `Sprite2D`/`AnimatedSprite2D`/`TextureRect`/`ColorRect`/`TileMapLayer` (2D)
  or `MeshInstance3D` triangles with a depth buffer (3D):
  - palette quantization (default 16 colors);
  - unique 8x8 tile extraction;
  - SNES `.chr`/`.pal`/`.map`/`.inc` and SGDK PNG/`.res`;
  - configurable capture size.
- **Bake 3D sprite** rotates a copy of the 3D scene around its center and
  captures multiple frames into a sprite sheet. The result is a normal
  `RetroSprite` + `RetroAnimation` (`TURN` state), usable as a pre-rendered
  billboard/sprite animation on both consoles.

The source scene is never modified. Captures instantiate a duplicate with
scripts removed and processing disabled, so editor/UI scripts do not run during
capture. AnimatedSprite frame state is preserved from the duplicated resource.

## 3D reference profiles

The 3D pipeline keeps the **3D → 2D sprite** conversion, but can target the
budgets of the two reference 3D cartridge chips:

### Super FX / GSU — Star Fox reference

- reference chip: MARIO Chip 1 / GSU-1;
- 10.74 MHz (MARIO Chip 1), 8 Mbit ROM, 256 Kbit work RAM;
- Star Fox action frame buffer: 224x192, 4 bpp, roughly 20 fps target;
- profile defaults: 224x192 capture, 16 colors, up to 16 bake frames,
  1024-tile budget.

### Sega Virtua Processor — Virtua Racing reference

- SVP / Samsung SSP160x DSP at 23 MHz;
- 2 MB ROM, 128 KB DRAM, 2 KB IRAM;
- roughly 600 polygons/frame at 15 fps with 16 colors;
- profile defaults: 320x224 capture, 16 colors, up to 16 bake frames,
  2048-tile budget.

Selecting a profile in the Native tab writes its settings to the project
metadata and generates:

```text
<scene>_3d_profile.h
<scene>_3d_profile.json
```

The header exposes `RETRO_3D_CHIP_*`, capture size, bake frame count, target
frame rate, palette size, tile budget and the actor table. The JSON contains the
reference facts, scene, actors, bake data and budget warnings. A `3D_HANDOFF.md`
and `3d_handoff.json` also describe the generated base-console assets and the
external GSU/SVP toolchain path for a real co-processor cartridge build.

**Important:** these profiles are **reference budgets and asset metadata**.
This bridge does not execute GSU or SVP code and does not build Super FX/SVP
cartridge ROMs. The generated sprite sheets, tilemaps, scene table, profile
header and handoff document are complete for the base SNES/Mega Drive; using a
real co-processor requires the corresponding Super FX or SVP toolchain and
cartridge build flow.

References:

- [A Super FX FAQ](http://anthrofox.org/starfox/superfx.html)
- [Super FX — Wikipedia](https://en.wikipedia.org/wiki/Superfx)
- [Sega Virtua Processor — Sega Retro](https://segaretro.org/Sega_Virtua_Processor)
- [SVP technical notes](https://notaz.gp2x.de/docs/svpdoc.txt)

## Outputs and project registration

Generated files are written under the retro project (default `native/<scene>/`)
and registered in the project resource list with their source scene recorded in
`native_source`. The original Godot `.tscn`, textures and scripts are not
modified.

The Native tab stores its last import and port bundle in:

```text
.retro/editor/native_links.json
```

The JSON now also contains `game_scene`, the three include flags and the last
`port` result. Game Build reads this file to copy the bundle into the generated
project.

## Reproduce

```bash
scripts/test_native_bridge.sh
```

The test builds a synthetic Godot scene with `Sprite2D`, `AnimatedSprite2D`,
`Label`, `Button`, `Marker2D`, `Area2D`, `CollisionShape2D`, a real GDScript and
`MeshInstance3D`, exports a Super FX and an SVP profile, and compiles the
generated scene/profile/port headers with `816-tcc` and SGDK GCC 13.2. It also
converts a rendered image into a 2D tilemap, assembles the generated `.inc`
with `wla-65816`, and checks that Game Build copies the port bundle.

```bash
"$BIN" --headless --path "$ROOT/ide" --script res://tests/input_import_test.gd
```

## Known limits

- 3D is pre-rendered to sprites; there is no real-time 3D runtime for the base
  consoles in this bridge.
- Super FX/SVP profiles are references, not emulation or toolchains.
- AnimatedSprite frames are packed into one atlas; extremely large frame sets
  can exceed the platform tile budget. Warnings are emitted and extra tiles fall
  back to tile 0.
- TileMapLayer semantic import supports `TileSetAtlasSource` tiles. Scene
  collection sources, transposed cells and advanced terrain/alternative-tile
  semantics are not fully reconstructed; the rendered background capture remains
  the fallback.
- The software 3D fallback shades flat triangles and ignores textures, skeletal
  skinning and custom shaders. The editor GPU capture remains higher fidelity.
