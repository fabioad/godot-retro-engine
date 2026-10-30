# Embedded terminal control strings

GDTerm is pinned to `5e8595f2c9142478d9efb7b729cb85a07975764f`, with its
original pinned godot-cpp and libtmt submodules. `control_strings.patch` fixes
unsupported OSC/DCS/APC/PM/SOS strings and CSI queries being printed as text.

Previously `ESC ] ... ESC \\` leaked the final backslash into the terminal and
advanced the cursor. OpenTUI's OSC 66 probe then falsely detected text-sizing
support. OpenCode wrapped Unicode logo blocks and symbols in OSC 66 strings;
the emulator discarded their content and printed backslashes instead.

Unsupported strings now consume their complete terminator, including when
PTY reads split the escape sequence. Unsupported CSI requests are consumed
through their final byte. The regression test covers every read boundary and
checks subsequent UTF-8 text and cursor position.

Rebuild the Linux x86_64 debug extension used by the editor:

```sh
scripts/build_gdterm.sh
```

Requires Git, a C/C++ compiler, Python and SCons. To reuse a source checkout:

```sh
GDTERM_SOURCE=/tmp/gdterm scripts/build_gdterm.sh
```

Build the Linux release extension with `TARGET=template_release scripts/build_gdterm.sh`.

The other prebuilt platforms remain upstream binaries until rebuilt with this
patch. The Linux editor loads `libgdterm.linux.template_debug.x86_64.so`.
