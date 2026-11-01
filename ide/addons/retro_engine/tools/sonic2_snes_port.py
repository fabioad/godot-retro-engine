#!/usr/bin/env python3
"""Prototype generator: Sonic 2 (Mega Drive) -> SNES playable EHZ Act 1 slice.

Reads the Sonic 2 disassembly data and writes a PVSnesLib C project with:
  - original level tiles/map/palette
  - original 16x16 collision index + vertical/horizontal heightmaps
  - Sonic 2 ground/air physics subset
  - Sonic sprite frames (idle/walk/run/roll) as SNES OBJs
This is a development prototype; the engine integration comes after it runs.
"""
import json
import math
import os
import re
import struct
import subprocess
import sys
from PIL import Image

try:
    from sonic2_smps import build_ehz_module
except Exception:
    build_ehz_module = None

ROOT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else "/run/media/fabio/Dados/Fabio/sgdk-test-projects/s2disasm"
OUT = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("-") else "/tmp/opencode/sonic_port"
DEMO = "--demo" in sys.argv

# Playable slice: 64x64 tiles = 512x512 px, starting at world (0, 512).
SLICE_X = 0
SLICE_Y = 0
SLICE_W = 1376
SLICE_H = 128
CHUNKS_X = 8
CHUNKS_Y = 4


# ---------------------------------------------------------------- Kosinski ---
def kosinski(data):
    out = bytearray()
    ip = 0
    bits = 15
    field = data[ip] | (data[ip + 1] << 8)
    ip = 2

    def getbit():
        nonlocal ip, bits, field
        bit = field & 1
        field >>= 1
        bits -= 1
        if bits < 0:
            field = data[ip] | (data[ip + 1] << 8)
            ip += 2
            bits = 15
        return bit

    while True:
        if getbit():
            out.append(data[ip])
            ip += 1
            continue
        if getbit():
            low = data[ip]
            high = data[ip + 1]
            ip += 2
            off = (((0xFF00 | high) << 5) & 0xFF00) | low
            if off & 0x8000:
                off -= 0x10000
            high &= 7
            if high:
                count = high + 1
            else:
                buf = data[ip]
                ip += 1
                if buf == 1:
                    continue
                if buf == 0:
                    break
                count = buf
        else:
            count = ((getbit() << 1) | getbit()) + 1
            buf = data[ip]
            ip += 1
            off = 0xFF00 | buf
            if off & 0x8000:
                off -= 0x10000
        while count >= 0:
            out.append(out[len(out) + off])
            count -= 1
    return bytes(out)


def read(path):
    with open(path, "rb") as f:
        return f.read()


# ---------------------------------------------------------------- Nemesis ---
def nemesis_decode(data):
    """Decode Sonic 2's Nemesis art to 8x8 palette-index tiles.

    The Mega Drive decompressor packs two 4bpp pixels per byte, so the
    row accumulator is nibble-packed; XOR art is applied row to row across
    the whole stream (the previous row carries over tile boundaries).
    """
    ip = 2
    header = (data[0] << 8) | data[1]
    xor_mode = bool(header & 0x8000)
    ntiles = header & 0x7FFF
    table = [0] * 256
    base = data[ip]
    ip += 1
    while base != 0xFF:
        while True:
            b = data[ip]
            ip += 1
            if b >= 0x80:
                base = b
                break
            length = b & 0xF
            repeat = (b >> 4) & 7
            code = data[ip]
            ip += 1
            entry = (length << 8) | (repeat << 4) | (base & 0xF)
            if length == 8:
                table[code] = entry
            else:
                shift = 8 - length
                idx = code << shift
                for k in range(1 << shift):
                    table[idx + k] = entry
    pos = ip
    buf = (data[pos] << 8) | data[pos + 1]
    pos += 2
    cnt = 16
    out = []
    total = ntiles * 64
    while len(out) < total:
        peek = (buf >> (cnt - 8)) & 0xFF
        if peek >= 0xFC:
            cnt -= 6
            if cnt < 9:
                buf = ((buf << 8) | (data[pos] if pos < len(data) else 0)) & 0xFFFF
                pos += 1
                cnt += 8
            val = (buf >> (cnt - 7)) & 0x7F
            cnt -= 7
            if cnt < 9:
                buf = ((buf << 8) | (data[pos] if pos < len(data) else 0)) & 0xFFFF
                pos += 1
                cnt += 8
            pix = val & 0xF
            repeat = (val >> 4) & 7
            out.extend([pix] * (repeat + 1))
        else:
            e = table[peek]
            length = (e >> 8) & 0xFF
            repeat = (e >> 4) & 0xF
            pix = e & 0xF
            cnt -= length
            if cnt < 9:
                buf = ((buf << 8) | (data[pos] if pos < len(data) else 0)) & 0xFFFF
                pos += 1
                cnt += 8
            out.extend([pix] * (repeat + 1))
    out = out[:total]
    if xor_mode:
        prev = [0] * 8
        for t in range(ntiles):
            for r in range(8):
                row = out[t * 64 + r * 8: t * 64 + r * 8 + 8]
                row = [a ^ b for a, b in zip(row, prev)]
                out[t * 64 + r * 8: t * 64 + r * 8 + 8] = row
                prev = row
    return [[[out[t * 64 + y * 8 + x] for x in range(8)] for y in range(8)]
            for t in range(ntiles)]


def snes_tile_8x8(block):
    out = bytearray(32)
    for y in range(8):
        for x in range(8):
            idx = block[y][x] & 15
            for p in range(4):
                pair = p // 2
                off = pair * 16 + y * 2 + (p % 2)
                out[off] |= ((idx >> p) & 1) << (7 - x)
    return bytes(out)


# ---------------------------------------------------------------- Level data ---
layout = kosinski(read(f"{ROOT}/level/layout/EHZ_1.kos"))
chunks = kosinski(read(f"{ROOT}/mappings/128x128/EHZ_HTZ.kos"))
blocks = kosinski(read(f"{ROOT}/mappings/16x16/EHZ.kos"))
tiles = kosinski(read(f"{ROOT}/art/kosinski/EHZ_HTZ.kos"))
pal_md = read(f"{ROOT}/art/palettes/EHZ.bin")
base_md = read(f"{ROOT}/art/palettes/SonicAndTails.bin")

colp = kosinski(read(f"{ROOT}/collision/EHZ and HTZ primary 16x16 collision index.kos"))
cols = kosinski(read(f"{ROOT}/collision/EHZ and HTZ secondary 16x16 collision index.kos"))
colv = read(f"{ROOT}/collision/Collision array - Vertical.bin")
colh = read(f"{ROOT}/collision/Collision array - Horizontal.bin")
curve = read(f"{ROOT}/collision/Curve and resistance mapping.bin")
sine_raw = read(f"{ROOT}/misc/sinewave.bin")

TILE_COUNT = len(tiles) // 32

# MD palette word -> RGB
def md_color(word):
    r = (word >> 1) & 7
    g = (word >> 5) & 7
    b = (word >> 9) & 7
    return ((r << 5) | (r << 2) | (r >> 1),
            (g << 5) | (g << 2) | (g >> 1),
            (b << 5) | (b << 2) | (b >> 1))


def md_palette(data, count):
    out = []
    for i in range(min(count, len(data) // 2)):
        w = (data[i * 2] << 8) | data[i * 2 + 1]
        out.append(md_color(w))
    while len(out) < count:
        out.append((0, 0, 0))
    return out


level_pal = md_palette(pal_md, 48)
sprite_pal = md_palette(base_md, 16)
# Palette line 0 = backdrop/sprite palette: use the level sky for index 0.
palette = [(0, 0, 0)] * 64
for i in range(16):
    palette[i] = sprite_pal[i]
palette[0] = level_pal[0]
for i in range(48):
    palette[16 + i] = level_pal[i]


def snes_pal_bytes(colors):
    out = bytearray()
    for (r, g, b) in colors:
        r5 = r >> 3
        g5 = g >> 3
        b5 = b >> 3
        w = r5 | (g5 << 5) | (b5 << 10)
        out += struct.pack("<H", w)
    return bytes(out)


def block_word(bid, i):
    o = (bid * 4 + i) * 2
    return (blocks[o] << 8) | blocks[o + 1]


def tile_at(tx, ty):
    """Return (block tile word, palette, hflip, vflip, priority) for a tile."""
    cx, cy = tx // 16, ty // 16
    if cx < 0 or cy < 0 or cx >= 128 or cy >= 16:
        return 0, 0, 0, 0, 0
    chunk = layout[cy * 0x100 + cx]
    bx = (tx % 16) // 2
    by = (ty % 16) // 2
    o = (chunk * 64 + by * 8 + bx) * 2
    cw = (chunks[o] << 8) | chunks[o + 1]
    bid = cw & 0x3FF
    fx = (cw >> 10) & 1
    fy = (cw >> 11) & 1
    qx = (tx & 1) ^ fx
    qy = (ty & 1) ^ fy
    if bid * 8 + 8 > len(blocks):
        return 0, 0, 0, 0, 0
    w = block_word(bid, qy * 2 + qx)
    return (w & 0x7FF, (w >> 13) & 3, ((w >> 11) & 1) ^ fx,
            ((w >> 12) & 1) ^ fy, (w >> 15) & 1)


# Visual map for the slice, remapping used tiles.
used = {}
map_words = []
for ty in range(SLICE_H):
    for tx in range(SLICE_W):
        tile, pal, hf, vf, pri = tile_at(SLICE_X + tx, SLICE_Y // 8 + ty)
        if tile not in used:
            used[tile] = len(used)
        remapped = used[tile]
        word = (remapped & 0x3FF) | ((pal & 7) << 10) | ((pri & 1) << 13) | ((hf & 1) << 14) | ((vf & 1) << 15)
        map_words.append(word)

used_tiles = sorted(used.keys(), key=lambda t: used[t])
remap = {t: i for i, t in enumerate(used_tiles)}
# rebuild map with the actual remap (used[] was insertion order, not sorted)
map_words = []
for ty in range(SLICE_H):
    for tx in range(SLICE_W):
        tile, pal, hf, vf, pri = tile_at(SLICE_X + tx, SLICE_Y // 8 + ty)
        remapped = remap.get(tile, 0)
        word = (remapped & 0x3FF) | ((pal & 7) << 10) | ((pri & 1) << 13) | ((hf & 1) << 14) | ((vf & 1) << 15)
        map_words.append(word)

# BG page grid: 4x2 pages of 32x32 tiles (one 64x64 window = 2x2 pages).
PAGE_W = 32
PAGE_H = 32
PAGES_X = (SLICE_W + PAGE_W - 1) // PAGE_W
PAGES_Y = (SLICE_H + PAGE_H - 1) // PAGE_H
bg_pages = bytearray()
for py in range(PAGES_Y):
    for px in range(PAGES_X):
        for row in range(PAGE_H):
            for col in range(PAGE_W):
                tx = px * PAGE_W + col
                ty = py * PAGE_H + row
                word = map_words[ty * SLICE_W + tx] if tx < SLICE_W and ty < SLICE_H else 0
                bg_pages += struct.pack("<H", word)
bg_pages_bytes = bytes(bg_pages)
page_groups = [bg_pages_bytes[i * 16384:(i + 1) * 16384] for i in range((len(bg_pages_bytes) + 16383) // 16384)]


# SNES 4bpp tiles, packed MD nibbles -> SNES planes.
def md_tile_to_snes(data, tile):
    out = bytearray(32)
    for y in range(8):
        for x in range(8):
            b = data[tile * 32 + y * 4 + (x // 2)]
            idx = (b >> (0 if (x & 1) else 4)) & 15
            for p in range(4):
                pair = p // 2
                off = pair * 16 + y * 2 + (p % 2)
                bit = (idx >> p) & 1
                out[off] |= bit << (7 - x)
    return bytes(out)


bg_tiles = b"".join(md_tile_to_snes(tiles, t) for t in used_tiles)


# Full chunk map (256 chunks x 64 words) split into two 16 KiB halves so the
# C code can select 16-bit arrays without a 32 KiB section.
chunk_lo = chunks[:16384]
chunk_hi = chunks[16384:32768]

# Sine table (big-endian words in the source file).
sine = [struct.unpack(">h", sine_raw[i * 2:i * 2 + 2])[0] for i in range(256)]


# ---------------------------------------------------------------- Sprites ---
proj = json.load(open(f"{ROOT}/.retro/project.json"))
res = [r for r in proj["resources"] if r.get("id") == "sonic2_common_sonic"][0]
frames_meta = res["frames"]
sheet = Image.open(f"{ROOT}/.retro/generated/sprites/common_sonic.png")
if sheet.mode != "P":
    sheet = sheet.convert("P", palette=Image.ADAPTIVE, colors=16)
sprite_palette = sheet.getpalette()[:48]
# index 0 is transparent; keep the original colours for the rest
sprite_colors = [(sprite_palette[i * 3], sprite_palette[i * 3 + 1], sprite_palette[i * 3 + 2]) for i in range(16)]

# Animation frame ids from SonAni_* in s2.asm.
ANIMS = {
    "idle": [1],
    "walk": [0x0F, 0x10, 0x11, 0x12, 0x13, 0x14],
    "run": [0x2D, 0x2E, 0x2F, 0x30],
    "roll": [0x3D, 0x3E, 0x3F, 0x40, 0x41],
    "hurt": [0x4E],
    "death": [0x5C],
}
# Collect unique frames and build 16x16 pieces with global dedup.
frame_ids = []
anim_indices = {}
for name, ids in ANIMS.items():
    anim_indices[name] = []
    for fid in ids:
        if fid not in frame_ids:
            frame_ids.append(fid)
        anim_indices[name].append(frame_ids.index(fid))

pieces = []          # list of 16x16 index blocks (tuple of 256 ints)
piece_map = {}
frame_defs = []      # (w, h, [(dx,dy,piece_idx)])
for fid in frame_ids:
    rect = frames_meta[fid]["rect"]
    rx, ry, rw, rh = [int(v) for v in rect]
    crop = sheet.crop((rx, ry, rx + rw, ry + rh))
    pw = (rw + 15) // 16
    ph = (rh + 15) // 16
    entries = []
    for py in range(ph):
        for px in range(pw):
            block = []
            for y in range(16):
                for x in range(16):
                    sx, sy = px * 16 + x, py * 16 + y
                    block.append(crop.getpixel((sx, sy)) if sx < rw and sy < rh else 0)
            key = bytes(block)
            if key not in piece_map:
                piece_map[key] = len(pieces)
                pieces.append(block)
            entries.append((px * 16, py * 16, piece_map[key]))
    frame_defs.append((rw, rh, entries))

# OBJ tiles: each 16x16 piece = 4 consecutive 8x8 SNES 4bpp tiles.
def snes_tile_from_indices(block, ox, oy):
    out = bytearray(32)
    for y in range(8):
        for x in range(8):
            idx = block[(oy + y) * 16 + (ox + x)] & 15
            for p in range(4):
                pair = p // 2
                off = pair * 16 + y * 2 + (p % 2)
                out[off] |= ((idx >> p) & 1) << (7 - x)
    return bytes(out)

def piece_offset(p):
    # SNES 16x16 OBJ tiles: n, n+1 (top row), n+16, n+17 (bottom row).
    return (p // 8) * 32 + (p % 8) * 2

tile_rows = (len(pieces) + 7) // 8
obj_tiles = bytearray(tile_rows * 32 * 32)
for p, block in enumerate(pieces):
    base = piece_offset(p)
    for tile_idx, ox, oy in ((base, 0, 0), (base + 1, 8, 0), (base + 16, 0, 8), (base + 17, 8, 8)):
        off = tile_idx * 32
        obj_tiles[off:off + 32] = snes_tile_from_indices(block, ox, oy)

MAX_PIECES = max(len(f[2]) for f in frame_defs)

# ---------------------------------------------------------------- Rings ---
ring_proj = json.load(open(f"{ROOT}/.retro/project.json"))
ring_res = [r for r in ring_proj["resources"] if r.get("id") == "sonic2_common_ring"][0]
ring_meta = ring_res["frames"]
ring_sheet = Image.open(f"{ROOT}/.retro/generated/sprites/common_ring.png")
if ring_sheet.mode != "P":
    ring_sheet = ring_sheet.convert("P", palette=Image.ADAPTIVE, colors=16)
ring_palette = ring_sheet.getpalette()[:48]
ring_colors = [(ring_palette[i * 3], ring_palette[i * 3 + 1], ring_palette[i * 3 + 2]) for i in range(16)]
RING_FRAMES = 4
ring_pieces = []
for fid in range(RING_FRAMES):
    rect = ring_meta[fid]["rect"]
    rx, ry, rw, rh = [int(v) for v in rect]
    crop = ring_sheet.crop((rx, ry, rx + rw, ry + rh))
    block = []
    for y in range(16):
        for x in range(16):
            block.append(crop.getpixel((x, y)) if x < rw and y < rh else 0)
    ring_pieces.append(block)

ring_tiles = bytearray()
for block in ring_pieces:
    # 4 frames, 16x16 each; 2-tile top row + 16-tile row stride
    pass

# Same 16x16 OBJ layout as Sonic: n,n+1 / n+16,n+17 per frame.
ring_tile_rows = 1
ring_tiles = bytearray(32 * 32)  # 32 tiles: 4 frames in one 16-tile row x2
for p, block in enumerate(ring_pieces):
    base = piece_offset(p)
    for tile_idx, ox, oy in ((base, 0, 0), (base + 1, 8, 0), (base + 16, 0, 8), (base + 17, 8, 8)):
        off = tile_idx * 32
        ring_tiles[off:off + 32] = snes_tile_from_indices(block, ox, oy)

# Expand the compressed row/column ring list.
ring_raw = read(f"{ROOT}/level/rings/EHZ_1.bin")
ring_positions = []
ri = 0
while ri + 1 < len(ring_raw):
    rx = struct.unpack(">H", ring_raw[ri:ri + 2])[0]; ri += 2
    if rx & 0x8000:
        break
    if ri + 1 >= len(ring_raw):
        break
    rw = struct.unpack(">H", ring_raw[ri:ri + 2])[0]; ri += 2
    rcount = ((rw >> 12) & 7) + 1
    ry = rw & 0x0FFF
    if rw & 0x8000:
        for k in range(rcount):
            ring_positions.append((rx, ry + k * 0x18))
    else:
        for k in range(rcount):
            ring_positions.append((rx + k * 0x18, ry))
ring_flat = []
for rx, ry in ring_positions:
    ring_flat.append(rx)
    ring_flat.append(ry)

# ---------------------------------------------------------------- HUD font ---
FONT = {
 '0': ["01110","10001","10011","10101","11001","10001","01110"],
 '1': ["00100","01100","00100","00100","00100","00100","01110"],
 '2': ["01110","10001","00001","00010","00100","01000","11111"],
 '3': ["11111","00010","00100","00010","00001","10001","01110"],
 '4': ["00010","00110","01010","10010","11111","00010","00010"],
 '5': ["11111","10000","11110","00001","00001","10001","01110"],
 '6': ["00110","01000","10000","11110","10001","10001","01110"],
 '7': ["11111","00001","00010","00100","01000","01000","01000"],
 '8': ["01110","10001","10001","01110","10001","10001","01110"],
 '9': ["01110","10001","10001","01111","00001","00010","01100"],
 'A': ["01110","10001","10001","11111","10001","10001","10001"],
 'B': ["11110","10001","10001","11110","10001","10001","11110"],
 'C': ["01110","10001","10000","10000","10000","10001","01110"],
 'D': ["11110","10001","10001","10001","10001","10001","11110"],
 'E': ["11111","10000","10000","11110","10000","10000","11111"],
 'F': ["11111","10000","10000","11110","10000","10000","10000"],
 'G': ["01110","10001","10000","10111","10001","10001","01111"],
 'H': ["10001","10001","10001","11111","10001","10001","10001"],
 'I': ["01110","00100","00100","00100","00100","00100","01110"],
 'J': ["00111","00010","00010","00010","00010","10010","01100"],
 'K': ["10001","10010","10100","11000","10100","10010","10001"],
 'L': ["10000","10000","10000","10000","10000","10000","11111"],
 'M': ["10001","11011","10101","10101","10001","10001","10001"],
 'N': ["10001","11001","10101","10011","10001","10001","10001"],
 'O': ["01110","10001","10001","10001","10001","10001","01110"],
 'P': ["11110","10001","10001","11110","10000","10000","10000"],
 'Q': ["01110","10001","10001","10001","10101","10010","01101"],
 'R': ["11110","10001","10001","11110","10100","10010","10001"],
 'S': ["01111","10000","10000","01110","00001","00001","11110"],
 'T': ["11111","00100","00100","00100","00100","00100","00100"],
 'U': ["10001","10001","10001","10001","10001","10001","01110"],
 'V': ["10001","10001","10001","10001","10001","01010","00100"],
 'W': ["10001","10001","10001","10101","10101","11011","10001"],
 'X': ["10001","10001","01010","00100","01010","10001","10001"],
 'Y': ["10001","10001","01010","00100","00100","00100","00100"],
 'Z': ["11111","00001","00010","00100","01000","10000","11111"],
 ':': ["00000","00100","00100","00000","00100","00100","00000"],
 '-': ["00000","00000","00000","11111","00000","00000","00000"],
 ' ': ["00000","00000","00000","00000","00000","00000","00000"],
}
HUD_CHARS = "0123456789ACEGIMNORSTV:- "

def font_tile(rows):
    out = bytearray(32)
    for y in range(8):
        for x in range(8):
            idx = 6 if (1 <= x <= 5 and y < 7 and rows[y][x - 1] == '1') else 0
            for p in range(4):
                pair = p // 2
                off = pair * 16 + y * 2 + (p % 2)
                out[off] |= ((idx >> p) & 1) << (7 - x)
    return bytes(out)

hud_tiles = b"".join(font_tile(FONT[c]) for c in HUD_CHARS)
hud_colors = [(0,0,0),(255,255,255),(255,255,0)] + [(0,0,0)] * 13


# --------------------------------------------------------------- Objects ---
# Interactive EHZ Act 1 objects: springs, monitors, star posts and the goal
# signpost.  Art and mappings are taken from the disassembly (Nemesis artwork
# plus the original sprite mappings), so they are the Mega Drive graphics.
OBJECT_ART = {
    "monitor": "/art/nemesis/Monitor and contents.nem",
    "starpost": "/art/nemesis/Star pole.nem",
    "signpost": "/art/nemesis/Signpost.nem",
    "spring_v": "/art/nemesis/Vertical spring.nem",
    "spring_h": "/art/nemesis/Horizontal spring.nem",
    "spring_d": "/art/nemesis/Diagonal spring.nem",
    "buzzer": "/art/nemesis/Buzzer enemy.nem",
    "masher": "/art/nemesis/EHZ Pirahna badnik.nem",
    "coconuts": "/art/nemesis/Coconuts badnik from EHZ.nem",
    "spikes": "/art/nemesis/Spikes.nem",
    "explosion": "/art/nemesis/Explosion.nem",
    "shield": "/art/nemesis/Shield.nem",
    "stars": "/art/nemesis/Invincibility stars.nem",
    "lives": "/art/nemesis/Sonic lives counter.nem",
    "bridge": "/art/nemesis/EHZ bridge.nem",
}
object_art = {}
for _name, _path in OBJECT_ART.items():
    object_art[_name] = nemesis_decode(read(ROOT + _path))


def _asm_table(label, end_label):
    text = read(ROOT + "/s2.asm").decode("utf-8", errors="ignore")
    start = text.index(label + ":")
    end = text.index(end_label, start)
    vals = []
    for m in re.finditer(r"dc\.b\s+([^\n;]+)", text[start:end]):
        for part in m.group(1).split(","):
            part = part.strip()
            if not part:
                continue
            if part.startswith("$"):
                vals.append(int(part[1:], 16))
            elif re.match(r"^-?\d+$", part):
                vals.append(int(part) & 0xFF)
    return vals


spiral_cos = _asm_table("Obj06_CosineTable", "Obj06_Cylinder")
spiral_flip = _asm_table("Obj06_FlipAngleTable", "Obj06_CosineTable")




def md_tile_indices(data, tile):
    out = []
    for y in range(8):
        row = []
        for x in range(8):
            b = data[tile * 32 + y * 4 + (x // 2)]
            row.append((b >> (0 if (x & 1) else 4)) & 15)
        out.append(row)
    return out


# EHZ platform sprites reuse the level art (palette line 2), not a separate
# Nemesis file.
object_art["levelart"] = [md_tile_indices(tiles, t) for t in range(len(tiles) // 32)]


def _map_num(text):
    text = text.strip()
    neg = text.startswith("-")
    text = text.lstrip("+-")
    value = int(text[1:], 16) if text.startswith("$") else int(text, 0)
    return -value if neg else value


def parse_mapping_frames(paths, table_label):
    text = "".join(read(p).decode("utf-8", errors="ignore") + "\n" for p in paths)
    lines = text.splitlines()
    frame_labels = None
    for i, line in enumerate(lines):
        if re.match(r"^%s:" % re.escape(table_label), line.strip()):
            entries = []
            for j in range(i + 1, len(lines)):
                m = re.match(r"\s*mappingsTableEntry\.w\s+(\w+)", lines[j])
                if m:
                    entries.append(m.group(1))
                    continue
                if entries:
                    break
            frame_labels = entries
            break
    if not frame_labels:
        raise SystemExit("mapping table %s not found" % table_label)
    blocks = {}
    current = None
    for line in lines:
        m = re.match(r"^(\w+):", line.strip())
        if m:
            current = m.group(1)
            blocks.setdefault(current, [])
            continue
        m = re.match(r"\s*spritePiece\s+([^;]+)", line)
        if m and current:
            a = [v.strip() for v in m.group(1).split(",")]
            blocks[current].append((_map_num(a[0]), _map_num(a[1]),
                                    int(a[2]), int(a[3]), _map_num(a[4]),
                                    int(a[5]) & 1, int(a[6]) & 1))
    frames = []
    for label in frame_labels:
        if label not in blocks:
            raise SystemExit("missing sprite frame " + label)
        frames.append(blocks[label])
    return frames


object_mappings = {
    "monitor": (["/mappings/sprite/obj26.asm"], "Map_obj26"),
    "starpost": (["/mappings/sprite/obj79_a.asm"], "Map_obj79_a"),
    "signpost": (["/mappings/sprite/obj0D_a.asm"], "Map_obj0D_a"),
    "spring_y": (["/s2.asm"], "Obj41_MapUnc_1901C"),
    "spring_r": (["/s2.asm"], "Obj41_MapUnc_19032"),
    "buzzer": (["/mappings/sprite/obj4B.asm"], "Map_obj4B"),
    "masher": (["/mappings/sprite/obj5C.asm"], "Map_obj5C"),
    "coconuts": (["/mappings/sprite/obj9D.asm"], "Map_obj9D"),
    "spikes": (["/mappings/sprite/obj36.asm"], "Map_obj36"),
    "explosion": (["/mappings/sprite/obj27.asm"], "Map_obj27"),
    "shield": (["/mappings/sprite/obj38.asm"], "Map_obj38"),
    "stars": (["/mappings/sprite/obj35.asm"], "Map_obj35"),
    "bridge": (["/mappings/sprite/obj11_b.asm"], "Map_obj11_b"),
    "platform": (["/mappings/sprite/obj18_a.asm"], "Map_obj18_a"),
}
object_mapping_frames = {}
for _name, (_paths, _label) in object_mappings.items():
    object_mapping_frames[_name] = parse_mapping_frames(
        [ROOT + p for p in _paths], _label)


# Tails follower art comes from the imported sprite sheet.  Five frames are
# enough for idle/walk/fly; they are added as 8x8 tiles to the BG2 atlas.
_tails_res = [r for r in proj["resources"] if r.get("id") == "sonic2_common_tails"][0]
_tails_sheet = Image.open(f"{ROOT}/.retro/generated/sprites/common_tails.png")
if _tails_sheet.mode != "P":
    _tails_sheet = _tails_sheet.convert("P", palette=Image.ADAPTIVE, colors=16)
TAILS_FRAME_IDS = [1, 0x10, 0x11, 0x5E, 0x5F]
object_art["tails"] = []
object_mapping_frames["tails"] = []
for _fid in TAILS_FRAME_IDS:
    _tx, _ty, _tw, _th = [int(v) for v in _tails_res["frames"][_fid]["rect"]]
    _crop = _tails_sheet.crop((_tx, _ty, _tx + _tw, _ty + _th))
    _cols = (_tw + 7) // 8
    _rows = (_th + 7) // 8
    _base_tile = len(object_art["tails"])
    for _yy in range(_rows):
        for _xx in range(_cols):
            _block = []
            for _y in range(8):
                for _x in range(8):
                    _sx = _xx * 8 + _x
                    _sy = _yy * 8 + _y
                    _block.append(_crop.getpixel((_sx, _sy))
                                  if _sx < _tw and _sy < _th else 0)
            object_art["tails"].append(
                [[_block[_y * 8 + _x] for _x in range(8)] for _y in range(8)])
    _pieces = []
    for _yy in range(_rows):
        for _xx in range(_cols):
            _pieces.append((_xx * 8 - _tw // 2, _yy * 8 - _th // 2, 1, 1,
                            _base_tile + _yy * _cols + _xx, 0, 0))
    object_mapping_frames["tails"].append(_pieces)

# Four original tumble/rotation poses used on the corkscrew.  The full 360
# frame set is too large for the 512-tile BG2 budget; four poses already give
# a readable rotating Sonic.
TUMBLE_FRAME_IDS = [0x5F, 0x63, 0x67]
object_art["tumble"] = []
object_mapping_frames["tumble"] = []
for _fid in TUMBLE_FRAME_IDS:
    _tx, _ty, _tw, _th = [int(v) for v in frames_meta[_fid]["rect"]]
    _crop = sheet.crop((_tx, _ty, _tx + _tw, _ty + _th))
    _cols = (_tw + 7) // 8
    _rows = (_th + 7) // 8
    _base_tile = len(object_art["tumble"])
    for _yy in range(_rows):
        for _xx in range(_cols):
            _block = []
            for _y in range(8):
                for _x in range(8):
                    _sx = _xx * 8 + _x
                    _sy = _yy * 8 + _y
                    _block.append(_crop.getpixel((_sx, _sy))
                                  if _sx < _tw and _sy < _th else 0)
            object_art["tumble"].append(
                [[_block[_y * 8 + _x] for _x in range(8)] for _y in range(8)])
    _pieces = []
    for _yy in range(_rows):
        for _xx in range(_cols):
            _pieces.append((_xx * 8 - _tw // 2, _yy * 8 - _th // 2, 1, 1,
                            _base_tile + _yy * _cols + _xx, 0, 0))
    object_mapping_frames["tumble"].append(_pieces)

# Monitor 1-up: monitor casing plus the original Sonic head from the lives
# counter art at the content position used by mapping frame 2.
object_art["monitor_1up"] = object_art["monitor"] + object_art["lives"][:4]
object_mapping_frames["mon_1up"] = [[
    (-8, -11, 2, 2, len(object_art["monitor"]), 0, 0, 0, 0)
] + object_mapping_frames["monitor"][0]]
object_mapping_frames["mon_1up"][0] = [
    (a[0], a[1], a[2], a[3], a[4], a[5], a[6])
    for a in object_mapping_frames["mon_1up"][0]
]

# Global frame order.  Composite frames list the topmost piece first in the
# mappings, so the draw order is reversed.
OBJECT_FRAME_DEFS = (
    [("monitor", i, "monitor") for i in range(12)] +
    [("starpost", i, "starpost") for i in range(2)] +
    [("signpost", i, "signpost") for i in range(6)] +
    [("spring_y", i, "spring_v") for i in (0, 1, 2)] +
    [("spring_y", i, "spring_h") for i in (3, 4, 5)] +
    [("spring_y", 6, "spring_v")] +
    [("spring_y", i, "spring_d") for i in (7, 8, 9, 10)] +
    [("spring_r", i, "spring_d") for i in (7, 8, 9, 10)] +
    [("buzzer", 0, "buzzer"), ("buzzer", 1, "buzzer")] +
    [("masher", 0, "masher"), ("masher", 1, "masher")] +
    [("coconuts", 0, "coconuts"), ("coconuts", 1, "coconuts")] +
    [("spikes", 0, "spikes"), ("spikes", 1, "spikes")] +
    [("buzzer", 5, "buzzer"), ("buzzer", 6, "buzzer")] +
    [("coconuts", 3, "coconuts")] +
    [("explosion", i, "explosion") for i in (1, 2, 3, 4)] +
    [("shield", i, "shield") for i in range(6)] +
    [("stars", i, "stars") for i in (1, 2, 3, 4)] +
    [("mon_1up", 0, "monitor_1up")] +
    [("bridge", 0, "bridge"), ("bridge", 1, "bridge")] +
    [("platform", 0, "levelart")] +
    [("tails", i, "tails") for i in range(5)] +
    [("tumble", i, "tumble") for i in range(3)]
)

object_atlas = []
object_atlas_map = {}
object_draw_dx = []
object_draw_dy = []
object_draw_tile = []
object_draw_flip = []
object_frame_start = []
object_frame_len = []


def object_tile_index(tile):
    key = bytes(v for row in tile for v in row)
    if key not in object_atlas_map:
        object_atlas_map[key] = len(object_atlas) + 1  # tile 0 is blank
        object_atlas.append(tile)
    return object_atlas_map[key]


for _setname, _frame_id, _artname in OBJECT_FRAME_DEFS:
    if (_setname == "monitor" and _frame_id in (1, 2, 3, 4, 9, 10)) or (_setname == "bridge" and _frame_id == 1):
        object_frame_start.append(len(object_draw_dx))
        object_frame_len.append(0)
        continue
    _start = len(object_draw_dx)
    _pieces = list(reversed(object_mapping_frames[_setname][_frame_id]))
    for (_x, _y, _w, _h, _tile, _hf, _vf) in _pieces:
        for _ty in range(_h):
            for _tx in range(_w):
                _idx = _tile + _tx * _h + _ty
                if _idx >= len(object_art[_artname]):
                    continue
                _t = object_art[_artname][_idx]
                if not any(any(row) for row in _t):
                    continue
                object_draw_dx.append(_x + _tx * 8)
                object_draw_dy.append(_y + _ty * 8)
                object_draw_tile.append(object_tile_index(_t))
                object_draw_flip.append((1 if _hf else 0) | (2 if _vf else 0))
    object_frame_start.append(_start)
    object_frame_len.append(len(object_draw_dx) - _start)

object_chr = b"\x00" * 32 + b"".join(snes_tile_8x8(t) for t in object_atlas)

# Level object list: x (word), y+flags (word), id, subtype.
OBJECT_KINDS = {
    13: 4,   # goal signpost
    17: 9,   # bridge
    6: 11,   # spiral / corkscrew
    24: 10,  # EHZ platform
    38: 1,   # monitor
    54: 5,   # spikes
    65: 2,   # spring
    75: 6,   # Buzzer
    92: 7,   # Masher
    121: 3,  # star post
    157: 8,  # Coconuts
}
object_inst_x = []
object_inst_y = []
object_inst_kind = []
object_inst_sub = []
object_inst_flags = []
_object_raw = read(f"{ROOT}/level/objects/EHZ_1.bin")
for _i in range(0, len(_object_raw) - 5, 6):
    _ox = struct.unpack(">H", _object_raw[_i:_i + 2])[0]
    _ow = struct.unpack(">H", _object_raw[_i + 2:_i + 4])[0]
    _oid = _object_raw[_i + 4]
    _osub = _object_raw[_i + 5]
    if _oid not in OBJECT_KINDS:
        continue
    _of = (_ow >> 12) & 0xF
    object_inst_x.append(_ox)
    object_inst_y.append(_ow & 0x0FFF)
    object_inst_kind.append(OBJECT_KINDS[_oid])
    object_inst_sub.append(_osub)
    object_inst_flags.append((( _of >> 1) & 1) | (((_of >> 2) & 1) << 1))
OBJ_COUNT = len(object_inst_x)
OBJ_FRAME = {
    "MON_BROKEN": 11,
    "STAR_IDLE": 12, "STAR_ACTIVE": 13,
    "SIGN_0": 14, "SIGN_1": 15, "SIGN_2": 16, "SIGN_3": 17,
    "SIGN_4": 18, "SIGN_5": 19,
    "SPR_UP": 20, "SPR_UP1": 21, "SPR_UP2": 22,
    "SPR_H": 23, "SPR_H1": 24, "SPR_H2": 25,
    "SPR_DOWN": 26,
    "SPR_DU": 27, "SPR_DU1": 28, "SPR_DU2": 29, "SPR_DD": 30,
    "SPR_RDU": 31, "SPR_RDU1": 32, "SPR_RDU2": 33, "SPR_RDD": 34,
    "BUZ_0": 35, "BUZ_1": 36,
    "MASH_0": 37, "MASH_1": 38,
    "COCO_0": 39, "COCO_1": 40,
    "SPIKE_0": 41, "SPIKE_1": 42,
    "BUZ_FIRE0": 43, "BUZ_FIRE1": 44, "COCO_FIRE": 45,
    "EXPL_1": 46, "EXPL_2": 47, "EXPL_3": 48, "EXPL_4": 49,
    "SHIELD_0": 50, "SHIELD_1": 51, "SHIELD_2": 52,
    "SHIELD_3": 53, "SHIELD_4": 54, "SHIELD_5": 55,
    "STAR_1": 56, "STAR_2": 57, "STAR_3": 58, "STAR_4": 59,
    "MON_1UP": 60, "BRIDGE_0": 61, "BRIDGE_1": 62, "PLATFORM": 63,
    "TAILS_IDLE": 64, "TAILS_WALK0": 65, "TAILS_WALK1": 66,
    "TAILS_FLY0": 67, "TAILS_FLY1": 68,
    "TUMBLE0": 69, "TUMBLE1": 70, "TUMBLE2": 71,
}


# ---------------------------------------------------------------- Audio ---
# SNES SFX use the PVSnesLib sound engine plus BRR samples.  The engine's
# audio tool synthesizes the WAV, and the SDK's snesbrr encodes it.  If either
# tool is unavailable the port still builds (SFX_ENABLED=0).
SFX_PARAMS = {
    "ring": {"waveform": "square", "frequency": 1318.0, "duration_ms": 100.0,
             "volume": 0.65, "duty": 0.5, "attack_ms": 1.0, "decay_ms": 25.0,
             "sustain": 0.55, "release_ms": 60.0, "pitch_slide": 0.0,
             "vibrato_hz": 0.0, "vibrato_depth": 0.0, "noise": 0.0,
             "bitcrush": 16},
    "spring": {"waveform": "square", "frequency": 420.0, "duration_ms": 150.0,
               "volume": 0.65, "duty": 0.5, "attack_ms": 1.0, "decay_ms": 40.0,
               "sustain": 0.6, "release_ms": 70.0, "pitch_slide": 12.0,
               "vibrato_hz": 0.0, "vibrato_depth": 0.0, "noise": 0.0,
               "bitcrush": 16},
    "hurt": {"waveform": "saw", "frequency": 520.0, "duration_ms": 170.0,
             "volume": 0.7, "duty": 0.5, "attack_ms": 1.0, "decay_ms": 45.0,
             "sustain": 0.5, "release_ms": 90.0, "pitch_slide": -18.0,
             "vibrato_hz": 18.0, "vibrato_depth": 0.7, "noise": 0.12,
             "bitcrush": 16},
    "jump": {"waveform": "square", "frequency": 330.0, "duration_ms": 90.0,
             "volume": 0.55, "duty": 0.25, "attack_ms": 1.0, "decay_ms": 20.0,
             "sustain": 0.5, "release_ms": 45.0, "pitch_slide": 9.0,
             "vibrato_hz": 0.0, "vibrato_depth": 0.0, "noise": 0.0,
             "bitcrush": 16},
    "monitor": {"waveform": "noise", "frequency": 240.0, "duration_ms": 120.0,
                "volume": 0.55, "duty": 0.5, "attack_ms": 1.0, "decay_ms": 30.0,
                "sustain": 0.4, "release_ms": 60.0, "pitch_slide": -6.0,
                "vibrato_hz": 0.0, "vibrato_depth": 0.0, "noise": 0.85,
                "bitcrush": 16},
    "signpost": {"waveform": "triangle", "frequency": 880.0, "duration_ms": 220.0,
                 "volume": 0.6, "duty": 0.5, "attack_ms": 2.0, "decay_ms": 60.0,
                 "sustain": 0.5, "release_ms": 90.0, "pitch_slide": 5.0,
                 "vibrato_hz": 0.0, "vibrato_depth": 0.0, "noise": 0.0,
                 "bitcrush": 16},
}
SFX_ORDER = ["ring", "spring", "hurt", "jump", "monitor", "signpost"]


def _find_audio_tool():
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(here, "retro_audio_tool.py"),
        os.path.join(here, "..", "ide", "addons", "retro_engine", "tools", "retro_audio_tool.py"),
        os.path.expanduser("~/.local/share/godot-retro-engine/ide/addons/retro_engine/tools/retro_audio_tool.py"),
    ]
    for c in candidates:
        if os.path.isfile(c):
            return os.path.abspath(c)
    return ""


def _find_snesbrr():
    root = os.environ.get("PVSNESLIB_HOME", "")
    candidates = []
    if root:
        candidates.append(os.path.join(root, "devkitsnes", "tools", "snesbrr"))
    candidates.append(os.path.expanduser(
        "~/.local/share/godot-retro-engine/sdks/snes/devkitsnes/tools/snesbrr"))
    for c in candidates:
        if os.path.isfile(c):
            return c
    return ""


def _build_sfx():
    tool = _find_audio_tool()
    snesbrr = _find_snesbrr()
    if not tool or not snesbrr:
        return {}
    out = os.path.join(OUT, "audio")
    os.makedirs(out, exist_ok=True)
    data = {}
    try:
        for name in SFX_ORDER:
            params_path = os.path.join(out, name + ".json")
            wave_path = os.path.join(out, name + ".wav")
            brr_path = os.path.join(out, name + ".brr")
            with open(params_path, "w", encoding="utf-8") as f:
                json.dump(SFX_PARAMS[name], f)
            subprocess.run([sys.executable, tool, "sfx", "--params", params_path,
                            "--out", wave_path], check=True, capture_output=True)
            subprocess.run([snesbrr, "-e", wave_path, brr_path], check=True,
                           capture_output=True)
            data[name] = read(brr_path)
    except Exception:
        return {}
    return data


sfx_data = _build_sfx()
SFX_ENABLED = bool(sfx_data)
music_bank = build_ehz_module(ROOT, os.path.join(OUT, "audio")) if build_ehz_module else None
MUSIC_ENABLED = bool(music_bank)

# ---------------------------------------------------------------- C output ---
def carray(name, data, typ="unsigned char"):
    out = f"const {typ} {name}[] = {{\n"
    for i, v in enumerate(data):
        out += str(int(v))
        out += ","
        if (i + 1) % 16 == 0:
            out += "\n"
    out += "\n};\n"
    return out


def cwords(name, data):
    out = f"const unsigned short {name}[] = {{\n"
    for i, v in enumerate(data):
        out += str(int(v) & 0xFFFF)
        out += ","
        if (i + 1) % 16 == 0:
            out += "\n"
    out += "\n};\n"
    return out


os.makedirs(f"{OUT}/src", exist_ok=True)

def blob(label, filename, data):
    with open(f"{OUT}/src/{filename}", "wb") as bf:
        bf.write(data)
    return label, filename

blobs = [
    blob("bg_tiles", "bg_tiles.bin", bg_tiles),
    blob("bg_pal", "bg_pal.bin", snes_pal_bytes(palette)),
    blob("chunk_lo", "chunk_lo.bin", chunk_lo),
    blob("chunk_hi", "chunk_hi.bin", chunk_hi),
    blob("col_index_p", "col_index_p.bin", colp),
    blob("col_index_s", "col_index_s.bin", cols),
    blob("col_vertical", "col_vertical.bin", colv),
    blob("col_horizontal", "col_horizontal.bin", colh),
    blob("col_curve", "col_curve.bin", curve),
    blob("sine_table", "sine_table.bin", b"".join(struct.pack("<H", w & 0xFFFF) for w in sine)),
    blob("sonic_tiles", "sonic_tiles.bin", obj_tiles + ring_tiles + hud_tiles),
    blob("sonic_pal", "sonic_pal.bin", snes_pal_bytes(sprite_colors) + snes_pal_bytes(ring_colors) + snes_pal_bytes(hud_colors)),
    blob("obj_chr", "obj_chr.bin", object_chr),
    blob("obj_pal", "obj_pal.bin", snes_pal_bytes(ring_colors)),
    blob("spiral_cos", "spiral_cos.bin", bytes(v & 0xFF for v in spiral_cos)),
    blob("spiral_flip", "spiral_flip.bin", bytes(v & 0xFF for v in spiral_flip)),
]
for i, group in enumerate(page_groups):
    blobs.append(blob("page%d" % i, "page%d.bin" % i, group))
for _name in SFX_ORDER:
    if _name in sfx_data:
        blobs.append(blob("sfx_" + _name, "sfx_%s.brr" % _name, sfx_data[_name]))
if MUSIC_ENABLED:
    with open(os.path.join(OUT, "src", "ehz_bank.bnk"), "wb") as _bank_file:
        _bank_file.write(music_bank)
asm = """.MEMORYMAP
  SLOTSIZE $8000
  DEFAULTSLOT 0
  SLOT 0 $8000
  SLOT 1 $0 $2000
  SLOT 2 $2000 $E000
  SLOT 3 $0 $10000
.ENDME
.ROMBANKMAP
  BANKSTOTAL 16
  BANKSIZE $8000
  BANKS 16
.ENDRO

"""
for label, filename in blobs:
    asm += ".section \".rodata_%s\" superfree\n" % label
    asm += "%s:\n.incbin \"src/%s\"\n.export %s\n.ends\n\n" % (label, filename, label)
if MUSIC_ENABLED:
    asm += ".BANK 15\n.SECTION \"SOUNDBANK\"\nsoundbank:\n.incbin \"src/ehz_bank.bnk\"\n.export soundbank\n.ENDS\n"
with open(f"{OUT}/src/assets_data.asm", "w") as f:
    f.write(asm)

data_c = "#include \"assets.h\"\n\n"
# frame definitions
data_c += "const unsigned char frame_w[] = {" + ",".join(str(f[0]) for f in frame_defs) + "};\n"
data_c += "const unsigned char frame_h[] = {" + ",".join(str(f[1]) for f in frame_defs) + "};\n"
data_c += "const unsigned char frame_count[] = {" + ",".join(str(len(f[2])) for f in frame_defs) + "};\n"
data_c += "const short frame_pieces[][3] = {\n"
for w, h, entries in frame_defs:
    for dx, dy, p in entries:
        data_c += "{%d,%d,%d},\n" % (dx, dy, piece_offset(p))
data_c += "};\n"
for name, ids in anim_indices.items():
    data_c += "const unsigned char anim_%s[] = {%s};\n" % (name, ",".join(str(i) for i in ids))
data_c += carray("layout", layout)
data_c += carray("blocks", blocks)
data_c += cwords("ring_pos", ring_flat)
data_c += cwords("obj_draw_dx", [v & 0xFFFF for v in object_draw_dx])
data_c += cwords("obj_draw_dy", [v & 0xFFFF for v in object_draw_dy])
data_c += cwords("obj_draw_tile", object_draw_tile)
data_c += carray("obj_draw_flip", object_draw_flip)
data_c += cwords("obj_frame_start", object_frame_start)
data_c += carray("obj_frame_len", object_frame_len)
data_c += cwords("obj_x", object_inst_x)
data_c += cwords("obj_y", object_inst_y)
data_c += carray("obj_kind", object_inst_kind)
data_c += carray("obj_sub", object_inst_sub)
data_c += carray("obj_flags", object_inst_flags)

with open(f"{OUT}/src/assets.c", "w") as f:
    f.write(data_c)

# ---------------------------------------------------------------- C code ---
assets_h = """#ifndef ASSETS_H
#define ASSETS_H
#define SLICE_W %d
#define SLICE_H 128
#define SLICE_X 0
#define SLICE_Y 0
#define PAGES_X %d
#define PAGES_Y 4
#define TILE_COUNT %d
#define PIECE_COUNT %d
#define FRAME_COUNT %d
#define MAX_PIECES %d
#define PAGE_GROUP_COUNT %d
extern const unsigned char bg_tiles[];
extern const unsigned char bg_pal[];
extern const unsigned char chunk_lo[];
extern const unsigned char chunk_hi[];
extern const unsigned char layout[4096];
extern const unsigned char blocks[%d];
#define BG_TILES_SIZE %d
#define BG_PAL_SIZE %d
#define SONIC_TILES_SIZE %d
#define SONIC_PAL_SIZE 32

extern const unsigned char col_index_p[];
extern const unsigned char col_index_s[];
extern const unsigned char col_vertical[];
extern const unsigned char col_horizontal[];
extern const unsigned char col_curve[];
extern const unsigned short sine_table[];
extern const unsigned char sonic_tiles[];
extern const unsigned char sonic_pal[];
extern const unsigned char frame_w[];
extern const unsigned char frame_h[];
extern const unsigned char frame_count[];
extern const short frame_pieces[][3];
""" % (SLICE_W, PAGES_X, len(used_tiles), len(pieces), len(frame_defs), MAX_PIECES,
       len(page_groups), len(blocks), len(bg_tiles), len(snes_pal_bytes(palette)),
       len(obj_tiles))
for i in range(len(page_groups)):
    assets_h += "extern const unsigned char page%d[];\n" % i
assets_h += "#define RING_COUNT %d\n#define RING_FRAMES %d\n" % (len(ring_positions), RING_FRAMES)
assets_h += ""
assets_h += "#define HUD_TILES_SIZE %d\n#define HUD_TILE_BASE %d\n" % (len(hud_tiles), len(obj_tiles) // 32 + 32)
assets_h += "extern const unsigned short ring_pos[];\n"
assets_h += "#define RING_TILES_SIZE %d\n#define RING_BASE_TILE %d\n" % (len(ring_tiles), len(obj_tiles) // 32)
assets_h += "#define OBJ_COUNT %d\n#define OBJ_CHR_SIZE %d\n" % (OBJ_COUNT, len(object_chr))
assets_h += "#define OBJ_BG_MAP 0x3800\n#define OBJ_BG_CHR 0x4000\n"
for name, index in OBJ_FRAME.items():
    assets_h += "#define OF_%s %d\n" % (name, index)
assets_h += "extern const unsigned char obj_chr[];\nextern const unsigned char obj_pal[];\n"
assets_h += "extern const unsigned short obj_draw_dx[];\nextern const unsigned short obj_draw_dy[];\n"
assets_h += "extern const unsigned short obj_draw_tile[];\nextern const unsigned char obj_draw_flip[];\n"
assets_h += "extern const unsigned short obj_frame_start[];\nextern const unsigned char obj_frame_len[];\n"
assets_h += "extern const unsigned short obj_x[];\nextern const unsigned short obj_y[];\n"
assets_h += "extern const unsigned char obj_kind[];\nextern const unsigned char obj_sub[];\n"
assets_h += "extern const unsigned char obj_flags[];\n"
assets_h += "extern const unsigned char spiral_cos[%d];\nextern const unsigned char spiral_flip[%d];\n" % (len(spiral_cos), len(spiral_flip))
assets_h += "#define SFX_ENABLED %d\n" % (1 if SFX_ENABLED else 0)
assets_h += "#define MUSIC_ENABLED %d\n" % (1 if MUSIC_ENABLED else 0)
if MUSIC_ENABLED:
    assets_h += "#define MOD_EHZ 0\nextern const unsigned char soundbank[];\n"
if SFX_ENABLED:
    for _name in SFX_ORDER:
        assets_h += "#define SFX_%s_SIZE %d\n" % (_name.upper(), len(sfx_data[_name]))
        assets_h += "extern const unsigned char sfx_%s[];\n" % _name
    # spcPlaySound index 0 is the last loaded entry.
    for _idx, _name in enumerate(reversed(SFX_ORDER)):
        assets_h += "#define SFX_ID_%s %d\n" % (_name.upper(), _idx)

for name, ids in anim_indices.items():
    assets_h += "extern const unsigned char anim_%s[];\n" % name
    assets_h += "#define ANIM_%s_COUNT %d\n" % (name.upper(), len(ids))
assets_h += "#endif\n"
with open(f"{OUT}/src/assets.h", "w") as f:
    f.write(assets_h)

main_c = r'''#include <snes.h>
#include "assets.h"

#define TOP_SPEED   0x600
#define ACCEL       0x00C
#define DECEL       0x080
#define JUMP_FORCE  0x680
#define GRAVITY     0x038
#define XRADIUS     9
#define YRADIUS     19
#define WORLD_W     (SLICE_W * 8)
#define WORLD_H     (SLICE_H * 8)
#define CAM_W       256
#define CAM_H       224

static short xpos, ypos;      /* world pixel position (centre of Sonic) */
static short xsub, ysub;      /* subpixel accumulators (0..255) */
static short vx, vy;           /* 8.8 velocity */
static short inertia;          /* 8.8 ground speed */
static unsigned char angle;
static unsigned char grounded;
static unsigned char facing;
static unsigned char jumping;
static unsigned char anim_id;
static unsigned char anim_frame;
static unsigned char anim_timer;
static unsigned char ring_taken[RING_COUNT];
static unsigned short rings_collected, score, game_time;
static unsigned short frame_counter;
static unsigned char ring_anim;
static unsigned char time_timer;

static unsigned short obj_state[OBJ_COUNT];
static unsigned char obj_timer[OBJ_COUNT];
static unsigned char obj_phase[OBJ_COUNT];
static short obj_rx[OBJ_COUNT];
static short obj_ry[OBJ_COUNT];
static short obj_vy[OBJ_COUNT];
static unsigned short obj_map[32 * 32];
static short checkpoint_x = 96, checkpoint_y = 655;
static unsigned char last_starpost;
static unsigned char shield_flag;
static unsigned short invincible_timer;
static unsigned short speed_timer;
static unsigned char lives = 3;
static unsigned char goal_flag;
static unsigned short goal_timer;
static unsigned char sign_spin;
static unsigned char dead;
static unsigned short death_timer;
static unsigned char hurt_timer;
static unsigned char spindash_active;
static unsigned char spindash_charge;
static unsigned char rolling;
static unsigned char on_spiral;
static unsigned short spiral_i;
static unsigned char spiral_angle;
static unsigned char lost_count;
static short tail_hist_x[32], tail_hist_y[32];
static unsigned char tail_hist_i, tail_anim_timer, tail_anim_frame, tail_facing;
static short tail_x, tail_y;
static short lost_x[20], lost_y[20], lost_vx[20], lost_vy[20];
static unsigned char lost_timer[20];
static short proj_x[10], proj_y[10], proj_vx[10], proj_vy[10];
static unsigned char proj_kind[10], proj_timer[10];
static short expl_x[4], expl_y[4];
static unsigned char expl_timer[4];
static unsigned char game_over;
static unsigned short game_over_timer;

#if SFX_ENABLED
static brrsamples snd_ring, snd_spring, snd_hurt, snd_jump, snd_monitor, snd_signpost;
#endif

static short cam_x, cam_y;

static short px(void) { return xpos; }
static short py(void) { return ypos; }

static void move_x(short v)
{
    short frac = (short)(v & 0xFF);
    xpos += (short)(v >> 8);
    xsub += frac;
    if (xsub >= 256) { xsub -= 256; xpos++; }
}

static void move_y(short v)
{
    short frac = (short)(v & 0xFF);
    ypos += (short)(v >> 8);
    ysub += frac;
    if (ysub >= 256) { ysub -= 256; ypos++; }
}

static short s_sin(unsigned char a) { return sine_table[a]; }
static short s_cos(unsigned char a) { return sine_table[(unsigned char)(a + 64)]; }

/* 8.8 signed multiply without the 816-tcc libgcc multiply path, which froze
 * on negative slope values in testing. */
static short mul88(short a, short b)
{
    unsigned short ua, ub;
    long long res = 0;
    unsigned char neg = 0;
    if (a < 0) { a = (short)-a; neg ^= 1; }
    if (b < 0) { b = (short)-b; neg ^= 1; }
    ua = (unsigned short)a;
    ub = (unsigned short)b;
    while (ub) {
        if (ub & 1) res += ua;
        ua = (unsigned short)(ua << 1);
        ub = (unsigned short)(ub >> 1);
    }
    res >>= 8;
    if (res > 0x7FFF) res = 0x7FFF;
    return neg ? (short)-res : (short)res;
}

static unsigned int find_tile(short x, short y)
{
    int cx = (x >> 7) & 0x7F;
    int cy = (y >> 7) & 0x0F;
    unsigned char chunk = layout[cy * 0x100 + cx];
    int idx;
    const unsigned char *map;
    if (x < 0 || y < 0 || x >= WORLD_W || y >= WORLD_H) return 0;
    idx = (chunk & 127) * 128 + ((y & 0x70) + ((x >> 3) & 0xE));
    map = (chunk < 128) ? chunk_lo : chunk_hi;
    return ((unsigned int)map[idx] << 8) | map[idx + 1];
}

static unsigned char collision_id(unsigned int w)
{
    unsigned int b = w & 0x3FF;
    if (b == 0 || b >= 768) return 0;
    return col_index_p[b];
}

/* Port of FindFloor2 / FindWall2 core. Returns 1 when a collision was found. */
static unsigned char floor_block(short x, short y, unsigned char solid, unsigned char *out_angle,
        short *out_dist)
{
    unsigned int w = find_tile(x, y);
    unsigned int b = w & 0x3FF;
    unsigned char cid, a;
    int xf, yf, pos, h, d;
    if (b == 0 || !((w >> solid) & 1)) return 0;
    cid = collision_id(w);
    if (!cid) return 0;
    a = col_curve[cid];
    xf = (w >> 10) & 1;
    yf = (w >> 11) & 1;
    if (xf) { x = (short)~x; a = (unsigned char)-a; }
    if (yf) { a = (unsigned char)(a + 0x40); a = (unsigned char)-a; a = (unsigned char)(a - 0x40); }
    pos = x & 0xF;
    h = (signed char)col_vertical[(cid << 4) + pos];
    if (yf) h = -h;
    if (h == 0) return 0;
    if (h > 0) {
        d = (y & 0xF) + h;
        *out_dist = (short)(15 - d);
        *out_angle = a;
        return 1;
    }
    d = (y & 0xF) + h;
    if (d >= 0) return 0;
    *out_dist = (short)(~d);
    *out_angle = a;
    return 1;
}

static short floor2(short x, short y, unsigned char solid, unsigned char *out_angle)
{
    short d;
    if (floor_block(x, y, solid, out_angle, &d)) return d;
    return (short)(15 - (y & 0xF));
}

static short find_floor(short x, short y, unsigned char solid, unsigned char *out_angle)
{
    short d;
    if (floor_block(x, y, solid, out_angle, &d)) return d;
    return (short)(floor2(x, (short)(y + 16), solid, out_angle) + 16);
}

/* FindWall / FindWall2 port (rotated heightmap). */
static unsigned char wall_block(short x, short y, unsigned char solid, unsigned char *out_angle,
        short *out_dist)
{
    unsigned int w = find_tile(x, y);
    unsigned int b = w & 0x3FF;
    unsigned char cid, a;
    int xf, yf, pos, h, d;
    if (b == 0 || !((w >> solid) & 1)) return 0;
    cid = collision_id(w);
    if (!cid) return 0;
    a = col_curve[cid];
    xf = (w >> 10) & 1;
    yf = (w >> 11) & 1;
    if (yf) { y = (short)~y; a = (unsigned char)(a + 0x40); a = (unsigned char)-a; a = (unsigned char)(a - 0x40); }
    if (xf) { a = (unsigned char)-a; }
    pos = y & 0xF;
    h = (signed char)col_horizontal[(cid << 4) + pos];
    if (xf) h = -h;
    if (h == 0) return 0;
    if (h > 0) {
        d = (x & 0xF) + h;
        *out_dist = (short)(15 - d);
        *out_angle = a;
        return 1;
    }
    d = (x & 0xF) + h;
    if (d >= 0) return 0;
    *out_dist = (short)(~d);
    *out_angle = a;
    return 1;
}

static short wall2(short x, short y, unsigned char solid, unsigned char *out_angle)
{
    short d;
    if (wall_block(x, y, solid, out_angle, &d)) return d;
    return (short)(15 - (x & 0xF));
}

static short find_wall(short x, short y, unsigned char solid, unsigned char *out_angle)
{
    short d;
    if (wall_block(x, y, solid, out_angle, &d)) return d;
    return (short)(wall2((short)(x + 16), y, solid, out_angle) + 16);
}

/* Sonic_CheckFloor: nearest floor under the left/right feet. */
static short check_floor(short *out_angle)
{
    unsigned char a1 = 0, a2 = 0;
    short d1, d2, d;
    d1 = find_floor((short)(px() + XRADIUS), (short)(py() + YRADIUS), 0x0E, &a1);
    d2 = find_floor((short)(px() - XRADIUS), (short)(py() + YRADIUS), 0x0E, &a2);
    if (d2 <= d1) { d = d2; *out_angle = a2; }
    else { d = d1; *out_angle = a1; }
    if (*out_angle & 1) *out_angle = 0;
    return d;
}

static short check_ceiling(void)
{
    unsigned char a1 = 0, a2 = 0;
    short d1, d2, d;
    short y = (short)(py() - YRADIUS);
    y = (short)(y ^ 0xF);
    d1 = find_floor((short)(px() + XRADIUS), y, 0x0E, &a1);
    d2 = find_floor((short)(px() - XRADIUS), y, 0x0E, &a2);
    if (d2 <= d1) d = d2; else d = d1;
    return d;
}

static short check_left_wall(void)
{
    unsigned char a = 0;
    short x = (short)(px() - XRADIUS);
    x = (short)(x ^ 0xF);
    return find_wall(x, py(), 0x0E, &a);
}

static short check_right_wall(void)
{
    unsigned char a = 0;
    return find_wall((short)(px() + XRADIUS), py(), 0x0E, &a);
}

static void do_collision(void)
{
    short d;
    unsigned char a = 0;
    if (vy >= 0) {
        d = check_floor(&a);
        if (d <= 0 && d >= -14) {
            ypos += d;
            angle = a;
            vy = 0;
            grounded = 1;
            jumping = 0;
        }
    }
    if (!grounded && vy < 0) {
        d = check_ceiling();
        if (d < 0) {
            ypos -= d;
            if (vy < 0) vy = 0;
        }
    }
    d = check_left_wall();
    if (d < 0) { xpos -= d; if (vx < 0) vx = 0; }
    d = check_right_wall();
    if (d < 0) { xpos += d; if (vx > 0) vx = 0; }
}

static void angle_pos(void)
{
    unsigned char a = 0;
    short d = check_floor(&a);
    short step;
    if (d == 0) { angle = a; grounded = 1; return; }
    if (d < 0 && d >= -14) {
        ypos += d;
        angle = a;
        grounded = 1;
        return;
    }
    if (d > 0) {
        int sp = (vx < 0 ? -vx : vx) >> 8;
        step = (short)(sp + 4);
        if (step > 14) step = 14;
        if (d <= step) {
            ypos += d;
            angle = a;
            grounded = 1;
            return;
        }
    }
    grounded = 0;
}

static void ground_move(unsigned short pad)
{
    int left = (pad & KEY_LEFT) != 0;
    int right = (pad & KEY_RIGHT) != 0;
    unsigned char a = 0;
    short d;
    if (left && !right) {
        if (inertia > 0) inertia -= DECEL;
        else inertia -= ACCEL;
        if (inertia < -TOP_SPEED) inertia = -TOP_SPEED;
        facing = 1;
    } else if (right && !left) {
        if (inertia < 0) inertia += DECEL;
        else inertia += ACCEL;
        if (inertia > TOP_SPEED) inertia = TOP_SPEED;
        if (speed_timer && inertia > 0x900) inertia = 0x900;
        facing = 0;
    } else {
        if (inertia > 0) { inertia -= ACCEL; if (inertia < 0) inertia = 0; }
        else if (inertia < 0) { inertia += ACCEL; if (inertia > 0) inertia = 0; }
    }
    vx = inertia;
    vy = 0;
    move_x(vx);
    if (on_spiral) { grounded = 1; return; }
    d = check_floor(&a);
    {
        short sp = (vx < 0 ? -vx : vx) >> 8;
        short step = (short)(sp + 4);
        if (step > 14) step = 14;
        if (d <= 0 && d >= -14) { ypos += d; angle = a; grounded = 1; }
        else if (d > 0 && d <= step) { ypos += d; angle = a; grounded = 1; }
        else grounded = 0;
    }
}

static void air_move(unsigned short pad)
{
    int left = (pad & KEY_LEFT) != 0;
    int right = (pad & KEY_RIGHT) != 0;
    if (left) {
        vx -= (ACCEL * 2);
        if (vx < -TOP_SPEED) vx = -TOP_SPEED;
        facing = 1;
    } else if (right) {
        vx += (ACCEL * 2);
        if (vx > TOP_SPEED) vx = TOP_SPEED;
        if (speed_timer && vx > 0x900) vx = 0x900;
        facing = 0;
    }
    if (vy > -0x400 && vx != 0) vx -= vx >> 5;
    move_x(vx);
    move_y(vy);
    vy += GRAVITY;
    if (vy > 0xFC0) vy = 0xFC0;
    if (!(pad & (KEY_A | KEY_B | KEY_Y)) && vy < -0x400) vy = -0x400;
    angle = 0;
    do_collision();
}

static void jump_if_needed(unsigned short pressed)
{
    if ((pressed & (KEY_A | KEY_B | KEY_Y)) && grounded) {
        short sn = s_sin((unsigned char)(angle - 0x40));
        short cs = s_cos((unsigned char)(angle - 0x40));
        vx += mul88(JUMP_FORCE, cs);
        vy += mul88(JUMP_FORCE, sn);
        grounded = 0;
        jumping = 1;
        angle = 0;
#if SFX_ENABLED
        spcPlaySound(SFX_ID_JUMP);
#endif
    }
}

static const unsigned char *page_arrays[PAGE_GROUP_COUNT] = {
    /*PAGE_ARRAYS*/
};
static unsigned char page_x = 0xFF;
static unsigned char page_y = 0xFF;

static void load_page(unsigned char page, unsigned short dest)
{
    dmaCopyVram((u8 *)(page_arrays[page >> 3] + (unsigned int)(page & 7) * 2048), dest, 2048);
}

static void update_pages(void)
{
    unsigned char px = (unsigned char)(cam_x >> 8);
    unsigned char py = (unsigned char)((cam_y - SLICE_Y) >> 8);
    if (px > PAGES_X - 2) px = PAGES_X - 2;
    if (py > PAGES_Y - 2) py = PAGES_Y - 2;
    if (px == page_x && py == page_y) return;
    page_x = px;
    page_y = py;
    load_page((unsigned char)((py * PAGES_X) + px), 0x0000);
    load_page((unsigned char)((py * PAGES_X) + px + 1), 0x0400);
    load_page((unsigned char)(((py + 1) * PAGES_X) + px), 0x0800);
    load_page((unsigned char)(((py + 1) * PAGES_X) + px + 1), 0x0C00);
}

static void update_camera(void)
{
    cam_x = (short)(px() - 128);
    if (cam_x < 0) cam_x = 0;
    if (cam_x > WORLD_W - CAM_W) cam_x = WORLD_W - CAM_W;
    cam_y = (short)(py() - 96);
    if (cam_y < SLICE_Y) cam_y = SLICE_Y;
    if (cam_y > SLICE_Y + WORLD_H - CAM_H) cam_y = SLICE_Y + WORLD_H - CAM_H;
}

static void collect_rings(void)
{
    int i;
    for (i = 0; i < RING_COUNT; i++) {
        short rx, ry, dx, dy;
        if (ring_taken[i]) continue;
        rx = (short)ring_pos[i * 2];
        ry = (short)ring_pos[i * 2 + 1];
        dx = (rx > xpos) ? (short)(rx - xpos) : (short)(xpos - rx);
        dy = (ry > ypos) ? (short)(ry - ypos) : (short)(ypos - ry);
        if (dx < 12 && dy < 24) {
            ring_taken[i] = 1;
            if (rings_collected < 999) rings_collected++;
            score += 10;
#if SFX_ENABLED
            spcPlaySound(SFX_ID_RING);
#endif
        }
    }
}

static void draw_rings(void)
{
    int i;
    unsigned char slot = 0;
    ring_anim = (unsigned char)((frame_counter >> 3) & (RING_FRAMES - 1));
    for (i = 0; i < RING_COUNT; i++) {
        short rx, ry, sx, sy;
        if (ring_taken[i]) continue;
        rx = (short)ring_pos[i * 2];
        ry = (short)ring_pos[i * 2 + 1];
        if (rx < cam_x - 8 || rx > cam_x + 264) continue;
        if (ry < cam_y - 8 || ry > cam_y + 232) continue;
        sx = (short)(rx - cam_x - 8);
        sy = (short)(ry - cam_y - 8);
        oamSet((u16)((12 + slot) * 4), (u16)sx, (u16)sy, 3, 0, 0,
            (u16)(RING_BASE_TILE + ring_anim * 2), 1);
        oamSetEx((u16)((12 + slot) * 4), OBJ_LARGE, OBJ_SHOW);
        slot++;
        if (slot >= 40) break;
    }
    for (; slot < 40; slot++) oamSetEx((u16)((12 + slot) * 4), OBJ_LARGE, OBJ_HIDE);
}

static void draw_lost_rings(void)
{
    unsigned char i;
    for (i = 0; i < 20; i++) {
        if (i < lost_count && lost_timer[i]) {
            short sx = (short)(lost_x[i] - cam_x - 8);
            short sy = (short)(lost_y[i] - cam_y - 8);
            oamSet((u16)((52 + i) * 4), (u16)sx, (u16)sy, 3, 0, 0,
                (u16)(RING_BASE_TILE + ring_anim * 2), 1);
            oamSetEx((u16)((52 + i) * 4), OBJ_LARGE, OBJ_SHOW);
        } else {
            oamSetEx((u16)((52 + i) * 4), OBJ_LARGE, OBJ_HIDE);
        }
    }
}

static unsigned char hud_index(char c)
{
    if (c >= '0' && c <= '9') return (unsigned char)(c - '0');
    switch (c) {
        case 'A': return 10;
        case 'C': return 11;
        case 'E': return 12;
        case 'G': return 13;
        case 'I': return 14;
        case 'M': return 15;
        case 'N': return 16;
        case 'O': return 17;
        case 'R': return 18;
        case 'S': return 19;
        case 'T': return 20;
        case 'V': return 21;
        case ':': return 22;
        case '-': return 23;
        default: return 24;
    }
}

static unsigned char hud_char(unsigned char x, unsigned char y, char c, unsigned char slot)
{
    oamSet((u16)((72 + slot) * 4), (u16)x, (u16)y, 3, 0, 0,
        (u16)(HUD_TILE_BASE + hud_index(c)), 0);
    oamSetEx((u16)((72 + slot) * 4), OBJ_SMALL, OBJ_SHOW);
    return (unsigned char)(slot + 1);
}

static unsigned char hud_text(unsigned char x, unsigned char y, const char *text, unsigned char slot)
{
    while (*text && slot < 48) {
        slot = hud_char(x, y, *text, slot);
        x = (unsigned char)(x + 8);
        text++;
    }
    return slot;
}

static unsigned char hud_num(unsigned char x, unsigned char y, unsigned short value,
        unsigned char digits, unsigned char slot)
{
    static const unsigned short pow10[6] = {1, 10, 100, 1000, 10000, 100000};
    unsigned char i;
    for (i = 0; i < digits; i++) {
        unsigned short div = pow10[digits - 1 - i];
        char c = (char)('0' + ((value / div) % 10));
        slot = hud_char(x, y, c, slot);
        x = (unsigned char)(x + 8);
    }
    return slot;
}

static void draw_hud(void)
{
    unsigned char slot = 0;
    if (game_over) {
        slot = hud_text(92, 100, "GAME OVER", slot);
        for (; slot < 54; slot++) oamSetEx((u16)((72 + slot) * 4), OBJ_SMALL, OBJ_HIDE);
        return;
    }
    slot = hud_text(8, 8, "SCORE", slot);
    slot = hud_num(56, 8, score, 6, slot);
    slot = hud_text(8, 16, "TIME", slot);
    slot = hud_num(48, 16, game_time, 3, slot);
    slot = hud_text(8, 24, "RINGS", slot);
    slot = hud_num(56, 24, rings_collected, 3, slot);
    slot = hud_text(8, 200, "SONIC", slot);
    slot = hud_num(56, 200, lives, 1, slot);
    for (; slot < 54; slot++) oamSetEx((u16)((72 + slot) * 4), OBJ_SMALL, OBJ_HIDE);
}

static const unsigned char mon_frames[8] = {0, OF_MON_1UP, 0, 0, 5, 6, 7, 8};
static const unsigned char sign_seq[9] = {
    OF_SIGN_2, OF_SIGN_3, OF_SIGN_4, OF_SIGN_5, OF_SIGN_1,
    OF_SIGN_3, OF_SIGN_4, OF_SIGN_5, OF_SIGN_0
};

static unsigned char spring_frame(unsigned short i)
{
    unsigned char sub = obj_sub[i];
    unsigned char o = (unsigned char)((sub >> 3) & 0x0E);
    unsigned char red = (unsigned char)(sub & 2);
    unsigned char t = obj_timer[i];
    if (o == 0) {
        if (t) return (t & 4) ? OF_SPR_UP1 : OF_SPR_UP2;
        return OF_SPR_UP;
    }
    if (o == 2) {
        if (t) return (t & 4) ? OF_SPR_H1 : OF_SPR_H2;
        return OF_SPR_H;
    }
    if (o == 4) return OF_SPR_DOWN;
    if (o == 6) return red ? OF_SPR_RDU : OF_SPR_DU;
    return red ? OF_SPR_RDD : OF_SPR_DD;
}

static unsigned char sign_frame(void)
{
    unsigned short idx = (unsigned short)(sign_spin >> 2);
    if (idx >= 9) idx = 8;
    return sign_seq[idx];
}

static void obj_put(short sx, short sy, unsigned short tile, unsigned char flip,
        unsigned char pal, unsigned char prio)
{
    short tx = (short)(sx >> 3);
    short ty = (short)(sy >> 3);
    if (tx < 0 || tx >= 32 || ty < 0 || ty >= 28) return;
    obj_map[(unsigned short)ty * 32 + (unsigned short)tx] =
        (unsigned short)(tile | ((unsigned short)(flip & 3) << 14) |
            ((unsigned short)(pal & 7) << 10) | (prio ? 0x2000 : 0));
}

static void draw_obj_frame_prio(unsigned char frame, short sx, short sy,
        unsigned char flip, unsigned char pal, unsigned char prio)
{
    unsigned short i, start, count;
    start = obj_frame_start[frame];
    count = obj_frame_len[frame];
    for (i = 0; i < count; i++) {
        short dx = (short)obj_draw_dx[start + i];
        short dy = (short)obj_draw_dy[start + i];
        unsigned char fl = obj_draw_flip[start + i];
        if (flip & 1) { dx = (short)(-dx - 8); fl = (unsigned char)(fl ^ 1); }
        if (flip & 2) { dy = (short)(-dy - 8); fl = (unsigned char)(fl ^ 2); }
        obj_put((short)(sx + dx), (short)(sy + dy), obj_draw_tile[start + i], fl, pal, prio);
    }
}

static void draw_obj_frame_pal(unsigned char frame, short sx, short sy,
        unsigned char flip, unsigned char pal)
{
    draw_obj_frame_prio(frame, sx, sy, flip, pal, 1);
}

static void draw_obj_frame(unsigned char frame, short sx, short sy, unsigned char flip)
{
    draw_obj_frame_pal(frame, sx, sy, flip, 7);
}

static void clear_obj_map(void)
{
    unsigned short i;
    for (i = 0; i < 1024; i++) obj_map[i] = 0;
}

static void draw_objects(void)
{
    unsigned short i;
    for (i = 0; i < OBJ_COUNT; i++) {
        short ox = obj_rx[i];
        short oy = obj_ry[i];
        short sx, sy;
        unsigned char frame;
        if (obj_kind[i] == 11) continue;
        if (obj_kind[i] >= 5 && (obj_state[i] & 2)) continue;
        if (ox < cam_x - 64 || ox > cam_x + 320) continue;
        if (oy < cam_y - 96 || oy > cam_y + 320) continue;
        sx = (short)(ox - cam_x);
        sy = (short)(oy - cam_y);
        if (obj_kind[i] == 10) {
            draw_obj_frame_pal(OF_PLATFORM, sx, sy, obj_flags[i], 2);
            continue;
        }
        if (obj_kind[i] == 9) {
            short n = (short)obj_sub[i];
            short start = (short)(-n * 8 + 8);
            short k;
            for (k = 0; k < n; k++) {
                draw_obj_frame_pal(OF_BRIDGE_0, (short)(sx + start + k * 16), sy, 0, 2);
            }
            continue;
        }
        if (obj_kind[i] == 1) {
            if (obj_state[i] & 1) frame = OF_MON_BROKEN;
            else frame = mon_frames[obj_sub[i] & 7];
        } else if (obj_kind[i] == 2) {
            frame = spring_frame(i);
        } else if (obj_kind[i] == 3) {
            frame = (obj_state[i] & 1) ? OF_STAR_ACTIVE : OF_STAR_IDLE;
        } else if (obj_kind[i] == 5) {
            frame = (obj_sub[i] & 0xF0) ? OF_SPIKE_1 : OF_SPIKE_0;
        } else if (obj_kind[i] == 6) {
            frame = (obj_phase[i] & 4) ? OF_BUZ_0 : OF_BUZ_1;
        } else if (obj_kind[i] == 7) {
            frame = (obj_phase[i] & 8) ? OF_MASH_0 : OF_MASH_1;
        } else if (obj_kind[i] == 8) {
            frame = (obj_phase[i] & 16) ? OF_COCO_0 : OF_COCO_1;
        } else {
            frame = goal_flag ? sign_frame() : OF_SIGN_2;
        }
        draw_obj_frame(frame, sx, sy, obj_flags[i]);
    }
}

static void draw_effects(void)
{
    unsigned char i;
    short sx = (short)(xpos - cam_x);
    short sy = (short)(ypos - cam_y);
    if (shield_flag) {
        unsigned char f = (unsigned char)((frame_counter >> 3) & 7);
        if (f > 5) f = 5;
        draw_obj_frame((unsigned char)(OF_SHIELD_0 + f), sx, sy, 0);
    }
    if (invincible_timer) {
        unsigned char f = (unsigned char)((frame_counter >> 2) & 3);
        draw_obj_frame((unsigned char)(OF_STAR_1 + f), (short)(sx - 14), (short)(sy - 14), 0);
        draw_obj_frame((unsigned char)(OF_STAR_1 + ((f + 1) & 3)), (short)(sx + 14), (short)(sy - 10), 0);
        draw_obj_frame((unsigned char)(OF_STAR_1 + ((f + 2) & 3)), (short)(sx - 12), (short)(sy + 12), 0);
        draw_obj_frame((unsigned char)(OF_STAR_1 + ((f + 3) & 3)), (short)(sx + 12), (short)(sy + 12), 0);
    }
    if (on_spiral) {
        unsigned char f = (unsigned char)((spiral_angle >> 4) & 3);
        if (f > 2) f = 2;
        unsigned char p = (unsigned char)(xpos < (short)obj_x[spiral_i] ? 0 : 1);
        draw_obj_frame_prio((unsigned char)(OF_TUMBLE0 + f), (short)(xpos - cam_x),
            (short)(ypos - cam_y), 0, 7, p);
    }
    for (i = 0; i < 10; i++) {
        unsigned char frame;
        if (!proj_timer[i]) continue;
        if (proj_kind[i] == 1) frame = (proj_timer[i] & 4) ? OF_BUZ_FIRE0 : OF_BUZ_FIRE1;
        else frame = OF_COCO_FIRE;
        draw_obj_frame(frame, (short)(proj_x[i] - cam_x), (short)(proj_y[i] - cam_y), 0);
    }
    for (i = 0; i < 4; i++) {
        unsigned char f;
        if (!expl_timer[i]) continue;
        if (expl_timer[i] < 6) f = 0;
        else if (expl_timer[i] < 12) f = 1;
        else if (expl_timer[i] < 18) f = 2;
        else f = 3;
        draw_obj_frame((unsigned char)(OF_EXPL_1 + f),
            (short)(expl_x[i] - cam_x), (short)(expl_y[i] - cam_y), 0);
    }
}

static void draw_tails(void)
{
    unsigned char idx, frame;
    if (game_over || dead) return;
    if (++tail_anim_timer >= 6) {
        tail_anim_timer = 0;
        tail_anim_frame = (unsigned char)(tail_anim_frame ^ 1);
    }
    idx = (unsigned char)((tail_hist_i + 22) & 31);
    tail_x = tail_hist_x[idx];
    tail_y = tail_hist_y[idx];
    if (tail_y > ypos + 32) {
        tail_y = (short)(ypos - 8);
        frame = tail_anim_frame ? OF_TAILS_FLY1 : OF_TAILS_FLY0;
    } else if (tail_x < xpos - 6 || tail_x > xpos + 6) {
        frame = tail_anim_frame ? OF_TAILS_WALK1 : OF_TAILS_WALK0;
    } else {
        frame = OF_TAILS_IDLE;
    }
    if (tail_x < xpos - 2) tail_facing = 0;
    else if (tail_x > xpos + 2) tail_facing = 1;
    draw_obj_frame(frame, (short)(tail_x - cam_x), (short)(tail_y - cam_y),
        tail_facing);
}

static void monitor_grant(unsigned char sub)
{
    if (sub == 4) {
        if (rings_collected > 989) rings_collected = 999;
        else rings_collected = (unsigned short)(rings_collected + 10);
        score += 10;
    } else if (sub == 5) {
        speed_timer = 1200;
    } else if (sub == 6) {
        shield_flag = 1;
    } else if (sub == 7) {
        invincible_timer = 1200;
    } else if (sub == 1) {
        if (lives < 99) lives++;
    }
}

static void lose_rings(void)
{
    unsigned short n = rings_collected > 20 ? 20 : rings_collected;
    unsigned short i;
    lost_count = (unsigned char)n;
    rings_collected = (unsigned short)(rings_collected - n);
    for (i = 0; i < n; i++) {
        lost_x[i] = xpos;
        lost_y[i] = ypos;
        lost_vx[i] = (short)((i & 1) ? 0x180 : -0x180);
        lost_vx[i] = (short)(lost_vx[i] + (short)((i & 3) * 0x40));
        lost_vy[i] = (short)(-0x300 - (short)((i & 7) * 0x50));
        lost_timer[i] = 180;
    }
}

static void update_lost_rings(void)
{
    unsigned char i;
    for (i = 0; i < lost_count; i++) {
        unsigned char a = 0;
        short d;
        if (!lost_timer[i]) continue;
        if (lost_timer[i] > 1) lost_timer[i]--;
        else { lost_timer[i] = 0; continue; }
        lost_x[i] = (short)(lost_x[i] + (lost_vx[i] >> 8));
        lost_y[i] = (short)(lost_y[i] + (lost_vy[i] >> 8));
        lost_vy[i] = (short)(lost_vy[i] + GRAVITY);
        if (lost_vy[i] > 0x600) lost_vy[i] = 0x600;
        d = find_floor((short)(lost_x[i] + 8), (short)(lost_y[i] + 8), 0x0E, &a);
        if (d <= 0 && d >= -12) {
            lost_y[i] = (short)(lost_y[i] + d);
            lost_vy[i] = -0x300;
        }
        if (lost_timer[i] < 150) {
            short dx = (short)(xpos - lost_x[i]);
            short dy = (short)(ypos - lost_y[i]);
            if (dx < 0) dx = (short)-dx;
            if (dy < 0) dy = (short)-dy;
            if (dx < 14 && dy < 24) {
                lost_timer[i] = 0;
                if (rings_collected < 999) rings_collected++;
                score += 10;
            }
        }
        if (lost_y[i] > SLICE_Y + WORLD_H - 8) lost_timer[i] = 0;
    }
}

static void hurt_sonic(void)
{
    if (dead || hurt_timer || invincible_timer) return;
    spindash_active = 0;
    rolling = 0;
    on_spiral = 0;
#if SFX_ENABLED
    spcPlaySound(SFX_ID_HURT);
#endif
    if (shield_flag) {
        shield_flag = 0;
        hurt_timer = 60;
        invincible_timer = 90;
        return;
    }
    if (rings_collected) {
        lose_rings();
        hurt_timer = 60;
        invincible_timer = 90;
        vy = -0x300;
        vx = (short)(facing ? 0xA00 : -0xA00);
        inertia = vx;
        grounded = 0;
        jumping = 0;
    } else {
        dead = 1;
        death_timer = 0;
        vy = -0x500;
        vx = 0;
        inertia = 0;
        grounded = 0;
        jumping = 0;
    }
}

static void spawn_projectile(unsigned char kind, short x, short y, short vx, short vy)
{
    unsigned char i;
    for (i = 0; i < 10; i++) {
        if (proj_timer[i]) continue;
        proj_kind[i] = kind;
        proj_x[i] = x;
        proj_y[i] = y;
        proj_vx[i] = vx;
        proj_vy[i] = vy;
        proj_timer[i] = 180;
        return;
    }
}

static void update_projectiles(void)
{
    unsigned char i;
    for (i = 0; i < 10; i++) {
        short dx, dy;
        if (!proj_timer[i]) continue;
        proj_timer[i]--;
        proj_x[i] = (short)(proj_x[i] + (proj_vx[i] >> 8));
        proj_y[i] = (short)(proj_y[i] + (proj_vy[i] >> 8));
        if (proj_kind[i] == 2) {
            proj_vy[i] = (short)(proj_vy[i] + GRAVITY);
            if (proj_vy[i] > 0x600) proj_vy[i] = 0x600;
        }
        if (!dead && !invincible_timer) {
            dx = (short)(xpos - proj_x[i]);
            dy = (short)(ypos - proj_y[i]);
            if (dx < 0) dx = (short)-dx;
            if (dy < 0) dy = (short)-dy;
            if (dx < 14 && dy < 22) {
                proj_timer[i] = 0;
                hurt_sonic();
                continue;
            }
        }
        if (proj_y[i] > SLICE_Y + WORLD_H || proj_x[i] < -32 ||
                proj_x[i] > WORLD_W + 32) proj_timer[i] = 0;
    }
}

static void spawn_explosion(short x, short y)
{
    unsigned char i;
    for (i = 0; i < 4; i++) {
        if (expl_timer[i]) continue;
        expl_x[i] = x;
        expl_y[i] = y;
        expl_timer[i] = 1;
        return;
    }
}

static void update_explosions(void)
{
    unsigned char i;
    for (i = 0; i < 4; i++) {
        if (!expl_timer[i]) continue;
        expl_timer[i]++;
        if (expl_timer[i] > 24) expl_timer[i] = 0;
    }
}

static void reset_objects(void)
{
    unsigned short i;
    for (i = 0; i < OBJ_COUNT; i++) {
        obj_state[i] = 0;
        obj_timer[i] = 0;
        obj_phase[i] = 0;
        obj_rx[i] = (short)obj_x[i];
        obj_ry[i] = (short)obj_y[i];
        obj_vy[i] = (short)(obj_kind[i] == 7 ? -0x400 : 0);
    }
    for (i = 0; i < RING_COUNT; i++) ring_taken[i] = 0;
    for (i = 0; i < 10; i++) proj_timer[i] = 0;
    for (i = 0; i < 4; i++) expl_timer[i] = 0;
}

static void update_objects(void)
{
    unsigned short i;
    short feet = (short)(ypos + YRADIUS);
    for (i = 0; i < OBJ_COUNT; i++) {
        short base_x = (short)obj_x[i];
        short base_y = (short)obj_y[i];
        short ox, oy, dx, dy;
        unsigned char kind = obj_kind[i];
        feet = (short)(ypos + YRADIUS);
        if (kind == 6) {
            obj_phase[i]++;
            obj_rx[i] = (short)(base_x + mul88(s_sin(obj_phase[i]), 48));
            obj_ry[i] = (short)(base_y + mul88(s_sin((unsigned char)(obj_phase[i] + 64)), 12));
        } else if (kind == 7) {
            obj_phase[i]++;
            obj_ry[i] = (short)(obj_ry[i] + (obj_vy[i] >> 8));
            obj_vy[i] = (short)(obj_vy[i] + 0x18);
            if (obj_ry[i] >= base_y) {
                obj_ry[i] = base_y;
                obj_vy[i] = -0x500;
            }
        } else if (kind == 8) {
            obj_phase[i]++;
        }
        ox = obj_rx[i];
        oy = obj_ry[i];
        dx = (short)(xpos - ox);
        dy = (short)(ypos - oy);
        if (obj_timer[i]) obj_timer[i]--;
        if (dx < 0) dx = (short)-dx;
        if (dy < 0) dy = (short)-dy;
        if (kind == 6 && obj_timer[i] == 0 && dx < 180 && ypos < oy + 80) {
            short dir = (short)(xpos > ox ? 1 : -1);
            spawn_projectile(1, (short)(ox - 8), (short)(oy + 14),
                (short)(dir * 0x180), 0x180);
            obj_timer[i] = 150;
        }
        if (kind == 8 && obj_timer[i] == 0 && dx < 160) {
            short dir = (short)(xpos > ox ? 1 : -1);
            spawn_projectile(2, (short)(ox + dir * 12), (short)(oy - 8),
                (short)(dir * 0x100), -0x100);
            obj_timer[i] = 180;
        }
        if (kind == 11) {
            short rel = (short)(xpos - ox);
            if (on_spiral && spiral_i == i) {
                short d0 = (short)(rel + 0xD0);
                if (d0 < 0 || d0 >= 0x1A0 || jumping ||
                        (inertia < 0 ? -inertia : inertia) < 0x600) {
                    on_spiral = 0;
                } else {
                    ypos = (short)(oy + (signed char)spiral_cos[d0]);
                    spiral_angle = spiral_flip[(unsigned short)(d0 >> 3)];
                    grounded = 1;
                    vy = 0;
                }
            } else if (!on_spiral && rel >= -0xD0 && rel < -0xB0 &&
                    !jumping && (inertia < 0 ? -inertia : inertia) >= 0x600) {
                on_spiral = 1;
                spiral_i = i;
            }
        } else if (kind == 2) {
            unsigned char sub = obj_sub[i];
            unsigned char o = (unsigned char)((sub >> 3) & 0x0E);
            short strength = (sub & 2) ? 0xA00 : 0x1000;
            if (obj_timer[i]) continue;
            if (o == 0) {
                if (dx < 20 && feet >= oy - 10 && feet <= oy + 12 && vy >= 0) {
                    ypos = (short)(oy - YRADIUS - 2);
                    vy = (short)-strength;
                    vx = 0; inertia = 0; grounded = 0; jumping = 1;
                    obj_timer[i] = 14;
#if SFX_ENABLED
                    spcPlaySound(SFX_ID_SPRING);
#endif
                }
            } else if (o == 2) {
                if (dx < 24 && dy < 22) {
                    short dir = (obj_flags[i] & 1) ? -1 : 1;
                    vx = (short)(dir * strength);
                    inertia = vx;
                    vy = -0x200;
                    grounded = 0; jumping = 0;
                    facing = dir < 0;
                    xpos = (short)(ox + dir * 20);
                    obj_timer[i] = 14;
#if SFX_ENABLED
                    spcPlaySound(SFX_ID_SPRING);
#endif
                }
            } else if (o == 4) {
                if (dx < 16 && dy < 20 && vy <= 0) {
                    vy = strength; grounded = 0;
                    obj_timer[i] = 14;
#if SFX_ENABLED
                    spcPlaySound(SFX_ID_SPRING);
#endif
                }
            } else if (o == 6) {
                if (dx < 22 && dy < 24) {
                    short dir = (obj_flags[i] & 1) ? -1 : 1;
                    vx = (short)(dir * (strength >> 1));
                    vy = (short)-(strength >> 1);
                    inertia = vx; grounded = 0; jumping = 1;
                    facing = dir < 0;
                    obj_timer[i] = 14;
#if SFX_ENABLED
                    spcPlaySound(SFX_ID_SPRING);
#endif
                }
            } else {
                if (dx < 22 && dy < 24) {
                    short dir = (obj_flags[i] & 1) ? -1 : 1;
                    vx = (short)(dir * (strength >> 1));
                    vy = (short)(strength >> 2);
                    inertia = vx; grounded = 0;
                    facing = dir < 0;
                    obj_timer[i] = 14;
#if SFX_ENABLED
                    spcPlaySound(SFX_ID_SPRING);
#endif
                }
            }
        } else if (kind == 1) {
            if (!(obj_state[i] & 1)) {
                short top = (short)(oy - 16);
                if (dx < 20 && vy > 0 && feet >= top - 4 && feet <= top + 14) {
                    if (jumping) {
                        obj_state[i] = 1;
#if SFX_ENABLED
                        spcPlaySound(SFX_ID_MONITOR);
#endif
                        monitor_grant(obj_sub[i]);
                        ypos = (short)(top - YRADIUS);
                        vy = -0x380; grounded = 0;
                    } else {
                        ypos = (short)(top - YRADIUS);
                        vy = 0; grounded = 1; jumping = 0;
                    }
                }
            }
        } else if (kind == 3) {
            if (!(obj_state[i] & 1) && dx < 10 && ypos >= oy - 64 && ypos <= oy + 40) {
                obj_state[i] = 1;
                last_starpost = obj_sub[i];
                checkpoint_x = ox;
                checkpoint_y = (short)(oy - YRADIUS);
            }
        } else if (kind == 4) {
            short rel = (short)(xpos - ox);
            if (!goal_flag && rel >= 0 && rel < 0x20 && ypos >= oy - 80 && ypos <= oy + 40) {
                goal_flag = 1;
                goal_timer = 0;
                sign_spin = 0;
#if SFX_ENABLED
                spcPlaySound(SFX_ID_SIGNPOST);
#endif
            }
        }
        if (kind == 10) {
            short top = (short)(oy - 16);
            if (vy > 0 && feet >= top - 4 && feet <= top + 12 && dx < 40) {
                ypos = (short)(top - YRADIUS);
                vy = 0;
                grounded = 1;
                jumping = 0;
            }
        }
        if (kind == 9) {
            short n = (short)obj_sub[i];
            short top = (short)(oy - 8);
            if (vy > 0 && feet >= top - 4 && feet <= top + 12 &&
                    dx < (short)(n * 8 + 8)) {
                ypos = (short)(top - YRADIUS);
                vy = 0;
                grounded = 1;
                jumping = 0;
            }
        }
        if (kind >= 5 && kind <= 8 && !(obj_state[i] & 2)) {
            short hw, hh;
            unsigned char stomp;
            if (kind == 5) {
                hw = (obj_sub[i] & 0xF0) ? 30 : 14;
                hh = 22;
            } else if (kind == 6) {
                hw = 20;
                hh = 14;
            } else if (kind == 7) {
                hw = 14;
                hh = 18;
            } else {
                hw = 16;
                hh = 22;
            }
            stomp = (unsigned char)(kind != 5 && vy > 0 && dx < hw + 8 &&
                    feet >= oy - hh && feet <= oy + 8);
            if (stomp) {
                obj_state[i] |= 2;
                score += 100;
                spawn_explosion(ox, oy);
                vy = -0x380;
                grounded = 0;
                jumping = 1;
            } else if (dx < hw + 6 && dy < hh + 18) {
                hurt_sonic();
            }
        }
    }
    if (goal_flag) {
        if (goal_timer < 60000) goal_timer++;
        if (sign_spin < 40) sign_spin++;
    }
}

static void respawn_sonic(void)
{
    unsigned short i;
    xpos = checkpoint_x;
    ypos = checkpoint_y;
    xsub = 0;
    ysub = 0;
    vx = 0; vy = 0; inertia = 0;
    grounded = 0; jumping = 0;
    dead = 0;
    hurt_timer = 0;
    invincible_timer = 120;
    spindash_active = 0;
    spindash_charge = 0;
    rolling = 0;
    shield_flag = 0;
    speed_timer = 0;
    rings_collected = 0;
    game_time = 0;
    time_timer = 0;
    lost_count = 0;
    for (i = 0; i < 20; i++) lost_timer[i] = 0;
    for (i = 0; i < 10; i++) proj_timer[i] = 0;
    for (i = 0; i < 4; i++) expl_timer[i] = 0;
    for (i = 0; i < RING_COUNT; i++) ring_taken[i] = 0;
    for (i = 0; i < OBJ_COUNT; i++) {
        if (obj_kind[i] >= 5) obj_state[i] &= (unsigned short)~2;
    }
}

static void draw_sonic(void)
{
    unsigned char idx, i;
    unsigned char prio = 3;
    short sx, sy, fw, fh;
    const short *pieces;
    if (on_spiral && xpos < (short)obj_x[spiral_i]) prio = 0;
    if (game_over || on_spiral) {
        for (i = 0; i < MAX_PIECES; i++) oamSetEx((u16)(i * 4), OBJ_LARGE, OBJ_HIDE);
        return;
    }
    if (!dead && invincible_timer && (frame_counter & 2)) {
        for (i = 0; i < MAX_PIECES; i++) oamSetEx((u16)(i * 4), OBJ_LARGE, OBJ_HIDE);
        return;
    }
    if (dead) {
        idx = 4;
    } else if (hurt_timer) {
        idx = 5;
    } else if (rolling || on_spiral) {
        idx = 3;
    } else if (grounded) {
        if ((inertia < 0 ? -inertia : inertia) < 0x40) idx = 0;
        else if ((inertia < 0 ? -inertia : inertia) > 0x400) idx = 2;
        else idx = 1;
    } else {
        idx = 3; /* roll/jump */
    }
    {
        const unsigned char *list;
        unsigned char count;
        switch (idx) {
            case 0: list = anim_idle; count = ANIM_IDLE_COUNT; break;
            case 1: list = anim_walk; count = ANIM_WALK_COUNT; break;
            case 2: list = anim_run; count = ANIM_RUN_COUNT; break;
            case 3: list = anim_roll; count = ANIM_ROLL_COUNT; break;
            case 4: list = anim_death; count = ANIM_DEATH_COUNT; break;
            default: list = anim_hurt; count = ANIM_HURT_COUNT; break;
        }
        if (anim_id != idx) { anim_id = idx; anim_frame = 0; anim_timer = 0; }
        if (++anim_timer >= 6) { anim_timer = 0; anim_frame++; if (anim_frame >= count) anim_frame = 0; }
        idx = list[anim_frame];
    }
    fw = frame_w[idx];
    fh = frame_h[idx];
    sx = (short)(px() - cam_x - (fw >> 1));
    sy = (short)(py() - cam_y + YRADIUS - fh);
    pieces = &frame_pieces[0][0];
    {
        unsigned char base = 0;
        unsigned char c = 0;
        unsigned char f;
        for (f = 0; f < idx; f++) base += frame_count[f];
        for (i = 0; i < frame_count[idx]; i++) {
            short dx = pieces[(base + i) * 3 + 0];
            short dy = pieces[(base + i) * 3 + 1];
            short tile = pieces[(base + i) * 3 + 2];
            short ox = facing ? (short)(fw - 16 - dx) : dx;
            oamSet(c * 4, (short)(sx + ox), (short)(sy + dy), prio, facing, 0, tile, 0);
            oamSetEx(c * 4, OBJ_LARGE, OBJ_SHOW);
            c++;
        }
        for (; c < MAX_PIECES; c++) oamSetEx(c * 4, OBJ_LARGE, OBJ_HIDE);
    }
}

int main(void)
{
    unsigned short pad, pressed, oldpad = 0;
    consoleInit();
#if MUSIC_ENABLED || SFX_ENABLED
    spcBoot();
    spcAllocateSoundRegion(80);
#endif
#if MUSIC_ENABLED
    spcSetBank((u8 *)soundbank);
    spcLoad(MOD_EHZ);
#endif
#if SFX_ENABLED
    spcSetSoundEntry(15, 8, 6, SFX_RING_SIZE, (u8 *)sfx_ring, &snd_ring);
    spcSetSoundEntry(15, 8, 6, SFX_SPRING_SIZE, (u8 *)sfx_spring, &snd_spring);
    spcSetSoundEntry(15, 8, 6, SFX_HURT_SIZE, (u8 *)sfx_hurt, &snd_hurt);
    spcSetSoundEntry(15, 8, 6, SFX_JUMP_SIZE, (u8 *)sfx_jump, &snd_jump);
    spcSetSoundEntry(15, 8, 6, SFX_MONITOR_SIZE, (u8 *)sfx_monitor, &snd_monitor);
    spcSetSoundEntry(15, 8, 6, SFX_SIGNPOST_SIZE, (u8 *)sfx_signpost, &snd_signpost);
#endif
#if MUSIC_ENABLED
    spcPlay(0);
#endif
    setMode(BG_MODE1, 0);
    bgInitTileSet(0, (u8 *)bg_tiles, (u8 *)bg_pal, 0, BG_TILES_SIZE, BG_PAL_SIZE, BG_16COLORS, 0x1000);
    bgSetMapPtr(0, 0x0000, SC_64x64);
    bgSetGfxPtr(0, 0x1000);
    WaitForVBlank();
    bgSetEnable(0);
    REG_TM = 0x01;

    oamInitGfxSet((u8 *)sonic_tiles, SONIC_TILES_SIZE, (u8 *)sonic_pal, SONIC_PAL_SIZE, 0, 0x6000, OBJ_SIZE8_L16);
    setPalette((u16 *)sonic_pal, 128, SONIC_PAL_SIZE);
    dmaCopyVram((u8 *)(sonic_tiles + SONIC_TILES_SIZE), 0x6000 + SONIC_TILES_SIZE / 2, RING_TILES_SIZE);
    setPalette((u16 *)(sonic_pal + 32), 144, 32);
    dmaCopyVram((u8 *)(sonic_tiles + SONIC_TILES_SIZE + RING_TILES_SIZE), 0x6000 + HUD_TILE_BASE * 16, HUD_TILES_SIZE);
    setPalette((u16 *)(sonic_pal + 64), 160, 32);

    /* BG2: original object art, screen-space tilemap. */
    dmaCopyVram((u8 *)obj_chr, OBJ_BG_CHR, OBJ_CHR_SIZE);
    setPalette((u16 *)obj_pal, 112, 32);
    bgSetGfxPtr(1, OBJ_BG_CHR);
    bgSetMapPtr(1, OBJ_BG_MAP, SC_32x32);
    bgSetScroll(1, 0, 0);
    bgSetEnable(1);
    clear_obj_map();
    dmaCopyVram((u8 *)obj_map, OBJ_BG_MAP, 2048);
    REG_TM = 0x13; /* BG1 + BG2 (objects) + OBJ */

    xpos = 96; xsub = 0;
    ypos = 655; ysub = 0;
    vx = vy = inertia = 0;
    angle = 0;
    grounded = 0;
    facing = 0;
    jumping = 0;
    anim_id = 0xFF;
    anim_frame = 0;
    anim_timer = 0;
    rings_collected = 0;
    score = 0;
    game_time = 0;
    frame_counter = 0;
    ring_anim = 0;
    time_timer = 0;
    {
        int ri;
        for (ri = 0; ri < RING_COUNT; ri++) ring_taken[ri] = 0;
    }
    {
        int oi;
        for (oi = 0; oi < OBJ_COUNT; oi++) {
            obj_state[oi] = 0;
            obj_timer[oi] = 0;
            obj_phase[oi] = 0;
            obj_rx[oi] = (short)obj_x[oi];
            obj_ry[oi] = (short)obj_y[oi];
            obj_vy[oi] = (short)(obj_kind[oi] == 7 ? -0x400 : 0);
        }
    }
    {
        int li;
        for (li = 0; li < 20; li++) lost_timer[li] = 0;
        for (li = 0; li < 10; li++) proj_timer[li] = 0;
        for (li = 0; li < 4; li++) expl_timer[li] = 0;
    }
    game_over = 0;
    game_over_timer = 0;
    dead = 0;
    death_timer = 0;
    hurt_timer = 0;
    spindash_active = 0;
    spindash_charge = 0;
    rolling = 0;
    on_spiral = 0;
    {
        int ti;
        for (ti = 0; ti < 32; ti++) {
            tail_hist_x[ti] = 76;
            tail_hist_y[ti] = 655;
        }
        tail_hist_i = 0;
        tail_x = 76;
        tail_y = 655;
        tail_anim_timer = 0;
        tail_anim_frame = 0;
        tail_facing = 0;
    }
    lost_count = 0;
    checkpoint_x = 96; checkpoint_y = 655;
    last_starpost = 0;
    shield_flag = 0;
    invincible_timer = 0;
    speed_timer = 0;
    lives = 3;
    goal_flag = 0;
    goal_timer = 0;
    sign_spin = 0;
    update_camera();
    update_pages();
    setScreenOn();

    while (1) {
        pad = padsCurrent(0);
        if (game_over) {
            game_over_timer++;
            if (game_over_timer > 180) {
                game_over = 0;
                lives = 3;
                checkpoint_x = 96;
                checkpoint_y = 655;
                reset_objects();
                respawn_sonic();
            }
        } else if (dead) {
            death_timer++;
            move_y(vy);
            vy += GRAVITY;
            if (vy > 0xFC0) vy = 0xFC0;
            if (death_timer > 120) {
                if (lives > 0) lives--;
                if (lives == 0) {
                    game_over = 1;
                    game_over_timer = 0;
                    dead = 0;
                } else {
                    respawn_sonic();
                }
            }
        } else {
            if (goal_flag) pad = 0;
            pressed = pad & ~oldpad;
            oldpad = pad;
            if (spindash_active) {
                if (pressed & (KEY_A | KEY_B | KEY_Y)) {
                    if (spindash_charge < 8) spindash_charge++;
                }
                if (!(pad & KEY_DOWN)) {
                    inertia = (short)(0x800 + (short)spindash_charge * 0x100);
                    if (inertia > 0x1000) inertia = 0x1000;
                    vx = (short)(facing ? -inertia : inertia);
                    spindash_active = 0;
                    spindash_charge = 0;
                    rolling = 40;
                    grounded = 1;
                } else {
                    inertia = 0;
                    vx = 0;
                }
            } else if (grounded && (pad & KEY_DOWN) &&
                    (pressed & (KEY_A | KEY_B | KEY_Y))) {
                spindash_active = 1;
                spindash_charge = 1;
                rolling = 1;
                inertia = 0;
                vx = 0;
            } else if (grounded) {
                jump_if_needed(pressed);
                if (jumping && !(pad & (KEY_A | KEY_B | KEY_Y)) && vy < -0x400) vy = -0x400;
            }
            if (grounded) ground_move(pad);
            else air_move(pad);
            if (xpos < 16) { xpos = 16; if (vx < 0) vx = 0; if (inertia < 0) inertia = 0; }
            if (xpos > SLICE_W * 8 - 24) { xpos = SLICE_W * 8 - 24; if (vx > 0) vx = 0; if (inertia > 0) inertia = 0; }
            if (ypos > SLICE_Y + WORLD_H - 16) {
                dead = 1;
                death_timer = 0;
                vx = 0; vy = 0; inertia = 0;
                grounded = 0; jumping = 0;
            }
            update_objects();
            tail_hist_x[tail_hist_i] = xpos;
            tail_hist_y[tail_hist_i] = ypos;
            tail_hist_i = (unsigned char)((tail_hist_i + 1) & 31);
        }
        if (speed_timer) speed_timer--;
        if (invincible_timer) invincible_timer--;
        if (hurt_timer) hurt_timer--;
        if (rolling) rolling--;
        if (!game_over) {
            update_projectiles();
            update_explosions();
        }
        update_lost_rings();
        update_camera();
        update_pages();
        bgSetScroll(0, (u16)(cam_x - page_x * 256), (u16)((cam_y - SLICE_Y) - page_y * 256));
        frame_counter++;
        collect_rings();
        draw_rings();
        draw_lost_rings();
        if ((frame_counter & 7) == 0) draw_hud();
        if (!goal_flag && ++time_timer >= 60) { time_timer = 0; game_time++; }
        clear_obj_map();
        draw_objects();
        if (!game_over) draw_effects();
        draw_tails();
        draw_sonic();
#if MUSIC_ENABLED || SFX_ENABLED
        spcProcess();
#endif
        WaitForVBlank();
        dmaCopyVram((u8 *)obj_map, OBJ_BG_MAP, 2048);
    }
    return 0;
}
'''

main_c = main_c.replace(
    "    /*PAGE_ARRAYS*/",
    "    " + ",\n    ".join("page%d" % i for i in range(len(page_groups))))
with open(f"{OUT}/src/main.c", "w") as f:
    f.write(main_c)

makefile = """ifeq ($(strip $(PVSNESLIB_HOME)),)
$(error Set PVSNESLIB_HOME to the PVSnesLib root)
endif
export ROMNAME := sonic_port
export ROMTITLE := SONIC PORT
FASTROM := 1
ROMSIZE := 0A
ROMBANKS := 32
include $(PVSNESLIB_HOME)/devkitsnes/snes_rules
all: $(ROMNAME).sfc
"""
if DEMO:
    # Automated preview: force right and one jump. Uses assignment because the
    # 816-tcc code for `pad |= KEY_RIGHT` did not reach the physics in testing.
    with open(f"{OUT}/src/main.c") as f:
        demo = f.read()
    demo = demo.replace("int main(void)\n{\n    unsigned short pad, pressed, oldpad = 0;",
        "static unsigned short dbgframe;\nint main(void)\n{\n    unsigned short pad, pressed, oldpad = 0;")
    demo = demo.replace(
        "        pad = padsCurrent(0);\n",
        "        dbgframe++;\n        pad = padsCurrent(0) | KEY_RIGHT;\n"
        "        if (dbgframe >= 120 && dbgframe < 126) pad = KEY_RIGHT | KEY_A;\n")
    with open(f"{OUT}/src/main.c", "w") as f:
        f.write(demo)

with open(f"{OUT}/Makefile", "w") as f:
    f.write(makefile)

print("generated", OUT)
print("used tiles", len(used_tiles), "pieces", len(pieces), "frames", len(frame_defs), "max pieces", MAX_PIECES)
print("bg tiles", len(bg_tiles), "pages", len(bg_pages_bytes), "groups", len(page_groups), "obj", len(obj_tiles))
