# Godot Retro Engine website

Static site for the fork, inspired by the layout of <https://godotengine.org/>.
It uses only local HTML/CSS/JS and local screenshots at runtime.

## Run locally

```bash
python3 -m http.server 8765 --directory sites
```

Open <http://127.0.0.1:8765/>.

## Download target

Every download CTA points to:

<https://github.com/fabioad/godot-retro-engine/releases/>

## Hero carousel

The console preview at the top cycles through the Sonic 2 and Gothicvania
screenshots every 4.8 seconds. It pauses while hovered or focused, has previous
and next buttons plus dot navigation, and stays static when the visitor prefers
reduced motion. The controls also work with keyboard navigation.

## Languages

The site ships the same 41 locales as the editor:

```text
ar bg bn ca cs de el en eo es es_AR et fa fi fr ga gl he hu id it ja ka ko
lo nl pl pt pt_BR ro ru sk sv ta th tok tr uk vi zh_Hans zh_Hant
```

- The selector is in the header (inside the mobile menu on small screens).
- The choice is stored in `localStorage` and restored on the next visit.
- `?lang=pt_BR`, `?lang=ja` or any other code can be used to link directly to a locale.
- Missing strings fall back to English.
- `ar`, `fa` and `he` switch the page to right-to-left.

`locales.js` is generated. The runtime does not call any translation service.

## Editing

- `index.html` — content and sections; add `data-i18n="key"` to translatable text
- `styles.css` — palette, layout, responsive rules and RTL adjustments
- `script.js` — mobile nav, active section, language selector and UI behavior
- `assets/` — fork icon and ROM screenshots
- `build_locales.py` — regenerates `locales.js` from the English copy

After adding or changing English strings, rebuild the translations:

```bash
python3 sites/build_locales.py
```

The build is incremental: it keeps existing translations and only requests the
new strings. It uses the public Google Translate endpoint at build time, so run
it when you change the copy, not on every deploy.

The site is an independent project page and does not bundle ROMs or game assets.
