@tool
extends RefCounted
## Transparency-aware sprite-sheet slicing.
##
## Imported sheets are often stored as one "full" frame. The animation preview
## needs the individual frames to play something meaningful, so this helper
## finds the frame pitch from the transparent gaps and returns exact rects.
## It also applies the classic magenta/green transparency key used by indexed
## SNES/MUGEN sheets, where transparency is a palette colour instead of alpha.

const MIN_ALPHA := 0.01

## Return the frame rects for a sprite. Existing authored frames win; a single
## full-sheet frame is auto-sliced from the image alpha.
static func frames_for_sprite(sprite: RetroSprite, mode: String = "auto") -> Array:
	var out: Array = []
	if sprite == null:
		return out
	var authored: Array = sprite.get_frames()
	if authored.size() > 1:
		for f in authored:
			var r: Rect2i = Dictionary(f).get("rect", Rect2i())
			if r.size.x > 0 and r.size.y > 0:
				out.append(r)
		return out
	var image := sprite.get_image()
	if image == null:
		return out
	if authored.size() == 1:
		var only: Dictionary = authored[0]
		var only_rect: Rect2i = only.get("rect", Rect2i())
		if not _is_full_sheet(only_rect, image):
			return out
	return detect_frames(image, mode)

## Detect frame rects from the image. Both axes are inspected, so a 2-column
## sheet does not become a frame containing two characters.
static func detect_frames(image: Image, mode: String = "auto") -> Array:
	var out: Array = []
	if image == null:
		return out
	var src := image
	if src.get_format() != Image.FORMAT_RGBA8:
		src = src.duplicate()
		src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	if w <= 0 or h <= 0:
		return out
	if mode == "whole":
		out.append(Rect2i(0, 0, w, h))
		return out
	var xs := _axis_cells(src, true)
	var ys := _axis_cells(src, false)
	if mode == "horizontal":
		if xs.size() > 1:
			for x in xs:
				out.append(Rect2i(x.x, 0, x.y, h))
			return out
		out.append(Rect2i(0, 0, w, h))
		return out
	if mode == "vertical":
		if ys.size() > 1:
			for y in ys:
				out.append(Rect2i(0, y.x, w, y.y))
			return out
		out.append(Rect2i(0, 0, w, h))
		return out
	if mode == "grid":
		if xs.size() > 1 and ys.size() > 1:
			for y in ys:
				for x in xs:
					var r := Rect2i(x.x, y.x, x.y, y.y)
					if _region_has_alpha(src, r):
						out.append(r)
			if out.size() >= 2:
				return out
		out.append(Rect2i(0, 0, w, h))
		return out
	if xs.size() > 1 and ys.size() > 1:
		for y in ys:
			for x in xs:
				var r := Rect2i(x.x, y.x, x.y, y.y)
				if _region_has_alpha(src, r):
					out.append(r)
		if out.size() >= 2:
			return out
	if xs.size() > 1:
		for x in xs:
			out.append(Rect2i(x.x, 0, x.y, h))
		return out
	if ys.size() > 1:
		for y in ys:
			out.append(Rect2i(0, y.x, w, y.y))
		return out
	# Square / grid sheets: try the greatest common square that produces more
	# than one cell and has content in at least two cells.
	var side := mini(w, h)
	if side >= 8 and w % side == 0 and h % side == 0 and (w / side) * (h / side) >= 2:
		var grid := _grid_rects(w, h, side, side)
		if _count_non_empty(src, grid) >= 2:
			return grid
	# Last resort: use the transparent column/row runs themselves.
	var runs := _runs_from_mask(_axis_mask(src, true))
	if runs.size() >= 2:
		for r in runs:
			var start := int(r[0])
			var width := int(r[1]) - start + 1
			if width >= 2:
				out.append(Rect2i(start, 0, width, h))
	return out

## Materialise detected sheet frames into the sprite document. Existing frames
## are replaced only when the sheet was a single full-image frame.
static func ensure_sprite_frames(sprite: RetroSprite, duration: int = 6, mode: String = "auto") -> Array:
	if sprite == null:
		return []
	var authored: Array = sprite.get_frames()
	if authored.size() > 1:
		return authored
	var rects := frames_for_sprite(sprite, mode)
	if rects.size() < 2:
		return authored
	var frames: Array = []
	for i in range(rects.size()):
		frames.append({
			"name": "sheet_%d" % i,
			"rect": rects[i],
			"duration": maxi(1, duration),
			"hitboxes": [],
			"events": [],
		})
	sprite.set_frames(frames)
	return frames

## Apply the classic indexed-sheet chroma key (magenta or green) as alpha 0.
## Export still maps those pixels to palette index 0, so game output is
## unchanged; only the editor preview becomes transparent.
static func apply_chroma_key(image: Image, palette: PackedColorArray) -> bool:
	if image == null or palette.is_empty():
		return false
	if not is_key_color(palette[0]):
		return false
	if image.detect_alpha() != Image.ALPHA_NONE:
		return false
	var src := image
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	var key := palette[0]
	var kr := int(round(key.r * 255.0))
	var kg := int(round(key.g * 255.0))
	var kb := int(round(key.b * 255.0))
	var data := src.get_data()
	var changed := false
	var i := 0
	while i + 3 < data.size():
		if data[i] == kr and data[i + 1] == kg and data[i + 2] == kb:
			if data[i + 3] != 0:
				data[i + 3] = 0
				changed = true
		i += 4
	if changed:
		var out := Image.create_from_data(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8, data)
		src.copy_from(out)
	return changed

static func apply_sprite_key(sprite: RetroSprite) -> bool:
	if sprite == null or sprite.get_image() == null:
		return false
	return apply_chroma_key(sprite.get_image(), sprite.get_palette())

static func is_key_color(c: Color) -> bool:
	# Magenta is the de-facto SNES/MUGEN sprite transparency key. Pure green
	# is also common in indexed sheets. Do not key black/white: backgrounds
	# legitimately use them.
	var magenta := c.r > 0.85 and c.g < 0.2 and c.b > 0.85
	var green := c.r < 0.2 and c.g > 0.85 and c.b < 0.2
	return magenta or green

static func palette_has_key(palette: PackedColorArray) -> bool:
	return not palette.is_empty() and is_key_color(palette[0])

static func _is_full_sheet(rect: Rect2i, image: Image) -> bool:
	return rect.position.x <= 0 and rect.position.y <= 0 \
		and rect.size.x >= image.get_width() and rect.size.y >= image.get_height()

## Cells along one axis. Each cell is Vector2i(start, size). The pitch comes
## from the most common transparent-gap distance; otherwise the opaque runs
## themselves are used.
static func _axis_cells(image: Image, horizontal: bool) -> Array:
	var cells: Array = []
	var length := image.get_width() if horizontal else image.get_height()
	var cross := image.get_height() if horizontal else image.get_width()
	var runs := _runs_from_mask(_axis_mask(image, horizontal))
	if runs.is_empty():
		return cells
	var pitch := _pitch_from_runs(runs, length, cross, image, horizontal)
	if pitch > 0:
		var count := int(length / pitch)
		for i in range(count):
			var start := i * pitch
			var r := Rect2i(start, 0, pitch, image.get_height()) if horizontal else Rect2i(0, start, image.get_width(), pitch)
			if _region_has_alpha(image, r):
				cells.append(Vector2i(start, pitch))
		if cells.size() >= 2:
			return cells
	for run in runs:
		var start := int(run[0])
		var width := int(run[1]) - start + 1
		if width >= 2:
			cells.append(Vector2i(start, width))
	return cells

static func _pitch_from_runs(runs: Array, length: int, cross: int, image: Image, horizontal: bool) -> int:
	var deltas: Array = []
	for i in range(1, runs.size()):
		var delta := int(runs[i][0]) - int(runs[i - 1][0])
		if delta >= maxi(4, cross / 8) and delta <= length / 2:
			deltas.append(delta)
	if deltas.is_empty():
		return 0
	deltas.sort()
	var median := int(deltas[deltas.size() / 2])
	var tolerance := maxi(2, median / 4)
	var total := 0
	var count := 0
	for d in deltas:
		if absi(int(d) - median) <= tolerance:
			total += int(d)
			count += 1
	if count < 1:
		return 0
	var candidates: Array = [int(round(float(total) / float(count)))]
	if runs.size() > 1:
		candidates.append(int(round(float(length) / float(runs.size()))))
	var best_pitch := 0
	var best_score := -1
	for candidate in candidates:
		var p := int(candidate)
		if p < maxi(4, cross / 8) or p > length / 2:
			continue
		var cells := int(length / p)
		if cells < 2:
			continue
		var non_empty := 0
		for i in range(cells):
			var r := Rect2i(i * p, 0, p, image.get_height()) if horizontal else Rect2i(0, i * p, image.get_width(), p)
			if _region_has_alpha(image, r):
				non_empty += 1
		# Prefer a pitch that tiles the sheet exactly; this keeps frame cells
		# aligned even when the tight sprite bounds vary by a few pixels.
		var score := non_empty + (1000 if length % p == 0 else 0)
		if score > best_score:
			best_score = score
			best_pitch = p
	return best_pitch

static func _axis_mask(image: Image, horizontal: bool) -> PackedByteArray:
	var length := image.get_width() if horizontal else image.get_height()
	var cross := image.get_height() if horizontal else image.get_width()
	var mask := PackedByteArray()
	mask.resize(length)
	for i in range(length):
		var found := false
		for j in range(cross):
			var p := image.get_pixel(i, j) if horizontal else image.get_pixel(j, i)
			if p.a > MIN_ALPHA:
				found = true
				break
		mask[i] = 1 if found else 0
	return mask

static func _runs_from_mask(mask: PackedByteArray) -> Array:
	var runs: Array = []
	var start := -1
	for i in range(mask.size()):
		if mask[i] != 0 and start < 0:
			start = i
		elif mask[i] == 0 and start >= 0:
			runs.append([start, i - 1])
			start = -1
	if start >= 0:
		runs.append([start, mask.size() - 1])
	return runs

static func _region_has_alpha(image: Image, rect: Rect2i) -> bool:
	var x0 := clampi(rect.position.x, 0, image.get_width())
	var y0 := clampi(rect.position.y, 0, image.get_height())
	var x1 := clampi(rect.position.x + rect.size.x, 0, image.get_width())
	var y1 := clampi(rect.position.y + rect.size.y, 0, image.get_height())
	for y in range(y0, y1):
		for x in range(x0, x1):
			if image.get_pixel(x, y).a > MIN_ALPHA:
				return true
	return false

static func _grid_rects(w: int, h: int, fw: int, fh: int) -> Array:
	var out: Array = []
	for y in range(0, h, fh):
		for x in range(0, w, fw):
			out.append(Rect2i(x, y, fw, fh))
	return out

static func _count_non_empty(image: Image, rects: Array) -> int:
	var count := 0
	for r in rects:
		if _region_has_alpha(image, r):
			count += 1
	return count
