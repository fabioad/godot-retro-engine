@tool
extends Control
## Animated MUGEN character preview: AIR frame + SFF sprite + hitboxes.

const LOGICAL := Vector2(320, 240)

var sff
var air
var action: int = 0
var time_ticks: float = 0.0
var playing: bool = false
var show_boxes: bool = true
var loop: bool = true
var zoom: int = 0
var _texture: ImageTexture
var _last_key: String = ""

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(320, 240)
	set_process(false)

func set_char(p_sff, p_air, p_action: int = 0) -> void:
	sff = p_sff
	air = p_air
	action = p_action
	time_ticks = 0.0
	_last_key = ""
	queue_redraw()

func set_action(p_action: int) -> void:
	action = p_action
	time_ticks = 0.0
	_last_key = ""
	queue_redraw()

func set_time_ticks(t: float) -> void:
	time_ticks = t
	queue_redraw()

func tick(delta: float) -> void:
	if not playing or air == null:
		return
	time_ticks += delta * 60.0
	var total: int = air.total_ticks(action)
	if total > 0:
		if loop:
			time_ticks = fmod(time_ticks, total)
		elif time_ticks >= total:
			time_ticks = total - 1
			playing = false
			set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	tick(delta)

func _viewport() -> Rect2:
	var margin := 10.0
	var area := Vector2(maxf(1.0, size.x - margin * 2.0), maxf(1.0, size.y - margin * 2.0))
	var s := minf(area.x / LOGICAL.x, area.y / LOGICAL.y)
	if zoom > 0:
		s = float(zoom) / LOGICAL.x
	var vs := (LOGICAL * maxf(0.1, s)).floor()
	if zoom <= 0 and (vs.x > area.x or vs.y > area.y):
		vs = (LOGICAL * s).floor()
	var pos := ((size - vs) * 0.5).floor()
	return Rect2(pos, vs)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0e14"))
	var view := _viewport()
	draw_rect(view, Color("#05070b"))
	var cell := 8.0
	for y in range(int(ceil(view.size.y / cell))):
		for x in range(int(ceil(view.size.x / cell))):
			if (x + y) % 2 == 0:
				draw_rect(Rect2(view.position + Vector2(x, y) * cell, Vector2(cell, cell)), Color(1, 1, 1, 0.03))
	draw_rect(view, Color("#7fd1ff"), false, 1.0)
	if sff == null or air == null:
		draw_string(ThemeDB.fallback_font, view.position + Vector2(12, 26), "Open a MUGEN character (DEF + SFF + AIR) to preview it.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8b98ad"))
		return
	var frame: Dictionary = air.frame_at(action, int(time_ticks))
	if frame.is_empty():
		draw_string(ThemeDB.fallback_font, view.position + Vector2(12, 26), "Action %d has no frames." % action, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffd45e"))
		return
	var idx: int = sff.find_index(int(frame.get("group", 0)), int(frame.get("number", 0)))
	if idx < 0:
		draw_string(ThemeDB.fallback_font, view.position + Vector2(12, 26), "Sprite %d,%d not found in SFF." % [int(frame.get("group", 0)), int(frame.get("number", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ff9a9a"))
		return
	var img: Image = sff.render(idx)
	if img == null:
		return
	var key := "%d:%s:%s" % [idx, bool(frame.get("flip_h", false)), bool(frame.get("flip_v", false))]
	if key != _last_key:
		_last_key = key
		var draw_img := img.duplicate()
		if bool(frame.get("flip_h", false)):
			draw_img.flip_x()
		if bool(frame.get("flip_v", false)):
			draw_img.flip_y()
		_texture = ImageTexture.create_from_image(draw_img)
	var scale := view.size.x / LOGICAL.x
	# MUGEN axis is the sprite origin; place the character ground near y=200.
	var target := view.position + Vector2(LOGICAL.x * 0.5, LOGICAL.y - 38.0) * scale
	var pos := target - Vector2(sff.sprite_at(idx).get("axis", Vector2i.ZERO)) * scale
	pos += Vector2(float(frame.get("x", 0)), float(frame.get("y", 0))) * scale
	var draw_size := Vector2(img.get_width(), img.get_height()) * scale
	draw_texture_rect(_texture, Rect2(pos, draw_size), false)
	draw_rect(Rect2(pos, draw_size), Color("#7fd1ff"), false, 1.0)
	if show_boxes:
		for box in frame.get("clsn1", []):
			var r: Rect2i = box
			draw_rect(Rect2(target + Vector2(r.position) * scale, Vector2(r.size) * scale), Color("#ff7a7a"), false, 1.5)
		for box in frame.get("clsn2", []):
			var r: Rect2i = box
			draw_rect(Rect2(target + Vector2(r.position) * scale, Vector2(r.size) * scale), Color("#6ee7a8"), false, 1.5)
	var label := "Action %d  frame %d/%d  %dt  %d,%d" % [
		action, int(frame.get("index", 0)) + 1, int(frame.get("frame_count", 1)),
		int(frame.get("ticks", 1)), int(frame.get("group", 0)), int(frame.get("number", 0))]
	draw_string(ThemeDB.fallback_font, view.position + Vector2(8, view.size.y - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#cfe0f5"))
