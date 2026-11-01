#!/usr/bin/env python3
"""Build sites/locales.js from the English site copy.

This is a development helper. It uses the public Google Translate endpoint to
produce the 41 locales used by the editor. Brand names, console names and code
tokens are preserved by translating short batches and keeping a stable
delimiter between strings.
"""
from __future__ import annotations

import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "index.html"
OUT = ROOT / "locales.js"

LOCALES = {
    "ar": ("العربية", "rtl", "ar"),
    "bg": ("Български", "ltr", "bg"),
    "bn": ("বাংলা", "ltr", "bn"),
    "ca": ("Català", "ltr", "ca"),
    "cs": ("Čeština", "ltr", "cs"),
    "de": ("Deutsch", "ltr", "de"),
    "el": ("Ελληνικά", "ltr", "el"),
    "en": ("English", "ltr", "en"),
    "eo": ("Esperanto", "ltr", "eo"),
    "es": ("Español", "ltr", "es"),
    "es_AR": ("Español (Argentina)", "ltr", "es"),
    "et": ("Eesti", "ltr", "et"),
    "fa": ("فارسی", "rtl", "fa"),
    "fi": ("Suomi", "ltr", "fi"),
    "fr": ("Français", "ltr", "fr"),
    "ga": ("Gaeilge", "ltr", "ga"),
    "gl": ("Galego", "ltr", "gl"),
    "he": ("עברית", "rtl", "he"),
    "hu": ("Magyar", "ltr", "hu"),
    "id": ("Bahasa Indonesia", "ltr", "id"),
    "it": ("Italiano", "ltr", "it"),
    "ja": ("日本語", "ltr", "ja"),
    "ka": ("ქართული", "ltr", "ka"),
    "ko": ("한국어", "ltr", "ko"),
    "lo": ("ລາວ", "ltr", "lo"),
    "nl": ("Nederlands", "ltr", "nl"),
    "pl": ("Polski", "ltr", "pl"),
    "pt": ("Português", "ltr", "pt"),
    "pt_BR": ("Português (Brasil)", "ltr", "pt-BR"),
    "ro": ("Română", "ltr", "ro"),
    "ru": ("Русский", "ltr", "ru"),
    "sk": ("Slovenčina", "ltr", "sk"),
    "sv": ("Svenska", "ltr", "sv"),
    "ta": ("தமிழ்", "ltr", "ta"),
    "th": ("ไทย", "ltr", "th"),
    "tok": ("toki pona", "ltr", "en"),
    "tr": ("Türkçe", "ltr", "tr"),
    "uk": ("Українська", "ltr", "uk"),
    "vi": ("Tiếng Việt", "ltr", "vi"),
    "zh_Hans": ("简体中文", "ltr", "zh-CN"),
    "zh_Hant": ("繁體中文", "ltr", "zh-TW"),
}

# Strings that are not plain text in the page. Placeholders survive translation
# and are turned back into markup by script.js.
SPECIAL = {
    "feature.fidelity.desc": (
        "Cross-platform exports warn you when manual work is required, and generated "
        "projects are named {{SNES}} / {{MD}} so they never get confused with the source."
    ),
    "nav.language": "Language",
    "nav.open": "Open navigation",
    "nav.close": "Close navigation",
    "carousel.prev": "Previous preview",
    "carousel.next": "Next preview",
    "carousel.go": "Show preview {{n}}",
    "carousel.slides": "Preview slides",
}
DELIM = "\n@@\n"


def english_strings():
    soup = BeautifulSoup(HTML.read_text(encoding="utf-8"), "html.parser")
    strings = {}
    for el in soup.select("[data-i18n]"):
        key = el["data-i18n"]
        strings[key] = " ".join(el.get_text(" ", strip=True).split())
    strings.update(SPECIAL)
    return strings


def translate_batch(text: str, target: str, timeout=30):
    query = urllib.parse.quote(text)
    url = ("https://translate.googleapis.com/translate_a/single"
           f"?client=gtx&sl=en&tl={urllib.parse.quote(target)}&dt=t&q={query}")
    req = urllib.request.Request(url, headers={"User-Agent": "godot-retro-site/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        data = json.load(response)
    chunks = []
    for segment in data[0] or []:
        if segment and segment[0]:
            chunks.append(segment[0])
    return "".join(chunks)


def translate_strings(strings, target):
    keys = list(strings.keys())
    out = {}
    batch_size = 24
    for start in range(0, len(keys), batch_size):
        batch = keys[start:start + batch_size]
        text = DELIM.join(strings[key] for key in batch)
        translated = None
        for attempt in range(4):
            try:
                translated = translate_batch(text, target)
                break
            except Exception as exc:
                print(f"  retry {target} {start}: {exc}", file=sys.stderr)
                time.sleep(2 + attempt * 3)
        if translated is None:
            for key in batch:
                out[key] = strings[key]
            continue
        parts = translated.split(DELIM)
        if len(parts) != len(batch):
            # Retry one-by-one so delimiters cannot desynchronise the result.
            for key in batch:
                try:
                    out[key] = translate_batch(strings[key], target).strip()
                except Exception:
                    out[key] = strings[key]
                time.sleep(0.12)
        else:
            for key, value in zip(batch, parts):
                out[key] = value.strip()
        time.sleep(0.12)
    return out


def load_existing():
    if not OUT.exists():
        return {}
    text = OUT.read_text(encoding="utf-8").strip()
    prefix = "window.SITE_I18N = "
    if text.startswith(prefix):
        text = text[len(prefix):]
    text = text.rstrip(";").strip()
    try:
        payload = json.loads(text)
    except (ValueError, json.JSONDecodeError):
        return {}
    return payload.get("strings", {})


def main():
    strings = english_strings()
    existing = load_existing()
    print(f"{len(strings)} English strings, {len(LOCALES)} locales")
    locales = {"en": strings}
    for index, (code, (label, direction, target)) in enumerate(LOCALES.items(), 1):
        if code == "en":
            continue
        print(f"[{index:02d}/{len(LOCALES)}] {code} -> {target}")
        previous = existing.get(code, {})
        missing = {key: value for key, value in strings.items() if key not in previous}
        if target == "en":
            translated = dict(strings)
        elif missing:
            print(f"  {len(missing)} new string(s)")
            translated = translate_strings(missing, target)
            translated = {
                key: translated.get(key, previous.get(key, value))
                for key, value in strings.items()
            }
        else:
            translated = {key: previous.get(key, value) for key, value in strings.items()}
        locales[code] = translated
    payload = {
        "languages": [
            {"code": code, "label": label, "dir": direction}
            for code, (label, direction, _target) in LOCALES.items()
        ],
        "strings": locales,
    }
    OUT.write_text("window.SITE_I18N = " + json.dumps(payload, ensure_ascii=False, indent=2) + ";\n",
                   encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
