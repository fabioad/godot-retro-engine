# Terminal

The editor has a **Terminal** main screen next to **Retro**. It runs the
operating system's default shell through a real pseudo-terminal (PTY), not a
command-output text box.

The terminal engine is the MIT-licensed
[GDTerm](https://github.com/markeel/gdterm) extension, vendored at
`ide/addons/gdterm/`. It provides ANSI/VT100 rendering, scrollback, copy/paste,
unicode support and works with interactive programs such as `vi`, `top` and
`tail`. The extension is loaded explicitly by
`ide/addons/terminal/terminal_plugin.gd` before any terminal scene is created.

## Controls

The terminal header has:

```text
[tabs.....................] +  −          Terminals ▾   Aa
```

- `+` sits immediately after the last tab and creates a new terminal tab,
  VSCode-style.
- `−` sits next to `+` and closes the current tab.
- `Terminals ▾` creates a terminal, closes the current one, or selects another
  tab by name.
- `TabBar` switches between terminals and shows the current session. The active
  tab is highlighted and receives keyboard focus automatically, so typing goes
  to the terminal you just selected.
- `Aa` opens the font size menu: increase, decrease, reset, and the current
  size. The same actions are available with `Ctrl+=`, `Ctrl+-` and `Ctrl+0`
  (`Cmd` also works on macOS). Changes apply to every open terminal immediately.
- The chosen size is persisted in `user://terminal.cfg` and restored on the
  next launch. The range is 12–48 px.
- Each PTY has independent scrollback and working directory.
- The in-terminal right-click menu exposes copy, paste, restart and split/new
  terminal actions.

GDTerm starts the operating system's default shell: Linux/macOS use the user's
`$SHELL` (falling back to `/bin/bash`), Windows uses the default
`cmd.exe`/PowerShell through the platform PTY. The Retro build toolchain and
`vendor/sgdk-linux` are unrelated to this shell selection.

## Appearance

The terminal uses an OpenCode-inspired near-black palette:

| Role | Color |
| --- | --- |
| Background | `#0a0a0a` |
| Raised surface / input box | `#1e1e1e` |
| Header | `#0a0a0a` |
| Foreground | `#e0e0e0` |
| Muted text | `#8a8a8a` |
| Border | `#2a2a2a` |
| Primary / active tab | `#5c9cf5` |
| Accent purple | `#9d7cd8` |

The terminal font defaults to **18 px** Source Code Pro (scaled up on high-DPI
editors). Use `Aa` or the shortcuts below to change it. Tabs, buttons and the
`Terminals ▾` popup use the same surfaces, borders and accent color. The active
tab is underlined in OpenCode blue. The header is deliberately thin and black
so OpenCode's own TUI header and content keep the visual focus. Hovering a tab
shows the active font size; the `Terminals ▾` menu also ends with the current
theme/font size.

To override the size without editing files:

```bash
RETRO_TERMINAL_FONT_SIZE=30 dist/linux/run.sh
```

On Linux/macOS the shell is started through a small `user://terminal_shell.sh`
wrapper that exports `TERM=xterm-256color` and `COLORTERM=truecolor` before
executing `$SHELL`. GDTerm's native PTY hardcodes `TERM=ansi`, which makes
truecolor TUI applications (OpenCode, Neovim, etc.) fall back to reduced
colors. The wrapper keeps the real shell and its startup files unchanged.

## Unicode and control strings

The Linux x86_64 GDTerm extension is rebuilt from the pinned upstream revision
with `scripts/gdterm/control_strings.patch`. The patch makes libtmt consume
unsupported OSC, DCS, APC, PM and SOS strings through their complete
terminator, including when a PTY read splits the escape sequence. Unknown CSI
requests are also consumed through their final byte.

This matters for OpenTUI/OpenCode: the OSC 66 text-sizing probe used to leak
its terminating backslash as text, so Unicode block characters in the
OpenCode logo were discarded and printed as `\` bars. With the patch the
logo renders as the intended block letters, and the regression test checks
every possible read boundary:

```text
TERMINAL_CONTROL_STRINGS PASS (all read boundaries)
```

Rebuild the extension with:

```bash
scripts/build_gdterm.sh
TARGET=template_release scripts/build_gdterm.sh
```

The source checkout is pinned and goes to `vendor/gdterm/` (ignored by Git).
The Windows/macOS binaries remain the upstream prebuilt libraries until they
are rebuilt on those platforms.

## Tests

```bash
# Control-string/Unicode regression
"${CC:-cc}" -DFORCE_UTF8 -I vendor/gdterm/src/gdterm/pty/thirdparty/libtmt \
  scripts/gdterm/control_strings_test.c \
  vendor/gdterm/src/gdterm/pty/thirdparty/libtmt/tmt.c \
  vendor/gdterm/src/gdterm/pty/thirdparty/libtmt/u8mbtowc.c \
  vendor/gdterm/src/gdterm/pty/thirdparty/libtmt/wide_lookup.c \
  -o /tmp/gdterm-control-strings && /tmp/gdterm-control-strings

# Headless extension/plugin parse, PTY, tabs and font controls
"$BIN" --headless --editor --path ide --script res://tests/terminal_test.gd
```

The terminal plugin never runs during normal Retro builds; a terminal failure
only affects the Terminal screen and shows an explanatory message.
