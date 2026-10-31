@tool
extends RefCounted
## Native MUGEN SFF v1/v2 sprite-bank reader.
##
## Supports the payload formats used by real characters/stages: SFF v1 PCX,
## SFF v2 raw/RLE8/RLE5/LZ5 and PNG (formats 10/11/12). Sprites are rendered
## lazily so opening a 30 MB bank does not decode every frame at once.

var path: String = ""
var version: int = 0
var sprites: Array = []
var palettes: Array = []
var _images: Dictionary = {}
var _error: String = ""

func load_file(p_path: String) -> bool:
	path = p_path
	sprites.clear()
	palettes.clear()
	_images.clear()
	_error = ""
	var f := FileAccess.open(p_path, FileAccess.READ)
	if f == null:
		_error = "Cannot open SFF: " + p_path
		return false
	var data := f.get_buffer(f.get_length())
	f.close()
	if data.size() < 32 or data.slice(0, 11).get_string_from_ascii() != "ElecbyteSpr":
		_error = "Not a MUGEN SFF: " + p_path
		return false
	version = data[15]
	if version == 1:
		_parse_v1(data)
	else:
		_parse_v2(data)
	if sprites.is_empty():
		_error = "SFF has no sprites: " + p_path
		return false
	return true

func error_message() -> String:
	return _error

func sprite_count() -> int:
	return sprites.size()

func find(group: int, number: int) -> Dictionary:
	for s in sprites:
		if int(s.get("group", 0)) == group and int(s.get("number", 0)) == number:
			return s
	return {}

func find_index(group: int, number: int) -> int:
	for i in range(sprites.size()):
		var s: Dictionary = sprites[i]
		if int(s.get("group", 0)) == group and int(s.get("number", 0)) == number:
			return i
	return -1

func sprite_at(index: int) -> Dictionary:
	if index < 0 or index >= sprites.size():
		return {}
	return sprites[index]

## Render one sprite to an RGBA image. Linked sprites resolve recursively.
func render(index: int) -> Image:
	if _images.has(index):
		return _images[index]
	if index < 0 or index >= sprites.size():
		return null
	var s: Dictionary = sprites[index]
	var img: Image = null
	if s.get("image", null) is Image:
		img = s["image"]
	elif not s.get("pixels", PackedByteArray()).is_empty():
		var w := int(s.get("width", 0))
		var h := int(s.get("height", 0))
		var pixels: PackedByteArray = s["pixels"]
		var palette: PackedColorArray = s.get("palette", PackedColorArray())
		img = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		for y in range(h):
			for x in range(w):
				var i := y * w + x
				var idx := pixels[i] if i < pixels.size() else 0
				var c := Color(0, 0, 0, 0)
				if idx > 0 and idx < palette.size():
					c = palette[idx]
					c.a = 1.0
				img.set_pixel(x, y, c)
	elif int(s.get("link", -1)) >= 0 and int(s.get("link", -1)) < sprites.size() and int(s.get("link", -1)) != index:
		img = render(int(s["link"]))
	if img != null:
		_images[index] = img
	return img

func groups() -> Dictionary:
	var out: Dictionary = {}
	for s in sprites:
		var g := int(s.get("group", 0))
		if not out.has(g):
			out[g] = []
		out[g].append(int(s.get("number", 0)))
	for g in out.keys():
		out[g].sort()
	return out

# --------------------------------------------------------------------------
# SFF v1
# --------------------------------------------------------------------------
func _parse_v1(data: PackedByteArray) -> void:
	var count := _u32(data, 0x14)
	var offset := _u32(data, 0x18)
	var shared := data[0x24] != 0
	var seen: Dictionary = {}
	var local_palettes: Array = []
	var current_palette := PackedColorArray()
	for i in range(count):
		if offset == 0 or offset >= data.size() or seen.has(offset):
			break
		seen[offset] = true
		var next := _u32(data, offset)
		var size := _u32(data, offset + 4)
		var ax := _s16(data, offset + 8)
		var ay := _s16(data, offset + 10)
		var group := _u16(data, offset + 12)
		var number := _u16(data, offset + 14)
		var link := _u16(data, offset + 16)
		var samepal := data[offset + 18] != 0
		var s: Dictionary = {
			"group": group, "number": number, "axis": Vector2i(ax, ay),
			"width": 0, "height": 0, "link": link, "size": size,
			"pixels": PackedByteArray(), "palette": PackedColorArray(),
			"image": null,
		}
		if size > 0 and offset + 32 + size <= data.size():
			var pcx := data.slice(offset + 32, offset + 32 + size)
			var decoded := _pcx_decode(pcx)
			s["width"] = int(decoded.get("width", 0))
			s["height"] = int(decoded.get("height", 0))
			s["pixels"] = decoded.get("pixels", PackedByteArray())
			var pal: PackedColorArray = decoded.get("palette", PackedColorArray())
			if not samepal or current_palette.is_empty():
				if not pal.is_empty():
					current_palette = pal
					local_palettes.append(pal)
			s["palette"] = current_palette
		elif link < sprites.size():
			var src: Dictionary = sprites[link]
			s["width"] = int(src.get("width", 0))
			s["height"] = int(src.get("height", 0))
			s["pixels"] = src.get("pixels", PackedByteArray())
			s["palette"] = src.get("palette", PackedColorArray())
			s["image"] = src.get("image", null)
		sprites.append(s)
		offset = next
	palettes = local_palettes

# --------------------------------------------------------------------------
# SFF v2
# --------------------------------------------------------------------------
func _parse_v2(data: PackedByteArray) -> void:
	var spr_ofs := _u32(data, 0x24)
	var nspr := _u32(data, 0x28)
	var pal_ofs := _u32(data, 0x2C)
	var npal := _u32(data, 0x30)
	var lofs := _u32(data, 0x34)
	var tofs := _u32(data, 0x3C)
	for i in range(nspr):
		var o := spr_ofs + i * 28
		if o + 28 > data.size():
			break
		var group := _s16(data, o)
		var number := _s16(data, o + 2)
		var w := _u16(data, o + 4)
		var h := _u16(data, o + 6)
		var ax := _s16(data, o + 8)
		var ay := _s16(data, o + 10)
		var link := _u16(data, o + 12)
		var fmt := data[o + 14]
		var depth := data[o + 15]
		var ofs := _u32(data, o + 16)
		var size := _u32(data, o + 20)
		var palidx := _u16(data, o + 24)
		var flags := _u16(data, o + 26)
		var s: Dictionary = {
			"group": group, "number": number, "width": w, "height": h,
			"axis": Vector2i(ax, ay), "link": link, "size": size,
			"format": fmt, "depth": depth, "palette_index": palidx,
			"pixels": PackedByteArray(), "palette": PackedColorArray(),
			"image": null,
		}
		if size > 0:
			var base := tofs if (flags & 1) != 0 else lofs
			var start := base + ofs
			if start + size <= data.size():
				var raw := data.slice(start, start + size)
				match fmt:
					0:
						if depth == 8:
							s["pixels"] = raw.slice(0, mini(w * h, raw.size()))
					2:
						s["pixels"] = _rle8_decode(raw.slice(4), w, h)
					3:
						s["pixels"] = _rle5_decode(raw.slice(4), w, h)
					4:
						s["pixels"] = _lz5_decode(raw.slice(4), w, h)
					10, 11, 12:
						var png := raw.slice(4)
						var img := Image.new()
						if img.load_png_from_buffer(png) == OK:
							img.convert(Image.FORMAT_RGBA8)
							s["image"] = img
							s["width"] = img.get_width()
							s["height"] = img.get_height()
		sprites.append(s)
	# Palettes.
	for i in range(npal):
		var o := pal_ofs + i * 16
		if o + 16 > data.size():
			palettes.append(PackedColorArray())
			continue
		var numcols := _s16(data, o + 4)
		var link := _u16(data, o + 6)
		var ofs := _u32(data, o + 8)
		var siz := _u32(data, o + 12)
		if siz == 0 or siz == 0x80000000:
			palettes.append(PackedColorArray())
			continue
		var start := lofs + ofs
		if start + siz > data.size():
			palettes.append(PackedColorArray())
			continue
		var pal := PackedColorArray()
		var n := mini(int(siz / 4), 256)
		for k in range(n):
			var p := start + k * 4
			pal.append(Color8(data[p], data[p + 1], data[p + 2], 255))
		palettes.append(pal)
	# Resolve palette links and assign palettes to indexed sprites.
	for i in range(npal):
		if palettes[i].is_empty():
			var o := pal_ofs + i * 16
			var link := _u16(data, o + 6)
			if link < palettes.size() and link != i:
				palettes[i] = palettes[link]
	for s in sprites:
		if s.get("image", null) == null and not s.get("pixels", PackedByteArray()).is_empty():
			var pi := int(s.get("palette_index", 0))
			if pi >= 0 and pi < palettes.size() and not palettes[pi].is_empty():
				s["palette"] = palettes[pi]
			elif not palettes.is_empty() and not palettes[0].is_empty():
				s["palette"] = palettes[0]
	# Resolve true links (no payload of their own).
	for s in sprites:
		if s.get("image", null) == null and s.get("pixels", PackedByteArray()).is_empty():
			var link := int(s.get("link", -1))
			if link >= 0 and link < sprites.size() and link != sprites.find(s):
				var src: Dictionary = sprites[link]
				s["width"] = int(src.get("width", 0))
				s["height"] = int(src.get("height", 0))
				s["pixels"] = src.get("pixels", PackedByteArray())
				s["palette"] = src.get("palette", PackedColorArray())
				s["image"] = src.get("image", null)

# --------------------------------------------------------------------------
# PCX / RLE decoders (ported from the project's validated sff.py)
# --------------------------------------------------------------------------
func _pcx_decode(pcx: PackedByteArray) -> Dictionary:
	var data := pcx
	if data.size() > 12 and data.slice(0, 11).get_string_from_ascii() == "ElecbytePcx":
		data = data.slice(12)
	if data.size() < 128:
		return {}
	var w := _u16(data, 8) - _u16(data, 4) + 1
	var h := _u16(data, 10) - _u16(data, 6) + 1
	var bpl := _u16(data, 66)
	if w <= 0 or h <= 0 or bpl <= 0:
		return {}
	var img := PackedByteArray()
	img.resize(bpl * h)
	var i := 128
	var j := 0
	while j < img.size() and i < data.size():
		var b := data[i]
		i += 1
		if (b & 0xC0) == 0xC0:
			var run := b & 0x3F
			var val := data[i] if i < data.size() else 0
			i += 1
			for k in range(run):
				if j < img.size():
					img[j] = val
					j += 1
		else:
			img[j] = b
			j += 1
	var pixels := PackedByteArray()
	pixels.resize(w * h)
	for y in range(h):
		for x in range(w):
			pixels[y * w + x] = img[y * bpl + x]
	var pal := PackedColorArray()
	if data.size() >= 769:
		var tail := data.slice(data.size() - 769)
		if tail[0] == 0x0C:
			for k in range(256):
				pal.append(Color8(tail[1 + k * 3], tail[2 + k * 3], tail[3 + k * 3], 255))
	return {"width": w, "height": h, "pixels": pixels, "palette": pal}

func _rle8_decode(rle: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(w * h)
	var i := 0
	var j := 0
	var n := rle.size()
	while j < p.size() and i < n:
		var d := rle[i]
		i += 1
		var cnt := 1
		if (d & 0xC0) == 0x40:
			cnt = d & 0x3F
			d = rle[i] if i < n else 0
			i += 1
		for k in range(cnt):
			if j < p.size():
				p[j] = d
				j += 1
	return p

func _rle5_decode(rle: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(w * h)
	var i := 0
	var j := 0
	var n := rle.size()
	while j < p.size() and i < n:
		var rl := rle[i]
		i += 1
		var dl := (rle[i] & 0x7F) if i < n else 0
		var c := 0
		if i < n and (rle[i] >> 7) != 0:
			i += 1
			c = rle[i] if i < n else 0
		i += 1
		while true:
			if j < p.size():
				p[j] = c
				j += 1
			rl -= 1
			if rl < 0:
				dl -= 1
				if dl < 0:
					break
				c = (rle[i] & 0x1F) if i < n else 0
				rl = (rle[i] >> 5) if i < n else 0
				i += 1
	return p

func _lz5_decode(rle: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(w * h)
	var i := 0
	var j := 0
	var n := rle.size()
	if n == 0:
		return p
	var ct := rle[i]
	i += 1
	var cts := 0
	var rb := 0
	var rbc := 0
	while j < p.size() and i < n:
		var d := rle[i]
		i += 1
		if (ct & (1 << cts)) != 0:
			var cnt := 0
			if (d & 0x3F) == 0:
				d = ((d << 2) | (rle[i] if i < n else 0)) + 1
				i += 1
				cnt = (rle[i] if i < n else 0) + 2
				i += 1
			else:
				rb |= (d & 0xC0) >> rbc
				rbc += 2
				cnt = d & 0x3F
				if rbc < 8:
					d = (rle[i] if i < n else 0) + 1
					i += 1
				else:
					d = rb + 1
					rb = 0
					rbc = 0
			while true:
				if j < p.size() and j - d >= 0:
					p[j] = p[j - d]
					j += 1
				cnt -= 1
				if cnt < 0:
					break
		else:
			var cnt2 := 0
			if (d & 0xE0) == 0:
				cnt2 = (rle[i] if i < n else 0) + 8
				i += 1
			else:
				cnt2 = d >> 5
				d &= 0x1F
			for k in range(cnt2):
				if j < p.size():
					p[j] = d
					j += 1
		cts += 1
		if cts >= 8:
			ct = rle[i] if i < n else 0
			i += 1
			cts = 0
	return p

static func _u16(d: PackedByteArray, o: int) -> int:
	if o + 1 >= d.size():
		return 0
	return int(d[o]) | (int(d[o + 1]) << 8)

static func _s16(d: PackedByteArray, o: int) -> int:
	var v := _u16(d, o)
	return v - 65536 if v >= 32768 else v

static func _u32(d: PackedByteArray, o: int) -> int:
	if o + 3 >= d.size():
		return 0
	return int(d[o]) | (int(d[o + 1]) << 8) | (int(d[o + 2]) << 16) | (int(d[o + 3]) << 24)
