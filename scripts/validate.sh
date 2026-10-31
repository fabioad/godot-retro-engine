#!/usr/bin/env bash
# Create untouched working copies of the three reference projects and run the
# headless module + real toolchain validation on them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/dist/linux/GodotRetroEngine}"
WS="$ROOT/validation"
PROJ="$WS/projects"
mkdir -p "$PROJ"

copy_project() {
  local src="$1" name="$2"
  if [ ! -d "$src" ]; then
    echo "skip (missing): $src"
    return
  fi
  if [ ! -d "$PROJ/$name" ]; then
    echo "==> Copying $src -> $PROJ/$name"
    rsync -a --exclude '.git' --exclude '*.zip' --exclude '*.7z' "$src/" "$PROJ/$name/"
  fi
}

copy_project "/run/media/fabio/Dados/Fabio/dan-java/DanielDoBolosAdventure/daniel_snes" "daniel_snes"
copy_project "/run/media/fabio/Dados/Fabio/sidearms_pc_engine_snes" "sidearms"
copy_project "/run/media/fabio/Dados/Fabio/kof98_port_snes" "kof98"

mkdir -p "$WS/workspace"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/validate.gd -- \
  --workspace "$WS/workspace" \
  --project "$PROJ/daniel_snes" \
  --project "$PROJ/sidearms/port" \
  --project "$PROJ/kof98" \
  --copy 0 --build "${BUILD:-0}" 2>&1 | tee "$WS/validate.log"
cp "$ROOT/ide/validation/headless_report.json" "$WS/headless_report.json" 2>/dev/null || true
"$BIN" --headless --path "$ROOT/ide" --script res://tests/window_controls_test.gd 2>&1 | tee "$WS/window_controls.log"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/missing_sdk_test.gd 2>&1 | tee "$WS/missing_sdk.log"
"$BIN" --headless --editor --path "$ROOT/ide" --script res://tests/terminal_test.gd 2>&1 | tee "$WS/terminal.log"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/input_import_test.gd 2>&1 | tee "$WS/input_import.log"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/new_project_test.gd 2>&1 | tee "$WS/new_project.log"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/rom_profiles_test.gd 2>&1 | tee "$WS/rom_profiles.log"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/snes_rom_build_test.gd 2>&1 | tee "$WS/snes_rom_build.log"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/project_checks_test.gd 2>&1 | tee "$WS/project_checks.log"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/i18n_test.gd 2>&1 | tee "$WS/i18n.log"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/i18n_coverage_test.gd 2>&1 | tee "$WS/i18n_coverage.log"
"$BIN" --headless --path "$ROOT/ide" --script res://tests/resources_category_test.gd 2>&1 | tee "$WS/resources_category.log"
