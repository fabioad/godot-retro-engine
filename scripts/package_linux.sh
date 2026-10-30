#!/usr/bin/env bash
# Build Linux .deb and .rpm packages from dist/linux.
#
# The package installs the editor under /opt/godot-retro-engine and a
# user-facing launcher in /usr/bin. On first launch (and after an upgrade) the
# launcher copies the IDE project to the user's XDG data directory so the
# editor can write its .godot import cache without root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
BUILD="$DIST/linux"
PKG="$DIST/packages"
STAGE="$PKG/stage"
APP_NAME="godot-retro-engine"
APP_DIR="/opt/$APP_NAME"
VERSION="${VERSION:-$(sed -n 's/^version="\(.*\)"/\1/p' "$ROOT/ide/addons/retro_engine/plugin.cfg" | head -1)}"
VERSION="${VERSION:-0.1.0}"
MAINTAINER="${MAINTAINER:-Godot Retro Engine <retro@localhost>}"
DESCRIPTION="${DESCRIPTION:-SNES (PVSnesLib) and Mega Drive (SGDK) editor with real ROM builds, hardware-aware editors, emulator integration and a terminal.}"
URL="${URL:-https://github.com}"

if [ ! -x "$BUILD/GodotRetroEngine" ]; then
  echo "==> Linux binary missing; building it first"
  "$ROOT/scripts/build_linux.sh"
fi

rm -rf "$STAGE"
mkdir -p "$STAGE$APP_DIR" "$STAGE/usr/bin" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/scalable/apps"

cp "$BUILD/GodotRetroEngine" "$STAGE$APP_DIR/GodotRetroEngine"
chmod 755 "$STAGE$APP_DIR/GodotRetroEngine"
rsync -a \
  --exclude '.godot/' \
  --exclude 'workspaces/' \
  --exclude 'validation/' \
  "$ROOT/ide/" "$STAGE$APP_DIR/ide/"
cp "$ROOT/README.md" "$ROOT/LICENSE.txt" "$ROOT/LICENSE-RETRO.txt" "$ROOT/LICENSE-NOTICE.md" "$STAGE$APP_DIR/"
if [ -d "$ROOT/docs" ]; then
  cp -R "$ROOT/docs" "$STAGE$APP_DIR/docs"
fi
cp "$ROOT/ide/icon.svg" "$STAGE/usr/share/icons/hicolor/scalable/apps/$APP_NAME.svg"

cat > "$STAGE/usr/bin/$APP_NAME" <<EOF
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="\${GODOT_RETRO_ENGINE_HOME:-$APP_DIR}"
DATA_ROOT="\${GODOT_RETRO_ENGINE_DATA:-\${XDG_DATA_HOME:-\$HOME/.local/share}/$APP_NAME}"
PROJECT_DIR="\$DATA_ROOT/ide"
VERSION="$VERSION"

if [ ! -f "\$PROJECT_DIR/project.godot" ] || [ "\$(cat "\$DATA_ROOT/version" 2>/dev/null || true)" != "\$VERSION" ]; then
  mkdir -p "\$DATA_ROOT"
  if [ -d "\$PROJECT_DIR/workspaces" ]; then
    rm -rf "\$DATA_ROOT/workspaces.keep"
    mv "\$PROJECT_DIR/workspaces" "\$DATA_ROOT/workspaces.keep"
  fi
  rm -rf "\$PROJECT_DIR"
  cp -a "\$APP_DIR/ide" "\$PROJECT_DIR"
  if [ -d "\$DATA_ROOT/workspaces.keep" ]; then
    rm -rf "\$PROJECT_DIR/workspaces"
    mv "\$DATA_ROOT/workspaces.keep" "\$PROJECT_DIR/workspaces"
  fi
  printf '%s\n' "\$VERSION" > "\$DATA_ROOT/version"
fi

mkdir -p "\$PROJECT_DIR/workspaces"
[ -f "\$PROJECT_DIR/workspaces/.gdignore" ] || : > "\$PROJECT_DIR/workspaces/.gdignore"

HAS_PATH=0
for arg in "\$@"; do
  if [ "\$arg" = "--path" ]; then
    HAS_PATH=1
  fi
done
if [ "\$HAS_PATH" -eq 1 ]; then
  exec "\$APP_DIR/GodotRetroEngine" --editor "\$@"
else
  exec "\$APP_DIR/GodotRetroEngine" --editor --path "\$PROJECT_DIR" "\$@"
fi
EOF
chmod 755 "$STAGE/usr/bin/$APP_NAME"

cat > "$STAGE/usr/share/applications/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Godot Retro Engine
GenericName=SNES and Mega Drive game editor
Comment=$DESCRIPTION
Exec=$APP_NAME %F
Icon=$APP_NAME
Terminal=false
Categories=Development;Game;IDE;
Keywords=godot;snes;megadrive;genesis;retro;pvsneslib;sgdk;
StartupWMClass=GodotRetroEngine
EOF

FPM_COMMON=(
  -s dir -C "$STAGE"
  -n "$APP_NAME" -v "$VERSION" --iteration 1 -a native
  --license MIT
  --vendor "Godot Retro Engine"
  --maintainer "$MAINTAINER"
  --description "$DESCRIPTION"
  --deb-user root --deb-group root
  --rpm-user root --rpm-group root
)
if [ -n "$URL" ]; then
  FPM_COMMON+=(--url "$URL")
fi

DEB_DEPS=(
  "libc6 (>= 2.35)"
  "libstdc++6"
  "libgl1"
  "libx11-6"
  "libxcursor1"
  "libxinerama1"
  "libxi6"
  "libxrandr2"
  "libasound2t64 | libasound2"
  "libpulse0"
  "libudev1"
  "libdbus-1-3"
  "libfontconfig1"
  "libfreetype6"
  "libxkbcommon0"
  "libwayland-client0"
)
RPM_DEPS=(
  "glibc"
  "libstdc++"
  "mesa-libGL"
  "libX11"
  "libXcursor"
  "libXinerama"
  "libXi"
  "libXrandr"
  "alsa-lib"
  "pulseaudio-libs"
  "systemd-libs"
  "dbus-libs"
  "fontconfig"
  "freetype"
  "libxkbcommon"
)

DEB_ARGS=()
for dep in "${DEB_DEPS[@]}"; do
  DEB_ARGS+=(--depends "$dep")
done
RPM_ARGS=()
for dep in "${RPM_DEPS[@]}"; do
  RPM_ARGS+=(--depends "$dep")
done

mkdir -p "$PKG"
DEB_PATH="$PKG/${APP_NAME}_${VERSION}_amd64.deb"
RPM_PATH="$PKG/${APP_NAME}-${VERSION}-1.x86_64.rpm"
rm -f "$DEB_PATH" "$RPM_PATH"

echo "==> Building $DEB_PATH"
fpm "${FPM_COMMON[@]}" "${DEB_ARGS[@]}" \
  -t deb --category devel --deb-compression xz --deb-compression-level 9 \
  --after-install "$ROOT/scripts/package_linux_postinstall.sh" \
  --package "$DEB_PATH" .

echo "==> Building $RPM_PATH"
fpm "${FPM_COMMON[@]}" "${RPM_ARGS[@]}" \
  -t rpm --category "Development/Tools" \
  --rpm-compression xz --rpm-compression-level 9 --rpm-os linux \
  --after-install "$ROOT/scripts/package_linux_postinstall.sh" \
  --package "$RPM_PATH" .

echo "==> Packages"
sha256sum "$DEB_PATH" "$RPM_PATH" | tee "$PKG/SHA256SUMS"
ls -lh "$DEB_PATH" "$RPM_PATH"
echo "    Install deb: sudo apt install $DEB_PATH"
echo "    Install rpm: sudo dnf install $RPM_PATH"
