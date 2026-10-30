# New SNES / Mega Drive projects

The top toolbar has **New Project...**. It creates a complete starter project
for **SNES / PVSnesLib** or **Mega Drive / SGDK** — not an empty placeholder.

## Workflow

1. Choose the platform and project name.
2. Choose the destination folder (the IDE's `workspaces/` by default).
3. Use **Create project** or **Create + Build**.
4. The project is generated, imported into the IDE, selected and opened at
   `src/main.c`.

The destination is created as:

```text
<folder>/<name>/
  Makefile
  README.md
  src/main.c
  src/assets.c
  src/assets.h
  art/                  # editable stage/palette/tile source assets
  .retro/project.json
```

## Starter screen

The template is a real 16-colour console screen:

- checkered background;
- `RETRO` title and platform subtitle;
- diamond/colour accents;
- a `GAME DEMO` strip;
- `src/main.c` scrolls the background in the main loop, so a running ROM is
  visibly running.

The image is converted through the same validated pipeline used by Game Build:
16-colour quantization, unique 8x8 tile extraction, SNES `.chr/.pal/.map/.inc`
or SGDK PNG/`.res` data, and C asset arrays.

## Build and run

The IDE's **Build** tab detects the generated Makefile and SDK. **Create +
Build** compiles immediately. Command-line equivalents:

```sh
# SNES
PVSNESLIB_HOME=/path/to/pvsneslib make

# Mega Drive
GDK=/path/to/sgdk make
```

With the detected SDKs this produces a real ROM:

```text
<name>.sfc          (SNES, 262144 bytes in the validation run)
out/rom.bin         (Mega Drive, 131072 bytes in the validation run)
```

## Editing

- `src/main.c` — replace the demo scroll loop with the game loop.
- `src/assets.c/.h` — generated starter tiles/palette/map arrays.
- `art/` — editable source assets for the Stage/Sprite editors; the IDE
  registers these when the project is imported.
- `README.md` — project-specific build instructions.

The template is intentionally small: background, no input handling and no
gameplay. It is a buildable base for a real port, not a full game.

## Test

```bash
"$BIN" --headless --path ide --script res://tests/new_project_test.gd
```

The regression creates both platforms, imports them, verifies the editable
sources/art assets, builds both ROMs and checks the output files.
