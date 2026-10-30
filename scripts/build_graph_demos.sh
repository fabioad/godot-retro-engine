#!/usr/bin/env bash
# Build graph-runtime demo ROMs for both consoles from the committed examples.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
PVS="${PVSNESLIB_HOME:-/run/media/fabio/Dados/Fabio/pvsneslib-sdk-4.6}"
SGDK="${GDK:-/run/media/fabio/Dados/Fabio/sgdk211}"
WS="$ROOT/validation/projects"
rm -rf "$WS/retro_graph_snes" "$WS/retro_graph_md"
cp -a "$ROOT/examples/state_machine_snes" "$WS/retro_graph_snes"
cp -a "$ROOT/examples/state_machine_md" "$WS/retro_graph_md"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/generate_graph.gd -- \
  --platform snes --dir "$WS/retro_graph_snes/src" >/dev/null
"$BIN" --headless --path "$ROOT/ide" --script res://tests/generate_graph.gd -- \
  --platform megadrive --dir "$WS/retro_graph_md/src" >/dev/null
(
  cd "$WS/retro_graph_snes"
  PVSNESLIB_HOME="$PVS" make -j4 >/dev/null
)
(
  cd "$WS/retro_graph_md"
  source "$ROOT/vendor/sgdk-linux/env.sh"
  GDK="$SGDK" make -j1 LIBGCC="$SGDK/lib/libgcc.a" >/dev/null
)
echo "==> $WS/retro_graph_snes/retro_sm_snes.sfc"
echo "==> $WS/retro_graph_md/out/rom.bin"
