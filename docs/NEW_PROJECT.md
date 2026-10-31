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

## Starter screens

The ROM boots with the same **Godot Engine splash** used by Game Build for both
consoles, then fades into a static **HELLO WORLD** screen:

- Godot logo splash on black, with the hardware fade;
- checkered Hello World background;
- `HELLO` / `WORLD` title and platform subtitle
  (`SNES / PVSNESLIB` or `MEGA DRIVE / SGDK`);
- diamond/colour accents and `GODOT RETRO ENGINE` footer.

Set `RETRO_SPLASH` to `0` in `src/assets.h` (or remove `showSplash()`) to skip
the splash. The Hello World screen stays static so the title remains readable.

`src/main.c` starts with a commented workflow block covering the art editors,
the build command, Build + Run, the real-ROM Preview, and `art/` as the source
of truth. The generated assets come from the same validated Game Build
pipeline: 16-colour quantization, unique 8x8 tile extraction, SNES
`.chr/.pal/.map/.inc` or SGDK PNG/`.res` data, and C asset arrays.

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

- `src/main.c` — replace the static Hello World loop with the game loop; the
  workflow instructions are at the top of the file.
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

The regression creates both platforms, imports them, checks the Godot splash
flags and workflow comments, verifies the editable sources/art assets, builds
both ROMs and checks the output files.
