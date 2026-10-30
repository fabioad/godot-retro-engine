# SDK and emulator setup

## Super Nintendo — PVSnesLib 4.6

Expected layout (the supplied installation matches it):

```
pvsneslib-sdk-4.6/
├── devkitsnes/
│   ├── bin/816-tcc
│   ├── bin/wla-65816
│   ├── bin/wla-spc700
│   ├── bin/wlalink
│   ├── tools/gfx4snes
│   ├── tools/smconv
│   ├── tools/snesbrr
│   ├── tools/tmx2snes
│   └── snes_rules
└── pvsneslib/
    ├── include/snes.h
    ├── lib/LoROM_SlowROM/crt0_snes.obj
    ├── lib/LoROM_FastROM/...
    ├── lib/HiROM_SlowROM/...
    └── pvsneslib_version.txt
```

The IDE points `PVSNESLIB_HOME` at the `pvsneslib-sdk-4.6` root. For raw WLA-DX
projects it also exposes the SDK's `wla-65816`, `wlalink`, `wla-spc700` as
`WLA`, `WLALINK`, `WLA_SPC` and prepends `devkitsnes/bin` to `PATH`.

Verify manually:

```bash
export PVSNESLIB_HOME=/path/to/pvsneslib-sdk-4.6
cd some-project
make
```

The supplied PVSnesLib 4.6 binaries are native Linux ELF executables. The
sidearms project in this repository compiled successfully with them.

## In-app downloader

The SDK row has a **Download SDKs...** button. It downloads the official
GitHub releases directly into the IDE's user data directory, so a fresh
installation with no projects or SDKs can still install what it needs:

```text
PVSnesLib 4.6.0 (the downloader selects linux/windows/darwin):
https://github.com/alekmaul/pvsneslib/releases/download/4.6.0/

SGDK 2.11 source release:
https://github.com/Stephane-D/SGDK/archive/refs/tags/v2.11.zip
```

Installed paths:

```text
user://sdks/pvsneslib-4.6.0/pvsneslib
user://sdks/sgdk-2.11/SGDK-2.11
```

PVSnesLib is a ready-to-use Linux package; executable bits are restored after
extraction. SGDK includes `rescomp.jar`, headers and libraries. Full Linux C
builds still need Wine and the native host tools from
`scripts/setup_sgdk_linux.sh`; without them the IDE remains usable and reports
“resource compiler only” instead of failing.

The SDK Downloader's **Download / Reinstall** button for SGDK also runs the
bundled platform setup script after extraction. It builds `sjasm`, `convsym`,
`bintos` and `mac68k`, installs the `m68k-elf-*` wrappers and `env.sh`/`env.bat`
helpers into the downloaded SDK root, and updates the current editor session's
`PATH`. Wine + Java are required on Linux/macOS; Git Bash + Java on Windows.
Missing dependencies are reported in the download log with the manual command.

The app also starts cleanly with no projects: the project selector shows
`(no project)`, the SDK status explains what is missing, and Build/Game Build
show a configuration message instead of running a broken make command.

## Mega Drive — SGDK 2.11

Expected layout:

```
sgdk211/
├── inc/genesis.h
├── lib/libmd.a
├── lib/libmd_debug.a  (if debug builds are desired)
├── bin/rescomp.jar
├── makefile.gen
├── common.mk
└── md.ld
```

Resource compilation needs only **Java 17+** and `rescomp.jar`:

```bash
java -jar sgdk211/bin/rescomp.jar
```

Full C builds on Linux additionally need:

- `m68k-elf-gcc` (GCC 13.x is what SGDK 2.11 ships for Windows),
- `m68k-elf-ar`, `m68k-elf-ld`, `m68k-elf-objcopy`, `m68k-elf-nm`,
- native `sjasm`, `mac68k`, `bintos`, `convsym` tools
  (the Windows `.exe` files in `sgdk211/bin` cannot run directly on Linux),
- `make` and Java.

The IDE probes all of these and distinguishes **full ROM build ready** from
**resource compiler only**. “Toolchain missing” in the Mega Drive status means
`m68k-elf-gcc` is not in `PATH`; it does not mean SGDK is absent, and
`rescomp.jar` resource conversion still works. It does not download or bundle
GPL toolchains.

### Automated SGDK setup

The same scripts are bundled under
`ide/addons/retro_engine/setup/` and are what the SDK Downloader executes for
SGDK. The `scripts/setup_sgdk_*.sh` entry points are thin wrappers around them.

Linux:

```bash
SGDK_ROOT=/path/to/sgdk211 scripts/setup_sgdk_linux.sh
source vendor/sgdk-linux/env.sh
scripts/run_linux.sh
```

macOS:

```bash
SGDK_ROOT=$HOME/sgdk211 scripts/setup_sgdk_macos.sh
source vendor/sgdk-macos/env.sh
scripts/build_macos.sh
dist/macos/run.sh
```

macOS needs Wine and GNU make. `brew install --cask wine-stable` and
`brew install make` provide them; the script uses `gmake` when available.

Windows (Git Bash/MSYS2):

```bash
SGDK_ROOT=/c/sgdk211 scripts/setup_sgdk_windows.sh
source vendor/sgdk-win/env.sh
scripts/build_windows.sh
```

The Windows script validates SGDK's native `gcc.exe`, `make.exe`,
`sjasm.exe`, `convsym.exe`, `bintos.exe` and `rescomp.jar`, writes `env.sh`,
`env.bat` and `env.ps1`, and creates the extensionless `m68k-elf-*` / `make`
wrappers expected by the IDE. Java is required for `rescomp.jar`.

`scripts/setup_sgdk_linux.sh` and `scripts/setup_sgdk_macos.sh` share
`scripts/setup_sgdk_unix.sh`. They use the GCC 13.2 `m68k-elf` toolchain
shipped with SGDK for Windows through Wine and build `sjasm`, `convsym`,
`bintos` and `mac68k` wrappers natively from `$SGDK_ROOT/tools`. Each script
smoke-tests an SGDK sample into `out/rom.bin`.

`scripts/run_linux.sh` and `dist/linux/run.sh` now source
`vendor/sgdk-linux/env.sh` automatically, so the IDE sees `m68k-elf-gcc` and
shows “toolchain ready” instead of “toolchain missing”. The module and builder
also search `vendor/sgdk-linux/bin` next to the executable and export
`RETRO_SGDK_ROOT`/`PATH` themselves, so launching `GodotRetroEngine` directly
still builds Mega Drive ROMs.

The IDE builder passes `LIBGCC=$SGDK_ROOT/lib/libgcc.a` and uses a single make
job because the stock SGDK makefile does not order `.res` header generation
before C compilation. Dependency files generated by Wine (`-MMD`) are skipped
because they contain Windows drive letters that GNU make misparses.

Typical native Linux options:

1. Use the Doragasu Docker image (recommended by the SGDK manual):
   `https://gitlab.com/doragasu/docker-sgdk`.
2. Build/install an `m68k-elf` bare-metal toolchain and build the SGDK host
   tools from `sgdk211/tools/*` source with `make`.
3. Run the supplied Windows SGDK tools under Wine (not recommended for
   reproducible CI).

Verify resource conversion without a C toolchain:

```bash
cd sample/game/platformer
java -jar /path/to/sgdk211/bin/rescomp.jar res/resources.res \
     -o out/resources.c
```

(This exact invocation depends on the SGDK version; the project's own
`make` target is authoritative.)

## Emulators

Detection order: `PATH`, `~/.local/bin`, `/usr/games`, then Flatpak fallbacks.

| Platform | Emulator | IDs |
| --- | --- | --- |
| SNES | Mesen | `mesen` |
| SNES | bsnes | `bsnes`, `bsnes-flatpak` |
| SNES | Snes9x | `snes9x`, `snes9x-cli`, `snes9x-flatpak` |
| SNES | RetroArch (Mesen core) | `retroarch` |
| Mega Drive | BlastEm | `blastem` |
| Mega Drive | Gens / Gens KMod | `gens`, `gens-kmod` |
| Mega Drive | RetroArch (Genesis Plus GX) | `retroarch` |

The installed environment used during development has Mesen, bsnes, Snes9x
(Flatpak) and BlastEm.

ROM launch uses `OS.create_process` with the executable and its arguments.
Debug launch is only attempted for emulators with documented CLI debugger
flags (BlastEm `-d`, Gens/Gens KMod `-d`). Mesen and bsnes do not expose a
verified debugger CLI flag in the installed builds, so the IDE refuses to
pretend and explains why instead of silently launching a normal session.

## Configuration persistence

SDK roots, emulator choice, platform, mode and imported project paths are stored
in `user://retro_engine.cfg` (Godot user data directory). Project-specific data
lives beside the working copy:

```
<project>/.retro/project.json
<project>/.retro/editor/sprite.json
<project>/.retro/editor/stage.json
<project>/.retro/editor/animation.json
<project>/.retro/backups/
<project>/.retro/validation/
```
