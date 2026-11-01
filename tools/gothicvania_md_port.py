#!/usr/bin/env python3
"""Gothicvania (PVSnesLib/SNES) -> SGDK/Mega Drive source-level port.

The original game is a compact C homebrew: one 4800x224 graveyard level, a
64x64 hero, three enemies, a title/end/game-over state machine and SNESMOD
music.  A binary SNES translation is impossible, so this adapter converts the
original art/level/collision data and rebuilds the game logic in C for SGDK.

Outputs a standalone SGDK project with:
  - one composited BG_A level (ground + decorations) streamed as 32x32 pages;
  - the original bg.png night scene as BG_B (moon/clouds/mountains);
  - hero/enemy frames as Mega Drive 4bpp sprite bands;
  - the original collision map and spawn table;
  - MIDI -> VGM music (Baroque/Title) and small PCM SFX;
  - title, play, end and game-over states.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
TEMPLATE_DIR = ROOT / "gothicvania_md"

# Collision is 300x14 16x16 cells; the rendered layers are 600x28 8x8 tiles.
LEVEL_COLS = 300
LEVEL_ROWS = 14
TILE_COLS = 600
TILE_ROWS = 28
LEVEL_PAGES = 19
PAGE_W = 32
PAGE_H = 32
PAGE_TILES = 288

# VRAM tile plan (64x32 planes: BG_B at 0xC000, BG_A at 0xE000).
VRAM_FONT = 0
VRAM_LEVEL0 = 128
VRAM_LEVEL1 = VRAM_LEVEL0 + PAGE_TILES
VRAM_BG = VRAM_LEVEL1 + PAGE_TILES
VRAM_HERO = VRAM_BG + 384
VRAM_ENEMY0 = VRAM_HERO + 128
VRAM_ENEMY1 = VRAM_ENEMY0 + 128

PAL_LEVEL = 0
PAL_BG = 1
PAL_HERO = 2
PAL_ENEMY = 3


def _load_audio_tool():
    for path in (
        ROOT / "retro_audio_tool.py",
        ROOT.parent / "ide/addons/retro_engine/tools/retro_audio_tool.py",
        Path.home() / ".local/share/godot-retro-engine/ide/addons/retro_engine/tools/retro_audio_tool.py",
    ):
        if path.is_file():
            spec = importlib.util.spec_from_file_location("retro_audio_tool", path)
            mod = importlib.util.module_from_spec(spec)
            sys.modules["retro_audio_tool"] = mod
            spec.loader.exec_module(mod)
            return mod
    raise RuntimeError("retro_audio_tool.py not found")


def md_color(rgb) -> int:
    r, g, b = rgb
    r = max(0, min(7, int(round(r * 7 / 255))))
    g = max(0, min(7, int(round(g * 7 / 255))))
    b = max(0, min(7, int(round(b * 7 / 255))))
    return (r << 1) | (g << 5) | (b << 9)


def _palette_rgb(im: Image.Image):
    raw = im.getpalette() or []
    return [tuple(raw[i * 3:i * 3 + 3]) for i in range(16)]


def _enc_md_tile(cell) -> bytes:
    """8x8 palette indexes (0..15) -> Mega Drive 4bpp packed tile (32 bytes).

    Genesis VRAM tiles pack two 4-bit pixels per byte (high nibble first),
    unlike the SNES planar format.
    """
    out = bytearray(32)
    for y in range(8):
        for x in range(0, 8, 2):
            out[y * 4 + x // 2] = ((int(cell[y][x]) & 0xF) << 4) | (int(cell[y][x + 1]) & 0xF)
    return bytes(out)


def _flip_entry(cell, tile_index):
    """Return (canonical tile, hflip, vflip) for a 2D tuple tile."""
    orbit = [
        cell,
        tuple(tuple(row[::-1]) for row in cell),
        tuple(tuple(reversed(cell))),
        tuple(tuple(row[::-1]) for row in reversed(cell)),
    ]
    keys = [tuple(v for row in t for v in row) for t in orbit]
    best = min(range(4), key=lambda i: keys[i])
    return orbit[best], bool(best in (1, 3)), bool(best in (2, 3))


class TileBank:
    def __init__(self):
        self.tiles = [tuple(tuple(0 for _ in range(8)) for _ in range(8))]
        self.map = {}
        self.map[tuple(v for row in self.tiles[0] for v in row)] = 0

    def index(self, cell):
        # Exact dedup only.  Keeping H/V mirrored variants as real tiles
        # avoids relying on VDP flip bits for streamed page maps (and still
        # fits: the largest page has 276 unique tiles, slot size is 288).
        key = tuple(v for row in cell for v in row)
        if key not in self.map:
            self.map[key] = len(self.tiles)
            self.tiles.append(cell)
        return self.map[key], False, False

    def data(self):
        return b"".join(_enc_md_tile(t) for t in self.tiles)


def _load_layer(root: Path, tag: str):
    im = Image.open(root / "res/level" / f"{tag}_tileset.png")
    pal = _palette_rgb(im)
    tiles = []
    for ty in range(im.height // 8):
        for tx in range(im.width // 8):
            tiles.append(im.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8)))
    pages = (root / "res/level" / f"{tag}_pagesA.bin").read_bytes()
    pages += (root / "res/level" / f"{tag}_pagesB.bin").read_bytes()
    entries = struct.unpack("<%dH" % (len(pages) // 2), pages)
    return tiles, entries, pal


def build_level(root: Path, out: Path):
    gt, ge, gc = _load_layer(root, "ground")
    dt, de, dc = _load_layer(root, "deco")

    # Composite ground over decorations, exactly like the SNES BG0/BG1 priority.
    rgba = Image.new("RGBA", (TILE_COLS * 8, TILE_ROWS * 8), (0, 0, 0, 0))
    px = rgba.load()
    for y in range(TILE_ROWS):
        for x in range(TILE_COLS):
            # The committed SNES pages are 19 separate 32x32 row-major
            # pages, not one 600-wide row-major array.
            page = x // PAGE_W
            pi = page * (PAGE_W * PAGE_H) + y * PAGE_W + (x % PAGE_W)
            gei = ge[pi] if pi < len(ge) else 0
            dei = de[pi] if pi < len(de) else 0
            gcell = [[0] * 8 for _ in range(8)]
            dcell = [[0] * 8 for _ in range(8)]
            if gei & 0x3FF:
                t = gt[gei & 0x3FF]
                if (gei >> 14) & 1:
                    t = t.transpose(Image.FLIP_LEFT_RIGHT)
                if (gei >> 15) & 1:
                    t = t.transpose(Image.FLIP_TOP_BOTTOM)
                gcell = [[t.getpixel((xx, yy)) for xx in range(8)] for yy in range(8)]
            if dei & 0x3FF:
                t = dt[dei & 0x3FF]
                if (dei >> 14) & 1:
                    t = t.transpose(Image.FLIP_LEFT_RIGHT)
                if (dei >> 15) & 1:
                    t = t.transpose(Image.FLIP_TOP_BOTTOM)
                dcell = [[t.getpixel((xx, yy)) for xx in range(8)] for yy in range(8)]
            for yy in range(8):
                for xx in range(8):
                    gi = gcell[yy][xx]
                    di = dcell[yy][xx]
                    if gi:
                        r, g, b = gc[gi]
                        px[x * 8 + xx, y * 8 + yy] = (r, g, b, 255)
                    elif di:
                        r, g, b = dc[di]
                        px[x * 8 + xx, y * 8 + yy] = (r, g, b, 255)

    # 15 visible colours + transparent index 0.  The source layers together use
    # 20 colours; a single Mega Drive BG palette has 15 usable entries.
    rgb = rgba.convert("RGB")
    q = rgb.quantize(colors=15, method=Image.MEDIANCUT, dither=Image.NONE)
    qpal = q.getpalette() or []
    level_colors = [tuple(qpal[i * 3:i * 3 + 3]) for i in range(15)]
    qpx = q.load()
    alpha = rgba.load()

    index_img = [[0] * (TILE_COLS * 8) for _ in range(TILE_ROWS * 8)]
    for y in range(TILE_ROWS * 8):
        for x in range(TILE_COLS * 8):
            if alpha[x, y][3]:
                index_img[y][x] = (qpx[x, y] % 15) + 1

    # Emit one 256x224 indexed image per page.  ResComp converts these to a
    # Tileset + Tilemap, which is the exact path the engine already validated
    # for SNES image export (and avoids hand-rolled map/flip encoding).
    level_png_palette = [0, 0, 0]
    for c in level_colors:
        level_png_palette.extend(c)
    level_png_palette += [0] * (768 - len(level_png_palette))
    for page in range(LEVEL_PAGES):
        img = Image.new("P", (256, 224), 0)
        img.putpalette(level_png_palette)
        x0 = page * PAGE_W
        for y in range(224):
            for x in range(256):
                gx = x0 + x // 8
                if gx < TILE_COLS:
                    img.putpixel((x, y), index_img[y][gx * 8 + (x % 8)])
        img.save(out / f"page{page:02d}.png")

    palette = [md_color((0, 0, 0))] + [md_color(c) for c in level_colors]
    palette += [0] * (16 - len(palette))
    (out / "level_pal.bin").write_bytes(struct.pack(">16H", *palette))

    # Collision is already 300x14 (0 empty, 1 solid, 2 one-way platform).
    collision = (root / "res/level/collision.bin").read_bytes()
    if len(collision) != LEVEL_COLS * LEVEL_ROWS:
        raise RuntimeError("unexpected collision size: %d" % len(collision))
    (out / "level_collision.bin").write_bytes(collision)

    print("level: %d page images, %d composite colours"
          % (LEVEL_PAGES, len(level_colors) + 1))


def build_background(root: Path, out: Path):
    im = Image.open(root / "res/bg.png").convert("P")
    pal = _palette_rgb(im)
    bank = TileBank()
    entries = [0] * (32 * 32)
    for ty in range(32):
        for tx in range(32):
            cell = tuple(tuple(im.getpixel((tx * 8 + xx, ty * 8 + yy)) for xx in range(8))
                         for yy in range(8))
            if not any(any(row) for row in cell):
                continue
            idx, hf, vf = bank.index(cell)
            entries[ty * 32 + tx] = idx | (0x800 if hf else 0) | (0x1000 if vf else 0)
    # A 64x32 plane is two copies of the 256px-wide scene, so BG_B can wrap.
    wide = []
    for y in range(32):
        row = entries[y * 32:(y + 1) * 32]
        wide.extend(row)
        wide.extend(row)
    (out / "bg_tiles.bin").write_bytes(bank.data())
    (out / "bg_map.bin").write_bytes(struct.pack(">%dH" % len(wide), *wide))
    palette = [md_color(c) for c in pal[:16]]
    (out / "bg_pal.bin").write_bytes(struct.pack(">16H", *palette))
    print("background: %d tiles, %d map entries" % (len(bank.tiles), len(wide)))


def _nearest(color, palette):
    r, g, b = color
    best = 0
    best_d = 1 << 30
    for i, (pr, pg, pb) in enumerate(palette):
        d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if d < best_d:
            best_d = d
            best = i
    return best


def _sheet_frames(im: Image.Image, frame_w: int, frame_h: int):
    for f in range(im.height // frame_h):
        yield im.crop((0, f * frame_h, frame_w, (f + 1) * frame_h))


def _frame_md_data(frame: Image.Image, color_map, out_palette):
    """128x64 indexed frame -> 8 contiguous 32x32 quadrants (4096 bytes)."""
    data = bytearray()
    for qy in range(2):
        for qx in range(4):
            # Mega Drive sprites read their tiles top-to-bottom first, then
            # left-to-right, so each 32x32 quadrant is column-major.
            for tx in range(4):
                for ty in range(4):
                    cell = [[0] * 8 for _ in range(8)]
                    for yy in range(8):
                        for xx in range(8):
                            src = frame.getpixel((qx * 32 + tx * 8 + xx,
                                                  qy * 32 + ty * 8 + yy))
                            if src:
                                cell[yy][xx] = color_map[src]
                    data += _enc_md_tile(cell)
    return bytes(data)


def _palette_for_sheet(im: Image.Image):
    pal = _palette_rgb(im)
    used = []
    for v in im.getdata():
        if v and pal[v] not in used:
            used.append(pal[v])
    if len(used) <= 15:
        colors = used
        mapping = {i + 1: i + 1 for i in range(len(pal))}
        # actual source-index -> output-index map
        mapping = {}
        for idx, c in enumerate(pal):
            if c in colors:
                mapping[idx] = colors.index(c) + 1
    else:
        tmp = Image.new("RGB", (len(used), 1))
        tmp.putdata(used)
        q = tmp.quantize(colors=15, method=Image.MEDIANCUT)
        qp = q.getpalette() or []
        colors = [tuple(qp[i * 3:i * 3 + 3]) for i in range(15)]
        mapping = {idx: _nearest(c, colors) + 1 for idx, c in enumerate(pal) if c in used}
    return colors, mapping


def build_sprites(root: Path, out: Path):
    hero = Image.open(root / "res/hero.png").convert("P")
    colors, cmap = _palette_for_sheet(hero)
    frames = b"".join(_frame_md_data(f, cmap, colors) for f in _sheet_frames(hero, 128, 64))
    (out / "hero_frames.bin").write_bytes(frames)
    pal = [0] + [md_color(c) for c in colors]
    pal += [0] * (16 - len(pal))
    (out / "hero_pal.bin").write_bytes(struct.pack(">16H", *pal))

    # All three enemies share OBJ palette 3.  Their source palettes overlap a
    # lot; quantise the union to the 15 available entries.
    sheets = []
    union = []
    for name in ("skeleton", "gato", "ghost"):
        im = Image.open(root / f"res/{name}.png").convert("P")
        sheets.append(im)
        sp = _palette_rgb(im)
        for v in im.getdata():
            if v and sp[v] not in union:
                union.append(sp[v])
    if len(union) <= 15:
        ecolors = union
    else:
        tmp = Image.new("RGB", (len(union), 1))
        tmp.putdata(union)
        q = tmp.quantize(colors=15, method=Image.MEDIANCUT)
        qp = q.getpalette() or []
        ecolors = [tuple(qp[i * 3:i * 3 + 3]) for i in range(15)]
    epal = [0] + [md_color(c) for c in ecolors]
    epal += [0] * (16 - len(epal))
    (out / "enemy_pal.bin").write_bytes(struct.pack(">16H", *epal))

    enemy_blob = bytearray()
    for im in sheets:
        sp = _palette_rgb(im)
        cmap = {idx: _nearest(c, ecolors) + 1 for idx, c in enumerate(sp) if c in union}
        for f in _sheet_frames(im, 128, 64):
            enemy_blob += _frame_md_data(f, cmap, ecolors)
    (out / "enemy_frames.bin").write_bytes(enemy_blob)
    # Simple readable palette for the title/end text overlays.
    # SGDK's default font glyphs use palette index 15 for the ink.
    text = [0] * 13 + [md_color((190, 190, 190)),
                       md_color((255, 220, 80)), md_color((255, 255, 255))]
    (out / "text_pal.bin").write_bytes(struct.pack(">16H", *text))
    print("sprites: hero 21 frames, enemies 19+4+4 frames, %d enemy colours"
          % len(ecolors))


def build_audio(root: Path, out: Path):
    audio = _load_audio_tool()
    for src_name, out_name in (("Title.mid", "title"), ("Baroque.mid", "baroque")):
        src = root / "assets" / src_name
        if not src.is_file():
            raise RuntimeError("missing MIDI: %s" % src)
        _, events = audio.read_midi_events(str(src))
        audio.write_vgm_from_events(str(out / f"{out_name}.vgm"), events, out_name)

    sfx = {
        "jump": {"waveform": "square", "frequency": 420.0, "duration_ms": 130.0,
                 "volume": 0.65, "duty": 0.5, "attack_ms": 1.0, "decay_ms": 25.0,
                 "sustain": 0.55, "release_ms": 50.0, "pitch_slide": 18.0,
                 "vibrato_hz": 0.0, "vibrato_depth": 0.0, "noise": 0.0, "bitcrush": 16},
        "attack": {"waveform": "square", "frequency": 900.0, "duration_ms": 90.0,
                   "volume": 0.6, "duty": 0.25, "attack_ms": 1.0, "decay_ms": 20.0,
                   "sustain": 0.2, "release_ms": 40.0, "pitch_slide": -30.0,
                   "vibrato_hz": 0.0, "vibrato_depth": 0.0, "noise": 0.35, "bitcrush": 16},
        "hurt": {"waveform": "saw", "frequency": 520.0, "duration_ms": 180.0,
                 "volume": 0.7, "duty": 0.5, "attack_ms": 1.0, "decay_ms": 45.0,
                 "sustain": 0.4, "release_ms": 90.0, "pitch_slide": -22.0,
                 "vibrato_hz": 0.0, "vibrato_depth": 0.0, "noise": 0.0, "bitcrush": 16},
        "kill": {"waveform": "noise", "frequency": 300.0, "duration_ms": 160.0,
                 "volume": 0.65, "duty": 0.5, "attack_ms": 1.0, "decay_ms": 40.0,
                 "sustain": 0.2, "release_ms": 70.0, "pitch_slide": -12.0,
                 "vibrato_hz": 0.0, "vibrato_depth": 0.0, "noise": 0.8, "bitcrush": 12},
        "rise": {"waveform": "square", "frequency": 120.0, "duration_ms": 220.0,
                 "volume": 0.55, "duty": 0.5, "attack_ms": 2.0, "decay_ms": 30.0,
                 "sustain": 0.5, "release_ms": 80.0, "pitch_slide": 24.0,
                 "vibrato_hz": 0.0, "vibrato_depth": 0.0, "noise": 0.25, "bitcrush": 12},
    }
    for name, params in sfx.items():
        audio.synthesize_sfx(params, str(out / f"sfx_{name}.wav"), 16000)
    print("audio: title.vgm, baroque.vgm, %d PCM SFX" % len(sfx))


def write_project(root: Path, out: Path, name: str, audio_ok: bool):
    (out / "src").mkdir(parents=True, exist_ok=True)
    (out / "res").mkdir(parents=True, exist_ok=True)
    src = (TEMPLATE_DIR / "main.c").read_text(encoding="utf-8")
    (out / "src/main.c").write_text(src, encoding="utf-8")
    overlay = TEMPLATE_DIR / "title_overlay.png"
    if overlay.is_file():
        (out / "res/title_overlay.png").write_bytes(overlay.read_bytes())
        tpal = [md_color((0, 0, 0)), md_color((208, 24, 24)),
                md_color((56, 0, 128)), md_color((248, 204, 64))]
        tpal += [0] * (16 - len(tpal))
        (out / "res/title_pal.bin").write_bytes(struct.pack(">16H", *tpal))

    res = ["NEAR"]
    for entry in (
        "level_pal", "bg_tiles", "bg_map", "bg_pal", "hero_frames", "hero_pal",
        "enemy_frames", "enemy_pal", "text_pal", "level_collision",
    ):
        align = " 2" if entry.endswith(("pal", "info", "maps", "map", "collision")) else ""
        res.append(f'BIN {entry} "{entry}.bin"{align}')
    res.append('BIN title_pal "title_pal.bin" 2')
    res.append('IMAGE title_overlay "title_overlay.png" NONE')
    for page in range(LEVEL_PAGES):
        res.append(f'IMAGE page{page:02d} "page{page:02d}.png" NONE')
    if audio_ok:
        res += [
            'XGM2 title "title.vgm"',
            'XGM2 baroque "baroque.vgm"',
        ]
        for sfx in ("jump", "attack", "hurt", "kill", "rise"):
            res.append(f'WAV sfx_{sfx} "sfx_{sfx}.wav" XGM2')
    (out / "res/assets.res").write_text("\n".join(res) + "\n", encoding="utf-8")

    makefile = """ifndef GDK
$(error Set GDK to the SGDK root)
endif
include $(GDK)/makefile.gen

# The wine-based Linux toolchain cannot resolve the bare -lgcc; point the
# linker at the SDK's own libgcc.a (must be set after common.mk).
LIBGCC := $(GDK)/lib/libgcc.a

padROM: $(OUT)/rom.bin
\t$(SIZEBND) $(OUT)/rom.bin -sizealign 524288 -checksum
"""
    (out / "Makefile").write_text(makefile, encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("output")
    ap.add_argument("--name", default="gothicvania_md")
    ap.add_argument("--no-audio", action="store_true")
    args = ap.parse_args()
    root = Path(args.source)
    out = Path(args.output)
    res = out / "res"
    out.mkdir(parents=True, exist_ok=True)
    res.mkdir(parents=True, exist_ok=True)
    if not (root / "src/play.c").is_file():
        raise SystemExit("not a Gothicvania source project: %s" % root)
    build_level(root, res)
    build_background(root, res)
    build_sprites(root, res)
    audio_ok = False
    if not args.no_audio:
        try:
            build_audio(root, res)
            audio_ok = True
        except Exception as exc:
            print("warning: audio conversion skipped: %s" % exc, file=sys.stderr)
    write_project(root, out, args.name, audio_ok)
    print("generated %s" % out)


if __name__ == "__main__":
    main()
