#!/usr/bin/env bash
# macOS editor build. Must run on macOS with Xcode command line tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [ "$(uname -s)" != "Darwin" ]; then
  echo "macOS builds must run on macOS (Xcode required)." >&2
  exit 1
fi
scripts/bootstrap.sh
SCONS="${SCONS:-$HOME/.local/bin/scons}"
command -v "$SCONS" >/dev/null 2>&1 || SCONS=scons
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

cd "$ROOT"
"$SCONS" platform=macos target=editor arch=universal use_lto=no -j"$JOBS" \
  "$@"

APP="bin/Godot.app"
if [ -d "$APP" ]; then
  mkdir -p "$ROOT/dist/macos"
  rm -rf "$ROOT/dist/macos/GodotRetroEngine.app" "$ROOT/dist/macos/Godot.app"
  cp -R "$APP" "$ROOT/dist/macos/GodotRetroEngine.app"
  rm -rf "$ROOT/dist/macos/ide"; cp -R "$ROOT/ide" "$ROOT/dist/macos/ide"
  echo "==> Built $ROOT/dist/macos/GodotRetroEngine.app"
  echo "    Launch: $ROOT/dist/macos/GodotRetroEngine.app/Contents/MacOS/Godot --editor --path $ROOT/dist/macos/ide"
else
  echo "Expected $APP was not produced; inspect the SCons output." >&2
  exit 1
fi
