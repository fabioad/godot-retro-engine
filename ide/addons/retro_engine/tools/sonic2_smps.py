"""Sonic 2 SMPS -> SNESMOD IT/soundbank helper.

The SNES port cannot run the Mega Drive's Z80 SMPS driver.  Instead this
module reads the original EHZ SMPS note data and turns it into a small IT
module with the five sampled instruments provided by the engine's audio tool.
The notes, arrangement and loop are therefore source-level; the FM timbre is
approximated with square/saw/sine samples.
"""
from __future__ import annotations

import importlib.util
import math
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


MULT = [0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12, 12, 15, 15]


def _hex_values(text):
    return [int(v.strip().lstrip("$"), 16) for v in text.split(",")]


def _parse_voices(lines):
    voices = []
    cur = None
    for line in lines:
        text = line.split(";")[0].strip()
        if not text:
            continue
        if text.startswith("smpsVcAlgorithm"):
            if cur is not None:
                voices.append(cur)
            cur = {"alg": 0, "fb": 0, "detune": [0] * 4, "coarse": [1] * 4,
                   "tl": [0] * 4, "attack": [31] * 4, "decay": [0] * 4,
                   "sustain": [0] * 4, "release": [0] * 4}
            parts = text.split(None, 1)
            if len(parts) == 2:
                cur["alg"] = _hex_values(parts[1])[0]
        elif cur is not None:
            parts = text.split(None, 1)
            if len(parts) != 2:
                continue
            name, values = parts
            vals = _hex_values(values)
            if name == "smpsVcAlgorithm":
                cur["alg"] = vals[0]
            elif name == "smpsVcFeedback":
                cur["fb"] = vals[0]
            elif name == "smpsVcDetune":
                cur["detune"] = vals
            elif name == "smpsVcCoarseFreq":
                cur["coarse"] = vals
            elif name == "smpsVcAttackRate":
                cur["attack"] = vals
            elif name == "smpsVcDecayRate1":
                cur["decay"] = vals
            elif name == "smpsVcDecayLevel":
                cur["sustain"] = vals
            elif name == "smpsVcReleaseRate":
                cur["release"] = vals
            elif name == "smpsVcTotalLevel":
                cur["tl"] = vals
    if cur is not None:
        voices.append(cur)
    return voices


def _fm_sample(voice, rate=16744, seconds=0.22, base_freq=523.251,
               loop_start=0.18):
    """Render one YM2612 voice as a sample with a single-period sustain loop."""
    n = max(1, int(rate * seconds))
    alg = voice["alg"] & 7
    fb = voice["fb"] & 7
    ratios = []
    amps = []
    attacks = []
    decays = []
    sustains = []
    for i in range(4):
        coarse = voice["coarse"][i] & 0xF
        detune = voice["detune"][i] & 7
        ratios.append(MULT[coarse] * (1.0 + (detune - 3) * 0.003))
        tl = voice["tl"][i] & 0x7F
        amps.append(10.0 ** (-tl * 0.75 / 20.0))
        attacks.append(0.004 + (31 - (voice["attack"][i] & 0x1F)) * 0.007)
        decays.append(0.02 + (31 - (voice["decay"][i] & 0x1F)) * 0.012)
        sustains.append(1.0 - (voice["sustain"][i] & 0xF) * 0.05)
    phases = [0.0, 0.0, 0.0, 0.0]
    prev = 0.0
    out = []
    for idx in range(n):
        t = idx / rate
        envs = []
        for i in range(4):
            if t < attacks[i]:
                env = t / max(1e-6, attacks[i])
            elif t < attacks[i] + decays[i]:
                env = 1.0 - (1.0 - sustains[i]) * ((t - attacks[i]) / max(1e-6, decays[i]))
            else:
                env = sustains[i]
            envs.append(env)
        for i in range(4):
            phases[i] = (phases[i] + base_freq * ratios[i] / rate) % 1.0

        def op(i, mod=0.0):
            return math.sin(2.0 * math.pi * phases[i] + 2.2 * mod) * envs[i] * amps[i]

        o1 = op(0, fb * prev)
        prev = o1
        o2 = op(1)
        o3 = op(2)
        o4 = op(3)
        if alg == 0:
            o2 = op(1, o1); o3 = op(2, o2); o4 = op(3, o3); val = o4
        elif alg == 1:
            o3 = op(2, o1 + o2); o4 = op(3, o3); val = o4
        elif alg == 2:
            o2 = op(1); o3 = op(2, o2); o4 = op(3, o3 + o1); val = o4
        elif alg == 3:
            o2 = op(1, o1); o4 = op(3, o3); val = o2 + o4
        elif alg == 4:
            o2 = op(1, o1); o4 = op(3, o3); val = o2 + o4
        elif alg == 5:
            o2 = op(1, o1); o3 = op(2, o1); o4 = op(3, o1); val = o2 + o3 + o4
        elif alg == 6:
            o2 = op(1, o1); o3 = op(2, o1); val = o2 + o3 + o4
        else:
            val = o1 + o2 + o3 + o4
        out.append(val)

    # Loop exactly one fundamental period.  Pick the phase offset whose
    # one-period repeat is closest, so the seam is continuous.
    period = max(2, int(round(rate / base_freq)))
    target = max(period, int(rate * loop_start))
    best = target
    best_error = None
    limit = min(period // 2, 64)
    for delta in range(-limit, limit + 1):
        at = target + delta
        if at < period or at + period >= n:
            continue
        error = abs(out[at + period] - out[at])
        if best_error is None or error < best_error:
            best_error = error
            best = at
    out = out[:best + period]
    return {"name": "fm", "data": out, "loop": True, "rate": rate,
            "loop_start": best, "loop_end": len(out), "fadeout": 320}


def _pitch_sample(sample, audio, factor):
    """Resample a sample so it plays `factor` times faster at the base note."""
    if abs(factor - 1.0) < 1e-6:
        return sample
    data = audio._resample_linear(sample["data"], sample["rate"],
                                  max(1, int(round(sample["rate"] / factor))))
    out = dict(sample)
    out["data"] = data
    out["loop"] = False
    out.pop("loop_start", None)
    out.pop("loop_end", None)
    return out


def _square_sample(rate=16744, seconds=0.3):
    period = rate / 523.251
    n = max(1, int(round(rate * seconds / period)) * int(round(period)))
    out = []
    phase = 0.0
    for i in range(n):
        phase = (phase + 523.251 / rate) % 1.0
        envelope = min(1.0, i / (rate * 0.005)) * min(1.0, (n - i) / (rate * 0.01))
        out.append((1.0 if phase < 0.5 else -1.0) * envelope * 0.7)
    return {"name": "psg", "data": out, "loop": True, "rate": rate,
            "loop_start": 0, "loop_end": n, "fadeout": 320}


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
        match = re.match(r"smpsSetvoice\s+(\$[0-9A-Fa-f]+|\d+)", text)
        if match:
            value = match.group(1)
            value = int(value[1:], 16) if value.startswith("$") else int(value)
            tokens.append(("setvoice", value))
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
    state = {"time": 0.0, "last_note": None, "pitch": 0, "voice": 0}

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
                            events.append((state["time"], note, True, state["voice"]))
                            events.append((state["time"] + duration, note, False, state["voice"]))
                            state["last_note"] = note
                    elif pending and pending[0] == "noattack":
                        note = state["last_note"]
                        if note is not None:
                            for i in range(len(events) - 1, -1, -1):
                                if events[i][1] == note and not events[i][2]:
                                    events.append((state["time"] + duration, note, False,
                                                   events[i][3]))
                                    break
                    pending = None
                    state["time"] += duration
                elif op == "loop":
                    count, target = token[1], token[2]
                    if target in labels:
                        emit(labels[target], index, count - 1)
                elif op == "jump":
                    return
                elif op == "setvoice":
                    state["voice"] = token[1]
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
        tick = 256.0 / (158.0 * 60.0)

        voices = _parse_voices(lines)
        if not voices:
            return None
        fm_samples = []
        for index, voice in enumerate(voices):
            sample = _fm_sample(voice, rate=16744, seconds=0.22,
                                base_freq=523.251, loop_start=0.18)
            sample["name"] = "fm%d" % index
            fm_samples.append(sample)
        # Keep the relative voice levels from Total Level instead of making
        # every instrument equally loud.
        peak = max((abs(v) for sample in fm_samples for v in sample["data"]),
                   default=0.0)
        if peak > 1e-6:
            scale = 0.82 / peak
            for sample in fm_samples:
                sample["data"] = [v * scale for v in sample["data"]]

        drum_specs = [
            ("kick", "Kick", 1.0),
            ("snare", "Snare", 1.0),
            ("tom", "Tom", 1.0),
            ("floortom", "Bongo", 2.0),
        ]
        drum_samples = []
        drum_program = {}
        for name, wav_name, factor in drum_specs:
            path = os.path.join(root, "sound", "DAC", wav_name + ".wav")
            if not os.path.isfile(path):
                continue
            values, rate = audio.read_wav_mono(path)
            if rate != 16744:
                values = audio._resample_linear(values, rate, 16744)
                rate = 16744
            peak = max((abs(v) for v in values), default=0.0)
            if peak > 1e-6:
                values = [v * 0.9 / peak for v in values]
            sample = {"name": name, "data": values, "loop": False, "rate": rate}
            sample = _pitch_sample(sample, audio, factor)
            drum_program[name] = len(fm_samples) + len(drum_samples)
            drum_samples.append(sample)

        square = _square_sample(rate=16744, seconds=0.20)
        samples = fm_samples + drum_samples + [square]
        instrument_map = {index: index + 1 for index in range(len(samples))}

        # The original driver maps DAC note numbers to these samples.  All
        # drums play at the base note so they keep their original speed.
        drum_notes = {
            36: drum_program.get("kick"),
            38: drum_program.get("snare"),
            47: drum_program.get("tom"),
            41: drum_program.get("floortom"),
            39: drum_program.get("clap"),
            37: drum_program.get("scratch"),
            40: drum_program.get("clap"),
            42: drum_program.get("clap"),
            45: drum_program.get("tom"),
            50: drum_program.get("tom"),
            49: drum_program.get("tom"),
        }
        square_program = len(samples) - 1

        channels = [
            ("EHZ_FM1", 0, None),
            ("EHZ_FM2", 1, None),
            ("EHZ_FM3", 2, None),
            ("EHZ_FM4", 3, None),
            ("EHZ_FM5", 4, None),
            ("EHZ_PSG1", 5, square_program),
            ("EHZ_PSG2", 6, square_program),
            ("EHZ_DAC", 9, None),
        ]
        events = []
        for label, channel, fixed_program in channels:
            for time, note, is_on, voice in _render_channel(lines, label, tick):
                if fixed_program is not None:
                    program = fixed_program
                elif label == "EHZ_DAC":
                    program = drum_notes.get(note)
                    if program is None:
                        continue
                    note = 60
                else:
                    if voice >= len(fm_samples):
                        continue
                    program = voice
                events.append(audio.NoteEvent(
                    time, channel, note, 100 if is_on else 0, program, not is_on))
        if not events:
            return None
        events.sort(key=lambda event: (event.time, event.is_off))
        os.makedirs(out_dir, exist_ok=True)
        it_path = os.path.join(out_dir, "ehz.it")
        audio.write_it_from_events(it_path, events, "EHZ", speed=1, tempo=93,
                                   samples_override=samples,
                                   instrument_map=instrument_map)
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
    except Exception:
        return None
    except Exception:
        return None
