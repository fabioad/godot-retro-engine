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
import struct
import sys
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else "/run/media/fabio/Dados/Fabio/sgdk-test-projects/s2disasm"
OUT = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("-") else "/tmp/opencode/sonic_port"
DEMO = "--demo" in sys.argv

# Playable slice: 64x64 tiles = 512x512 px, starting at world (0, 512).
SLICE_X = 0
SLICE_Y = 0
SLICE_W = 1332
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
HUD_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ:- "

def font_tile(rows):
    out = bytearray(32)
    for y in range(8):
        for x in range(8):
            on = 1 if (1 <= x <= 5 and y < 7 and rows[y][x - 1] == '1') else 0
            for p in range(4):
                pair = p // 2
                off = pair * 16 + y * 2 + (p % 2)
                out[off] |= (on & 1) << (7 - x)
    return bytes(out)

hud_tiles = b"".join(font_tile(FONT[c]) for c in HUD_CHARS)
hud_colors = [(0,0,0),(255,255,255),(255,255,0)] + [(0,0,0)] * 13




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
]
for i, group in enumerate(page_groups):
    blobs.append(blob("page%d" % i, "page%d.bin" % i, group))
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

with open(f"{OUT}/src/assets.c", "w") as f:
    f.write(data_c)

# ---------------------------------------------------------------- C code ---
assets_h = """#ifndef ASSETS_H
#define ASSETS_H
#define SLICE_W 1332
#define SLICE_H 128
#define SLICE_X 0
#define SLICE_Y 0
#define PAGES_X 42
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
""" % (len(used_tiles), len(pieces), len(frame_defs), MAX_PIECES, len(page_groups), len(blocks), len(bg_tiles), len(snes_pal_bytes(palette)), len(obj_tiles))
for i in range(len(page_groups)):
    assets_h += "extern const unsigned char page%d[];\n" % i
assets_h += "#define RING_COUNT %d\n#define RING_FRAMES %d\n" % (len(ring_positions), RING_FRAMES)
assets_h += ""
assets_h += "#define HUD_TILES_SIZE %d\n#define HUD_TILE_BASE %d\n" % (len(hud_tiles), len(obj_tiles) // 32 + 32)
assets_h += "extern const unsigned short ring_pos[];\n"
assets_h += "#define RING_TILES_SIZE %d\n#define RING_BASE_TILE %d\n" % (len(ring_tiles), len(obj_tiles) // 32)

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
        facing = 0;
    } else {
        if (inertia > 0) { inertia -= ACCEL; if (inertia < 0) inertia = 0; }
        else if (inertia < 0) { inertia += ACCEL; if (inertia > 0) inertia = 0; }
    }
    vx = inertia;
    vy = 0;
    move_x(vx);
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
    }
}

static const unsigned char *page_arrays[PAGE_GROUP_COUNT] = {
    page0, page1, page2, page3, page4, page5, page6, page7,
    page8, page9, page10, page11, page12, page13, page14, page15,
    page16, page17, page18, page19, page20
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

static unsigned char hud_index(char c)
{
    if (c >= '0' && c <= '9') return (unsigned char)(c - '0');
    if (c >= 'A' && c <= 'Z') return (unsigned char)(10 + (c - 'A'));
    if (c == ':') return 36;
    if (c == '-') return 37;
    return 38;
}

static unsigned char hud_char(unsigned char x, unsigned char y, char c, unsigned char slot)
{
    oamSet((u16)((60 + slot) * 4), (u16)x, (u16)y, 3, 0, 0,
        (u16)(HUD_TILE_BASE + hud_index(c)), 2);
    oamSetEx((u16)((60 + slot) * 4), OBJ_SMALL, OBJ_SHOW);
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
    slot = hud_text(8, 8, "SCORE", slot);
    slot = hud_num(56, 8, score, 6, slot);
    slot = hud_text(8, 16, "TIME", slot);
    slot = hud_num(48, 16, game_time, 3, slot);
    slot = hud_text(8, 24, "RINGS", slot);
    slot = hud_num(56, 24, rings_collected, 3, slot);
    for (; slot < 48; slot++) oamSetEx((u16)((60 + slot) * 4), OBJ_SMALL, OBJ_HIDE);
}

static void draw_sonic(void)
{
    unsigned char idx, i;
    short sx, sy, fw, fh;
    const short *pieces;
    if (grounded) {
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
            default: list = anim_roll; count = ANIM_ROLL_COUNT; break;
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
            oamSet(c * 4, (short)(sx + ox), (short)(sy + dy), 3, facing, 0, tile, 0);
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
    setMode(BG_MODE1, 0);
    bgInitTileSet(0, (u8 *)bg_tiles, (u8 *)bg_pal, 0, BG_TILES_SIZE, BG_PAL_SIZE, BG_16COLORS, 0x1000);
    bgSetMapPtr(0, 0x0000, SC_64x64);
    bgSetGfxPtr(0, 0x1000);
    WaitForVBlank();
    bgSetEnable(0);
    REG_TM = 0x01;

    oamInitGfxSet((u8 *)sonic_tiles, SONIC_TILES_SIZE, (u8 *)sonic_pal, SONIC_PAL_SIZE, 0, 0x4000, OBJ_SIZE8_L16);
    setPalette((u16 *)sonic_pal, 128, SONIC_PAL_SIZE);
    dmaCopyVram((u8 *)(sonic_tiles + SONIC_TILES_SIZE), 0x4000 + SONIC_TILES_SIZE / 2, RING_TILES_SIZE);
    setPalette((u16 *)(sonic_pal + 32), 144, 32);
    dmaCopyVram((u8 *)(sonic_tiles + SONIC_TILES_SIZE + RING_TILES_SIZE), 0x4000 + HUD_TILE_BASE * 16, HUD_TILES_SIZE);
    setPalette((u16 *)(sonic_pal + 64), 160, 32);
    REG_TM = 0x11; /* BG1 + OBJ */

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
    update_camera();
    update_pages();
    setScreenOn();

    while (1) {
        pad = padsCurrent(0);
        pressed = pad & ~oldpad;
        oldpad = pad;
        if (grounded) {
            jump_if_needed(pressed);
            if (jumping && !(pad & (KEY_A | KEY_B | KEY_Y)) && vy < -0x400) vy = -0x400;
        }
        if (grounded) ground_move(pad);
        else air_move(pad);
        if (xpos < 16) { xpos = 16; if (vx < 0) vx = 0; if (inertia < 0) inertia = 0; }
        if (xpos > SLICE_W * 8 - 24) { xpos = SLICE_W * 8 - 24; if (vx > 0) vx = 0; if (inertia > 0) inertia = 0; }
        if (ypos > SLICE_Y + WORLD_H - 16) {
            xpos = 96; ypos = 655; xsub = 0; ysub = 0;
            vx = vy = inertia = 0; grounded = 0; jumping = 0;
        }
        update_camera();
        update_pages();
        bgSetScroll(0, (u16)(cam_x - page_x * 256), (u16)((cam_y - SLICE_Y) - page_y * 256));
        frame_counter++;
        collect_rings();
        draw_rings();
        if ((frame_counter & 7) == 0) draw_hud();
        if (++time_timer >= 60) { time_timer = 0; game_time++; }
        draw_sonic();
        WaitForVBlank();
    }
    return 0;
}
'''

with open(f"{OUT}/src/main.c", "w") as f:
    f.write(main_c)

makefile = """ifeq ($(strip $(PVSNESLIB_HOME)),)
$(error Set PVSNESLIB_HOME to the PVSnesLib root)
endif
export ROMNAME := sonic_port
export ROMTITLE := SONIC PORT
FASTROM := 1
ROMSIZE := 09
ROMBANKS := 16
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
    demo = demo.replace("        pad = padsCurrent(0);\n        pressed = pad & ~oldpad;",
        "        dbgframe++;\n        pad = padsCurrent(0) | KEY_RIGHT;\n"
        "        if (dbgframe >= 120 && dbgframe < 126) pad = KEY_RIGHT | KEY_A;\n"
        "        pressed = pad & ~oldpad;")
    with open(f"{OUT}/src/main.c", "w") as f:
        f.write(demo)

with open(f"{OUT}/Makefile", "w") as f:
    f.write(makefile)

print("generated", OUT)
print("used tiles", len(used_tiles), "pieces", len(pieces), "frames", len(frame_defs), "max pieces", MAX_PIECES)
print("bg tiles", len(bg_tiles), "pages", len(bg_pages_bytes), "groups", len(page_groups), "obj", len(obj_tiles))
