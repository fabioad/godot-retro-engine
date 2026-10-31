# Godot Retro Engine

A specialized fork of **Godot Engine 4.7.2** for building **native SNES and Sega Mega Drive games** with **PVSnesLib 4.6** and **SGDK 2.11**.

This is not an emulator and not a mock console. The editor imports existing SDK projects, edits real console resources, invokes the real SDK toolchains, produces real ROMs, and launches them in real emulators.

```
                 Godot editor UI (fork)
                          |
        +-----------------+------------------+
        |                                    |
  C++ retro_engine module              GDScript addon
  - SDK detection                      - Retro workspace
  - project importer                   - sprite / stage / animation UI
  - tile & palette converters          - palette editor
  - build runner (threaded)            - code browser
  - emulator launcher                  - hardware monitor
  - resource estimates
        |                                    |
        +-----------------+------------------+
                          |
              PVSnesLib 4.6 / SGDK 2.11
                          |
                  native .sfc / .md ROM
                          |
               Mesen / bsnes / Snes9x / BlastEm
```

## What is implemented

### Fork and module
- Pinned Godot **4.7.2-stable** source fork, built as the Linux editor.
- C++ module `modules/retro_engine`, built directly with the engine from this repository. It is the same module the editor uses and the headless harness tests.
- Editor plugin `ide/addons/retro_engine` adds a **Retro** main workspace and a global toolbar with platform selection, Build and Run.

### SDK integration
- Auto-detects PVSnesLib by validating `devkitsnes/snes_rules`, `pvsneslib/lib/*/crt0_snes.obj`, headers and native Linux tools.
- Auto-detects SGDK by validating `inc/genesis.h`, `lib/libmd.a`, `bin/rescomp.jar` and the `m68k-elf` toolchain.
- Reports precise missing capabilities instead of pretending a toolchain is ready.
- Injects `PVSNESLIB_HOME` / `GDK` into every real build.
- Supports user-selected SDK roots, persisted in `user://retro_engine.cfg`.

### Non-destructive project import
- Scans Makefiles, `Makefile.pvsnes`, source trees, resources and existing ROMs.
- Detects PVSnesLib, WLA-DX, SGDK and generic Make projects.
- Creates an isolated working copy by default; the original tree is never touched. "Link in place" is available for advanced users and still only writes `.retro/` metadata.
- Working copies live under `res://workspaces` and carry a `.gdignore`, so Godot's own importer never scans them. This prevents native build artifacts such as WLA-DX/816-tcc `.obj` files from being parsed as Wavefront OBJ text (which floods the log with UTF-8 errors and stalls the editor scan).
- Classifies **every** resource as editable or read-only, with a reason. Images are detected as sprites (alpha/strip dimensions), tile sheets (names/companion maps) or generic images; double-click opens them in the Sprite or Stage tab, never in a floating preview. SFF/AIR remain read-only; audio has a real BGM/SFX editor.
- Stores metadata in `.retro/project.json`, `.retro/editor/*.json`, `.retro/backups/`, `.retro/validation/`.

### Visual editors
- **Sprite editor**: pixel painting with nearest-neighbour zoom, indexed palette strip, exact palette-index preservation, PNG palette (`PLTE/tRNS`) reading, indexed PNG writing, `.chr`/`.pic` decoding, 2/4/8 bpp, frames, origin, hit/hurt boxes, per-frame events, VRAM estimate, SNES and SGDK export.
- **Stage editor**: real `.chr`/`.pic` + `.map` + `.pal` import, plain stage PNGs without a companion `.map`, tile map painting, tile picker, layers with editable parallax, animated scrolling preview with sprite animation and authored stage clips (`stage_animations.json`), collision rectangles, map resizing, geometry limits, SNES/SGDK export.
- **Animation editor**: all fighting-game states (`IDLE`, `WALK`, `JUMP`, `CROUCH`, `ATTACK`, `HIT`, `BLOCK`, `SPECIAL`, `SUPER`, `THROW`), frame durations in console frames, auto-playing 60 Hz preview with timeline follow, transparency-aware sprite-sheet splitting (alpha gaps, indexed magenta/green key, grid/strip modes and auto-frame cycling), **Frames from sprite** that materialises detected frames, loops, transitions, per-frame hitboxes and events, `.inc` (65816) and `.h` (SGDK/C) export.
- **Palette editor**: CGRAM/CRAM limits, exact index order, `.pal` import/export, nearest-color remap.
- **Hardware monitor**: VRAM, CGRAM/CRAM, ROM, OAM/VDP per-line sprite limits, BG layer/bpp/mode checks. Estimates are labeled as static estimates, not ROM measurements.
- **Preview**: native resolution viewport, integer scaling, scrolling, parallax, collision overlay, sprite overlay, per-line limit hints, and a permanent warning that it is approximate.
- **Input Mapping editor**: per-action SNES (`KEY_*`) and Mega Drive (`BUTTON_*`) masks, keyboard/gamepad test bindings, hold/priority flags, animation-state target and next-state association, conflict validation, native export to a PVSnesLib `.h`, WLA-DX `.inc` or SGDK `.h` state table, and **Import Godot InputMap** to map project actions/events while preserving state associations.
- **Optional C state-machine generator**: emits `retro_input.h` + `retro_state_machine.c/.h` for either SDK, with priority/hold evaluation, target state, pending next state, animation-end transition, animation-duration auto-end (`retro_sm_tick`) and forced-state API. Existing game source is never modified.
- **State-machine simulator**: editor-side playback of the same priority/hold logic with action buttons, keyboard/gamepad bindings, 60 Hz stepping, animation-duration auto transitions, pending-next display and animation preview.
- **Visual state graph**: GraphEdit workspace with nodes per animation state, draggable transitions, compound ALL/ANY conditions (`pressed`/`held`/`released`), per-transition cooldown, priority and animation-duration auto transitions. Generates a standalone C runtime without touching existing game code.
- **Hitbox timeline**: per-animation-frame hitboxes/hurtboxes with draggable canvas boxes, per-frame editing, two-character AABB collision preview, simulator-state follow mode, and native `.inc`/SGDK `.h` hitbox-table export.
- **MUGEN Tools**: a single tab with native SFF v1/v2 reading (PCX/RLE8/RLE5/LZ5/PNG), AIR frame playback over transparent sprites, SND auditioning, stage DEF layers with MUGEN delta/parallax, character/stage import into SNES/Mega Drive projects, and the previous Inputs/Simulator/Graph/Hitboxes/Import pages as buttons.
- **MUGEN import/export**: parses real `.air` actions (Clsn1/Clsn2, defaults, per-frame boxes) and `.cns` HitDef parameters; explicit action→state import, AIR export and HitDef→move-property application.
- **Collision runtime**: generates a standalone C module with hitbox tables, move properties, AABB hit/block checks, hitstop, post-hit invulnerability, HitDef-ID multi-hit gating, basic pushback and automatic BLOCK/GUARD-state inference (`retro_collision.c/.h`, 16-bit state indices).
- **MUGEN state import**: parses real `Statedef`/`ChangeAnim`/`ChangeState`/`HitDef` blocks, auto-maps every unique state, reads `.cmd` command sequences, batch-imports all mapped AIR animations, evaluates arithmetic/`ifelse` HitDef damage with safe defaults, and generates the complete fight graph (no node cap by default, 16-bit node indices).
- **Game Build options**: generates real PVSnesLib and SGDK projects from native Godot scenes or converts an SNES project to Mega Drive and vice versa; the generated project includes the native UI/node/script port bundle. Optional Godot-logo black-screen fade in/out can be compiled into the ROM.
- **SNES ROM mappings**: LoROM/HiROM SlowROM/FastROM, ExHiROM FastROM 8 MiB, Tales of Phantasia 6 MiB, Star Ocean S-DD1 6 MiB header/layout and MSU-1 companion files; the best mapping and size are suggested from the estimated game payload.
- **Coherence checks**: platform selector vs active project, project mode, build system, SDK path, stored export/3D profiles and Game Build source mode are validated before compiling. Incoherences are shown as blocking errors or warnings, and the Build tab offers **Use project platform** to fix the selector.
- **Localization**: Retro UI follows Godot's editor locale and ships dictionaries for all 40 Godot editor locales (Portuguese, English, Spanish, French, German, Japanese, Chinese, Arabic, and the rest), with English fallback for any missing key. It covers the main workspace, New Project, Game Build, Native port bundle, coherence alerts, SDK downloader, hardware monitor and Terminal. See `docs/LOCALIZATION.md`.
- **Terminal**: a `Terminal` main screen next to Retro with real OS PTY shells, multiple VSCode-style tabs, `+`, `−` and a terminal menu. Powered by the MIT GDTerm extension.
- **New project templates**: **New Project...** creates a complete, buildable SNES/PVSnesLib or Mega Drive/SGDK starter project (16-colour screen, editable C sources, Makefile, art assets and README), with **Create + Build** producing a real ROM.
- **SDK setup**: detects existing PVSnesLib/SGDK installations, or downloads the official GitHub releases into user data with **Download SDKs...**. The SGDK download button also runs the bundled platform setup script to build `sjasm`/`convsym`/`bintos`, install the `m68k-elf-*` wrappers and configure the session `PATH`; it installs Wine, Java and build tools when missing (administrator approval may be requested). Missing SDKs/projects never crash startup; builds show configuration guidance.
- **Audio**: imports `.mid`, `.it`, `.mp3` and `.wav`; converts BGM to SNESMOD/IT and Mega Drive YM2612 FM/XGM2/PCM; synthesizes SFX with waveform, ADSR, pitch slide, vibrato, noise and bitcrush controls; previews the target arrangement and compiles real ROM audio.
- **Native Godot bridge**: converts the scene open in the Godot editor — sprites, animations, UI `Control` widgets, cameras, collision/bodies, markers, audio/animation/timer/light/path nodes, `MeshInstance3D` and `TileMapLayer` — into SNES/Mega Drive assets. It captures 2D/3D scenes into console tilemaps, bakes 3D scenes into sprite sheets, and exports a portable port bundle (`*_port.h/.json/.md`) with UI layout, other nodes, script metadata and copied script sources. **Import game scene** uses the project's Jogo/Game main scene. Super FX (Star Fox) and SVP (Virtua Racing) profiles supply 3D reference budgets; the generated sprites still run on the base consoles.
- **Code panel**: indexes C functions and assembly labels, edits `.c/.h/.asm/.inc` with a timestamped backup before writing, and stores explicit code↔asset associations in project JSON. Arbitrary C is never converted into visual nodes.
- **Build panel**: asynchronous real `make` with streamed logs, ANSI stripping, diagnostics with file/line/column, double-click to open the source, ROM size, warnings, errors and elapsed time.

### Build / run / debug
- **Build SNES**, **Build Mega Drive**, **Run ROM**, **Debug ROM**, **Attach Debugger**, **Clean Build**, **Rebuild All**, **Export ROM**.
- Emulator detection for Mesen, bsnes, Snes9x, BlastEm, Gens/Gens KMod, RetroArch and Flatpak installs.
- ROM header inspection for SNES (LoROM/HiROM/ExHiROM, checksum/complement, size byte) and Mega Drive (`SEGA` header).
- Debug launch uses documented CLI flags only; when an emulator has no reliable debugger flag, the IDE refuses to pretend and explains why.

## Repository layout

```
modules/retro_engine/           C++ module compiled directly into this fork
ide/                           Retro IDE project + editor addon + headless tests
scripts/                       prerequisite checks, Linux/Windows/macOS build, validation
examples/                      minimal SNES/MD projects consuming generated state-machine C
docs/                          architecture, format compatibility, SDK setup
core/, editor/, scene/, ...    upstream Godot 4.7.2 source and history
validation/                    generated test copies and reports
dist/                          built editors
```

## Build

Clone this fork with Git. The engine source is already included; no second
Godot download is needed. See [migration notes](docs/FORK_MIGRATION.md) and
the [upstream README](docs/UPSTREAM_README.md).

### Linux (primary)
```bash
scripts/bootstrap.sh
scripts/build_linux.sh
scripts/run_linux.sh
```

The build produces `dist/linux/GodotRetroEngine` and a self-contained `dist/linux/ide` workspace.

### Mega Drive toolchain
If a native `m68k-elf` toolchain is not installed, the supplied SGDK Windows
GCC 13.2 binaries can be used with native host tools.

Linux:

```bash
SGDK_ROOT=/path/to/sgdk211 scripts/setup_sgdk_linux.sh
source vendor/sgdk-linux/env.sh
```

macOS:

```bash
SGDK_ROOT=$HOME/sgdk211 scripts/setup_sgdk_macos.sh
source vendor/sgdk-macos/env.sh
```

Windows (Git Bash/MSYS2):

```bash
SGDK_ROOT=/c/sgdk211 scripts/setup_sgdk_windows.sh
source vendor/sgdk-win/env.sh
```

The Linux/macOS scripts build `sjasm`, `convsym`, `bintos` and `mac68k`
natively, create `m68k-elf-*` Wine wrappers and smoke-test an SGDK sample. The
Windows script validates SGDK's native `.exe` tools and writes `env.sh`,
`env.bat` and `env.ps1`. The IDE builder passes `LIBGCC=<SDK>/lib/libgcc.a` and
uses one job for SGDK to avoid the stock makefile's `.res`/header race.

### Windows
On Windows with Visual Studio or MinGW:
```bat
scripts\build_windows.sh
```
Cross-compiling from Linux with mingw-w64 is also supported:
```bash
sudo apt install mingw-w64
scripts/build_windows.sh
```
The cross-build auto-detects Godot's optional `bin/build_deps/agility_sdk` and
`bin/build_deps/angle-x86_64-gcc` folders and enables D3D12/ANGLE when present.
Without them it still builds with Vulkan and disables WinRT/AccessKit. The
output is `dist/windows/GodotRetroEngine.exe` (GUI), the console stub
`GodotRetroEngine.console.exe`, `run.bat` and the `ide` folder.

### macOS
On macOS with Xcode command-line tools:
```bash
scripts/build_macos.sh
```
Cross-compiling from Linux with osxcross and a macOS SDK:
```bash
export OSXCROSS_ROOT=/path/to/osxcross
export OSXCROSS_SDK=darwin25.1   # match the SDK in osxcross
scripts/build_macos.sh
```
The script builds both `x86_64` and `arm64`; Godot's bundle step uses `lipo` to
create a universal app. Vulkan/ANGLE/AccessKit are disabled by default (Metal
renderer on native macOS); pass `vulkan=yes`, `angle=yes` or `accesskit=yes` to
override. osxcross builds use ANGLE and are unsigned.

Output: `dist/macos/GodotRetroEngine.app`, `run.sh` and the `ide` folder.

## First run

1. Launch the editor (`scripts/run_linux.sh`).
2. Open the **Retro** workspace (top workspace selector).
3. Choose **SNES** or **Mega Drive**.
4. Click **SDK...** and select:
   - SNES: the PVSnesLib root containing `devkitsnes/` and `pvsneslib/` (for the supplied SDK: `/run/media/fabio/Dados/Fabio/pvsneslib-sdk-4.6`).
   - Mega Drive: the SGDK root containing `inc/` and `lib/` (for the supplied SDK: `/run/media/fabio/Dados/Fabio/sgdk211`).
5. Click **Import Project...**, select a project directory, review the detection summary, keep **Create an isolated working copy**, confirm.
6. Pick a resource in the tree. Use **As Sprite / As Stage / As Palette** when a format is ambiguous.
7. Edit, then **Build** in the Build tab, and **Run ROM**.

## Test harness

```bash
scripts/build_linux.sh
scripts/validate.sh              # scan + codec + import checks
BUILD=1 scripts/validate.sh      # also rebuild all three SNES projects
source vendor/sgdk-linux/env.sh
scripts/validate_sgdk.sh         # import + real SGDK build + ROM probe
scripts/build_state_machine_demos.sh   # real SNES + MD ROMs using generated C
scripts/build_graph_demos.sh           # SNES + MD ROMs using graph-generated C
scripts/test_state_graph_logic.sh      # graph runtime host logic + both SDK compilers
scripts/test_hitboxes.sh               # hitbox tables + collision math + both SDK compilers
scripts/test_air_cns.sh                # real KOF AIR/CNS import + AIR round-trip
scripts/test_collision_runtime.sh      # hitstop/invulnerability host logic + both SDK compilers
scripts/test_mugen_import.sh           # full state import + fight graph + both SDK compilers
scripts/test_native_bridge.sh          # native scene -> sprites/tilemaps/profiles + both SDK compilers
scripts/test_game_build.sh              # native/cross-platform SNES+MD ROMs + logo splash
scripts/test_state_machine_logic.sh
scripts/smoke_emulators.sh             # launches real ROMs in Mesen/BlastEm
```

The headless harness uses the same module as the editor: it scans/imports projects, decodes and re-encodes native tiles/palettes, edits one sprite pixel, exports, rebuilds, probes the resulting ROM and checks emulator availability. Reports go to `ide/validation/headless_report.json`.

Measured results are in [`docs/VALIDATION.md`](docs/VALIDATION.md). All three
reference SNES projects and an SGDK sample built real ROMs; the stage edit
rebuild test changed the ROM hash and restoring the asset reproduced the
original hash.

## Real SDK notes

- PVSnesLib 4.6 in the supplied tree includes native Linux binaries (`816-tcc`, `wla-65816`, `wlalink`, `gfx4snes`, `smconv`, …).
- SGDK 2.11 in the supplied tree contains Windows tools. Linux needs an `m68k-elf` GCC toolchain plus native `sjasm`, `mac68k`, `bintos`, `convsym`. Java (`rescomp.jar`) is enough for resource conversion, and the IDE reports that distinction instead of failing silently.
- The IDE does not bundle SDKs or emulators and does not relicense them. See `LICENSE-NOTICE.md`.

## Honest limitations

- **SFF/AIR** (MUGEN sprite/animation banks) are recognized and visualised only through the generated `.chr/.pal/.inc` files produced by the project's converters. There is no SFF/AIR editor, and the IDE says so.
- **Game Build** generates console projects from native assets or from the active project. It is a background/showcase build: it displays the converted stage, not a full game script or input-driven gameplay. The generated project includes the native UI/node/script port bundle (`port/` + `PORTING.md`) for the manual gameplay port; GDScript is copied as reference, not transpiled. The Godot logo splash is optional and attribution is in `LICENSE-NOTICE.md`.
- **Native 3D** is pre-rendered into 2D sprites or tilemaps. The Super FX and SVP profiles are reference budgets (Star Fox / Virtua Racing), not GSU/SVP emulators or cartridge toolchains; real co-processor ROMs need those SDKs. Captures use a script-stripped duplicate, and a software renderer covers headless 2D/3D capture when GPU capture is unavailable.
- **MUGEN state import** is not a complete MUGEN VM. Commands and command
  sequences are compiled from `.cmd` files, expression-based HitDef damage uses
  safe defaults for variables/helpers, and timing triggers become duration-based
  auto transitions. Triggers that depend on runtime variables, helpers, random
  values, enemy state or custom `VarSet`/`VarAdd` logic are reported as skipped
  rather than approximated as always-true. The graph has no default node cap and
  uses 16-bit indices; set `Max nodes` in the MUGEN tab if a smaller editable
  graph is preferred.
- **Audio** conversion renders MIDI→SNES with the FluidR3_GM soundfont and MIDI→Mega Drive with real YM2612 FM. `.mp3`/`.wav` BGM uses full-duration PCM; SNES adapts the rate to fit the BRR budget.
- **Stage layers** are represented and exportable, but the base map is the painted layer; parallax layers are metadata/duplicates, not a full multi-layer compositor yet.
- **Preview** is a faithful palette/tile reconstruction, not an emulator. It cannot reproduce every PPU/VDP timing effect, HDMA, raster trick or sprite overflow behaviour. Only the ROM in an emulator/hardware is authoritative.
- **Debugger** integration is limited to documented emulator CLI flags. Memory inspection/breakpoints inside the IDE are not implemented for emulators that require a plugin/remote protocol.
- **Automatic C → visual graph conversion is intentionally not attempted.** Associations are explicit and stored without rewriting source.
- The input-map and visual-graph generators are opt-in. They write separate files; they do not edit your `main.c` or scene code. The game must call `retro_sm_update(...)` and `retro_sm_tick()` each frame, and may call `retro_sm_animation_end()` for an explicit animation-end transition.
- The editor simulator mirrors the generated polling matchers, but it is not a cycle-accurate game runtime.
- Multiple graph transitions between the same pair of states share one visual edge; all condition sets remain editable in the transition list.
- Emulator smoke tests are process-level (ROM loaded and emulator remains alive). Pixel-perfect automated comparison against hardware is not implemented.
- Mega Drive full C builds use the setup scripts in `scripts/`: Linux/macOS run SGDK's Windows GCC 13.2 through Wine with native host tools; Windows uses SGDK's native `.exe` tools. Resource compilation alone needs only Java.
- Windows x86_64 and macOS universal editor builds were cross-compiled in the original project with MinGW-w64 13.2 and osxcross; the fork's build scripts mirror that flow. A full fork engine recompilation and Windows/macOS artifact build were not repeated in this checkout.

## Licenses

Godot is MIT-licensed. PVSnesLib is zlib-licensed. SGDK is MIT-licensed, with GCC/libgcc under GPL3 + runtime exception. Emulators have their own licenses. Details and notices are in `LICENSE-NOTICE.md`.
