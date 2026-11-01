# Cross-compiling the editor (Linux, Windows, macOS)

## Linux

```bash
scripts/build_linux.sh
scripts/package_linux.sh
```

Artifacts:

```text
dist/linux/GodotRetroEngine
dist/packages/godot-retro-engine_0.1.60_amd64.deb
dist/packages/godot-retro-engine-0.1.60-1.x86_64.rpm
dist/releases/godot-retro-engine-0.1.60-linux-x86_64.tar.gz
```

## Windows (MinGW-w64 from Linux)

The local toolchain is a Linux-native MinGW-w64 extracted without sudo:

```bash
source ~/.local/share/godot-retro-engine/toolchains/env-mingw.sh
JOBS=12 scripts/build_windows.sh
```

Artifacts:

```text
dist/windows/GodotRetroEngine.exe
dist/windows/GodotRetroEngine.console.exe
dist/windows/ide/
dist/windows/run.bat
dist/releases/godot-retro-engine-0.1.60-windows-x86_64.zip
```

The PE binary was smoke-tested under Wine:

```text
4.7.2.stable.custom_build.30174bf8c
```

## macOS universal (osxcross)

OSXCross 3.0 was built with the LLVM flavor, LLVM/Clang 21 and the macOS 26.1
SDK. The toolchain is installed under the user data directory:

```bash
source ~/.local/share/godot-retro-engine/toolchains/env-osxcross.sh
JOBS=12 scripts/build_macos.sh
```

Artifacts:

```text
dist/macos/GodotRetroEngine.app
dist/macos/ide/
dist/macos/run.sh
dist/releases/godot-retro-engine-0.1.60-macos-universal.zip
```

The executable is a universal Mach-O with `x86_64` and `arm64` slices. It is
unsigned (osxcross cannot codesign); on first launch macOS may require
right-click → Open or removing the quarantine attribute.

## Checksums

See `dist/releases/SHA256SUMS-0.1.60.txt`.
