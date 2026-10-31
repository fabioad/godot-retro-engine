#!/usr/bin/env python3
"""Run a real SNES/Mega Drive ROM through a libretro core for the editor.

The process is started by rom_preview.gd, connects back to the editor over
127.0.0.1 and streams raw frames. It accepts pause/run, frame step, speed,
button press/release (including taps) and rewind commands. Rewind is backed by
libretro save states and the frames produced for each state.

Protocol:
  editor -> host : newline separated ASCII commands
  host -> editor : one JSON hello line, then binary frames:
                   b"LRF1" + u32 width + u32 height + u32 format +
                   u32 frame + u32 payload_size + payload
                   format 0 = RGB565, 1 = RGBA8888

This is intentionally a thin libretro frontend: the ROM executes exactly like
it does in an emulator. It is not a scripted approximation of the game.
"""
from __future__ import annotations

import argparse
import collections
import ctypes as C
import json
import os
import socket
import struct
import sys
import time

try:
    import numpy as np
except Exception:  # pragma: no cover - reported to the editor
    np = None

FORMAT_RGB565 = 0
FORMAT_RGBA8888 = 1

ENV_EXPERIMENTAL = 0x10000
RETRO_ENVIRONMENT_SET_PIXEL_FORMAT = 10
RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY = 9
RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY = 31
RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY = 30
RETRO_ENVIRONMENT_GET_LIBRETRO_PATH = 19
RETRO_ENVIRONMENT_GET_LOG_INTERFACE = 27
RETRO_ENVIRONMENT_GET_CAN_DUPE = 3
RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION = 52
RETRO_ENVIRONMENT_SET_VARIABLES = 16
RETRO_ENVIRONMENT_SET_CORE_OPTIONS = 53
RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2 = 67
RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL = 68
RETRO_ENVIRONMENT_SET_CONTROLLER_INFO = 35
RETRO_ENVIRONMENT_SET_MEMORY_MAPS = 36 | ENV_EXPERIMENTAL
RETRO_ENVIRONMENT_SET_GEOMETRY = 37
RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS = 44
RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME = 18
RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS = 42 | ENV_EXPERIMENTAL
RETRO_ENVIRONMENT_SET_HW_RENDER = 14
RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER = 56
RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE = 47 | ENV_EXPERIMENTAL
RETRO_ENVIRONMENT_GET_FASTFORWARDING = 49 | ENV_EXPERIMENTAL
RETRO_ENVIRONMENT_GET_INPUT_BITMASKS = 51 | ENV_EXPERIMENTAL
RETRO_ENVIRONMENT_GET_VFS_INTERFACE = 45 | ENV_EXPERIMENTAL
RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE = 65
RETRO_ENVIRONMENT_GET_GAME_INFO_EXT = 66

RETRO_DEVICE_JOYPAD = 1

# libretro joypad button ids
PAD_B = 0
PAD_Y = 1
PAD_SELECT = 2
PAD_START = 3
PAD_UP = 4
PAD_DOWN = 5
PAD_LEFT = 6
PAD_RIGHT = 7
PAD_A = 8
PAD_X = 9
PAD_L = 10
PAD_R = 11


class GameInfo(C.Structure):
    _fields_ = [
        ("path", C.c_char_p),
        ("data", C.c_void_p),
        ("size", C.c_size_t),
        ("meta", C.c_char_p),
    ]


class Geometry(C.Structure):
    _fields_ = [
        ("base_width", C.c_uint),
        ("base_height", C.c_uint),
        ("max_width", C.c_uint),
        ("max_height", C.c_uint),
        ("aspect_ratio", C.c_float),
    ]


class Timing(C.Structure):
    _fields_ = [("fps", C.c_double), ("sample_rate", C.c_double)]


class SystemAVInfo(C.Structure):
    _fields_ = [("geometry", Geometry), ("timing", Timing)]


class LibretroHost:
    def __init__(self, core_path: str, rom_path: str, platform: str,
                 system_dir: str, save_dir: str):
        self.core_path = core_path
        self.rom_path = rom_path
        self.platform = platform
        self.system_dir = system_dir
        self.save_dir = save_dir
        self.lib = C.CDLL(core_path)
        self.pixel_format = 2  # RGB565
        self.width = 0
        self.height = 0
        self.frame_index = -1
        self.buttons = 0
        self._frame_payload = b""
        self._frame_format = FORMAT_RGBA8888
        self._audio = bytearray()
        self.audio_enabled = True
        self.audio_rate = 0.0
        self._last_payload = b""
        self._last_w = 0
        self._last_h = 0
        self._last_format = FORMAT_RGB565
        self._keep = []
        self._shutdown = False
        self._serialize_size = 0
        self._bind()
        self._set_callbacks()

    def _bind(self) -> None:
        lib = self.lib
        lib.retro_set_environment.argtypes = [C.CFUNCTYPE(C.c_bool, C.c_uint, C.c_void_p)]
        lib.retro_set_video_refresh.argtypes = [C.CFUNCTYPE(None, C.c_void_p, C.c_uint, C.c_uint, C.c_size_t)]
        lib.retro_set_audio_sample.argtypes = [C.CFUNCTYPE(None, C.c_int16, C.c_int16)]
        lib.retro_set_audio_sample_batch.argtypes = [C.CFUNCTYPE(C.c_size_t, C.POINTER(C.c_int16), C.c_size_t)]
        lib.retro_set_input_poll.argtypes = [C.CFUNCTYPE(None)]
        lib.retro_set_input_state.argtypes = [C.CFUNCTYPE(C.c_int16, C.c_uint, C.c_uint, C.c_uint, C.c_uint)]
        lib.retro_init.argtypes = []
        lib.retro_deinit.argtypes = []
        lib.retro_load_game.argtypes = [C.POINTER(GameInfo)]
        lib.retro_load_game.restype = C.c_bool
        lib.retro_unload_game.argtypes = []
        lib.retro_run.argtypes = []
        lib.retro_get_system_av_info.argtypes = [C.POINTER(SystemAVInfo)]
        lib.retro_set_controller_port_device.argtypes = [C.c_uint, C.c_uint]
        lib.retro_reset.argtypes = []
        lib.retro_serialize_size.argtypes = []
        lib.retro_serialize_size.restype = C.c_size_t
        lib.retro_serialize.argtypes = [C.c_void_p, C.c_size_t]
        lib.retro_serialize.restype = C.c_bool
        lib.retro_unserialize.argtypes = [C.c_void_p, C.c_size_t]
        lib.retro_unserialize.restype = C.c_bool

    def _set_str(self, data, value: str) -> None:
        if not data:
            return
        raw = value.encode("utf-8")
        self._keep.append(raw)
        C.cast(data, C.POINTER(C.c_char_p))[0] = C.c_char_p(raw)

    def _env(self, cmd: int, data) -> bool:
        if cmd == RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
            self.pixel_format = int(C.cast(data, C.POINTER(C.c_int)).contents.value)
            return True
        if cmd == RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
            self._set_str(data, self.system_dir)
            return True
        if cmd == RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
            self._set_str(data, self.save_dir)
            return True
        if cmd == RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY:
            self._set_str(data, self.system_dir)
            return True
        if cmd == RETRO_ENVIRONMENT_GET_LIBRETRO_PATH:
            self._set_str(data, self.core_path)
            return True
        if cmd == RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
            if data:
                C.cast(data, C.POINTER(C.c_uint)).contents.value = 2
            return True
        if cmd == RETRO_ENVIRONMENT_GET_CAN_DUPE:
            if data:
                C.cast(data, C.POINTER(C.c_bool)).contents.value = True
            return True
        if cmd == RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER:
            if data:
                C.cast(data, C.POINTER(C.c_uint)).contents.value = 0
            return True
        if cmd == RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:
            if data:
                C.cast(data, C.POINTER(C.c_int)).contents.value = 3
            return True
        if cmd == RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
            if data:
                C.cast(data, C.POINTER(C.c_bool)).contents.value = False
            return True
        if cmd == RETRO_ENVIRONMENT_GET_FASTFORWARDING:
            if data:
                C.cast(data, C.POINTER(C.c_bool)).contents.value = False
            return True
        if cmd == RETRO_ENVIRONMENT_SET_HW_RENDER:
            return False
        if cmd == RETRO_ENVIRONMENT_GET_VFS_INTERFACE:
            return False
        if cmd in (RETRO_ENVIRONMENT_SET_VARIABLES,
                   RETRO_ENVIRONMENT_SET_CORE_OPTIONS,
                   RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2,
                   RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL,
                   RETRO_ENVIRONMENT_SET_CONTROLLER_INFO,
                   RETRO_ENVIRONMENT_SET_MEMORY_MAPS,
                   RETRO_ENVIRONMENT_SET_GEOMETRY,
                   RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS,
                   RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME,
                   RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS):
            return True
        # The extended content API must be explicitly unsupported. Returning
        # true here makes some cores read a game_info_ext pointer that was
        # never provided and crash in retro_load_game().
        if cmd in (RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE,
                   RETRO_ENVIRONMENT_GET_GAME_INFO_EXT):
            return False
        return False

    def _video(self, data, width, height, pitch) -> None:
        if not data:
            if self._last_payload:
                self.frame_index += 1
                self._frame_payload = self._last_payload
                self.width = self._last_w
                self.height = self._last_h
                self._frame_format = self._last_format
            return
        width = int(width)
        height = int(height)
        pitch = int(pitch)
        raw = C.string_at(data, pitch * height)
        if np is None:
            raise RuntimeError("numpy is required for the libretro frame bridge")
        arr = np.frombuffer(raw, dtype=np.uint8).reshape(height, pitch)
        if self.pixel_format == 2:  # RGB565
            values = np.frombuffer(raw, dtype=np.uint16).reshape(height, pitch // 2)[:, :width]
            r = ((values >> 11) & 0x1F).astype(np.uint8) << 3
            g = ((values >> 5) & 0x3F).astype(np.uint8) << 2
            b = (values & 0x1F).astype(np.uint8) << 3
        elif self.pixel_format == 0:  # 0RGB1555
            values = np.frombuffer(raw, dtype=np.uint16).reshape(height, pitch // 2)[:, :width]
            r = ((values >> 10) & 0x1F).astype(np.uint8) << 3
            g = ((values >> 5) & 0x1F).astype(np.uint8) << 3
            b = (values & 0x1F).astype(np.uint8) << 3
        else:  # XRGB8888
            values = np.frombuffer(raw, dtype=np.uint32).reshape(height, pitch // 4)[:, :width]
            r = ((values >> 16) & 0xFF).astype(np.uint8)
            g = ((values >> 8) & 0xFF).astype(np.uint8)
            b = (values & 0xFF).astype(np.uint8)
        a = np.full_like(r, 255)
        payload = np.ascontiguousarray(np.dstack((r, g, b, a))).tobytes()
        fmt = FORMAT_RGBA8888
        self.width = width
        self.height = height
        self._frame_payload = payload
        self._frame_format = fmt
        self._last_payload = payload
        self._last_w = width
        self._last_h = height
        self._last_format = fmt
        self.frame_index += 1

    def _audio_sample(self, left, right) -> None:
        if self.audio_enabled:
            self._audio += struct.pack("<hh", int(left), int(right))

    def _audio_batch(self, data, frames) -> int:
        if self.audio_enabled and data and frames > 0:
            self._audio += C.string_at(data, int(frames) * 4)
        return int(frames)

    def take_audio(self) -> bytes:
        if not self._audio:
            return b""
        data = bytes(self._audio)
        self._audio.clear()
        return data

    def _input_state(self, port, device, index, button_id) -> int:
        if port != 0:
            return 0
        if button_id == 256:  # joypad mask query (we advertise no bitmasks)
            return self.buttons & 0xFFFF
        if 0 <= button_id < 16:
            return 1 if (self.buttons >> button_id) & 1 else 0
        return 0

    def _set_callbacks(self) -> None:
        self._env_cb = C.CFUNCTYPE(C.c_bool, C.c_uint, C.c_void_p)(self._env)
        self._video_cb = C.CFUNCTYPE(None, C.c_void_p, C.c_uint, C.c_uint, C.c_size_t)(self._video)
        self._audio_cb = C.CFUNCTYPE(None, C.c_int16, C.c_int16)(self._audio_sample)
        self._batch_cb = C.CFUNCTYPE(C.c_size_t, C.POINTER(C.c_int16), C.c_size_t)(self._audio_batch)
        self._poll_cb = C.CFUNCTYPE(None)(lambda: None)
        self._state_cb = C.CFUNCTYPE(C.c_int16, C.c_uint, C.c_uint, C.c_uint, C.c_uint)(self._input_state)
        lib = self.lib
        lib.retro_set_environment(self._env_cb)
        lib.retro_set_video_refresh(self._video_cb)
        lib.retro_set_audio_sample(self._audio_cb)
        lib.retro_set_audio_sample_batch(self._batch_cb)
        lib.retro_set_input_poll(self._poll_cb)
        lib.retro_set_input_state(self._state_cb)

    def start(self) -> dict:
        self.lib.retro_init()
        rom = open(self.rom_path, "rb").read()
        self._rom_buffer = C.create_string_buffer(rom)
        info = GameInfo(self.rom_path.encode(),
                        C.cast(self._rom_buffer, C.c_void_p), len(rom), None)
        if not self.lib.retro_load_game(C.byref(info)):
            raise RuntimeError("libretro core could not load %s" % self.rom_path)
        av = SystemAVInfo()
        self.lib.retro_get_system_av_info(C.byref(av))
        fps = float(av.timing.fps) or 60.0
        self.lib.retro_set_controller_port_device(0, RETRO_DEVICE_JOYPAD)
        self._serialize_size = int(self.lib.retro_serialize_size())
        self.audio_rate = float(av.timing.sample_rate)
        return {
            "ok": True,
            "audio_rate": self.audio_rate,
            "width": int(av.geometry.base_width),
            "height": int(av.geometry.base_height),
            "max_width": int(av.geometry.max_width),
            "max_height": int(av.geometry.max_height),
            "fps": fps,
            "format": self._frame_format,
            "rewind": self._serialize_size > 0,
            "core": os.path.basename(self.core_path),
            "rom": os.path.basename(self.rom_path),
        }

    def run_frame(self):
        self.lib.retro_run()
        audio = self.take_audio()
        if not self._frame_payload:
            return b"", audio
        packet = b"LRF1" + struct.pack("<IIIII", self.width, self.height,
                                       self._frame_format, self.frame_index,
                                       len(self._frame_payload)) + self._frame_payload
        return packet, audio

    def serialize(self) -> bytes:
        if self._serialize_size <= 0:
            return b""
        buf = C.create_string_buffer(self._serialize_size)
        if not self.lib.retro_serialize(buf, self._serialize_size):
            return b""
        return bytes(buf.raw[: self._serialize_size])

    def unserialize(self, state: bytes) -> bool:
        if not state:
            return False
        buf = C.create_string_buffer(state)
        return bool(self.lib.retro_unserialize(buf, len(state)))

    def close(self) -> None:
        try:
            self.lib.retro_unload_game()
        except Exception:
            pass
        try:
            self.lib.retro_deinit()
        except Exception:
            pass


def connect(port: int) -> socket.socket:
    deadline = time.time() + 8.0
    last = None
    while time.time() < deadline:
        try:
            sock = socket.create_connection(("127.0.0.1", port), timeout=1.0)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            return sock
        except OSError as exc:
            last = exc
            time.sleep(0.05)
    raise RuntimeError("could not connect to the editor: %s" % last)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", required=True)
    parser.add_argument("--rom", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--platform", choices=["snes", "megadrive"], default="snes")
    parser.add_argument("--system", default="")
    parser.add_argument("--save", default="")
    args = parser.parse_args()

    system_dir = args.system or os.path.join(os.path.dirname(args.core), "system")
    save_dir = args.save or os.path.join(os.path.expanduser("~"), ".local", "share",
                                         "godot-retro-engine", "libretro-saves")
    os.makedirs(system_dir, exist_ok=True)
    os.makedirs(save_dir, exist_ok=True)

    sock = None
    host = None
    try:
        sock = connect(args.port)
        host = LibretroHost(args.core, args.rom, args.platform, system_dir, save_dir)
        hello = host.start()
        sock.sendall((json.dumps(hello) + "\n").encode("utf-8"))
        sock.setblocking(False)
    except Exception as exc:
        payload = {"ok": False, "error": str(exc)}
        try:
            if sock is None:
                sock = connect(args.port)
            sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))
        except Exception:
            print(json.dumps(payload), file=sys.stderr)
        if host is not None:
            host.close()
        return

    paused = False
    speed = 1.0
    out_buf = bytearray()
    cmd_buf = b""
    history: collections.deque = collections.deque()
    history_bytes = 0
    max_history_bytes = 96 * 1024 * 1024
    frames_since_pause = 0
    tap_left = 0
    frame_interval = 1.0 / max(1.0, float(hello["fps"]))
    next_time = time.perf_counter()
    quitting = False

    def queue(packet: bytes) -> None:
        nonlocal out_buf
        if not packet:
            return
        if len(out_buf) > 4 * 1024 * 1024:
            return  # editor is behind; drop the new frame, not a partial one
        out_buf.extend(packet)

    def flush() -> None:
        nonlocal out_buf
        while out_buf:
            try:
                sent = sock.send(out_buf)
            except BlockingIOError:
                return
            except OSError:
                out_buf = bytearray()
                return
            if sent <= 0:
                return
            del out_buf[:sent]

    def remember(packet: bytes) -> None:
        nonlocal history_bytes
        if not packet or host._serialize_size <= 0:
            return
        state = host.serialize()
        if not state:
            return
        entry = (host.frame_index, state, packet)
        history.append(entry)
        history_bytes += len(state) + len(packet)
        while history and history_bytes > max_history_bytes:
            old = history.popleft()
            history_bytes -= len(old[1]) + len(old[2])

    def run_one(remember_frame: bool = True) -> None:
        nonlocal frames_since_pause
        packet, audio = host.run_frame()
        queue(packet)
        if audio:
            queue(b"AUD0" + struct.pack("<III", int(host.audio_rate),
                                        len(audio) // 4, len(audio)) + audio)
        if remember_frame:
            remember(packet)
        frames_since_pause += 1

    def handle(line: str) -> None:
        nonlocal paused, speed, frame_interval, quitting, tap_left, history_bytes
        parts = line.strip().split()
        if not parts:
            return
        cmd = parts[0].lower()
        if cmd == "run":
            paused = False
            frames_since_pause = 0
            next_time_reset()
        elif cmd == "pause":
            paused = True
        elif cmd == "step":
            count = max(1, int(parts[1])) if len(parts) > 1 else 1
            for _ in range(count):
                run_one()
        elif cmd == "speed":
            speed = max(0.05, min(4.0, float(parts[1]))) if len(parts) > 1 else 1.0
            frame_interval = 1.0 / max(1.0, float(hello["fps"]) * speed)
            next_time_reset()
        elif cmd == "press":
            if len(parts) > 1:
                host.buttons |= int(parts[1], 0) & 0xFFFF
        elif cmd == "release":
            if len(parts) > 1:
                host.buttons &= ~(int(parts[1], 0) & 0xFFFF)
        elif cmd == "tap":
            mask = int(parts[1], 0) & 0xFFFF if len(parts) > 1 else 0
            count = max(1, int(parts[2])) if len(parts) > 2 else 4
            host.buttons |= mask
            for _ in range(count):
                run_one()
            host.buttons &= ~mask
        elif cmd == "audio":
            host.audio_enabled = len(parts) > 1 and parts[1].strip() not in ("0", "off", "false")
            host._audio.clear()
        elif cmd == "rewind":
            count = max(1, int(parts[1])) if len(parts) > 1 else 1
            idx = len(history) - 1 - count
            if idx < 0:
                idx = 0
            if history:
                entry = history[idx]
                host.unserialize(entry[1])
                host.frame_index = entry[0]
                queue(entry[2])
                while len(history) > idx + 1:
                    old = history.pop()
                    history_bytes -= len(old[1]) + len(old[2])
                paused = True
                host.buttons = 0
        elif cmd == "reset":
            host.lib.retro_reset()
            history.clear()
            history_bytes = 0
            paused = False
            frames_since_pause = 0
            next_time_reset()
        elif cmd == "quit":
            quitting = True

    def next_time_reset() -> None:
        nonlocal next_time
        next_time = time.perf_counter()

    try:
        while not quitting:
            # Commands from the editor.
            try:
                chunk = sock.recv(4096)
                if chunk == b"":
                    break
                cmd_buf += chunk
                while b"\n" in cmd_buf:
                    line, cmd_buf = cmd_buf.split(b"\n", 1)
                    handle(line.decode("utf-8", "replace"))
            except BlockingIOError:
                pass
            except OSError:
                break

            if not paused:
                run_one()
                if tap_left > 0:
                    tap_left -= 1
                    if tap_left == 0:
                        host.buttons = 0
                now = time.perf_counter()
                next_time += frame_interval
                if next_time > now:
                    time.sleep(min(0.02, next_time - now))
                else:
                    next_time = now
            else:
                time.sleep(0.002)
            flush()
    finally:
        try:
            sock.close()
        except Exception:
            pass
        host.close()


if __name__ == "__main__":
    main()
