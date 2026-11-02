#!/usr/bin/env python3
"""Fill English fallbacks for the newest Retro UI features.

The editor keeps 41 dictionaries in locales.json. The preview, audio and BGM
features added in 0.1.6/0.1.7, plus the cross-export warning added in 0.1.59,
were translated only for the hand-reviewed locales. This script translates the
remaining English fallbacks while protecting placeholders and technical terms.

Usage:
    python3 scripts/translate_new_features.py --dry-run
    python3 scripts/translate_new_features.py
    python3 scripts/translate_new_features.py --locale ar
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALES = ROOT / "ide" / "addons" / "retro_engine" / "locales.json"

# Google Translate target for each editor locale. tok intentionally uses
# English because there is no supported machine translator for it.
TARGETS = {
    "ar": "ar", "bg": "bg", "bn": "bn", "ca": "ca", "cs": "cs",
    "de": "de", "el": "el", "eo": "eo", "es": "es", "es_AR": "es",
    "et": "et", "fa": "fa", "fi": "fi", "fr": "fr", "ga": "ga",
    "gl": "gl", "he": "he", "hu": "hu", "id": "id", "it": "it",
    "ja": "ja", "ka": "ka", "ko": "ko", "lo": "lo", "nl": "nl",
    "pl": "pl", "pt": "pt", "pt_BR": "pt-BR", "ro": "ro", "ru": "ru",
    "sk": "sk", "sv": "sv", "ta": "ta", "th": "th", "tok": "en",
    "tr": "tr", "uk": "uk", "vi": "vi", "zh_Hans": "zh-CN",
    "zh_Hant": "zh-TW",
}

# Terms that must survive translation unchanged.
PROTECTED_TERMS = [
    "PVSnesLib", "Mega Drive", "SGDK", "Godot", "SNES", "BGM", "SFX",
    "MIDI", "WAV", "MP3", "ROM", "BPM", "MSU-1", "Inputs", "Start",
    "Enter", "F8", "F9",
]
SOURCE_OVERRIDES = {
    # Clearer UI wording than the bare English button labels.
    "preview.power": "Run ROM",
    "audio.synth_sfx": "Synthesize SFX",
    "bgm.title": "BGM sequencer",
}
REVIEWED = {"de", "es", "fr", "it", "ja", "pt", "pt_BR", "ru", "zh_Hans", "zh_Hant"}
PLACEHOLDER_RE = re.compile(r"\{[a-zA-Z_][a-zA-Z0-9_]*\}")
PROTECTED_RE = re.compile(
    "|".join([re.escape(term) for term in PROTECTED_TERMS] + [r"\bP\b"])
)


def is_new_feature(key: str) -> bool:
    return (
        key == "game_build.cross_export_warning"
        or key == "resources.images"
        or key.startswith(("preview.", "bgm.", "audio."))
    )


def protect(text: str):
    mapping = {}

    def keep(match):
        token = f"{{{{{len(mapping)}}}}}"
        mapping[token] = match.group(0)
        return token

    text = PLACEHOLDER_RE.sub(keep, text)
    text = PROTECTED_RE.sub(keep, text)
    return text, mapping


def restore(text: str, mapping: dict) -> str:
    for token, original in mapping.items():
        text = text.replace(token, original)
    return text


def has_words(text: str) -> bool:
    protected, _ = protect(text)
    protected = re.sub(r"\{\{\d+\}\}", "", protected)
    return bool(re.search(r"[A-Za-zÀ-ÿ]", protected))


def translate_batch(texts: list[str], target: str, timeout=40) -> list[str]:
    query = "&".join("q=" + urllib.parse.quote(text) for text in texts)
    url = (
        "https://translate.googleapis.com/translate_a/t"
        f"?client=dict-chrome-ex&sl=en&tl={urllib.parse.quote(target)}&{query}"
    )
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        data = json.load(response)
    if not isinstance(data, list):
        raise ValueError(f"unexpected translation response: {type(data).__name__}")
    return [str(item) for item in data]


def translate_strings(strings: dict[str, str], target: str) -> dict[str, str]:
    keys = list(strings)
    result: dict[str, str] = {}
    protected = {key: protect(strings[key]) for key in keys}
    batch_size = 24
    for start in range(0, len(keys), batch_size):
        batch = keys[start:start + batch_size]
        translated = None
        for attempt in range(4):
            try:
                translated = translate_batch([protected[key][0] for key in batch], target)
                break
            except Exception as exc:  # network errors, rate limits
                print(f"  retry {target} {start}: {exc}", file=sys.stderr)
                time.sleep(3 + attempt * 4)
        if translated is None or len(translated) != len(batch):
            for key in batch:
                try:
                    translated_one = translate_batch([protected[key][0]], target)
                    result[key] = restore(translated_one[0].strip(), protected[key][1])
                except Exception:
                    result[key] = strings[key]
                time.sleep(0.2)
        else:
            for key, value in zip(batch, translated):
                result[key] = restore(value.strip(), protected[key][1])
        time.sleep(0.25)
    return result


def placeholders(text: str) -> list[str]:
    return sorted(PLACEHOLDER_RE.findall(text))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--locale", action="append", help="only handle this editor locale")
    parser.add_argument("--force", default="", help="comma-separated keys to refresh outside reviewed locales")
    args = parser.parse_args()
    force_keys = {key.strip() for key in args.force.split(",") if key.strip()}

    data = json.loads(LOCALES.read_text(encoding="utf-8"))
    english = data["en"]
    source = {key: SOURCE_OVERRIDES.get(key, english[key]) for key in english}
    locales = args.locale or [code for code in data if code != "en"]
    total = 0

    for code in locales:
        if code not in data:
            print(f"unknown locale: {code}", file=sys.stderr)
            return 2
        target = TARGETS.get(code, "en")
        current = data[code]
        missing = {}
        for key in english:
            if not is_new_feature(key) or key not in current or target == "en":
                continue
            forced = key in force_keys and code not in REVIEWED
            needs = (
                current[key] == english[key]
                or "{{" in current[key]
                or "}}" in current[key]
            )
            if (forced or needs) and has_words(source[key]):
                missing[key] = source[key]
        if not missing:
            print(f"{code}: up to date")
            continue
        print(f"{code}: {len(missing)} string(s) -> {target}")
        total += len(missing)
        if args.dry_run:
            for key in missing:
                print(f"  {key} = {english[key][:100]}")
            continue

        translated = translate_strings(missing, target)
        for key, value in translated.items():
            if (
                not value
                or "{{" in value
                or "}}" in value
                or placeholders(value) != placeholders(english[key])
            ):
                print(f"  keeping English for {code}/{key}", file=sys.stderr)
                value = english[key]
            current[key] = value

    if args.dry_run:
        print(f"dry run: {total} string(s) would be translated")
        return 0

    if total:
        LOCALES.write_text(
            json.dumps(data, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        print(f"updated {LOCALES} ({total} string(s))")
    else:
        print("nothing to update")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
