@tool
extends RefCounted
## Import a Mega Drive level (Sonic 2 disassembly format) as a RetroStage.
##
## The Sonic 2 disassembly stores the level data as Kosinski-compressed
## streams plus uncompressed palette files:
##   level/layout/<ZONE>_<act>.kos   128x16 chunk layout (FG rows at +$100)
##   mappings/128x128/<ZONE>.kos    chunk -> 8x8 block map (16x16 px blocks)
##   mappings/16x16/<ZONE>.kos      block -> 2x2 tiles (8x8 px tiles)
##   art/kosinski/<ZONE>.kos        tile graphics (packed 4bpp)
##   art/palettes/<ZONE>.bin        Mega Drive palette lines
##
## The importer preserves the original tile indices, palette line selection
## and flips; only the colour depth (9-bit Mega Drive -> 15-bit SNES) changes.

const TILES_X := 16
const TILE_BYTES := 32
const LEVEL_CHUNKS_W := 128
const LEVEL_CHUNKS_H := 16
const CHUNK_BYTES := 128

const ZONES := {
	"EHZ": {"art": "EHZ_HTZ", "blocks": "EHZ", "chunks": "EHZ_HTZ", "palette": "EHZ", "label": "Emerald Hill Zone"},
	"MTZ": {"art": "MTZ", "blocks": "MTZ", "chunks": "MTZ", "palette": "MTZ", "label": "Metropolis Zone"},
	"ARZ": {"art": "ARZ", "blocks": "ARZ", "chunks": "ARZ", "palette": "ARZ", "label": "Aquatic Ruin Zone"},
	"CNZ": {"art": "CNZ", "blocks": "CNZ", "chunks": "CNZ", "palette": "CNZ", "label": "Casino Night Zone"},
	"CPZ": {"art": "CPZ_DEZ", "blocks": "CPZ_DEZ", "chunks": "CPZ_DEZ", "palette": "CPZ", "label": "Chemical Plant Zone"},
	"OOZ": {"art": "OOZ", "blocks": "OOZ", "chunks": "OOZ", "palette": "OOZ", "label": "Oil Ocean Zone"},
	"MCZ": {"art": "MCZ", "blocks": "MCZ", "chunks": "MCZ", "palette": "MCZ", "label": "Mystic Cave Zone"},
	"WFZ": {"art": "WFZ_SCZ", "blocks": "WFZ_SCZ", "chunks": "WFZ_SCZ", "palette": "WFZ", "label": "Wing Fortress Zone"},
	"SCZ": {"art": "WFZ_SCZ", "blocks": "WFZ_SCZ", "chunks": "WFZ_SCZ", "palette": "SCZ", "label": "Sky Chase Zone"},
	"DEZ": {"art": "CPZ_DEZ", "blocks": "CPZ_DEZ", "chunks": "CPZ_DEZ", "palette": "DEZ", "label": "Death Egg Zone"},
}

## Returns true when the project looks like the Sonic 2 disassembly.
static func detects(project: RetroProject) -> bool:
	if project == null or project.get_platform() != "megadrive":
		return false
	return FileAccess.file_exists(project.resolve("level/layout/EHZ_1.kos")) \
		and FileAccess.file_exists(project.resolve("mappings/128x128/EHZ_HTZ.kos")) \
		and FileAccess.file_exists(project.resolve("art/kosinski/EHZ_HTZ.kos"))

## Builds a RetroStage from the first level of a Sonic 2 disassembly.
## Returns null when the project is not a supported Sonic 2 source.
static func build(project: RetroProject, zone := "EHZ", act := 1) -> RetroStage:
	if not detects(project):
		return null
	if not ZONES.has(zone):
		zone = "EHZ"
	var cfg: Dictionary = ZONES[zone]
	var layout_path := _first_existing(project, [
		"level/layout/%s_%d.kos" % [zone, act],
		"level/layout/%s.kos" % zone,
	])
	var chunks_path := project.resolve("mappings/128x128/%s.kos" % String(cfg["chunks"]))
	var blocks_path := project.resolve("mappings/16x16/%s.kos" % String(cfg["blocks"]))
	var art_path := project.resolve("art/kosinski/%s.kos" % String(cfg["art"]))
	var palette_path := project.resolve("art/palettes/%s.bin" % String(cfg["palette"]))
	for path in [layout_path, chunks_path, blocks_path, art_path, palette_path]:
		if path.is_empty() or not FileAccess.file_exists(path):
			return null
	var layout := _kosinski(FileAccess.get_file_as_bytes(layout_path))
	var chunks := _kosinski(FileAccess.get_file_as_bytes(chunks_path))
	var blocks := _kosinski(FileAccess.get_file_as_bytes(blocks_path))
	var tiles := _kosinski(FileAccess.get_file_as_bytes(art_path))
	var raw_palette := FileAccess.get_file_as_bytes(palette_path)
	if layout.size() < LEVEL_CHUNKS_H * 0x100:
		return null
	if chunks.size() < CHUNK_BYTES or blocks.size() < 8 or tiles.size() < TILE_BYTES:
		return null

	var tile_count := tiles.size() / TILE_BYTES
	var palette := _build_palette(project, raw_palette)

	# Crop the part of the level that the camera shows when the act starts.
	# The Mega Drive camera keeps the player 0x60 px below the top edge.
	var start := _start_position(project, zone, act)
	var crop_w := 32
	var crop_h := 28
	var cam_x := clampi(int(start.x) - 128, 0, LEVEL_CHUNKS_W * 16 * 8 - crop_w * 8)
	var cam_y := clampi(int(start.y) - 0x60, 0, LEVEL_CHUNKS_H * 16 * 8 - crop_h * 8)
	var tile_x0 := clampi(cam_x / 8, 0, LEVEL_CHUNKS_W * 16 - crop_w)
	var tile_y0 := clampi(cam_y / 8, 0, LEVEL_CHUNKS_H * 16 - crop_h)

	var stage := RetroStage.new()
	stage.set_name("Sonic 2 - %s Act %d" % [String(cfg.get("label", zone)), act])
	stage.set_platform("megadrive")
	stage.set_mode("h40")
	stage.set_bpp(4)
	stage.set_tile_size(8)
	stage.set_tiles_x(TILES_X)
	stage.set_column_major(false)
	stage.set_palette(palette)
	stage.set_map_size(Vector2i(crop_w, crop_h))
	var map := PackedByteArray()
	map.resize(crop_w * crop_h * 2)
	stage.set_map(map)

	for ty in range(crop_h):
		for tx in range(crop_w):
			var info := _tile_info(layout, chunks, blocks, tile_x0 + tx, tile_y0 + ty)
			var tile := int(info.get("tile", 0))
			if tile >= tile_count:
				tile = 0
			stage.set_tile(tx, ty, tile, int(info.get("palette", 0)),
				int(info.get("hflip", 0)), int(info.get("vflip", 0)), int(info.get("priority", 0)))

	var indices := Image.create_empty(TILES_X * 8, ceili(float(tile_count) / TILES_X) * 8, false, Image.FORMAT_R8)
	indices.fill(Color(0, 0, 0, 1))
	var preview := Image.create_empty(indices.get_width(), indices.get_height(), false, Image.FORMAT_RGBA8)
	preview.fill(Color(0, 0, 0, 0))
	var preview_base := 16 * 2 # palette line used by the terrain
	for t in range(tile_count):
		var tx := (t % TILES_X) * 8
		var ty := (t / TILES_X) * 8
		for py in range(8):
			for px in range(8):
				var idx := _tile_pixel(tiles, t, px, py)
				indices.set_pixel(tx + px, ty + py, Color8(idx, 0, 0))
				if idx != 0 and preview_base + idx < palette.size():
					preview.set_pixel(tx + px, ty + py, palette[preview_base + idx])
	stage.set_tileset(preview)
	stage.set_tile_indices(indices)
	stage.set_camera_limits({"x": 0, "y": 0, "w": LEVEL_CHUNKS_W * 16 * 8, "h": LEVEL_CHUNKS_H * 16 * 8})
	stage.set_metadata({
		"source": "sonic2_disassembly",
		"zone": zone,
		"act": act,
		"layout": layout_path,
		"tile_count": tile_count,
		"crop_x": tile_x0,
		"crop_y": tile_y0,
		"crop_w": crop_w,
		"crop_h": crop_h,
	})
	return stage

static func _first_existing(project: RetroProject, candidates: Array) -> String:
	for rel in candidates:
		var path := project.resolve(String(rel))
		if FileAccess.file_exists(path):
			return path
	return ""

static func _start_position(project: RetroProject, zone: String, act: int) -> Vector2i:
	for rel in ["startpos/%s_%d.bin" % [zone, act], "startpos/%s.bin" % zone]:
		var path := project.resolve(rel)
		if FileAccess.file_exists(path):
			var data := FileAccess.get_file_as_bytes(path)
			if data.size() >= 4:
				return Vector2i((data[0] << 8) | data[1], (data[2] << 8) | data[3])
	return Vector2i(128, 0x60)

static func _build_palette(project: RetroProject, raw: PackedByteArray) -> PackedColorArray:
	var line0: Array = []
	var base := project.resolve("art/palettes/SonicAndTails.bin")
	if FileAccess.file_exists(base):
		line0 = _md_palette(FileAccess.get_file_as_bytes(base), 16)
	var level := _md_palette(raw, 48)
	# Palette line 0 is the sprite/backdrop palette in the original game. The
	# backdrop colour (index 0) is what shows through transparent BG pixels.
	var out: PackedColorArray = []
	for i in range(16):
		var color := Color(0, 0, 0)
		if i < line0.size() and line0[i] is Color:
			color = line0[i]
		if i == 0 and not level.is_empty():
			color = level[0]
		out.push_back(color)
	for i in range(48):
		out.push_back(level[i] if i < level.size() else Color(0, 0, 0))
	return out

static func _md_palette(data: PackedByteArray, max_colors: int) -> Array:
	var out: Array = []
	var count := mini(data.size() / 2, max_colors)
	for i in range(count):
		var word := (data[i * 2] << 8) | data[i * 2 + 1]
		var r := (word >> 1) & 0x7
		var g := (word >> 5) & 0x7
		var b := (word >> 9) & 0x7
		out.append(Color8((r << 5) | (r << 2) | (r >> 1),
			(g << 5) | (g << 2) | (g >> 1),
			(b << 5) | (b << 2) | (b >> 1)))
	return out

static func _tile_pixel(tiles: PackedByteArray, tile: int, x: int, y: int) -> int:
	var off := tile * TILE_BYTES + y * 4 + (x / 2)
	var byte := tiles[off]
	return (byte >> (0 if (x & 1) else 4)) & 0x0F

## Resolves one 8x8 tile entry (tile index, palette, flips, priority).
static func _tile_info(layout: PackedByteArray, chunks: PackedByteArray,
		blocks: PackedByteArray, tx: int, ty: int) -> Dictionary:
	var cx := tx / 16
	var cy := ty / 16
	if cx < 0 or cy < 0 or cx >= LEVEL_CHUNKS_W or cy >= LEVEL_CHUNKS_H:
		return {}
	var chunk := layout[cy * 0x100 + cx]
	var chunk_off := chunk * CHUNK_BYTES
	if chunk_off + CHUNK_BYTES > chunks.size():
		return {}
	var bx := (tx % 16) / 2
	var by := (ty % 16) / 2
	var chunk_word := (chunks[chunk_off + (by * 8 + bx) * 2] << 8) | chunks[chunk_off + (by * 8 + bx) * 2 + 1]
	var block := chunk_word & 0x3FF
	var flip_x := (chunk_word >> 10) & 1
	var flip_y := (chunk_word >> 11) & 1
	var block_off := block * 8
	if block_off + 8 > blocks.size():
		# Sonic 2 shares one chunk map between zones; ids beyond the current
		# zone's 16x16 map are empty space.
		return {}
	var qx := (tx & 1) ^ flip_x
	var qy := (ty & 1) ^ flip_y
	var word_off := block_off + (qy * 2 + qx) * 2
	var word := (blocks[word_off] << 8) | blocks[word_off + 1]
	return {
		"tile": word & 0x7FF,
		"palette": (word >> 13) & 3,
		"hflip": ((word >> 11) & 1) ^ flip_x,
		"vflip": ((word >> 12) & 1) ^ flip_y,
		"priority": (word >> 15) & 1,
	}

## Kosinski decompressor (Sonic 2 variant). Uses the same bit/offset rules as
## the game's KosDec routine.
static func _kosinski(data: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	if data.size() < 4:
		return out
	# Description fields are 16-bit words read little-endian and consumed from
	# the LSB. The original routine fetches the next field as soon as the
	# sixteenth bit is consumed, *before* reading the payload bytes of the
	# current instruction; keeping that order is required for correct data.
	var st := {"pos": 2, "bits": 15, "field": data[0] | (data[1] << 8)}
	var get_bit := func() -> int:
		var bit := int(st["field"]) & 1
		st["field"] = int(st["field"]) >> 1
		st["bits"] = int(st["bits"]) - 1
		if int(st["bits"]) < 0:
			var p := int(st["pos"])
			st["field"] = (data[p] | (data[p + 1] << 8)) if p + 1 < data.size() else 0
			st["pos"] = p + 2
			st["bits"] = 15
		return bit
	while true:
		if out.size() > 0x800000 or int(st["pos"]) > data.size() + 8:
			break
		var bit: int = get_bit.call()
		if bit:
			var p := int(st["pos"])
			if p >= data.size():
				break
			out.append(data[p])
			st["pos"] = p + 1
			continue
		# Match. The next bit selects the extended (separate) encoding.
		var separate: int = get_bit.call()
		var offset := 0
		var count := 0
		if separate:
			var p := int(st["pos"])
			if p + 1 >= data.size():
				break
			var low := data[p]
			var high := data[p + 1]
			st["pos"] = p + 2
			offset = ((high & 0xF8) << 5 | low) - 0x2000
			count = high & 7
			if count:
				count += 2
			else:
				p = int(st["pos"])
				if p >= data.size():
					break
				var extra := data[p]
				st["pos"] = p + 1
				if extra == 0:
					break
				if extra == 1:
					continue
				count = extra + 1
		else:
			# Inline copy: two bits for the count, one byte for the offset.
			count = ((get_bit.call() << 1) | get_bit.call()) + 2
			var p := int(st["pos"])
			if p >= data.size():
				break
			var low := data[p]
			st["pos"] = p + 1
			offset = (low - 256) if low else -256
		var src := out.size() + offset
		if src < 0:
			break
		for i in range(count):
			out.append(out[src + i])
	return out
