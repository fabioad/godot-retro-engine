#!/usr/bin/env bash
# Rebuild GDTerm with the terminal control-string fixes used by the IDE.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${GDTERM_SOURCE:-$ROOT/vendor/gdterm}"
REVISION=5e8595f2c9142478d9efb7b729cb85a07975764f
if [ ! -d "$SOURCE/.git" ]; then
  git clone https://github.com/markeel/gdterm.git "$SOURCE"
  git -C "$SOURCE" checkout "$REVISION"
fi
if [ "$(git -C "$SOURCE" rev-parse HEAD)" != "$REVISION" ]; then
  echo "Expected GDTerm revision $REVISION in $SOURCE" >&2
  exit 1
fi
git -C "$SOURCE" submodule update --init godot-cpp src/gdterm/pty/thirdparty/libtmt
PATCH="$ROOT/scripts/gdterm/control_strings.patch"
if ! git -C "$SOURCE" apply --reverse --check "$PATCH" 2>/dev/null; then
  git -C "$SOURCE" apply --check "$PATCH"
  git -C "$SOURCE" apply "$PATCH"
fi
TMT="$SOURCE/src/gdterm/pty/thirdparty/libtmt"
TEST_BIN="$(mktemp /tmp/gdterm-control-strings.XXXXXX)"
trap 'rm -f "$TEST_BIN"' EXIT
"${CC:-cc}" -DFORCE_UTF8 -I "$TMT" "$ROOT/scripts/gdterm/control_strings_test.c" \
  "$TMT/tmt.c" "$TMT/u8mbtowc.c" "$TMT/wide_lookup.c" -o "$TEST_BIN"
"$TEST_BIN"
SCONS="${SCONS:-$HOME/.local/bin/scons}"
command -v "$SCONS" >/dev/null 2>&1 || SCONS=scons
TARGET="${TARGET:-template_debug}"
case "$TARGET" in template_debug|template_release) ;; *) echo "Invalid TARGET: $TARGET" >&2; exit 1 ;; esac
cd "$SOURCE"
# This script installs the Linux x86_64 extension bundled with the IDE.
"$SCONS" platform=linux arch=x86_64 target="$TARGET" -j"${JOBS:-8}" \
  build_profile="$ROOT/scripts/gdterm/build_profile.json"
# Stage and rename: an open editor may still have the previous library mapped.
for LIB in "addons/gdterm/bin/libgdterm.linux.$TARGET.x86_64.so"; do
  cp "$LIB" "$ROOT/ide/addons/gdterm/bin/$(basename "$LIB").new"
  mv -f "$ROOT/ide/addons/gdterm/bin/$(basename "$LIB").new" "$ROOT/ide/addons/gdterm/bin/$(basename "$LIB")"
done
