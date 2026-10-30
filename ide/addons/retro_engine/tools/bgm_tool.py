#!/usr/bin/env python3
"""MIDI/IT import and MIDI export for the Retro BGM piano roll.

The song JSON is shared with bgm_sequencer.gd/bgm_roll.gd. It contains tracks,
notes and chip-oriented settings. MIDI is the portable source format consumed
by retro_audio_tool.py; IT files are read through libopenmpt when available.
"""
from __future__ import annotations

import argparse
import ctypes
import json
import math
import struct
import sys
from pathlib import Path

try:
    import mido
except Exception:  # pragma: no cover - reported to the caller
    mido = None

STEPS_PER_BEAT = 4
MAX_SNES_TRACKS = 8
MAX_MD_TRACKS = 10


def default_track(platform: str, index: int) -> dict:
    if platform == "megadrive":
        if index < 6:
            kind = "fm"
            name = f"FM {index + 1}"
        elif index < 9:
            kind = "psg"
            name = f"PSG {index - 5}"
        else:
            kind = "dac"
            name = "DAC"
        return {
            "name": name, "kind": kind, "channel": index, "midi_channel": min(8, index),
            "muted": False, "solo": False, "volume": 100, "pan": 64,
            "instrument": 0, "fm_patch": "lead", "waveform": "square",
            "fm": {"algorithm": 7, "feedback": 0, "operators": [
                {"mul": 1, "tl": 16, "ar": 31, "dr": 8, "sl": 1, "rr": 12, "detune": 0}
                for _ in range(4)
            ]},
            "psg": {"waveform": "square", "volume": 15, "noise": 0.0,
                    "attack_ms": 2, "decay_ms": 80, "sustain": 0.7, "release_ms": 100},
            "dac": {"sample": ""},
            "notes": [],
        }
    return {
        "name": f"SPC {index + 1}", "kind": "snes", "channel": index,
        "midi_channel": index, "muted": False, "solo": False,
        "volume": 100, "pan": 64, "instrument": 0, "waveform": "square",
        "snes": {
            "waveform": "square", "attack_ms": 2, "decay_ms": 50, "sustain": 0.65,
            "release_ms": 70, "echo": 0, "noise": 0.0, "pitch_mod": 0.0,
            "detune": 0.0,
        },
        "notes": [],
    }


def default_song(platform: str, name: str) -> dict:
    count = MAX_MD_TRACKS if platform == "megadrive" else MAX_SNES_TRACKS
    return {
        "name": name, "platform": platform, "bpm": 120.0,
        "steps": 64, "steps_per_beat": STEPS_PER_BEAT,
        "tracks": [default_track(platform, i) for i in range(count)],
    }


def _program_for_track(track: dict) -> int:
    kind = str(track.get("kind", "snes"))
    if kind == "psg":
        return 80
    if kind == "dac":
        return 0
    if kind == "fm":
        return {"piano": 0, "guitar": 24, "bass": 32, "strings": 48,
                "brass": 56, "lead": 80}.get(str(track.get("fm_patch", "lead")), 80)
    wave = str(track.get("waveform", track.get("snes", {}).get("waveform", "square")))
    if wave == "sine":
        return 0
    if wave == "saw":
        return 24
    if wave == "triangle":
        return 48
    if wave == "noise":
        return 119
    return 80


def _channel_for_track(track: dict, index: int) -> int:
    kind = str(track.get("kind", "snes"))
    if kind in ("psg", "dac") and bool(track.get("psg", {}).get("noise", 0)):
        return 9
    value = int(track.get("midi_channel", index))
    if value < 0 or value > 15:
        value = index % 16
    if value == 9 and kind not in ("psg", "dac"):
        value = 8
    return value


def export_midi(song: dict, out_path: str) -> dict:
    if mido is None:
        raise RuntimeError("mido is required for MIDI export")
    bpm = max(20.0, min(400.0, float(song.get("bpm", 120.0))))
    steps = max(1, int(song.get("steps", 64)))
    spb = max(1, int(song.get("steps_per_beat", STEPS_PER_BEAT)))
    ticks_per_beat = 480
    step_ticks = ticks_per_beat / float(spb)
    mid = mido.MidiFile(type=1, ticks_per_beat=ticks_per_beat)
    meta = mido.MidiTrack()
    mid.tracks.append(meta)
    meta.append(mido.MetaMessage("track_name", name=str(song.get("name", "song")), time=0))
    meta.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(bpm), time=0))
    meta.append(mido.MetaMessage("time_signature", numerator=spb, denominator=4, time=0))
    for ti, track in enumerate(song.get("tracks", [])):
        notes = track.get("notes", [])
        if not notes and str(track.get("kind", "")) != "dac":
            continue
        channel = _channel_for_track(track, ti)
        m = mido.MidiTrack()
        mid.tracks.append(m)
        m.append(mido.MetaMessage("track_name", name=str(track.get("name", f"Track {ti + 1}")), time=0))
        m.append(mido.Message("program_change", program=_program_for_track(track), channel=channel, time=0))
        m.append(mido.Message("control_change", control=7,
                              value=max(0, min(127, int(round(float(track.get("volume", 100)) * 127 / 100.0)))),
                              channel=channel, time=0))
        m.append(mido.Message("control_change", control=10,
                              value=max(0, min(127, int(track.get("pan", 64)))), channel=channel, time=0))
        if float(track.get("echo", track.get("snes", {}).get("echo", 0))) > 0:
            m.append(mido.Message("control_change", control=91,
                                  value=max(0, min(127, int(track.get("echo", track.get("snes", {}).get("echo", 0))))),
                                  channel=channel, time=0))
        timeline: list[tuple[int, int, int, int]] = []
        for note in notes:
            start = max(0, min(steps - 1, int(note.get("step", 0))))
            length = max(1, int(note.get("length", 1)))
            end = min(steps, start + length)
            pitch = max(0, min(127, int(note.get("pitch", 60))))
            velocity = max(1, min(127, int(note.get("velocity", 100))))
            gate = max(0.1, min(2.0, float(note.get("gate", 1.0))))
            end = max(start + 1, int(round(start + (end - start) * gate)))
            timeline.append((int(round(start * step_ticks)), 1, pitch, velocity))
            timeline.append((int(round(end * step_ticks)), 0, pitch, 0))
        timeline.sort(key=lambda item: (item[0], item[1]))
        current = 0
        for tick, is_on, pitch, velocity in timeline:
            delta = max(0, tick - current)
            current = tick
            if is_on:
                m.append(mido.Message("note_on", note=pitch, velocity=velocity, channel=channel, time=delta))
            else:
                m.append(mido.Message("note_off", note=pitch, velocity=0, channel=channel, time=delta))
        m.append(mido.MetaMessage("end_of_track", time=0))
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    mid.save(out_path)
    return {"ok": True, "out": out_path, "tracks": len(mid.tracks), "bpm": bpm, "steps": steps}


def _waveform_from_program(program: int) -> str:
    if 0 <= program <= 7:
        return "sine"
    if 24 <= program <= 31:
        return "saw"
    if 48 <= program <= 55:
        return "triangle"
    if program == 119:
        return "noise"
    return "square"


def _fm_family_from_program(program: int) -> str:
    if 0 <= program <= 7:
        return "piano"
    if 24 <= program <= 31 or 40 <= program <= 47:
        return "guitar"
    if 32 <= program <= 39:
        return "bass"
    if 48 <= program <= 55:
        return "strings"
    if 56 <= program <= 63:
        return "brass"
    return "lead"


def import_midi(midi_path: str, out_path: str, name: str, platform: str) -> dict:
    if mido is None:
        raise RuntimeError("mido is required for MIDI import")
    mid = mido.MidiFile(midi_path)
    tracks = default_song(platform, name)["tracks"]
    track_names = {}
    channels: dict[int, dict] = {}
    tempo = 500000
    max_tick = 0
    for track_index, source_track in enumerate(mid.tracks):
        absolute = 0
        current_name = ""
        for msg in source_track:
            absolute += msg.time
            max_tick = max(max_tick, absolute)
            if msg.type == "track_name" and not current_name:
                current_name = msg.name
            if msg.type == "set_tempo" and tempo == 500000:
                tempo = msg.tempo
            if msg.type == "program_change":
                data = channels.setdefault(msg.channel, {"program": 0, "volume": 100, "pan": 64, "notes": {}, "name": current_name})
                data["program"] = msg.program
            elif msg.type == "control_change" and msg.channel in channels:
                if msg.control == 7:
                    channels[msg.channel]["volume"] = round(msg.value * 100 / 127)
                elif msg.control == 10:
                    channels[msg.channel]["pan"] = msg.value
            elif msg.type in ("note_on", "note_off"):
                data = channels.setdefault(msg.channel, {"program": 0, "volume": 100, "pan": 64, "notes": {}, "name": current_name})
                key = (msg.channel, msg.note)
                if msg.type == "note_on" and msg.velocity > 0:
                    data["notes"][msg.note] = (absolute, msg.velocity)
                else:
                    started = data["notes"].pop(msg.note, None)
                    if started:
                        data.setdefault("finished", []).append((started[0], absolute, msg.note, started[1]))
    step_ticks = (mid.ticks_per_beat / float(STEPS_PER_BEAT))
    max_step = max(1, int(math.ceil(max_tick / step_ticks)))
    steps = max(64, int(math.ceil(max_step / 16.0) * 16))
    bpm = mido.tempo2bpm(tempo)
    for channel, data in sorted(channels.items()):
        if channel >= len(tracks):
            continue
        track = tracks[channel]
        track["name"] = data.get("name") or f"Ch {channel + 1}"
        track["volume"] = max(0, min(100, int(data.get("volume", 100))))
        track["pan"] = max(0, min(127, int(data.get("pan", 64))))
        program = int(data.get("program", 0))
        if platform == "megadrive":
            track["fm_patch"] = _fm_family_from_program(program)
            if channel >= 6:
                track["kind"] = "psg"
                track["psg"]["waveform"] = "square"
        else:
            track["waveform"] = _waveform_from_program(program)
        for start_tick, end_tick, pitch, velocity in data.get("finished", []):
            start = max(0, min(steps - 1, int(round(start_tick / step_ticks))))
            end = max(start + 1, int(round(end_tick / step_ticks)))
            track["notes"].append({
                "step": start, "length": max(1, end - start), "pitch": int(pitch),
                "velocity": max(1, min(127, int(velocity))), "slide": 0.0,
                "vibrato": 0.0, "delay": 0.0, "gate": 1.0,
            })
    song = {"name": name, "platform": platform, "bpm": round(bpm, 2),
            "steps": steps, "steps_per_beat": STEPS_PER_BEAT, "tracks": tracks}
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    Path(out_path).write_text(json.dumps(song, indent=2), encoding="utf-8")
    return {"ok": True, "out": out_path, "bpm": song["bpm"], "steps": steps,
            "tracks": sum(1 for t in tracks if t["notes"])}


def _load_openmpt():
    for name in ("libopenmpt.so.0", "libopenmpt.so"):
        try:
            lib = ctypes.CDLL(name)
            lib.openmpt_module_create_from_memory.argtypes = [
                ctypes.c_char_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
            lib.openmpt_module_create_from_memory.restype = ctypes.c_void_p
            for func, restype, argtypes in (
                ("openmpt_module_get_num_orders", ctypes.c_int, [ctypes.c_void_p]),
                ("openmpt_module_get_order_pattern", ctypes.c_int, [ctypes.c_void_p, ctypes.c_int]),
                ("openmpt_module_get_pattern_num_rows", ctypes.c_int, [ctypes.c_void_p, ctypes.c_int]),
                ("openmpt_module_get_num_channels", ctypes.c_int, [ctypes.c_void_p]),
                ("openmpt_module_get_pattern_row_channel_command", ctypes.c_int,
                 [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int]),
                ("openmpt_module_get_current_tempo2", ctypes.c_double, [ctypes.c_void_p]),
                ("openmpt_module_get_current_speed", ctypes.c_int, [ctypes.c_void_p]),
                ("openmpt_module_get_duration_seconds", ctypes.c_double, [ctypes.c_void_p]),
                ("openmpt_module_get_pattern_rows_per_beat", ctypes.c_int, [ctypes.c_void_p, ctypes.c_int]),
                ("openmpt_module_set_position_order_row", ctypes.c_int, [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]),
                ("openmpt_module_destroy", None, [ctypes.c_void_p]),
            ):
                fn = getattr(lib, func)
                fn.restype = restype
                fn.argtypes = argtypes
            return lib
        except Exception:
            continue
    return None


def import_it(it_path: str, out_path: str, name: str, platform: str) -> dict:
    lib = _load_openmpt()
    if lib is None:
        raise RuntimeError("libopenmpt is not available; install libopenmpt0")
    data = Path(it_path).read_bytes()
    module = lib.openmpt_module_create_from_memory(data, len(data), None, None, None)
    if not module:
        raise RuntimeError("libopenmpt could not load the IT file")
    try:
        lib.openmpt_module_set_position_order_row(module, 0, 0)
        orders = max(0, int(lib.openmpt_module_get_num_orders(module)))
        channels = max(1, min(MAX_MD_TRACKS if platform == "megadrive" else MAX_SNES_TRACKS,
                              int(lib.openmpt_module_get_num_channels(module))))
        tempo = float(lib.openmpt_module_get_current_tempo2(module))
        if tempo < 20 or tempo > 400:
            tempo = 120.0
        try:
            rows_per_beat = max(1, min(16, int(lib.openmpt_module_get_pattern_rows_per_beat(module, 0))))
        except Exception:
            rows_per_beat = 4
        tracks = default_song(platform, name)["tracks"]
        active: dict[int, tuple[int, int, int]] = {}
        global_step = 0
        for order in range(orders):
            pattern = int(lib.openmpt_module_get_order_pattern(module, order))
            rows = max(1, int(lib.openmpt_module_get_pattern_num_rows(module, pattern)))
            try:
                rows_per_beat = max(1, int(lib.openmpt_module_get_pattern_rows_per_beat(module, pattern)))
            except Exception:
                rows_per_beat = 4
            for row in range(rows):
                for channel in range(channels):
                    note = int(lib.openmpt_module_get_pattern_row_channel_command(module, pattern, row, channel, 0))
                    instrument = int(lib.openmpt_module_get_pattern_row_channel_command(module, pattern, row, channel, 1))
                    volume = int(lib.openmpt_module_get_pattern_row_channel_command(module, pattern, row, channel, 2))
                    if 1 <= note <= 120:
                        previous = active.get(channel)
                        if previous is not None:
                            start, pitch, velocity = previous
                            tracks[channel]["notes"].append({
                                "step": start, "length": max(1, global_step - start),
                                "pitch": pitch, "velocity": velocity, "slide": 0.0,
                                "vibrato": 0.0, "delay": 0.0, "gate": 1.0,
                            })
                        # The IT volume column maps 1..64 to 0..63. Many modules
                        # leave it at 1 for every note, which means "no useful
                        # volume information"; keep those audible.
                        if 3 <= volume <= 64:
                            velocity = max(1, min(127, int(round(volume * 127 / 64.0))))
                        else:
                            velocity = 100
                        active[channel] = (global_step, note, velocity)
                        if instrument > 0:
                            tracks[channel]["instrument"] = instrument
                            if platform == "megadrive":
                                if channel >= 6:
                                    tracks[channel]["kind"] = "psg"
                                else:
                                    tracks[channel]["kind"] = "fm"
                            else:
                                tracks[channel]["kind"] = "snes"
                    elif note in (254, 255):
                        previous = active.pop(channel, None)
                        if previous is not None:
                            start, pitch, velocity = previous
                            tracks[channel]["notes"].append({
                                "step": start, "length": max(1, global_step - start),
                                "pitch": pitch, "velocity": velocity, "slide": 0.0,
                                "vibrato": 0.0, "delay": 0.0, "gate": 1.0,
                            })
                global_step += 1
        for channel, (start, pitch, velocity) in active.items():
            tracks[channel]["notes"].append({
                "step": start, "length": max(1, global_step - start),
                "pitch": pitch, "velocity": velocity, "slide": 0.0,
                "vibrato": 0.0, "delay": 0.0, "gate": 1.0,
            })
        steps = max(64, int(math.ceil(global_step / 16.0) * 16))
        try:
            duration = float(lib.openmpt_module_get_duration_seconds(module))
        except Exception:
            duration = 0.0
        if duration > 0.5:
            # Fit the fixed-tempo MIDI export to the module's real duration so
            # the SNES/MD preview has the same length as the IT file.
            fitted = steps * 60.0 / (duration * rows_per_beat)
            if 20.0 <= fitted <= 400.0:
                tempo = fitted
        song = {"name": name, "platform": platform, "bpm": round(tempo, 2),
                "steps": steps, "steps_per_beat": rows_per_beat,
                "tracks": tracks}
        Path(out_path).parent.mkdir(parents=True, exist_ok=True)
        Path(out_path).write_text(json.dumps(song, indent=2), encoding="utf-8")
        return {"ok": True, "out": out_path, "bpm": song["bpm"], "steps": steps,
                "tracks": sum(1 for t in tracks if t["notes"]), "orders": orders}
    finally:
        lib.openmpt_module_destroy(module)


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    exp = sub.add_parser("export-midi")
    exp.add_argument("--song", required=True)
    exp.add_argument("--out", required=True)
    imp_m = sub.add_parser("import-midi")
    imp_m.add_argument("--midi", required=True)
    imp_m.add_argument("--out", required=True)
    imp_m.add_argument("--name", default="song")
    imp_m.add_argument("--platform", choices=["snes", "megadrive"], default="snes")
    imp_i = sub.add_parser("import-it")
    imp_i.add_argument("--it", required=True)
    imp_i.add_argument("--out", required=True)
    imp_i.add_argument("--name", default="song")
    imp_i.add_argument("--platform", choices=["snes", "megadrive"], default="snes")
    args = parser.parse_args()
    try:
        if args.command == "export-midi":
            result = export_midi(json.loads(Path(args.song).read_text(encoding="utf-8")), args.out)
        elif args.command == "import-midi":
            result = import_midi(args.midi, args.out, args.name, args.platform)
        else:
            result = import_it(args.it, args.out, args.name, args.platform)
        print(json.dumps(result))
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
