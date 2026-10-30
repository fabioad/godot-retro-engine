# Retro addon localization

The Retro addon follows the editor locale through
`TranslationServer.get_locale()`. When Godot's editor is in Brazilian Portuguese,
the Retro UI is in Brazilian Portuguese; English is used for English locales and
as the fallback for unsupported languages.

## Languages

All 40 Godot 4.7 editor locales have a dictionary:

```text
ar bg bn ca cs de el eo es es_AR et fa fi fr ga gl he hu id it
ja ka ko lo nl pl pt pt_BR ro ru sk sv ta th tok tr uk vi
zh_Hans zh_Hant
```

Regional/script variants resolve to the closest dictionary: `pt_PT → pt`,
`fr_FR → fr`, `de_DE → de`, `es_MX → es`, `zh_CN → zh_Hans`,
`zh_TW → zh_Hant`, `en_GB → en`.

The data lives in:

```text
ide/addons/retro_engine/locales.json   # 41 dictionaries (40 Godot locales + en)
ide/addons/retro_engine/i18n.gd        # small lazy loader + locale resolution
```

The JSON is loaded lazily because a single 16k-entry GDScript dictionary exceeds
the GDScript parser limits. English is the source language; `pt_BR` is the
hand-reviewed Portuguese reference. The other locales were generated in bulk
with a translation service and should be reviewed by native speakers over time.
Technical terms (`Sprite`, `Stage`, `Build`, `Tile`, `Map`, `ROM`, `SNES`,
`Mega Drive`, `PVSnesLib`, `SGDK`, ...) are protected from translation so they
remain consistent; Toki Pona has no supported machine translator and uses the
English dictionary (fallback).

Use `I18n.t("key", {"name": value})`; placeholders are named (`{name}`,
`{path}`, `{project}`, ...). `ProjectChecks` returns structured
`{"code": ..., "params": ...}` entries, so the Build panel and tests can
translate or inspect them without depending on English text.

## Localized areas

- Main Retro toolbar: New/Import Project, SDK, Download SDKs, Export ROM.
- Resource tree, categories, read-only note and Sprite/Stage/Palette buttons.
- Main workspace tab titles.
- Hardware Monitor labels, mode descriptions and static-estimate messages.
- Build panel: build/run/debug/clean buttons, stats, diagnostics, SDK errors and
  coherence errors/warnings.
- Project coherence checks (platform, mode, build system, SDK path, export/3D
  profiles, `build_mode` target).
- New Project dialog and its SDK/build messages.
- Game Build dialog, modes, warnings and build messages.
- Native tab: scene capture, game scene, port bundle checkboxes, status/log.
- SDK Downloader dialog.
- Terminal screen/menu and font controls.

Generated files (`main.c`, headers, JSON port manifests, `README.md`) remain in
English intentionally so they are portable across toolchains and projects.

## Adding another language

Add a dictionary to `locales.json` using the same keys as `en`, then extend the
locale fallback mapping in `i18n.gd` if needed. Missing keys fall back to
English.

## Tests

```bash
"$BIN" --headless --path ide --script res://tests/i18n_test.gd
"$BIN" --headless --path ide --script res://tests/i18n_coverage_test.gd
```

`i18n_test.gd` checks `pt_BR`, `en` and fallback behavior and instantiates the
New Project, Game Build and SDK Downloader dialogs. `i18n_coverage_test.gd`
checks all 40 locales for key parity (420 keys each), preserved `{placeholders}`
and locale resolution (`pt_PT`, `fr_FR`, `es_MX`, `zh_CN`, `zh_TW`, ...).

```text
I18N_LOCALE ar keys=420 sample=مشروع جديد...
I18N_LOCALE fr keys=420 sample=Nouveau projet...
I18N_LOCALE ja keys=420 sample=新しいプロジェクト...
I18N_LOCALE pt_BR keys=420 sample=Novo Projeto...
I18N_LOCALE zh_Hans keys=420 sample=新项目...
I18N_FALLBACK pt_PT -> pt_BR
I18N_FALLBACK fr_FR -> fr
I18N_FALLBACK zh_CN -> zh_Hans
I18N_FALLBACK zh_TW -> zh_Hant
I18N_COVERAGE_TEST PASS
```
