#!/usr/bin/env bash
# Check the native fork checkout and build prerequisites.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -f "$ROOT/SConstruct" ] || [ ! -f "$ROOT/modules/retro_engine/SCsub" ]; then
  echo "Expected the Godot Retro Engine fork with modules/retro_engine in the repository root." >&2
  exit 1
fi
SCONS="${SCONS:-$HOME/.local/bin/scons}"
if ! command -v "$SCONS" >/dev/null 2>&1 && ! command -v scons >/dev/null 2>&1; then
  echo "SCons is required. Install it with your package manager or: python3 -m pip install --user scons" >&2
  exit 1
fi
echo "==> Godot source and Retro module ready in $ROOT"
echo "    Next: scripts/build_linux.sh (or the Windows/macOS build script)"
