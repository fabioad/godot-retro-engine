@tool
extends RefCounted
## Transparency-aware sprite-sheet slicing.
##
## Imported sheets are often stored as one "full" frame. The animation preview
## needs the individual frames to play something meaningful, so this helper
## finds the frame pitch from the transparent gaps and returns exact rects.

const MIN_ALPHA := 0.01

## Return the frame rects for a sprite. Existing authored frames win; a single
## full-sheet frame is auto-sliced from the image alpha.
static func frames_for_sprite(sprite: RetroSprite) -> Array:
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
	return detect_frames(image)

## Detect frame rects from the image. Handles horizontal strips (most common),
## vertical strips and square grids.
static func detect_frames(image: Image) -> Array:
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
	if w >= h * 2:
		out = _detect_strip(src, true)
	elif h >= w * 2:
		out = _detect_strip(src, false)
	if out.size() >= 2:
		return out
	# Square / grid sheets: try the greatest common square that produces more
	# than one cell and has content in at least two cells.
	var side := mini(w, h)
	if side >= 8 and w % side == 0 and h % side == 0 and (w / side) * (h / side) >= 2:
		var grid := _grid_rects(w, h, side, side)
		if _count_non_empty(src, grid) >= 2:
			return grid
	# Last resort: use the transparent column/row runs themselves.
	var runs := _detect_runs(src, true)
	if runs.size() >= 2:
		return runs
	return []

## Materialise detected sheet frames into the sprite document. Existing frames
## are replaced only when the sheet was a single full-image frame.
static func ensure_sprite_frames(sprite: RetroSprite, duration: int = 6) -> Array:
	if sprite == null:
		return []
	var authored: Array = sprite.get_frames()
	if authored.size() > 1:
		return authored
	var rects := frames_for_sprite(sprite)
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

static func _is_full_sheet(rect: Rect2i, image: Image) -> bool:
	return rect.position.x <= 0 and rect.position.y <= 0 \
		and rect.size.x >= image.get_width() and rect.size.y >= image.get_height()

static func _detect_strip(image: Image, horizontal: bool) -> Array:
	var out: Array = []
	var length := image.get_width() if horizontal else image.get_height()
	var cross := image.get_height() if horizontal else image.get_width()
	var opaque := PackedByteArray()
	opaque.resize(length)
	for i in range(length):
		var found := false
		for j in range(cross):
			var p := image.get_pixel(i, j) if horizontal else image.get_pixel(j, i)
			if p.a > MIN_ALPHA:
				found = true
				break
		opaque[i] = 1 if found else 0
	var runs := _runs_from_mask(opaque)
	if runs.is_empty():
		return out
	# Most common distance between consecutive opaque starts is the frame pitch.
	var deltas: Dictionary = {}
	for i in range(1, runs.size()):
		var delta := int(runs[i][0]) - int(runs[i - 1][0])
		if delta >= maxi(4, cross / 8) and delta <= length / 2:
			deltas[delta] = int(deltas.get(delta, 0)) + 1
	var pitch := 0
	var best := 0
	for d in deltas.keys():
		var count := int(deltas[d])
		if count > best or (count == best and int(d) < pitch):
			best = count
			pitch = int(d)
	if best >= 2 and pitch > 0:
		var frame_count := int(length / pitch)
		for i in range(frame_count):
			var start := i * pitch
			if _region_has_alpha(image, Rect2i(start, 0, pitch, image.get_height()) if horizontal else Rect2i(0, start, image.get_width(), pitch)):
				out.append(Rect2i(start, 0, pitch, image.get_height()) if horizontal else Rect2i(0, start, image.get_width(), pitch))
		if out.size() >= 2:
			return out
	# No regular pitch: each separated opaque run is one frame. Pad to the
	# widest run so the preview does not jitter horizontally.
	var max_w := 0
	for r in runs:
		max_w = maxi(max_w, int(r[1]) - int(r[0]) + 1)
	for r in runs:
		var start := int(r[0])
		var width := int(r[1]) - start + 1
		if width < 2:
			continue
		if horizontal:
			out.append(Rect2i(start, 0, max_w, image.get_height()))
		else:
			out.append(Rect2i(0, start, image.get_width(), max_w))
	return out

static func _detect_runs(image: Image, horizontal: bool) -> Array:
	var out: Array = []
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
	for r in _runs_from_mask(mask):
		var start := int(r[0])
		var width := int(r[1]) - start + 1
		if width < 2:
			continue
		if horizontal:
			out.append(Rect2i(start, 0, width, image.get_height()))
		else:
			out.append(Rect2i(0, start, image.get_width(), width))
	return out

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
