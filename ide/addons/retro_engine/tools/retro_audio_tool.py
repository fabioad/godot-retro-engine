#!/usr/bin/env python3
"""Retro Engine audio conversion and synthesis helper.

This tool intentionally uses the real SDK/chip formats:

* SNES BGM: MIDI/IT -> Impulse Tracker module -> smconv -> SNESMOD soundbank.
* SNES SFX: synthesized/decoded WAV -> snesbrr -> BRR sample.
* Mega Drive BGM: MIDI -> VGM (SN76489 PSG) -> rescomp/xgmtool -> XGM.
* Mega Drive SFX: synthesized/decoded WAV -> rescomp WAV/XGM (PCM).

It also renders WAV previews so the editor can audition the arrangement before
building a ROM.  All conversions are deterministic and dependency-light:
mido, numpy, ffmpeg, timidity, smconv, snesbrr and rescomp are used when the
corresponding operation needs them.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import struct
import subprocess
import sys
import wave
from dataclasses import dataclass
from pathlib import Path

try:
    import mido
except Exception:  # pragma: no cover - only needed for MIDI input
    mido = None

try:
    import numpy as np
except Exception:  # pragma: no cover
    np = None


# ---------------------------------------------------------------------------
# Small WAV helpers
# ---------------------------------------------------------------------------

def write_wav(path: str, samples, rate: int, channels: int = 1) -> None:
    """Write float samples in [-1, 1] as 16-bit PCM WAV."""
    if np is not None:
        data = np.asarray(samples, dtype=np.float32).reshape(-1)
        pcm = np.clip(data * 32767.0, -32768, 32767).astype("<i2").tobytes()
    else:
        pcm = b"".join(struct.pack("<h", max(-32768, min(32767, int(s * 32767)))) for s in samples)
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm)


def read_wav_mono(path: str):
    with wave.open(path, "rb") as w:
        channels = w.getnchannels()
        width = w.getsampwidth()
        rate = w.getframerate()
        raw = w.readframes(w.getnframes())
    if width == 2:
        vals = struct.unpack("<" + "h" * (len(raw) // 2), raw)
        scale = 32768.0
    elif width == 1:
        vals = [b - 128 for b in raw]
        scale = 128.0
    else:
        raise ValueError("unsupported WAV sample width")
    if channels > 1:
        vals = [sum(vals[i:i + channels]) / channels for i in range(0, len(vals), channels)]
    return [v / scale for v in vals], rate


def run(cmd, cwd=None, check=True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, check=check, text=True, errors="replace",
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def ffmpeg_to_wav(src: str, dst: str, rate: int, channels: int = 1) -> None:
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", src,
         "-ac", str(channels), "-ar", str(rate), "-sample_fmt", "s16", dst])


# ---------------------------------------------------------------------------
# MIDI helpers
# ---------------------------------------------------------------------------

@dataclass
class NoteEvent:
    time: float
    channel: int
    note: int
    velocity: int
    program: int
    is_off: bool


def read_midi_events(path: str):
    if mido is None:
        raise RuntimeError("mido is required to read MIDI files")
    mid = mido.MidiFile(path)
    ticks_per_beat = mid.ticks_per_beat
    tempo = 500000.0  # microseconds per beat
    absolute_ticks = 0
    time = 0.0
    events: list[NoteEvent] = []
    program = [0] * 16
    # mido merge_tracks keeps delta times; process in order.
    for msg in mido.merge_tracks(mid.tracks):
        absolute_ticks += msg.time
        if msg.type == "set_tempo":
            tempo = float(msg.tempo)
        seconds_per_tick = (tempo / 1_000_000.0) / ticks_per_beat
        time = absolute_ticks * seconds_per_tick
        if msg.type == "program_change":
            program[msg.channel] = msg.program
        elif msg.type == "note_on" and msg.velocity > 0:
            events.append(NoteEvent(time, msg.channel, msg.note, msg.velocity, program[msg.channel], False))
        elif msg.type in ("note_off",) or (msg.type == "note_on" and msg.velocity == 0):
            events.append(NoteEvent(time, msg.channel, msg.note, 0, program[msg.channel], True))
    return mid, events


def midi_duration(events: list[NoteEvent]) -> float:
    return max((e.time for e in events), default=0.0) + 0.5


def channel_instrument(channel: int, program: int) -> int:
    """Return 1-based IT instrument index (1 sine, 2 square, 3 saw, 4 tri, 5 noise)."""
    if channel == 9:
        return 5
    if 32 <= program <= 39:
        return 2
    if 24 <= program <= 31:
        return 3
    if 80 <= program <= 87 or 56 <= program <= 63:
        return 2
    if 0 <= program <= 7:
        return 1
    return 4


def build_instrument_samples():
    """Create 16-bit mono instrument samples and IT sample metadata."""
    rate = 16744
    period = 64
    out = []
    for name, kind in [("sine", "sine"), ("square", "square"), ("saw", "saw"),
                       ("triangle", "triangle"), ("noise", "noise")]:
        if kind == "noise":
            rng = random.Random(0x5EED)
            data = [rng.uniform(-0.65, 0.65) for _ in range(256)]
            loop = False
        else:
            data = []
            for i in range(period):
                p = i / period
                if kind == "sine":
                    v = math.sin(2.0 * math.pi * p) * 0.8
                elif kind == "square":
                    v = 0.72 if p < 0.5 else -0.72
                elif kind == "saw":
                    v = (2.0 * p - 1.0) * 0.75
                else:
                    v = (4.0 * abs(p - 0.5) - 1.0) * 0.75
                data.append(v)
            loop = True
        out.append({"name": name, "data": data, "loop": loop, "rate": rate})
    return out


# ---------------------------------------------------------------------------
# IT writer
# ---------------------------------------------------------------------------

def _le16(v): return struct.pack("<H", int(v) & 0xFFFF)
def _le32(v): return struct.pack("<I", int(v) & 0xFFFFFFFF)


def write_it_from_events(path: str, events: list[NoteEvent], title: str,
                         speed: int = 6, tempo: int = 150,
                         samples_override=None, force_instrument=None,
                         instrument_map=None) -> dict:
    """Write a minimal valid IT module with 8 channels and 5 sampled instruments."""
    if not events:
        raise RuntimeError("MIDI has no note events")
    row_seconds = (2.5 / float(tempo)) * float(speed)
    rows_total = 1
    # Map MIDI channels to 8 IT channels, drums last.
    mapping: dict[int, int] = {}
    next_ch = 0
    for e in events:
        if e.channel not in mapping:
            if e.channel == 9:
                mapping[e.channel] = 7
            elif next_ch == 7:
                next_ch = 6
                mapping[e.channel] = next_ch
                next_ch += 1
            else:
                mapping[e.channel] = next_ch
                next_ch += 1
    # Row events: row -> channel -> (note, instrument, volume)
    cell: dict[int, dict[int, tuple[int, int, int]]] = {}
    for e in events:
        row = max(0, int(round(e.time / row_seconds)))
        rows_total = max(rows_total, row + 1)
        ch = mapping.get(e.channel, 0)
        if e.is_off:
            cell.setdefault(row, {})[ch] = (255, 0, 0)
        else:
            vol = max(1, min(64, int(round(e.velocity * 64 / 127))))
            if force_instrument is not None:
                instr = force_instrument
            elif instrument_map is not None and e.program in instrument_map:
                instr = instrument_map[e.program]
            else:
                instr = channel_instrument(e.channel, e.program)
            cell.setdefault(row, {})[ch] = (max(1, min(119, e.note)), instr, vol)
    patterns = max(1, (rows_total + 63) // 64)
    if patterns > 200:
        patterns = 200
        rows_total = patterns * 64
    samples = samples_override if samples_override is not None else build_instrument_samples()

    # ---- IT header --------------------------------------------------------
    header = bytearray(0xC0)
    header[0:4] = b"IMPM"
    name = title.encode("ascii", "replace")[:25]
    header[4:4 + len(name)] = name
    header[0x1E:0x20] = _le16(0x0004)  # pattern highlight
    header[0x20:0x22] = _le16(patterns)  # orders
    header[0x22:0x24] = _le16(len(samples))  # instruments
    header[0x24:0x26] = _le16(len(samples))  # samples
    header[0x26:0x28] = _le16(patterns)
    header[0x28:0x2A] = _le16(0x0214)
    header[0x2A:0x2C] = _le16(0x0214)
    header[0x2C:0x2E] = _le16(0x000C)  # instruments + linear slides
    header[0x2E:0x30] = _le16(0x0000)
    header[0x30] = 128  # global volume
    header[0x31] = 128  # mix volume
    header[0x32] = speed
    header[0x33] = tempo
    header[0x34] = 128  # pan separation
    header[0x35] = 0
    header[0x36:0x38] = _le16(0)
    header[0x38:0x3C] = _le32(0)
    for i in range(64):
        header[0x40 + i] = 32
        header[0x80 + i] = 64

    data = bytearray(header)
    data += bytes(range(patterns))  # orders

    ins_table_pos = len(data)
    data += b"\x00" * (len(samples) * 4)
    smp_table_pos = len(data)
    data += b"\x00" * (len(samples) * 4)
    pat_table_pos = len(data)
    data += b"\x00" * (patterns * 4)

    # ---- Instruments ------------------------------------------------------
    ins_offsets = []
    for s in samples:
        ins_offsets.append(len(data))
        ins = bytearray(547)
        ins[0:4] = b"IMPI"
        nm = s["name"].encode("ascii")[:25]
        ins[0x1F:0x1F + len(nm)] = nm
        ins[0x14:0x16] = _le16(int(s.get("fadeout", 0)))
        ins[0x18] = 128  # global volume
        ins[0x19] = 0xA0  # use default pan, center
        ins[0x1C:0x1E] = _le16(0x0214)
        ins[0x1E] = 1  # one sample
        # Notemap: note i -> sample 1
        off = 0x40
        for i in range(120):
            ins[off + i * 2] = i
            ins[off + i * 2 + 1] = 1
        # Three empty envelopes (81 bytes each)
        env_off = 0x40 + 240
        for _ in range(3):
            # FLG, length, loop/sustain nodes all zero
            ins[env_off:env_off + 81] = b"\x00" * 81
            env_off += 81
        data += ins

    # ---- Patterns ---------------------------------------------------------
    pat_offsets = []
    for p in range(patterns):
        pat_offsets.append(len(data))
        body = bytearray()
        for r in range(64):
            row_index = p * 64 + r
            channels = cell.get(row_index, {})
            for ch in sorted(channels):
                note, instr, vol = channels[ch]
                body.append((ch + 1) | 0x80)
                if note == 255:
                    body.append(0x01)  # note only
                    body.append(255)
                else:
                    body.append(0x07)  # note + instrument + volume
                    body.append(note)
                    body.append(instr)
                    body.append(vol)
            body.append(0)  # end of row
        data += _le16(len(body)) + _le16(64) + b"\x00\x00\x00\x00" + body

    # ---- Sample headers + data --------------------------------------------
    smp_offsets = []
    sample_data_blobs = []
    for s in samples:
        smp_offsets.append(len(data))
        hdr = bytearray(80)
        hdr[0:4] = b"IMPS"
        nm = s["name"].encode("ascii")[:25]
        hdr[0x14:0x14 + len(nm)] = nm
        hdr[0x11] = 64  # global volume
        flags = 0x01 | 0x02 | (0x10 if s["loop"] else 0)
        hdr[0x12] = flags
        hdr[0x13] = 64  # default volume
        hdr[0x2E] = 1  # signed samples
        hdr[0x2F] = 32  # default panning
        n = len(s["data"])
        loop_start = int(s.get("loop_start", 0))
        loop_end = int(s.get("loop_end", n))
        hdr[0x30:0x34] = _le32(n)
        hdr[0x34:0x38] = _le32(loop_start)
        hdr[0x38:0x3C] = _le32(loop_end)
        hdr[0x3C:0x40] = _le32(s["rate"])
        hdr[0x40:0x44] = _le32(0)
        hdr[0x44:0x48] = _le32(0)
        # sample pointer is patched after all headers exist
        smp_offsets[-1] = len(data)
        data += hdr
        smp_offsets[-1] = len(data) - 80
        pcm = b"".join(struct.pack("<h", max(-32768, min(32767, int(v * 32767)))) for v in s["data"])
        sample_data_blobs.append(pcm)

    # Patch sample data pointers and append blobs
    for i, blob in enumerate(sample_data_blobs):
        ptr = len(data)
        struct.pack_into("<I", data, smp_offsets[i] + 0x48, ptr)
        data += blob

    # Patch offset tables
    for i, off in enumerate(ins_offsets):
        struct.pack_into("<I", data, ins_table_pos + i * 4, off)
    for i, off in enumerate(smp_offsets):
        struct.pack_into("<I", data, smp_table_pos + i * 4, off)
    for i, off in enumerate(pat_offsets):
        struct.pack_into("<I", data, pat_table_pos + i * 4, off)

    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_bytes(data)
    return {"rows": rows_total, "patterns": patterns, "instruments": len(samples),
            "row_seconds": row_seconds, "duration": rows_total * row_seconds}


# Tracker modules libopenmpt can render (the editor also imports their notes
# through bgm_tool.py). `.it` keeps the native SNESMOD path on SNES.
MODULE_EXTS = {".it", ".xm", ".s3m", ".mod", ".mtm", ".umx", ".mptm", ".669",
               ".far", ".okt", ".stm", ".amf", ".dsm", ".mdl", ".psm", ".ptm",
               ".dbm", ".med", ".mt2", ".mo3"}


# ---------------------------------------------------------------------------
# VGM writer (Mega Drive SN76489 PSG)
# ---------------------------------------------------------------------------

PSG_CLOCK = 3579545
VGM_RATE = 44100


def _psg_tone(counter: int) -> bytes:
    counter = max(1, min(1023, int(counter)))
    latch = 0x80 | (counter & 0x0F)
    high = (counter >> 4) & 0x3F
    return bytes([0x50, latch, 0x50, high])


def _psg_vol(channel: int, attenuation: int) -> bytes:
    attenuation = max(0, min(15, int(attenuation)))
    return bytes([0x50, 0x80 | (channel << 5) | 0x10 | attenuation])


def _psg_noise(control: int) -> bytes:
    return bytes([0x50, 0xE0 | (control & 0x07)])


YM_CLOCK = 7670453


def _ym_write(port: int, reg: int, value: int) -> bytes:
    return bytes([0x52 if port == 0 else 0x53, reg & 0xFF, value & 0xFF])


def _ym_patch_init() -> bytes:
    out = bytearray()
    # LFO off, timers off, DAC off, all keys off.
    for reg, value in ((0x22, 0x00), (0x27, 0x00), (0x28, 0x00), (0x2B, 0x00)):
        out += _ym_write(0, reg, value)
    return bytes(out)


def _fm_family(program: int, channel: int) -> str:
    if channel == 9:
        return "noise"
    if 32 <= program <= 39:
        return "bass"
    if 24 <= program <= 31 or 40 <= program <= 47:
        return "guitar"
    if 48 <= program <= 55:
        return "strings"
    if 56 <= program <= 63:
        return "brass"
    if 80 <= program <= 87:
        return "lead"
    if 0 <= program <= 7:
        return "piano"
    return "lead"


# Per-family YM2612 patches: (op0_mul, op1_mul, op0_tl, op1_tl,
# attack, decay, sustain_level, release). Algorithm 7 keeps both operators
# as carriers; OP3/OP4 are silenced.
_FM_PATCHES = {
    "piano":   (1, 2, 0x10, 0x1C, 0x1F, 0x18, 0x02, 0x0A),
    "guitar":  (2, 3, 0x0A, 0x18, 0x1F, 0x10, 0x01, 0x08),
    "bass":    (1, 1, 0x08, 0x20, 0x1F, 0x06, 0x00, 0x0F),
    "strings": (1, 2, 0x14, 0x20, 0x0C, 0x00, 0x00, 0x0C),
    "brass":   (2, 3, 0x10, 0x18, 0x1A, 0x08, 0x01, 0x0C),
    "lead":    (1, 4, 0x10, 0x1C, 0x1F, 0x08, 0x01, 0x0C),
}


def _ym_patch_writes(ch: int, family: str) -> bytes:
    port = ch // 3
    c = ch % 3
    mul0, mul1, tl0, tl1, ar, dr, sl, rr = _FM_PATCHES.get(family, _FM_PATCHES["lead"])
    out = bytearray()
    for op in range(4):
        base = c * 4 + op * 4
        mul = mul0 if op == 0 else (mul1 if op == 1 else 1)
        tl = tl0 if op == 0 else (tl1 if op == 1 else 0x7F)
        out += _ym_write(port, 0x30 + base, mul)
        out += _ym_write(port, 0x40 + base, tl)
        out += _ym_write(port, 0x50 + base, ar)
        out += _ym_write(port, 0x60 + base, dr)
        out += _ym_write(port, 0x70 + base, 0x00)
        out += _ym_write(port, 0x80 + base, (sl << 4) | rr)
        out += _ym_write(port, 0x90 + base, 0x00)
    out += _ym_write(port, 0xB0 + c, 0x07)
    out += _ym_write(port, 0xB4 + c, 0xC0)
    return bytes(out)


def _ym_frequency(port: int, channel: int, note: int) -> bytes:
    freq = 440.0 * (2.0 ** ((note - 69) / 12.0))
    block = 4
    fnum = int(round(freq * (2 ** (20 - block)) * 144.0 / YM_CLOCK))
    while fnum > 2047 and block < 7:
        block += 1
        fnum = int(round(freq * (2 ** (20 - block)) * 144.0 / YM_CLOCK))
    while fnum < 512 and block > 0:
        block -= 1
        fnum = int(round(freq * (2 ** (20 - block)) * 144.0 / YM_CLOCK))
    fnum = max(0, min(2047, fnum))
    low_reg = 0xA0 + port * 4 + channel
    high_reg = 0xA8 + port * 4 + channel
    return _ym_write(port, low_reg, fnum & 0xFF) + _ym_write(port, high_reg, ((block & 7) << 3) | ((fnum >> 8) & 7))


def write_vgm_from_events(path: str, events: list[NoteEvent], title: str) -> dict:
    """Write a VGM with 5 YM2612 FM channels + PSG noise percussion."""
    duration = midi_duration(events)
    # Quantize to 60 Hz frames.
    frames = max(1, int(math.ceil(duration * 60.0)))
    # Track active notes per MIDI channel.
    # Assign MIDI channels to 3 tone channels; drums to noise.
    tone_map: dict[int, int] = {}
    next_tone = 0
    for e in events:
        if e.channel == 9:
            continue
        if e.channel not in tone_map:
            tone_map[e.channel] = next_tone % 3
            next_tone += 1
    events = sorted(events, key=lambda e: e.time)
    fm_map: dict[int, int] = {}
    next_fm = 0
    for e in events:
        if e.channel == 9:
            continue
        if e.channel not in fm_map:
            fm_map[e.channel] = next_fm % 6
            next_fm += 1
    fm_active: dict[int, int] = {}
    fm_patch: dict[int, str] = {}
    last_noise = -1
    event_index = 0
    commands = bytearray(_ym_patch_init())
    for f in range(frames):
        t = f / 60.0
        while event_index < len(events) and events[event_index].time <= t + 1e-9:
            e = events[event_index]
            event_index += 1
            if e.channel == 9:
                if not e.is_off:
                    control = 4 if e.note in (35, 36) else 6
                    commands += _psg_noise(control)
                    commands += _psg_vol(3, 0)
                    last_noise = f
                continue
            fm_ch = fm_map.get(e.channel, 0)
            if e.is_off:
                if fm_ch in fm_active:
                    commands += _ym_write(0 if fm_ch < 3 else 1, 0x28, (fm_ch << 4) & 0x70)
                    fm_active.pop(fm_ch, None)
            elif fm_active.get(fm_ch) != e.note:
                if fm_ch in fm_active:
                    commands += _ym_write(0 if fm_ch < 3 else 1, 0x28, (fm_ch << 4) & 0x70)
                family = _fm_family(e.program, e.channel)
                if fm_patch.get(fm_ch) != family:
                    commands += _ym_patch_writes(fm_ch, family)
                    fm_patch[fm_ch] = family
                commands += _ym_frequency(fm_ch // 3, fm_ch % 3, e.note)
                commands += _ym_write(0 if fm_ch < 3 else 1, 0x28, ((fm_ch << 4) & 0x70) | 0x0F)
                fm_active[fm_ch] = e.note
        if last_noise >= 0 and f - last_noise > 5:
            commands += _psg_vol(3, 15)
            last_noise = -1
        commands += b"\x62"  # wait 735 samples (~1/60s)
    commands += b"\x66"

    # VGM header
    vgm = bytearray(0x100)
    vgm[0:4] = b"Vgm "
    vgm[0x08:0x0C] = _le32(0x150)
    vgm[0x0C:0x10] = _le32(PSG_CLOCK)
    vgm[0x18:0x1C] = _le32(frames * 735)
    vgm[0x30:0x34] = _le32(YM_CLOCK)
    vgm[0x34:0x38] = _le32(0x100 - 0x34)
    out = bytes(vgm) + bytes(commands)
    # EOF offset relative to 0x04
    eof = len(out) - 4
    out = bytearray(out)
    struct.pack_into("<I", out, 0x04, eof)
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_bytes(out)
    return {"duration": duration, "frames": frames}


def render_vgm_psg(vgm_path: str, wav_path: str) -> None:
    data = Path(vgm_path).read_bytes()
    if data[:4] != b"Vgm ":
        raise ValueError("not a VGM file")
    data_off = 0x34 + struct.unpack_from("<I", data, 0x34)[0]
    pos = data_off
    # Simple PSG state renderer at 44100 Hz.
    rate = VGM_RATE
    tone = [0, 0, 0, 0]
    vol = [15, 15, 15, 15]
    noise_control = 0
    phase = [0.0, 0.0, 0.0]
    noise_lfsr = 0x8000
    latched = [0, 0, 0, 0]
    last_tone_ch = 0
    samples = []
    def advance(n):
        nonlocal noise_lfsr
        for _ in range(n):
            mix = 0.0
            for ch in range(3):
                if vol[ch] >= 15 or tone[ch] <= 0:
                    continue
                freq = PSG_CLOCK / (32.0 * tone[ch])
                phase[ch] += freq / rate
                phase[ch] %= 1.0
                amp = (15 - vol[ch]) / 15.0
                mix += amp * (0.5 if phase[ch] < 0.5 else -0.5)
            if vol[3] < 15:
                # Noise channel, shift LFSR at a fixed audible rate.
                if len(samples) % 4 == 0:
                    bit = ((noise_lfsr >> 0) ^ (noise_lfsr >> 3)) & 1
                    noise_lfsr = (noise_lfsr >> 1) | (bit << 15)
                amp = (15 - vol[3]) / 15.0
                mix += amp * (0.45 if (noise_lfsr & 1) else -0.45)
            samples.append(mix / 4.0)
    while pos < len(data):
        cmd = data[pos]
        pos += 1
        if cmd == 0x50:
            b = data[pos]; pos += 1
            if b & 0x80:
                ch = (b >> 5) & 3
                if b & 0x10:
                    vol[ch] = b & 0x0F
                elif ch == 3:
                    noise_control = b & 0x07
                else:
                    latched[ch] = b & 0x0F
                    last_tone_ch = ch
            else:
                # Data byte for the previously latched tone channel.
                tone[last_tone_ch] = ((b & 0x3F) << 4) | latched[last_tone_ch]
        elif cmd == 0x61:
            n = struct.unpack_from("<H", data, pos)[0]; pos += 2
            advance(n)
        elif cmd == 0x62:
            advance(735)
        elif cmd == 0x63:
            advance(882)
        elif cmd == 0x66:
            break
        elif cmd in (0x67,):
            # data block: skip
            if pos + 7 <= len(data):
                size = struct.unpack_from("<I", data, pos + 3)[0]
                pos += 7 + size
        else:
            # Unknown command: stop rather than desync.
            break
    write_wav(wav_path, samples, rate)


# ---------------------------------------------------------------------------
# SFX synthesis
# ---------------------------------------------------------------------------

def synthesize_sfx(params: dict, out_wav: str, rate: int = 32000) -> dict:
    duration = max(0.01, float(params.get("duration_ms", 250)) / 1000.0)
    freq = max(1.0, float(params.get("frequency", 440.0)))
    volume = max(0.0, min(1.0, float(params.get("volume", 0.8))))
    wave = str(params.get("waveform", "square")).lower()
    duty = max(0.05, min(0.95, float(params.get("duty", 0.5))))
    attack = max(0.0, float(params.get("attack_ms", 5)) / 1000.0)
    decay = max(0.0, float(params.get("decay_ms", 40)) / 1000.0)
    sustain = max(0.0, min(1.0, float(params.get("sustain", 0.7))))
    release = max(0.0, float(params.get("release_ms", 60)) / 1000.0)
    slide = float(params.get("pitch_slide", 0))  # semitones over duration
    vib_hz = float(params.get("vibrato_hz", 0))
    vib_depth = float(params.get("vibrato_depth", 0))  # semitones
    noise_mix = max(0.0, min(1.0, float(params.get("noise", 0))))
    bits = max(2, min(16, int(params.get("bitcrush", 16))))
    n = max(1, int(rate * duration))
    rng = random.Random(0xBEEF)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / rate
        env = 1.0
        if attack > 0 and t < attack:
            env = t / attack
        elif t < attack + decay:
            env = 1.0 - (1.0 - sustain) * ((t - attack) / max(1e-9, decay))
        elif t > duration - release:
            env = sustain * max(0.0, (duration - t) / max(1e-9, release))
        else:
            env = sustain
        semis = slide * (t / duration) + (vib_depth * math.sin(2 * math.pi * vib_hz * t) if vib_hz > 0 else 0.0)
        f = freq * (2.0 ** (semis / 12.0))
        phase += f / rate
        phase %= 1.0
        if wave == "square":
            s = 1.0 if phase < duty else -1.0
        elif wave == "saw":
            s = 2.0 * phase - 1.0
        elif wave == "triangle":
            s = 4.0 * abs(phase - 0.5) - 1.0
        elif wave == "noise":
            s = rng.uniform(-1.0, 1.0)
        else:
            s = math.sin(2.0 * math.pi * phase)
        if noise_mix > 0:
            s = s * (1.0 - noise_mix) + rng.uniform(-1.0, 1.0) * noise_mix
        s *= env * volume
        if bits < 16:
            q = 2 ** bits
            s = round(s * q) / q
        out.append(s)
    write_wav(out_wav, out, rate)
    return {"rate": rate, "samples": n, "duration_ms": duration * 1000.0}


# ---------------------------------------------------------------------------
# Asset conversion
# ---------------------------------------------------------------------------

def convert_asset(input_path: str, out_dir: str, name: str, kind: str, target: str,
                  sfx_params: dict | None = None) -> dict:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    src = Path(input_path)
    ext = src.suffix.lower()
    result = {"ok": True, "input": str(src), "name": name, "kind": kind,
              "target": target, "files": {}, "preview": ""}
    if kind == "sfx":
        if ext in (".wav", ".mp3") or sfx_params is not None:
            raw = out / f"{name}.wav"
            if sfx_params is not None:
                synthesize_sfx(sfx_params, str(raw), 32000 if target == "snes" else 16000)
            else:
                rate = 32000 if target == "snes" else 16000
                ffmpeg_to_wav(str(src), str(raw), rate)
            result["files"]["wav"] = str(raw)
            result["preview"] = str(raw)
            if target == "snes":
                brr = out / f"{name}.brr"
                snesbrr = os.environ.get("SNESBRR", "")
                if not snesbrr:
                    snesbrr = os.path.join(os.environ.get("PVSNESLIB_HOME", ""),
                                          "devkitsnes", "tools", "snesbrr")
                if not os.path.exists(snesbrr):
                    snesbrr = "snesbrr"
                run([snesbrr, "-e", str(raw), str(brr)])
                result["files"]["brr"] = str(brr)
            return result
        raise RuntimeError(f"unsupported SFX input: {ext}")
    # BGM
    preview = out / f"{name}_preview.wav"
    if ext == ".mid":
        mid, events = read_midi_events(str(src))
        if target == "snes":
            it = out / f"{name}.it"
            target_seconds = max(float(mid.length), midi_duration(events))
            try:
                gm = out / f"{name}_gm.wav"
                info = render_midi_gm(str(src), str(gm), 32000)
                pad_wav_to_duration(str(gm), target_seconds)
                info["duration"] = target_seconds
                write_sample_it(str(it), str(gm), name, preview_path=str(preview))
                result["files"]["gm_wav"] = str(gm)
                result["info"] = info
            except Exception as exc:
                # Keep the engine usable on hosts without TiMidity/FluidR3.
                info = write_it_from_events(str(it), events, name)
                info["fallback"] = str(exc)
                result["info"] = info
                ffmpeg_to_wav(str(it), str(preview), 32000)
                pad_wav_to_duration(str(preview), target_seconds)
            result["files"]["it"] = str(it)
        else:
            vgm = out / f"{name}.vgm"
            info = write_vgm_from_events(str(vgm), events, name)
            result["files"]["vgm"] = str(vgm)
            render_midi_fm_preview(events, str(preview))
            result["info"] = info
    elif ext in MODULE_EXTS:
        if target == "snes" and ext == ".it":
            dst = out / f"{name}.it"
            if src.resolve() != dst.resolve():
                dst.write_bytes(src.read_bytes())
            result["files"]["it"] = str(dst)
            ffmpeg_to_wav(str(dst), str(preview), 32000)
        elif target == "snes":
            # Non-IT modules are rendered through libopenmpt and embedded as
            # one loopable PCM/BRR sample, matching the WAV/MP3 BGM path.
            raw = out / f"{name}.wav"
            ffmpeg_to_wav(str(src), str(raw), 32000)
            dst = out / f"{name}.it"
            write_sample_it(str(dst), str(raw), name, preview_path=str(preview))
            result["files"]["it"] = str(dst)
            result["files"]["gm_wav"] = str(raw)
        else:
            # Render the module and store it as an XGM PCM music sample.
            raw = out / f"{name}.wav"
            ffmpeg_to_wav(str(src), str(raw), 13300)
            result["files"]["wav"] = str(raw)
            result["preview"] = str(raw)
            result["info"] = {"mode": "pcm"}
    elif ext in (".wav", ".mp3"):
        rate = 32000 if target == "snes" else 13300
        raw = out / f"{name}.wav"
        ffmpeg_to_wav(str(src), str(raw), rate)
        if target == "snes":
            # A single-sample IT module keeps the exact loopable PCM.
            it = out / f"{name}.it"
            write_sample_it(str(it), str(raw), name, preview_path=str(preview))
            result["files"]["it"] = str(it)
        else:
            result["files"]["wav"] = str(raw)
            result["preview"] = str(raw)
            result["info"] = {"mode": "pcm"}
    else:
        raise RuntimeError(f"unsupported BGM input: {ext}")
    if not result.get("preview"):
        result["preview"] = str(preview)
    return result


def trim_pcm_music(path: Path, out: Path, max_seconds: float = 8.0) -> None:
    samples, rate = read_wav_mono(str(path))
    max_n = int(rate * max_seconds)
    if len(samples) > max_n:
        samples = samples[:max_n]
        write_wav(str(out), samples, rate)


def _resample_linear(samples, source_rate: int, target_rate: int):
    if source_rate == target_rate or not samples:
        return samples
    ratio = target_rate / float(source_rate)
    out_len = max(1, int(len(samples) * ratio))
    out = []
    for i in range(out_len):
        pos = i / ratio
        i0 = min(len(samples) - 1, int(pos))
        i1 = min(len(samples) - 1, i0 + 1)
        frac = pos - i0
        out.append(samples[i0] * (1.0 - frac) + samples[i1] * frac)
    return out


def pad_wav_to_duration(path: str, seconds: float) -> None:
    samples, rate = read_wav_mono(path)
    n = max(1, int(round(seconds * rate)))
    if len(samples) < n:
        samples.extend([0.0] * (n - len(samples)))
    elif len(samples) > n:
        samples = samples[:n]
    write_wav(path, samples, rate)

def write_sample_it(path: str, wav_path: str, title: str, max_seconds: float = 0.0,
                    preview_path: str = "") -> None:
    """Create a one-instrument IT module for full-duration PCM/BRR music.

    The sample rate is chosen so the BRR data stays inside the ~58 KiB SPC
    sample budget. Short cues keep 8 kHz; long MIDI renders drop to ~5-6 kHz
    instead of being cut at 8 seconds.
    """
    samples, rate = read_wav_mono(wav_path)
    if max_seconds > 0:
        samples = samples[:int(rate * max_seconds)]
    duration = len(samples) / float(rate) if rate else 1.0
    # 16-bit PCM -> BRR is 9/32 of the PCM size. Keep a safety margin.
    max_brr_bytes = 52000
    max_samples = int(max_brr_bytes * 32 / 18)
    target_rate = int(max_samples / max(0.01, duration))
    target_rate = max(4000, min(8000, target_rate))
    samples = _resample_linear(samples, rate, target_rate)
    rate = target_rate
    if preview_path:
        # The IT module has a fixed 64-row pattern; rendering it can cut or
        # loop samples longer than 16 s. The BRR/soundbank sample itself is
        # full-length, so write the resampled sample directly for preview.
        write_wav(preview_path, samples, rate)
    sample = {"name": title[:24], "data": samples, "loop": True, "rate": rate}
    ev = [NoteEvent(0.0, 0, 60, 127, 0, False)]
    write_it_from_events(path, ev, title, speed=6, tempo=60,
                         samples_override=[sample], force_instrument=1)


def render_midi_gm(mid_path: str, out_wav: str, rate: int = 32000) -> dict:
    cfg = "/etc/timidity/fluidr3_gm.cfg"
    args = ["timidity", "-Ow", "--output-mono", "-s", str(rate)]
    if os.path.exists(cfg):
        args += ["-c", cfg]
    args += ["-o", out_wav, mid_path]
    run(args)
    # FluidR3's timidity amp is quiet for a mono render; normalize so the
    # BRR sample is audible on the SPC without changing the arrangement.
    samples, actual_rate = read_wav_mono(out_wav)
    peak = max((abs(v) for v in samples), default=0.0)
    if peak > 1e-6:
        gain = 0.85 / peak
        write_wav(out_wav, [v * gain for v in samples], actual_rate)
    return {"rate": actual_rate, "source": "FluidR3_GM.sf2" if os.path.exists(cfg) else "timidity-default"}


def render_midi_fm_preview(events: list[NoteEvent], out_wav: str, rate: int = 44100) -> None:
    """Approximate the YM2612 arrangement for the editor preview.

    The ROM itself plays the generated YM2612 VGM. This renderer uses the same
    note on/off timeline with a two-operator sine/harmonic voice so the preview
    is not a General-MIDI render and has the FM character.
    """
    duration = midi_duration(events)
    n = max(1, int(duration * rate))
    evs = sorted(events, key=lambda e: e.time)
    active: dict[int, tuple[int, float]] = {}
    out = []
    phase: dict[int, float] = {}
    env: dict[int, float] = {}
    ei = 0
    for i in range(n):
        t = i / rate
        while ei < len(evs) and evs[ei].time <= t:
            e = evs[ei]; ei += 1
            if e.channel == 9:
                continue
            if e.is_off:
                active.pop(e.channel, None)
            else:
                active[e.channel] = (e.note, 0.0)
                env[e.channel] = 0.0
        mix = 0.0
        for ch, (note, _) in list(active.items()):
            f = 440.0 * (2.0 ** ((note - 69) / 12.0))
            phase[ch] = (phase.get(ch, 0.0) + f / rate) % 1.0
            env[ch] = min(1.0, env.get(ch, 0.0) + 0.002)
            wave = math.sin(2 * math.pi * phase[ch]) + 0.35 * math.sin(4 * math.pi * phase[ch])
            mix += wave * env[ch] * 0.12
        out.append(max(-1.0, min(1.0, mix)))
    write_wav(out_wav, out, rate)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("convert")
    c.add_argument("--input", required=True)
    c.add_argument("--out-dir", required=True)
    c.add_argument("--name", required=True)
    c.add_argument("--kind", choices=["bgm", "sfx"], required=True)
    c.add_argument("--target", choices=["snes", "megadrive"], required=True)
    c.add_argument("--params")
    s = sub.add_parser("sfx")
    s.add_argument("--params", required=True)
    s.add_argument("--out", required=True)
    args = ap.parse_args()
    if args.cmd == "convert":
        params = json.loads(Path(args.params).read_text()) if args.params else None
        res = convert_asset(args.input, args.out_dir, args.name, args.kind, args.target, params)
        print(json.dumps(res, indent=2))
    elif args.cmd == "sfx":
        params = json.loads(Path(args.params).read_text())
        print(json.dumps(synthesize_sfx(params, args.out), indent=2))
