"""Sonic 2 SMPS -> SNESMOD IT/soundbank helper.

The SNES port cannot run the Mega Drive's Z80 SMPS driver.  Instead this
module reads the original EHZ SMPS note data and turns it into a small IT
module with the five sampled instruments provided by the engine's audio tool.
The notes, arrangement and loop are therefore source-level; the FM timbre is
approximated with square/saw/sine samples.
"""
from __future__ import annotations

import importlib.util
import os
import re
import subprocess
import sys


NOTE_BASE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
DRUM_NOTES = {
    "dKick": 36, "dSnare": 38, "dMidTom": 47, "dFloorTom": 41,
    "dHiTom": 50, "dLowTom": 45, "dCrash": 49, "dHiClap": 39,
    "dMidClap": 40, "dLowClap": 42, "dScratch": 37,
}


def _load_audio_tool() -> object:
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(here, "retro_audio_tool.py"),
        os.path.join(here, "..", "ide", "addons", "retro_engine", "tools",
                     "retro_audio_tool.py"),
        os.path.expanduser(
            "~/.local/share/godot-retro-engine/ide/addons/retro_engine/tools/retro_audio_tool.py"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            spec = importlib.util.spec_from_file_location("retro_audio_tool", path)
            module = importlib.util.module_from_spec(spec)
            sys.modules["retro_audio_tool"] = module
            spec.loader.exec_module(module)
            return module
    raise RuntimeError("retro_audio_tool.py not found")


def _find_smconv() -> str:
    root = os.environ.get("PVSNESLIB_HOME", "")
    candidates = []
    if root:
        candidates.append(os.path.join(root, "devkitsnes", "tools", "smconv"))
    candidates.append(os.path.expanduser(
        "~/.local/share/godot-retro-engine/sdks/snes/devkitsnes/tools/smconv"))
    for path in candidates:
        if os.path.isfile(path):
            return path
    return ""


def _note_number(name: str):
    match = re.match(r"n([A-G])([sb]?)(\d)$", name)
    if not match:
        return None
    value = NOTE_BASE[match.group(1)]
    if match.group(2) == "s":
        value += 1
    elif match.group(2) == "b":
        value -= 1
    # Sonic's note naming uses C5 as the middle octave.
    return int(match.group(3)) * 12 + value


def _parse_channel(lines, label):
    started = False
    channel_lines = []
    for line in lines:
        stripped = line.strip()
        match = re.match(r"^(EHZ_[A-Za-z0-9]+):", stripped)
        if match:
            if re.match(r"^EHZ_(FM\d|PSG\d|DAC|Header|Voices)$", match.group(1)):
                if started:
                    break
                if match.group(1) == label:
                    started = True
                continue
        if started:
            channel_lines.append(line)

    tokens = []
    labels = {}
    for line in channel_lines:
        text = line.split(";")[0].strip()
        if not text:
            continue
        match = re.match(r"^([A-Za-z0-9_]+):", text)
        if match:
            labels[match.group(1)] = len(tokens)
            continue
        match = re.match(r"dc\.b\s+(.*)", text)
        if match:
            for token in (part.strip() for part in match.group(1).split(",")):
                if not token:
                    continue
                if token == "smpsNoAttack":
                    tokens.append(("noattack",))
                elif token == "nMaxPSG":
                    tokens.append(("note", 60))
                elif token in DRUM_NOTES:
                    tokens.append(("note", DRUM_NOTES[token]))
                elif re.match(r"^n[A-G]", token):
                    number = _note_number(token)
                    tokens.append(("note", number) if number is not None else ("rest",))
                elif re.match(r"^\$[0-9A-Fa-f]+$", token):
                    tokens.append(("dur", int(token[1:], 16)))
                elif re.match(r"^\d+$", token):
                    tokens.append(("dur", int(token)))
                else:
                    tokens.append(("misc", token))
            continue
        match = re.match(r"smpsLoop\s+\$[0-9A-Fa-f]+,\s*(\$[0-9A-Fa-f]+|\d+),\s*(\w+)", text)
        if match:
            count = match.group(1)
            count = int(count[1:], 16) if count.startswith("$") else int(count)
            tokens.append(("loop", count, match.group(2)))
            continue
        match = re.match(r"smpsJump\s+(\w+)", text)
        if match:
            tokens.append(("jump", match.group(1)))
            continue
        match = re.match(r"smpsAlterPitch\s+(\$[0-9A-Fa-f]+|\d+)", text)
        if match:
            value = match.group(1)
            value = int(value[1:], 16) if value.startswith("$") else int(value)
            if value > 127:
                value -= 256
            tokens.append(("pitch", value))
    return tokens, labels


def _render_channel(lines, label, tick_seconds):
    tokens, labels = _parse_channel(lines, label)
    events = []
    state = {"time": 0.0, "last_note": None, "pitch": 0}

    def emit(start, end, repeat):
        for _ in range(repeat):
            index = start
            pending = None
            while index < end:
                token = tokens[index]
                op = token[0]
                if op == "note":
                    pending = ("note", token[1] + state["pitch"])
                elif op == "rest":
                    pending = ("rest",)
                elif op == "noattack":
                    pending = ("noattack",)
                elif op == "dur":
                    duration = token[1] * tick_seconds
                    if pending and pending[0] == "note":
                        note = pending[1]
                        if 0 <= note <= 127:
                            events.append((state["time"], note, True))
                            events.append((state["time"] + duration, note, False))
                            state["last_note"] = note
                    elif pending and pending[0] == "noattack":
                        note = state["last_note"]
                        if note is not None:
                            for i in range(len(events) - 1, -1, -1):
                                if events[i][1] == note and not events[i][2]:
                                    events.append((state["time"] + duration, note, False))
                                    break
                    pending = None
                    state["time"] += duration
                elif op == "loop":
                    count, target = token[1], token[2]
                    if target in labels:
                        emit(labels[target], index, count - 1)
                elif op == "jump":
                    return
                elif op == "pitch":
                    state["pitch"] = token[1]
                index += 1

    emit(0, len(tokens), 1)
    return events


def build_ehz_module(root: str, out_dir: str):
    """Return the SNESMOD soundbank bytes for EHZ, or None if tools fail."""
    asm = os.path.join(root, "sound", "music", "82 - EHZ.asm")
    if not os.path.isfile(asm):
        return None
    smconv = _find_smconv()
    if not smconv:
        return None
    try:
        audio = _load_audio_tool()
    except Exception:
        return None
    try:
        lines = open(asm, encoding="utf-8", errors="ignore").read().splitlines()
        # 60 Hz clock, tempo $9E, one tick every 256/(tempo*60) seconds.
        tick = 256.0 / (158.0 * 60.0)
        channels = [
            ("EHZ_FM1", 0, 80),  # square lead
            ("EHZ_FM2", 1, 24),  # saw bass
            ("EHZ_FM3", 2, 0),   # sine
            ("EHZ_FM4", 3, 56),  # square
            ("EHZ_FM5", 4, 32),  # square
            ("EHZ_PSG1", 5, 80), # square
            ("EHZ_PSG2", 6, 80), # square
            ("EHZ_DAC", 9, 0),   # noise/drums
        ]
        events = []
        for label, channel, program in channels:
            for time, note, is_on in _render_channel(lines, label, tick):
                events.append(audio.NoteEvent(
                    time, channel, note, 100 if is_on else 0, program, not is_on))
        if not events:
            return None
        events.sort(key=lambda event: (event.time, event.is_off))
        os.makedirs(out_dir, exist_ok=True)
        it_path = os.path.join(out_dir, "ehz.it")
        # Row length ~= one SMPS tick.
        audio.write_it_from_events(it_path, events, "EHZ", speed=1, tempo=93)
        bank_base = os.path.join(out_dir, "ehz_bank")
        subprocess.run([smconv, "-s", "-o", bank_base, it_path], check=True,
                       capture_output=True)
        bank_path = bank_base + ".bnk"
        if not os.path.isfile(bank_path):
            return None
        with open(bank_path, "rb") as handle:
            return handle.read()
    except Exception:
        return None
