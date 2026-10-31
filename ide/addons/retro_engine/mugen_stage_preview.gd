@tool
extends Control
## MUGEN stage DEF + SFF layered preview with MUGEN delta (parallax).

const LOGICAL := Vector2(320, 240)

var definition
var sff
var air
var camera_x: float = 0.0
var camera_y: float = 0.0
var time_ticks: float = 0.0
var zoom: int = 0
var _textures: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(320, 240)

func set_stage(p_def, p_sff, p_air) -> void:
	definition = p_def
	sff = p_sff
	air = p_air
	_textures.clear()
	queue_redraw()

func set_camera(x: float, y: float = 0.0) -> void:
	camera_x = x
	camera_y = y
	queue_redraw()

func set_time_ticks(t: float) -> void:
	time_ticks = t
	queue_redraw()

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
	draw_rect(view, Color("#7fd1ff"), false, 1.0)
	if definition == null or sff == null:
		draw_string(ThemeDB.fallback_font, view.position + Vector2(12, 26), "Open a MUGEN stage (DEF + SFF) to preview its layers.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8b98ad"))
		return
	var scale := view.size.x / LOGICAL.x
	var layers: Array = definition.bg_layers.duplicate()
	layers.sort_custom(func(a, b): return int(a.get("layerno", 0)) < int(b.get("layerno", 0)))
	for layer in layers:
		var l: Dictionary = layer
		var group := 0
		var number := 0
		var ticks := 0
		if String(l.get("type", "normal")) == "anim":
			var action := _to_int(String(l.get("actionno", "")))
			if air != null and action >= 0:
				var fr: Dictionary = air.frame_at(action, int(time_ticks))
				if not fr.is_empty():
					group = int(fr.get("group", 0))
					number = int(fr.get("number", 0))
		else:
			var spr := String(l.get("spriteno", ""))
			var pair := _pair(spr)
			group = int(pair.x)
			number = int(pair.y)
		if group == 0 and number == 0 and not l.has("spriteno"):
			continue
		var idx: int = sff.find_index(group, number)
		if idx < 0:
			continue
		var image: Image = sff.render(idx)
		if image == null:
			continue
		var tex: ImageTexture = _textures.get(idx, null)
		if tex == null:
			tex = ImageTexture.create_from_image(image)
			_textures[idx] = tex
		var start := _pair(String(l.get("start", "0,0")))
		var delta := _pair(String(l.get("delta", "1,1")))
		var axis: Vector2i = sff.sprite_at(idx).get("axis", Vector2i.ZERO)
		var pos := Vector2(start.x + camera_x * delta.x, start.y + camera_y * delta.y) - Vector2(axis)
		var dest := Rect2(view.position + pos * scale, Vector2(image.get_width(), image.get_height()) * scale)
		var visible := dest.intersection(view)
		if visible.size.x <= 0 or visible.size.y <= 0:
			continue
		var src := Rect2((visible.position - dest.position) / scale, visible.size / scale)
		draw_texture_rect_region(tex, visible, src)
	var label := "camera %.0f,%.0f   layers %d" % [camera_x, camera_y, layers.size()]
	draw_string(ThemeDB.fallback_font, view.position + Vector2(8, view.size.y - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#cfe0f5"))

static func _pair(text: String) -> Vector2:
	var parts := text.split(",")
	if parts.size() < 2:
		return Vector2.ZERO
	return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))

static func _to_int(text: String) -> int:
	var s := text.strip_edges()
	if s.is_empty():
		return -1
	var v := 0
	var neg := false
	for c in s:
		if c == "-" and v == 0:
			neg = true
		elif c >= "0" and c <= "9":
			v = v * 10 + int(c)
		else:
			break
	return -v if neg else v
