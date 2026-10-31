@tool
extends Control
## Animation preview: exact frame crop, hitboxes and origin, at 60 Hz timing.
##
## The preview has two sources:
##  - the selected animation state, sampled with its real frame durations;
##  - a sprite-sheet fallback that slices the sheet by transparency and cycles
##    its frames when the state has no frames yet (common after importing a
##    sheet). The fallback is clearly labelled so it is never mistaken for
##    authored animation data.

const SpriteSheet = preload("res://addons/retro_engine/sprite_sheet.gd")

var sprite: RetroSprite
var animation: RetroAnimation
var state_name: String = "IDLE"
var time: float = 0.0
var zoom: int = 0
var auto_fit: bool = true
var show_boxes: bool = true
var show_origin: bool = true
var slice_mode: String = "auto"

var _texture: ImageTexture
var _last_image: Image
var _sheet_image: Image
var _sheet_frames: Array = []

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(300, 220)

func set_slice_mode(mode: String) -> void:
	if slice_mode == mode:
		return
	slice_mode = mode
	_sheet_image = null
	_sheet_frames = []
	_last_image = null
	_prepare_texture()
	queue_redraw()

func set_data(p_sprite: RetroSprite, p_animation: RetroAnimation, p_state: String) -> void:
	sprite = p_sprite
	animation = p_animation
	state_name = p_state
	_last_image = null
	queue_redraw()

func tick(delta: float) -> void:
	set_time(time + delta)

## Set the preview time and pre-build the frame texture outside `_draw`, so a
## new animation frame never flashes an uninitialized white texture.
func set_time(value: float) -> void:
	time = value
	_prepare_texture()
	queue_redraw()

func _prepare_texture() -> void:
	var frame := resolve_frame()
	if frame.is_empty():
		return
	var image := frame_image(frame)
	if image == null or image == _last_image:
		return
	_last_image = image
	_texture = ImageTexture.create_from_image(image)

## Sheet rects for the current sprite. Authored multi-frame sprites are used
## directly; a single full-sheet frame is split by transparency once and cached.
func sprite_sheet_frames() -> Array:
	if sprite == null:
		return []
	var authored: Array = sprite.get_frames()
	if authored.size() > 1:
		return authored
	var image := sprite.get_image()
	if image == null:
		return authored
	if image != _sheet_image:
		_sheet_image = image
		_sheet_frames = SpriteSheet.frames_for_sprite(sprite, slice_mode)
	return _sheet_frames

## Resolve the frame that must be drawn at `time`.
##
## Returns an empty dictionary when there is nothing to preview. The returned
## dictionary always contains `sprite_frame`, `image_index` and `source`
## ("animation" or "sprite_sheet"), so both the editor and tests can inspect
## the same decision used by `_draw`.
func resolve_frame() -> Dictionary:
	if sprite == null:
		return {}
	var authored: Array = sprite.get_frames()
	var sheet: Array = sprite_sheet_frames()
	var has_auto_sheet := sheet.size() > authored.size() and sheet.size() > 1
	var state_frames: Array = []
	if animation != null:
		state_frames = animation.get_state(state_name).get("frames", [])
	# A state with 0/1 frame plus a multi-frame sprite sheet is an imported
	# placeholder. Cycle the split frames rather than freezing on one image.
	var force_sheet := sheet.size() > 1 and state_frames.size() <= 1
	if animation != null and not force_sheet:
		var sample: Dictionary = animation.sample(state_name, time)
		if not sample.is_empty():
			var si := int(sample.get("sprite_frame", 0))
			if si >= 0 and si < authored.size():
				var authored_rect: Rect2i = Dictionary(authored[si]).get("rect", Rect2i())
				var full_sheet := sprite.get_image() != null and authored_rect.size.x >= sprite.get_image().get_width() and authored_rect.size.y >= sprite.get_image().get_height()
				# A single authored frame that covers the whole sheet is a
				# placeholder: play the detected sub-frames instead.
				if not (full_sheet and has_auto_sheet):
					sample["image_index"] = si
					sample["source"] = "animation"
					sample["auto_sheet"] = false
					return sample
			var r: Rect2i = sample.get("rect", Rect2i())
			if r.size.x > 0 and r.size.y > 0 and sprite.get_image() != null:
				var full_image := r.position.x <= 0 and r.position.y <= 0 \
					and r.size.x >= sprite.get_image().get_width() and r.size.y >= sprite.get_image().get_height()
				if not (full_image and has_auto_sheet):
					sample["image_index"] = -1
					sample["source"] = "animation"
					sample["auto_sheet"] = false
					return sample
	var frames: Array = sheet if not sheet.is_empty() else authored
	if frames.is_empty():
		return {}
	var total := 0
	for f in frames:
		total += maxi(1, int(_frame_duration(f)))
	var tick := int(time * 60.0)
	var target := tick % total if total > 0 else 0
	var acc := 0
	for i in range(frames.size()):
		var f = frames[i]
		acc += maxi(1, int(_frame_duration(f)))
		if target < acc:
			var result: Dictionary = {}
			if f is Dictionary:
				result = Dictionary(f).duplicate()
				result["rect"] = Dictionary(f).get("rect", Rect2i())
			else:
				result["rect"] = f
			result["index"] = i
			result["sprite_frame"] = i
			result["image_index"] = i
			result["duration"] = int(_frame_duration(f))
			result["source"] = "sprite_sheet"
			result["auto_sheet"] = has_auto_sheet or sheet.size() > authored.size() or force_sheet
			result["frame_count"] = frames.size()
			return result
	return {}

func _frame_duration(frame) -> int:
	if frame is Dictionary:
		return maxi(1, int(Dictionary(frame).get("duration", 6)))
	return 6

func sheet_mode() -> bool:
	return String(resolve_frame().get("source", "")) == "sprite_sheet"

func sheet_duration_seconds() -> float:
	var frames := sprite_sheet_frames()
	var total := 0
	for f in frames:
		total += maxi(1, int(_frame_duration(f)))
	return float(total) / 60.0

func frame_image(frame: Dictionary) -> Image:
	if sprite == null or frame.is_empty():
		return null
	var si := int(frame.get("image_index", -1))
	var auto_sheet := bool(frame.get("auto_sheet", false))
	if si >= 0 and si < sprite.get_frames().size() and not auto_sheet:
		var image: Image = sprite.render_frame(si)
		if image != null:
			return image
	var r: Rect2i = frame.get("rect", Rect2i())
	if r.size.x <= 0 or r.size.y <= 0 or sprite.get_image() == null:
		return null
	var image_size := Vector2i(sprite.get_image().get_width(), sprite.get_image().get_height())
	var clipped := Rect2i(
		Vector2i(clampi(r.position.x, 0, image_size.x), clampi(r.position.y, 0, image_size.y)),
		Vector2i(clampi(r.size.x, 0, image_size.x - clampi(r.position.x, 0, image_size.x)),
			clampi(r.size.y, 0, image_size.y - clampi(r.position.y, 0, image_size.y))))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return null
	return sprite.get_image().get_region(clipped)

func _viewport_rect() -> Rect2:
	var margin := 10.0
	var area_size := Vector2(maxf(1.0, size.x - margin * 2.0), maxf(1.0, size.y - margin * 2.0))
	var native := Vector2(256, 224)
	var scale := minf(area_size.x / native.x, area_size.y / native.y)
	# Integer scaling keeps console pixels crisp; allow the full control when
	# the viewport is too small for 1x.
	var view_size := (native * maxf(1.0, floorf(scale))).floor()
	if view_size.x > area_size.x or view_size.y > area_size.y:
		view_size = (native * scale).floor()
	var origin := ((size - view_size) * 0.5).floor()
	return Rect2(origin, view_size)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0e14"))
	var view := _viewport_rect()
	draw_rect(view, Color("#05070b"))
	# Subtle checkerboard: transparent pixels are visible without looking like
	# a real part of the game screen.
	var cell := 8.0
	var cols := int(ceil(view.size.x / cell))
	var rows := int(ceil(view.size.y / cell))
	for y in range(rows):
		for x in range(cols):
			if (x + y) % 2 == 0:
				draw_rect(Rect2(view.position + Vector2(x, y) * cell, Vector2(cell, cell)), Color(1, 1, 1, 0.025))
	draw_rect(view, Color("#7fd1ff"), false, 1.0)
	var cx := view.position.x + view.size.x * 0.5
	var cy := view.position.y + view.size.y * 0.5
	draw_line(Vector2(cx, view.position.y), Vector2(cx, view.end.y), Color(1, 1, 1, 0.07))
	draw_line(Vector2(view.position.x, cy), Vector2(view.end.x, cy), Color(1, 1, 1, 0.07))

	if sprite == null:
		draw_string(ThemeDB.fallback_font, view.position + Vector2(12, 26), "Load a sprite to preview it.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8b98ad"))
		return
	var frame := resolve_frame()
	if frame.is_empty():
		draw_string(ThemeDB.fallback_font, view.position + Vector2(12, 26), "State '%s' has no frames and the sprite has no frames to cycle." % state_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffd45e"))
		return
	var image := frame_image(frame)
	if image == null:
		draw_string(ThemeDB.fallback_font, view.position + Vector2(12, 26), "Frame has no image data.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ff9a9a"))
		return
	if _last_image != image:
		_last_image = image
		_texture = ImageTexture.create_from_image(image)
	var fit := minf((view.size.x - 20.0) / float(image.get_width()), (view.size.y - 44.0) / float(image.get_height()))
	var draw_zoom := float(zoom) if zoom > 0 and not auto_fit else (floorf(fit) if fit >= 1.0 else fit)
	draw_zoom = clampf(draw_zoom, 0.1, 16.0)
	var draw_size := Vector2(image.get_width(), image.get_height()) * draw_zoom
	var origin := (view.get_center() - draw_size * 0.5).floor()
	# Origin marker from the sprite document (world anchor).
	if show_origin:
		var sprite_origin := Vector2(sprite.get_origin())
		var marker := origin + sprite_origin * draw_zoom
		draw_line(marker - Vector2(6, 0), marker + Vector2(6, 0), Color("#ffd45e"), 1.0)
		draw_line(marker - Vector2(0, 6), marker + Vector2(0, 6), Color("#ffd45e"), 1.0)
	draw_texture_rect(_texture, Rect2(origin, draw_size), false)
	draw_rect(Rect2(origin, draw_size), Color("#7fd1ff"), false, 1.0)
	if show_boxes:
		for box in frame.get("hitboxes", []):
			var r: Rect2i = box.get("rect", Rect2i())
			if r.size.x <= 0 or r.size.y <= 0:
				continue
			var c := Color("#ff7a7a") if String(box.get("type", "hit")) == "hit" else Color("#6ee7a8")
			draw_rect(Rect2(origin + Vector2(r.position) * draw_zoom, Vector2(r.size) * draw_zoom), c, false, 1.5)
	var source := String(frame.get("source", "animation"))
	var title := state_name if source == "animation" else "Sprite sheet"
	var frame_count := int(frame.get("frame_count", sprite.get_frames().size()))
	var label := "%s  frame %d/%d  %df @ %dHz" % [title, int(frame.get("index", 0)), maxi(1, frame_count), int(frame.get("duration", 1)), animation.get_fps() if animation else 60]
	draw_string(ThemeDB.fallback_font, view.position + Vector2(8, view.size.y - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#cfe0f5"))
	if source == "sprite_sheet":
		var note := "Auto-split by transparency - %d frames" % frame_count
		if not bool(frame.get("auto_sheet", false)):
			note = "No frames in '%s' yet - cycling %d sprite frames" % [state_name, frame_count]
		draw_string(ThemeDB.fallback_font, view.position + Vector2(8, 18), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffd45e"))
