#!/usr/bin/env bash
# Native Linux editor build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
scripts/bootstrap.sh
SCONS="${SCONS:-$HOME/.local/bin/scons}"
command -v "$SCONS" >/dev/null 2>&1 || SCONS=scons
JOBS="${JOBS:-$(nproc)}"
# Keep memory bounded on 16 GB workstations while still using the cores.
[ "$JOBS" -gt 12 ] && JOBS=12

cd "$ROOT"
"$SCONS" platform=linuxbsd target=editor use_lto=no -j"$JOBS" \
  "$@"

mkdir -p "$ROOT/dist/linux"
BUILT="$(ls -t bin/godot.linuxbsd.editor.x86_64* 2>/dev/null | head -1 || true)"
if [ -z "$BUILT" ]; then
  echo "Editor binary not found in bin" >&2
  exit 1
fi
# The dist binary may be running right now (the editor keeps it open), and
# Linux refuses to overwrite a busy executable. Stage it and rename instead;
# the running process keeps the old inode.
cp "$BUILT" "$ROOT/dist/linux/GodotRetroEngine.new"
mv -f "$ROOT/dist/linux/GodotRetroEngine.new" "$ROOT/dist/linux/GodotRetroEngine"
chmod +x "$ROOT/dist/linux/GodotRetroEngine"
# Imported project working copies live inside dist/linux/ide/workspaces. They
# are user data, so keep them across rebuilds instead of deleting the tree.
PRESERVED_WS=""
if [ -d "$ROOT/dist/linux/ide/workspaces" ]; then
  PRESERVED_WS="$(mktemp -d "$ROOT/dist/linux/.workspaces.XXXXXX")"
  mv "$ROOT/dist/linux/ide/workspaces" "$PRESERVED_WS/workspaces"
fi
rm -rf "$ROOT/dist/linux/ide"; cp -r "$ROOT/ide" "$ROOT/dist/linux/ide"
if [ -n "$PRESERVED_WS" ]; then
  rm -rf "$ROOT/dist/linux/ide/workspaces"
  mv "$PRESERVED_WS/workspaces" "$ROOT/dist/linux/ide/workspaces"
  rmdir "$PRESERVED_WS"
fi
cp "$ROOT/README.md" "$ROOT/dist/linux/" 2>/dev/null || true

cat > "$ROOT/dist/linux/run.sh" <<'EOF'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Keep imported working copies out of Godot's own resource importer (binary
# .obj build artifacts would be parsed as Wavefront OBJ text).
mkdir -p "$DIR/ide/workspaces"
[ -f "$DIR/ide/workspaces/.gdignore" ] || : > "$DIR/ide/workspaces/.gdignore"
exec "$DIR/GodotRetroEngine" --editor --path "$DIR/ide" "$@"
EOF
chmod +x "$ROOT/dist/linux/run.sh"

echo "==> Built $ROOT/dist/linux/GodotRetroEngine"
echo "    Run: $ROOT/dist/linux/run.sh"
