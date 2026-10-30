#!/usr/bin/env bash
# Shared SGDK setup for Linux and macOS.
#
# SGDK 2.11 ships Windows m68k-elf GCC binaries and tools sources. This script
# runs the Windows compiler through Wine and builds sjasm, convsym and bintos
# natively, then writes wrappers and an env.sh for the IDE.
#
# Usage: setup_sgdk_unix.sh linux|macos [--no-smoke] [--install-deps]
set -euo pipefail

PLATFORM="${1:-}"
shift || true
if [ "$PLATFORM" != "linux" ] && [ "$PLATFORM" != "macos" ]; then
  echo "usage: $0 linux|macos [--no-smoke] [--install-deps]" >&2
  exit 2
fi
NO_SMOKE=0
INSTALL_DEPS=0
for arg in "$@"; do
  case "$arg" in
    --no-smoke) NO_SMOKE=1 ;;
    --install-deps) INSTALL_DEPS=1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
OUT="${RETRO_SGDK_OUT:-$PWD/vendor/sgdk-$PLATFORM}"
BIN="${RETRO_SGDK_BIN:-$OUT/bin}"
SRC="${RETRO_SGDK_SRC:-$OUT/src}"
TEST_DIR="${RETRO_SGDK_TEST:-$OUT/test}"

if [ "$PLATFORM" = "macos" ] && [ "$(uname -s)" != "Darwin" ] \
    && [ "${RETRO_SETUP_ALLOW_NON_MACOS:-0}" != "1" ]; then
  echo "The macOS setup must run on macOS (or set RETRO_SETUP_ALLOW_NON_MACOS=1 for testing)." >&2
  exit 1
fi

find_sgdk() {
  local candidate
  for candidate in \
    "${SGDK_ROOT:-}" "${GDK:-}" \
    "$ROOT/vendor/sgdk211" "$ROOT/../sgdk211" \
    "$HOME/sgdk211" "$HOME/sgdk" \
    "/opt/sgdk211" "/usr/local/sgdk211"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate/bin/gcc.exe" ] && [ -d "$candidate/tools/sjasm/src" ]; then
      (cd "$candidate" && pwd)
      return 0
    fi
  done
  return 1
}

if ! SGDK_ROOT="$(find_sgdk)"; then
  cat >&2 <<'EOF'
SGDK 2.11 was not found.
Set SGDK_ROOT to the folder containing bin/gcc.exe, inc/genesis.h, lib/libmd.a
and tools/. Example:
  SGDK_ROOT="$HOME/sgdk211" scripts/setup_sgdk_linux.sh
EOF
  exit 1
fi

run_privileged() {
  if [ "${RETRO_SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "+ $*"
    return 0
  fi
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return 0
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    echo "+ sudo $*"
    sudo -n "$@"
    return 0
  fi
  if command -v pkexec >/dev/null 2>&1; then
    echo "+ pkexec $*"
    pkexec "$@"
    return 0
  fi
  echo "Automatic installation needs root: run the setup script from a terminal with sudo." >&2
  return 1
}

install_linux_deps() {
  echo "==> Installing Wine, Java and build tools"
  if command -v apt-get >/dev/null 2>&1; then
    run_privileged sh -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y wine default-jre-headless make gcc python3'
  elif command -v dnf >/dev/null 2>&1; then
    run_privileged dnf install -y wine java-21-openjdk-headless make gcc python3
  elif command -v pacman >/dev/null 2>&1; then
    run_privileged pacman -S --needed --noconfirm wine jdk-openjdk base-devel python
  elif command -v zypper >/dev/null 2>&1; then
    run_privileged zypper --non-interactive install wine java-21-openjdk make gcc python3
  else
    echo "No supported package manager found (apt-get, dnf, pacman or zypper)." >&2
    return 1
  fi
  if [ "${RETRO_SETUP_DRY_RUN:-0}" != "1" ] && command -v wine >/dev/null 2>&1; then
    if ! WINEDEBUG=-all wine "$SGDK_ROOT/bin/gcc.exe" --version >/dev/null 2>&1; then
      echo "Wine is installed but cannot run SGDK's 32-bit gcc.exe." >&2
      echo "On Debian/Ubuntu enable i386 and install wine32:i386; on Fedora install wine-core.i686." >&2
    fi
  fi
}

install_macos_deps() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required for automatic Wine/Java installation." >&2
    echo "Install Homebrew from https://brew.sh and rerun the setup." >&2
    return 1
  fi
  echo "==> Installing Wine, GNU make and Java with Homebrew"
  HOMEBREW_NO_AUTO_UPDATE=1 brew install make
  HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask --no-quarantine wine-stable
  HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask temurin
  for candidate in /Library/Java/JavaVirtualMachines/*/Contents/Home/bin; do
    if [ -x "$candidate/java" ]; then
      export PATH="$candidate:$PATH"
      break
    fi
  done
}

needs_install() {
  [ "$INSTALL_DEPS" -eq 1 ] || return 1
  [ "${RETRO_SETUP_FORCE_DEPS:-0}" = "1" ] && return 0
  if ! find_wine >/dev/null 2>&1; then
    return 0
  fi
  if [ "$PLATFORM" = "macos" ]; then
    ! command -v gmake >/dev/null 2>&1 || ! command -v java >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1
  else
    ! command -v make >/dev/null 2>&1 || ! command -v cc >/dev/null 2>&1 || ! command -v java >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1
  fi
}


find_wine() {
  local candidate
  if [ -n "${RETRO_WINE:-}" ]; then
    printf '%s\n' "$RETRO_WINE"
    return 0
  fi
  if [ -n "${WINECMD:-}" ]; then
    printf '%s\n' "$WINECMD"
    return 0
  fi
  for candidate in wine wine64; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  if [ "$PLATFORM" = "macos" ]; then
    for candidate in \
      "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine" \
      "/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine" \
      "/opt/homebrew/bin/wine" "/usr/local/bin/wine"; do
      if [ -x "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  fi
  return 1
}

if needs_install; then
  if [ "$PLATFORM" = "macos" ]; then
    install_macos_deps || true
  else
    install_linux_deps || true
  fi
fi

if ! WINECMD="$(find_wine)"; then
  if [ "$PLATFORM" = "macos" ]; then
    echo "Wine is required for SGDK's Windows m68k-elf GCC binaries." >&2
    echo "Install it with 'brew install --cask wine-stable' or use a native m68k-elf toolchain." >&2
  else
    echo "Wine is required for SGDK's Windows m68k-elf GCC binaries." >&2
    echo "Install it with 'sudo apt install wine64' or use a native m68k-elf toolchain." >&2
  fi
  exit 1
fi

MAKE="${MAKE:-}"
if [ -z "$MAKE" ]; then
  if command -v gmake >/dev/null 2>&1; then
    MAKE=gmake
  else
    MAKE=make
  fi
fi
CC="${CC:-}"
if [ -z "$CC" ]; then
  if command -v cc >/dev/null 2>&1; then
    CC=cc
  elif command -v clang >/dev/null 2>&1; then
    CC=clang
  else
    CC=gcc
  fi
fi
for tool in "$MAKE" "$CC" python3 java; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool not found: $tool" >&2
    exit 1
  fi
done

if [ "$PLATFORM" = "macos" ]; then
  JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
else
  JOBS="$(nproc 2>/dev/null || echo 4)"
fi
[ "$JOBS" -gt 12 ] && JOBS=12

mkdir -p "$BIN" "$SRC"

echo "==> SGDK root: $SGDK_ROOT"
echo "==> Wine: $WINECMD"
echo "==> Building host tools (sjasm, convsym, bintos)"
rm -rf "$SRC/sjasm" "$SRC/convsym"
cp -a "$SGDK_ROOT/tools/sjasm/src" "$SRC/sjasm"
cp -a "$SGDK_ROOT/tools/convsym" "$SRC/convsym"
find "$SRC/sjasm" "$SRC/convsym" -name '*.o' -delete 2>/dev/null || true
rm -rf "$SRC/convsym/build"
"$MAKE" -C "$SRC/sjasm" -j"$JOBS" >/dev/null
"$MAKE" -C "$SRC/convsym" -j"$JOBS" >/dev/null
"$CC" -O2 -o "$BIN/bintos" "$SGDK_ROOT/tools/bintos/src/bintos.c"
cp "$SRC/sjasm/sjasm" "$BIN/sjasm"
cp "$SRC/convsym/build/convsym" "$BIN/convsym"

echo "==> Generating Wine wrappers"
WINE_JSON="$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$WINECMD")"
cat > "$BIN/_wine_common.py" <<PYEOF
import os
import sys

SGDK = os.environ.get("RETRO_SGDK_ROOT", "")
WINE = ${WINE_JSON}


def to_win(path: str) -> str:
    if path.startswith("/"):
        return "Z:" + path.replace("/", "\\\\")
    return path


def run(tool: str, args, env_extra=None):
    if not SGDK:
        raise SystemExit("RETRO_SGDK_ROOT is not set; source vendor/sgdk-${PLATFORM}/env.sh")
    exe = os.path.join(SGDK, "bin", tool + ".exe")
    env = dict(os.environ)
    env["WINEDEBUG"] = "-all"
    if env_extra:
        env.update(env_extra)
    os.execvpe(WINE, [WINE, exe] + list(args), env)
PYEOF

cat > "$BIN/m68k-elf-gcc" <<'PYEOF'
#!/usr/bin/env python3
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import _wine_common as W

args = []
for a in sys.argv[1:]:
    # Wine writes .d files with Windows drive paths; make cannot parse those.
    if a in ("-MMD", "-MD", "-MP"):
        continue
    if a.startswith("/"):
        a = W.to_win(a)
    elif a.startswith("@"):
        a = "@" + W.to_win(a[1:])
    else:
        for pre in ("-B", "-I", "-L", "-T", "-o", "-MF", "-MT", "-include", "-isystem", "-iquote", "-idirafter"):
            if a.startswith(pre) and len(a) > len(pre) and a[len(pre)] == "/":
                val = W.to_win(a[len(pre):])
                if pre == "-B":
                    val = val.rstrip("\\") + "\\"
                a = pre + val
                break
    args.append(a)
W.run("gcc", args)
PYEOF

for tool in ar as ld nm objcopy objdump ranlib strip; do
cat > "$BIN/m68k-elf-$tool" <<PYEOF
#!/usr/bin/env python3
import os
import sys
sys.path.insert(0, os.path.dirname(__file__))
import _wine_common as W
W.run("$tool", [W.to_win(a) for a in sys.argv[1:]])
PYEOF
done

cat > "$BIN/mac68k" <<'PYEOF'
#!/usr/bin/env python3
import os
import sys
sys.path.insert(0, os.path.dirname(__file__))
import _wine_common as W
W.run("mac68k", [W.to_win(a) for a in sys.argv[1:]])
PYEOF
chmod +x "$BIN"/*

{
  printf '# Generated by scripts/setup_sgdk_%s.sh\n' "$PLATFORM"
  printf 'export RETRO_SGDK_ROOT=%q\n' "$SGDK_ROOT"
  printf 'export GDK=%q\n' "$SGDK_ROOT"
  printf 'export RETRO_WINE=%q\n' "$WINECMD"
  printf 'export PATH=%q:$PATH\n' "$BIN"
} > "$OUT/env.sh"

if [ "$NO_SMOKE" -eq 0 ]; then
  echo "==> Smoke test (SGDK sample copied under $TEST_DIR)"
  rm -rf "$TEST_DIR"
  cp -a "$SGDK_ROOT/sample/basics/image" "$TEST_DIR"
  cat > "$TEST_DIR/Makefile" <<EOF
GDK := $SGDK_ROOT
include \$(GDK)/makefile.gen
EOF
  (
    cd "$TEST_DIR"
    export RETRO_SGDK_ROOT="$SGDK_ROOT"
    export GDK="$SGDK_ROOT"
    export RETRO_WINE="$WINECMD"
    export PATH="$BIN:$PATH"
    "$MAKE" clean >/dev/null 2>&1 || true
    "$MAKE" -j1 LIBGCC="$SGDK_ROOT/lib/libgcc.a" >/dev/null
  )
  if [ ! -s "$TEST_DIR/out/rom.bin" ]; then
    echo "Smoke test did not produce $TEST_DIR/out/rom.bin" >&2
    exit 1
  fi
  echo "    ROM: $TEST_DIR/out/rom.bin"
fi

cat <<EOF
==> SGDK $PLATFORM toolchain ready.
    source $OUT/env.sh
    Then launch the editor from that shell:
EOF
if [ "$PLATFORM" = "macos" ]; then
  cat <<EOF
      scripts/build_macos.sh
      dist/macos/run.sh
EOF
else
  cat <<EOF
      scripts/run_linux.sh
EOF
fi
