#!/usr/bin/env bash
# Build the two real state-machine demo ROMs from the committed examples.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
PVS="${PVSNESLIB_HOME:-/run/media/fabio/Dados/Fabio/pvsneslib-sdk-4.6}"
SGDK="${GDK:-/run/media/fabio/Dados/Fabio/sgdk211}"
WS="$ROOT/validation/projects"

for pair in "snes retro_sm_snes" "md retro_sm_md"; do
  set -- $pair
  kind=$1; name=$2
  rm -rf "$WS/$name"; cp -a "$ROOT/examples/state_machine_$kind" "$WS/$name"
done

"$BIN" --headless --path "$ROOT/ide" --script res://tests/generate_sm.gd -- \
  --platform snes --dir "$WS/retro_sm_snes/src"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/generate_sm.gd -- \
  --platform megadrive --dir "$WS/retro_sm_md/src"

(
  cd "$WS/retro_sm_snes"
  PVSNESLIB_HOME="$PVS" make -j4
)
(
  cd "$WS/retro_sm_md"
  source "$ROOT/vendor/sgdk-linux/env.sh"
  GDK="$SGDK" make -j1 LIBGCC="$SGDK/lib/libgcc.a"
)

echo "==> $WS/retro_sm_snes/retro_sm_snes.sfc"
echo "==> $WS/retro_sm_md/out/rom.bin"
