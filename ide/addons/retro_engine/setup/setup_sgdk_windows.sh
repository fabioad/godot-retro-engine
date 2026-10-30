#!/usr/bin/env bash
# Prepare SGDK 2.11 for native Windows (Git Bash / MSYS2).
#
# SGDK already ships gcc.exe, make.exe, sjasm.exe, convsym.exe, bintos.exe and
# rescomp.jar. This script validates them, writes Git Bash wrappers for the
# extensionless m68k-elf-* names expected by the IDE, and generates env.sh,
# env.bat and env.ps1.
#
# Usage (Git Bash):
#   SGDK_ROOT=/c/sgdk211 scripts/setup_sgdk_windows.sh [--install-deps]
#   source vendor/sgdk-win/env.sh
#   scripts/build_windows.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
OUT="${RETRO_SGDK_OUT:-$PWD/vendor/sgdk-win}"
BIN="${RETRO_SGDK_BIN:-$OUT/bin}"
TEST_DIR="${RETRO_SGDK_TEST:-$OUT/test}"
NO_SMOKE=0
INSTALL_DEPS=0
for arg in "$@"; do
  case "$arg" in
    --no-smoke) NO_SMOKE=1 ;;
    --install-deps) INSTALL_DEPS=1 ;;
  esac
done

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *)
    if [ "${RETRO_SETUP_ALLOW_NON_WINDOWS:-0}" != "1" ]; then
      echo "Run this script in Git Bash or MSYS2 on Windows (or set RETRO_SETUP_ALLOW_NON_WINDOWS=1 for testing)." >&2
      exit 1
    fi
    ;;
esac

if ! command -v cygpath >/dev/null 2>&1; then
  echo "Required tool not found: cygpath (run this in Git Bash or MSYS2)" >&2
  exit 1
fi

if ! command -v java >/dev/null 2>&1 && [ "$INSTALL_DEPS" -eq 1 ] \
    && command -v winget.exe >/dev/null 2>&1; then
  echo "==> Installing Java with winget"
  winget.exe install --id Microsoft.OpenJDK.21 --silent \
    --accept-source-agreements --accept-package-agreements || true
  for candidate in \
    "/c/Program Files/Microsoft/jdk-"*/bin \
    "/c/Program Files/Eclipse Adoptium/jdk-"*/bin \
    "/c/Program Files/Java/jdk-"*/bin; do
    if [ -x "$candidate/java.exe" ]; then
      export PATH="$candidate:$PATH"
      break
    fi
  done
fi

if ! command -v java >/dev/null 2>&1; then
  echo "Required tool not found: java. Install a JDK or rerun with --install-deps." >&2
  exit 1
fi

find_sgdk() {
  local candidate
  for candidate in \
    "${SGDK_ROOT:-}" "${GDK:-}" \
    "$ROOT/vendor/sgdk211" "$ROOT/../sgdk211" \
    "$HOME/sgdk211" "$HOME/sgdk"; do
    [ -n "$candidate" ] || continue
    case "$candidate" in
      [A-Za-z]:*) candidate="$(cygpath -u "$candidate" 2>/dev/null || printf '%s' "$candidate")" ;;
    esac
    if [ -f "$candidate/bin/gcc.exe" ] && [ -f "$candidate/bin/make.exe" ]; then
      (cd "$candidate" && pwd)
      return 0
    fi
  done
  if [ -n "${USERPROFILE:-}" ]; then
    candidate="$(cygpath -u "$USERPROFILE")/sgdk211"
    if [ -f "$candidate/bin/gcc.exe" ] && [ -f "$candidate/bin/make.exe" ]; then
      (cd "$candidate" && pwd)
      return 0
    fi
  fi
  candidate="/c/sgdk211"
  if [ -f "$candidate/bin/gcc.exe" ] && [ -f "$candidate/bin/make.exe" ]; then
    (cd "$candidate" && pwd)
    return 0
  fi
  return 1
}

if ! SGDK_ROOT="$(find_sgdk)"; then
  cat >&2 <<'EOF'
SGDK 2.11 was not found.
Set SGDK_ROOT to the folder containing bin/gcc.exe, inc/genesis.h and lib/libmd.a.
Example:
  SGDK_ROOT=/c/sgdk211 scripts/setup_sgdk_windows.sh
EOF
  exit 1
fi

for tool in gcc.exe make.exe sjasm.exe convsym.exe bintos.exe rescomp.jar; do
  if [ ! -f "$SGDK_ROOT/bin/$tool" ]; then
    echo "SGDK is incomplete: missing bin/$tool" >&2
    exit 1
  fi
done

SGDK_WIN="$(cygpath -m "$SGDK_ROOT")"
SGDK_BACK="$(cygpath -w "$SGDK_ROOT")"

mkdir -p "$BIN"

cat > "$BIN/_win_common.sh" <<'EOF'
#!/usr/bin/env bash
# Shared path conversion for the Windows SGDK wrappers.
SGDK="${RETRO_SGDK_ROOT:-}"
if [ -z "$SGDK" ]; then
  echo "RETRO_SGDK_ROOT is not set; source vendor/sgdk-win/env.sh" >&2
  exit 1
fi

winpath() {
  cygpath -w "$1" 2>/dev/null || printf '%s' "$1"
}

convert_arg() {
  a="$1"
  case "$a" in
    @/*) printf '@%s' "$(winpath "${a#@}")" ;;
    /*) winpath "$a" ;;
    -B/*|-I/*|-L/*|-T/*|-o/*|-MF/*|-MT/*|-include/*|-isystem/*|-iquote/*|-idirafter/*)
      pre="${a%%/*}"
      rest="${a#*/}"
      val="$(winpath "/$rest")"
      if [ "$pre" = "-B" ]; then
        val="${val%\\}\\"
      fi
      printf '%s/%s' "$pre" "$val"
      ;;
    *) printf '%s' "$a" ;;
  esac
}
EOF

cat > "$BIN/m68k-elf-gcc" <<'EOF'
#!/usr/bin/env bash
set -e
. "$(dirname "$0")/_win_common.sh"
args=()
for a in "$@"; do
  case "$a" in
    -MMD|-MD|-MP) continue ;;
  esac
  args+=("$(convert_arg "$a")")
done
exec "$SGDK/bin/gcc.exe" "${args[@]}"
EOF

for tool in ar as ld nm objcopy objdump ranlib strip; do
cat > "$BIN/m68k-elf-$tool" <<EOF
#!/usr/bin/env bash
set -e
. "\$(dirname "\$0")/_win_common.sh"
args=()
for a in "\$@"; do
  args+=("\$(convert_arg "\$a")")
done
exec "\$SGDK/bin/$tool.exe" "\${args[@]}"
EOF
done

for tool in sjasm convsym bintos mac68k; do
cat > "$BIN/$tool" <<EOF
#!/usr/bin/env bash
set -e
. "\$(dirname "\$0")/_win_common.sh"
args=()
for a in "\$@"; do
  args+=("\$(convert_arg "\$a")")
done
exec "\$SGDK/bin/$tool.exe" "\${args[@]}"
EOF
done

cat > "$BIN/make" <<'EOF'
#!/usr/bin/env bash
set -e
. "$(dirname "$0")/_win_common.sh"
exec "$SGDK/bin/make.exe" "$@"
EOF
chmod +x "$BIN"/*

{
  printf '# Generated by scripts/setup_sgdk_windows.sh\n'
  printf 'export RETRO_SGDK_ROOT=%q\n' "$SGDK_WIN"
  printf 'export GDK=%q\n' "$SGDK_WIN"
  printf 'export PATH=%q:$PATH\n' "$BIN"
} > "$OUT/env.sh"

cat > "$OUT/env.bat" <<EOF
@echo off
set "RETRO_SGDK_ROOT=$SGDK_BACK"
set "GDK=%RETRO_SGDK_ROOT%"
set "PATH=%RETRO_SGDK_ROOT%\\bin;%PATH%"
EOF

cat > "$OUT/env.ps1" <<EOF
\$env:RETRO_SGDK_ROOT = '$SGDK_BACK'
\$env:GDK = \$env:RETRO_SGDK_ROOT
\$env:PATH = "\$env:RETRO_SGDK_ROOT\\bin;" + \$env:PATH
EOF

if [ "$NO_SMOKE" -eq 0 ]; then
  echo "==> Smoke test (SGDK sample copied under $TEST_DIR)"
  rm -rf "$TEST_DIR"
  cp -a "$SGDK_ROOT/sample/basics/image" "$TEST_DIR"
  SGDK_MAKE="${SGDK_WIN// /\\ }"
  cat > "$TEST_DIR/Makefile" <<EOF
GDK := $SGDK_MAKE
include \$(GDK)/makefile.gen
EOF
  (
    cd "$TEST_DIR"
    export RETRO_SGDK_ROOT="$SGDK_WIN"
    export GDK="$SGDK_WIN"
    export PATH="$BIN:$PATH"
    "$BIN/make" clean >/dev/null 2>&1 || true
    if ! "$BIN/make" -j1 > "$OUT/smoke.log" 2>&1; then
      echo "SGDK smoke test failed:" >&2
      tail -40 "$OUT/smoke.log" >&2
      exit 1
    fi
  )
  if [ ! -s "$TEST_DIR/out/rom.bin" ]; then
    echo "Smoke test did not produce $TEST_DIR/out/rom.bin" >&2
    exit 1
  fi
  echo "    ROM: $TEST_DIR/out/rom.bin"
fi

cat <<EOF
==> SGDK Windows toolchain ready.
    Git Bash:  source $OUT/env.sh
    cmd.exe:   $OUT\\env.bat
    PowerShell: . $OUT\\env.ps1
    Then launch the editor or run scripts/build_windows.sh from the same shell.
EOF
