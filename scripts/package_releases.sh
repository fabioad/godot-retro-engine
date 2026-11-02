#!/usr/bin/env bash
# Package the Linux, Windows and macOS editor builds into dist/releases.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
REL="$DIST/releases"
VERSION="${VERSION:-$(sed -n 's/^version="\(.*\)"/\1/p' "$ROOT/ide/addons/retro_engine/plugin.cfg" | head -1)}"
COMMIT="${COMMIT:-$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'local')}"
STAMP="$(date -Iseconds)"

LINUX_BIN="$DIST/linux/GodotRetroEngine"
WINDOWS_BIN="$DIST/windows/GodotRetroEngine.exe"
MACOS_APP="$DIST/macos/GodotRetroEngine.app"

for required in "$LINUX_BIN" "$WINDOWS_BIN" "$MACOS_APP"; do
  if [ ! -e "$required" ]; then
    echo "missing build artifact: $required" >&2
    exit 1
  fi
done

mkdir -p "$REL"
STAGE="$(mktemp -d "$DIST/.release-linux.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/godot-retro-engine"
mkdir -p "$PKG"

cp "$LINUX_BIN" "$PKG/GodotRetroEngine"
chmod +x "$PKG/GodotRetroEngine"
rsync -a \
  --exclude '.godot/' \
  --exclude 'workspaces/' \
  --exclude 'validation/' \
  "$DIST/linux/ide/" "$PKG/ide/"
cp "$DIST/linux/run.sh" "$PKG/run.sh"
cp "$DIST/linux/README.md" "$PKG/README.md" 2>/dev/null || true
cp "$ROOT/LICENSE.txt" "$ROOT/LICENSE-RETRO.txt" "$ROOT/LICENSE-NOTICE.md" "$PKG/"
if [ -d "$ROOT/docs" ]; then
  cp -R "$ROOT/docs" "$PKG/docs"
fi

LINUX_ARCHIVE="$REL/godot-retro-engine-$VERSION-linux-x86_64.tar.gz"
WINDOWS_ARCHIVE="$REL/godot-retro-engine-$VERSION-windows-x86_64.zip"
MACOS_ARCHIVE="$REL/godot-retro-engine-$VERSION-macos-universal.zip"

echo "==> $LINUX_ARCHIVE"
tar -czf "$LINUX_ARCHIVE" -C "$STAGE" godot-retro-engine

echo "==> $WINDOWS_ARCHIVE"
rm -f "$WINDOWS_ARCHIVE"
(cd "$DIST/windows" && zip -qr "$WINDOWS_ARCHIVE" .)

echo "==> $MACOS_ARCHIVE"
rm -f "$MACOS_ARCHIVE"
(cd "$DIST/macos" && zip -qry "$MACOS_ARCHIVE" .)

cat > "$REL/BUILD_INFO-$VERSION.txt" <<EOF
Built from fork commit: $COMMIT
Version: $VERSION
Build date: $STAMP
Linux:   dist/linux/GodotRetroEngine + .deb/.rpm
Windows: dist/windows/GodotRetroEngine.exe (PE32+ x86_64)
macOS:   dist/macos/GodotRetroEngine.app (Mach-O universal x86_64+arm64)
EOF

CHECKSUMS="$REL/SHA256SUMS-$VERSION.txt"
(
  cd "$REL"
  sha256sum \
    "$(basename "$LINUX_ARCHIVE")" \
    "$(basename "$WINDOWS_ARCHIVE")" \
    "$(basename "$MACOS_ARCHIVE")" \
    ../packages/godot-retro-engine_"$VERSION"_amd64.deb \
    ../packages/godot-retro-engine-"$VERSION"-1.x86_64.rpm \
    > "$CHECKSUMS"
)

echo "==> $REL"
ls -lh "$LINUX_ARCHIVE" "$WINDOWS_ARCHIVE" "$MACOS_ARCHIVE" "$CHECKSUMS"
