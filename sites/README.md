# Godot Retro Engine website

Static site for the fork, inspired by the layout of <https://godotengine.org/>.
It uses only local HTML/CSS/JS and local screenshots.

## Run locally

```bash
python3 -m http.server 8765 --directory sites
```

Open <http://127.0.0.1:8765/>.

## Download target

Every download CTA points to:

<https://github.com/fabioad/godot-retro-engine/releases/>

## Editing

- `index.html` — content and sections
- `styles.css` — palette, layout and responsive rules
- `script.js` — mobile nav, active section and small UI behavior
- `assets/` — fork icon and ROM screenshots

The site is an independent project page and does not bundle ROMs or game assets.
