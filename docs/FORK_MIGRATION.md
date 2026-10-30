# Fork integration

This fork uses the official Godot `4.7.2-stable` tag as its parent. The
`retro-engine` branch preserves the upstream history; the original project's
independent commit history is not imported. The local `master` branch is kept.

Every upstream file in the original `vendor/godot` was compared to the tag.
The contents match after CRLF/LF normalization. No engine source patches
were needed outside the new `modules/retro_engine` directory.

- `modules/retro_engine`: original C++ module, moved from `overlay/modules`.
- `ide`: original editor workspace, addons, assets and headless tests.
- `scripts`: build and validation tools; engine builds run from the root.
- `examples` and `docs`: original examples and documentation.
- `LICENSE.txt` and `COPYRIGHT.txt`: unchanged upstream license notices.
- `LICENSE-RETRO.txt`: license of the original Retro additions.
- `docs/UPSTREAM_README.md`: original Godot README.

Build products, imported workspaces, validation fixtures, external SDKs and
local agent settings are excluded. Historical validation results in
`docs/VALIDATION.md` describe the original project, not a fresh full test run.

Build and launch on Linux:

```sh
scripts/build_linux.sh
scripts/run_linux.sh
```

## Migration validation

- Compared all upstream source files with the official `4.7.2-stable` tag:
  identical after CRLF/LF normalization.
- All shell scripts passed `bash -n`; prerequisite checks passed.
- SCons dry run completed and includes the Retro module in the build plan.
- Headless editor import passed without errors.
- Backend smoke, project coherence, localization and localization coverage
  tests passed using the existing 4.7.2 executable from the original project.

A complete recompilation of the migrated checkout has not been run. SDK ROM
builds and Windows/macOS builds have not been repeated for this migration.
