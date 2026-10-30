#!/usr/bin/env bash
# Windows editor build.
#
# Two supported paths:
#   1. Run this script on Windows with Visual Studio or MinGW toolchains.
#   2. Cross-compile from Linux with mingw-w64:
#        sudo apt install mingw-w64
#        scripts/build_windows.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
scripts/bootstrap.sh
SCONS="${SCONS:-$HOME/.local/bin/scons}"
command -v "$SCONS" >/dev/null 2>&1 || SCONS=scons
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 8)}"

HOST_OS="$(uname -s 2>/dev/null || echo Windows)"
EXTRA=()
if [ "$HOST_OS" != "Darwin" ] && [ "${HOST_OS#MINGW}" = "$HOST_OS" ] && [ "${HOST_OS#MSYS}" = "$HOST_OS" ]; then
  # Linux host: cross-compile with MinGW.
  if command -v x86_64-w64-mingw32-g++ >/dev/null 2>&1; then
    EXTRA=(use_mingw=yes mingw_prefix=x86_64-w64-mingw32-)
  else
    echo "mingw-w64 not found. Install it (sudo apt install mingw-w64) or run this script on Windows." >&2
    exit 1
  fi
fi

cd "$ROOT"
"$SCONS" platform=windows target=editor use_lto=no -j"$JOBS" \
  extra_suffix=retro_engine "${EXTRA[@]}" "$@"

mkdir -p "$ROOT/dist/windows"
BUILT="$(ls -t bin/godot.windows.editor.x86_64*.exe 2>/dev/null | head -1 || true)"
if [ -z "$BUILT" ]; then
  echo "Windows editor binary not found in bin" >&2
  exit 1
fi
cp "$BUILT" "$ROOT/dist/windows/GodotRetroEngine.exe"
rm -rf "$ROOT/dist/windows/ide"; cp -r "$ROOT/ide" "$ROOT/dist/windows/ide"
cp "$ROOT/README.md" "$ROOT/dist/windows/" 2>/dev/null || true

cat > "$ROOT/dist/windows/run.bat" <<'EOF'
@echo off
"%~dp0GodotRetroEngine.exe" --editor --path "%~dp0ide" %*
EOF

echo "==> Built $ROOT/dist/windows/GodotRetroEngine.exe"
