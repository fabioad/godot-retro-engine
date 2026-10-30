#!/usr/bin/env bash
# macOS editor build.
#
# Native build: run on macOS with Xcode command line tools.
# Cross-build:  set OSXCROSS_ROOT to an osxcross installation on Linux.
#
# Both x86_64 and arm64 are built, then Godot's bundle step combines them into
# a universal .app with lipo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [ "$(uname -s)" != "Darwin" ] && [ -z "${OSXCROSS_ROOT:-}" ]; then
  echo "macOS builds must run on macOS (Xcode) or with OSXCROSS_ROOT (osxcross)." >&2
  exit 1
fi
scripts/bootstrap.sh
SCONS="${SCONS:-$HOME/.local/bin/scons}"
command -v "$SCONS" >/dev/null 2>&1 || SCONS=scons

EXTRA=()
if [ -n "${OSXCROSS_ROOT:-}" ]; then
  export PATH="$OSXCROSS_ROOT/bin:$PATH"
  if [ -n "${OSXCROSS_SDK:-}" ]; then
    EXTRA+=(osxcross_sdk="$OSXCROSS_SDK")
  fi
  # osxcross has no codesign; the app is unsigned for local testing.
  EXTRA+=(bundle_sign_identity=)
fi

JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 8)}"
[ "$JOBS" -gt 12 ] && JOBS=12

# Clang 18 (Ubuntu osxcross) does not recognize the visionOS platform name in
# @available(). Apple's Xcode clang does, so this compatibility patch is only
# applied for osxcross builds and is removed on exit.
CAMERA_SRC="$ROOT/modules/camera/camera_apple.mm"
if [ -n "${OSXCROSS_ROOT:-}" ] && grep -q "visionOS" "$CAMERA_SRC"; then
  cp "$CAMERA_SRC" "$CAMERA_SRC.osxcross.bak"
  trap 'mv -f "$CAMERA_SRC.osxcross.bak" "$CAMERA_SRC"' EXIT
  sed -i 's/, visionOS [0-9.]*, \*))/, *))/g' "$CAMERA_SRC"
fi

# ANGLE gives both slices an OpenGL renderer. Metal covers arm64 only.
DEPS="$ROOT/bin/build_deps"
RENDER=(vulkan=no)
if [ -n "${OSXCROSS_ROOT:-}" ]; then
  # clang 18 + SDK 26.1 cannot build the Metal C++ modules; ANGLE covers both.
  RENDER+=(metal=no)
fi
if [ -d "$DEPS/angle-x86_64-macos" ] && [ -d "$DEPS/angle-arm64-macos" ]; then
  RENDER+=(angle=yes)
else
  RENDER+=(angle=no)
fi
if [ -d "$DEPS/accesskit" ]; then
  RENDER+=(accesskit=yes)
else
  RENDER+=(accesskit=no)
fi

cd "$ROOT"
# Build both slices. Godot's generate_bundle step lipos the per-arch binaries
# and creates the universal .app on the second pass.
for arch in x86_64 arm64; do
  "$SCONS" platform=macos target=editor arch="$arch" use_lto=no \
    extra_suffix=retro_engine generate_bundle=yes \
    "${RENDER[@]}" \
    "${EXTRA[@]}" "$@" \
    -j"$JOBS"
done

APP="bin/godot_macos_editor_retro_engine.app"
if [ ! -d "$APP" ]; then
  echo "Expected $APP was not produced; inspect the SCons output." >&2
  exit 1
fi
mkdir -p "$ROOT/dist/macos"
rm -rf "$ROOT/dist/macos/GodotRetroEngine.app" "$ROOT/dist/macos/Godot.app"
cp -R "$APP" "$ROOT/dist/macos/GodotRetroEngine.app"
rm -rf "$ROOT/dist/macos/ide"; cp -R "$ROOT/ide" "$ROOT/dist/macos/ide"
cp "$ROOT/README.md" "$ROOT/dist/macos/" 2>/dev/null || true

cat > "$ROOT/dist/macos/run.sh" <<'EOF'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$DIR/ide/workspaces"
[ -f "$DIR/ide/workspaces/.gdignore" ] || : > "$DIR/ide/workspaces/.gdignore"
exec "$DIR/GodotRetroEngine.app/Contents/MacOS/Godot" --editor --path "$DIR/ide" "$@"
EOF
chmod +x "$ROOT/dist/macos/run.sh"

echo "==> Built $ROOT/dist/macos/GodotRetroEngine.app"
echo "    Launch: $ROOT/dist/macos/run.sh"
