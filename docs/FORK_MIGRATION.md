# Fork integration

This fork uses the official Godot `4.7.2-stable` tag as its parent. The
`retro-engine` branch preserves the upstream history; the original project's
independent commit history is not imported. The local `master` branch is kept.

Every upstream file in the original `vendor/godot` was compared to the tag.
The contents match after CRLF/LF normalization. No engine source patches
were needed outside the new `modules/retro_engine` directory.

- `modules/retro_engine`: original C++ module, moved from `overlay/modules`.
- `ide`: original editor workspace, addons, assets and headless tests.
- `scripts`: build and validation tools; engine builds run from the root.
- `examples` and `docs`: original examples and documentation.
- `LICENSE.txt` and `COPYRIGHT.txt`: unchanged upstream license notices.
- `LICENSE-RETRO.txt`: license of the original Retro additions.
- `docs/UPSTREAM_README.md`: original Godot README.

Build products, imported workspaces, validation fixtures, external SDKs and
local agent settings are excluded. Historical validation results in
`docs/VALIDATION.md` describe the original project, not a fresh full test run.

Build and launch on Linux:

```sh
scripts/build_linux.sh
scripts/run_linux.sh
```

## Migration validation

- Compared all upstream source files with the official `4.7.2-stable` tag:
  identical after CRLF/LF normalization.
- All shell scripts passed `bash -n`; prerequisite checks passed.
- SCons dry run completed and includes the Retro module in the build plan.
- Headless editor import passed without errors.
- Backend smoke, project coherence, localization and localization coverage
  tests passed using the existing 4.7.2 executable from the original project.

A complete recompilation of the migrated checkout has not been run. SDK ROM
builds and Windows/macOS builds have not been repeated for this migration.

## Update from original project (2026-10-30)

Synchronized original project commits `03781ef` and `a7a51d1` (source HEAD:
`a7a51d14a62767a37204c96a481a8b0aaa9d008b`), preserving the fork layout and
build-script adaptations. Some localization changes were already included
in the initial integration snapshot.

Validation with the existing Godot 4.7.2 executable: headless editor import,
ROM profile selection, localization, locale coverage and project coherence
all passed. Seven real SNES builds passed: auto, LoROM, HiROM, ExHiROM,
Tales of Phantasia layout, Star Ocean header/layout and MSU-1. The tests
verified ROM sizes, headers, checksums and MSU-1 companion files. A complete
engine recompilation and Windows/macOS builds were not repeated.

## Sync 2026-10-30: packaging, cross-builds and SDK setup

Synchronized the original project commits `12bbcec`, `28b7603`, `f67112f`,
`0163d50` and `1afeee4`, preserving the fork layout:

- Linux `.deb`/`.rpm` packaging (`scripts/package_linux.sh` and post-install
  cache hooks).
- Windows cross-build fixes: `MINGW_PREFIX` handling, D3D12/ANGLE dependency
  detection, GUI/console executable selection.
- macOS osxcross support: x86_64 + arm64 universal build, ANGLE, temporary
  `visionOS` compatibility patch and the `clang_rt_stub.c` compiler-rt shim.
- SGDK setup scripts for Linux, macOS and Windows, bundled under
  `ide/addons/retro_engine/setup/`. The SDK Downloader now runs the matching
  script after extracting SGDK, builds the host tools, installs the
  `m68k-elf-*` wrappers and updates the session `PATH`.
- Localization dictionaries updated to 430 keys per locale (41 dictionaries).
- Space-containing SDK paths are configured through a no-space Unix link and the
  setup smoke test escapes `GDK`/`LIBGCC`.
- The SGDK downloader installs missing system dependencies with `--install-deps`:
  apt/dnf/pacman/zypper + sudo/pkexec on Linux, Homebrew on macOS, winget for
  Java on Windows.

Validation performed with the existing 4.7.2 executable against this fork's
`ide` workspace: headless editor import, localization, localization coverage,
ROM profile logic and project coherence. The SGDK downloader flow was validated
against the official SGDK 2.11 ZIP: `ready=false` before setup, `ready=true`
after setup, with `m68k-elf-gcc`, `sjasm`, `convsym`, `bintos` and `env.sh`
present. A complete fork engine recompilation and new Windows/macOS artifacts
were not repeated in this checkout.
