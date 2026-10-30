@tool
extends Control
## Pixel-accurate sprite editing canvas. All drawing uses nearest-neighbour
## sampling so palette indices and hard pixel edges are preserved visually.

signal modified()
signal hitbox_added(rect: Rect2i)
signal color_picked(color: Color)
signal pixel_hovered(x: int, y: int)

var image: Image
var palette: PackedColorArray = PackedColorArray()
var zoom: int = 4
var show_grid: bool = true
var show_origin: bool = true
var origin: Vector2i = Vector2i.ZERO
var active_color: Color = Color.WHITE
var edit_mode: String = "paint" # paint | hitbox | select
var hitbox_type: String = "hit"
var hitboxes: Array = []
var frame_rect: Rect2i = Rect2i()
var show_frame: bool = false

var _texture: ImageTexture
var _dirty: bool = true
var _painting: bool = false
var _erasing: bool = false
var _last_pixel: Vector2i = Vector2i(-1, -1)
var _hitbox_start: Vector2i = Vector2i(-1, -1)
var _undo: Array[Image] = []
var _redo: Array[Image] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(320, 240)

func set_image(p_image: Image) -> void:
	image = p_image
	_dirty = true
	queue_redraw()

func set_palette(p_palette: PackedColorArray) -> void:
	palette = p_palette
	queue_redraw()

func set_hitboxes(p_boxes: Array) -> void:
	hitboxes = p_boxes
	queue_redraw()

func set_edit_mode(mode: String) -> void:
	edit_mode = mode
	queue_redraw()

func push_undo() -> void:
	if image:
		_undo.append(image.duplicate())
		if _undo.size() > 40:
			_undo.pop_front()
		_redo.clear()

func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(image.duplicate())
	image = _undo.pop_back()
	_dirty = true
	modified.emit()
	queue_redraw()

func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(image.duplicate())
	image = _redo.pop_back()
	_dirty = true
	modified.emit()
	queue_redraw()

func fit_zoom(available: Vector2) -> void:
	if image == null:
		return
	var z := int(min(available.x / max(1, image.get_width()), available.y / max(1, image.get_height())))
	zoom = clampi(z, 1, 24)
	custom_minimum_size = Vector2(image.get_width() * zoom, image.get_height() * zoom)
	queue_redraw()

func _get_minimum_size() -> Vector2:
	if image:
		return Vector2(image.get_width() * zoom, image.get_height() * zoom)
	return Vector2(320, 240)

func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	draw_rect(area, Color("#151922"))
	if image == null:
		draw_string(ThemeDB.fallback_font, Vector2(12, 24), "No sprite loaded", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#8b98ad"))
		return
	if _dirty or _texture == null:
		_texture = ImageTexture.create_from_image(image)
		_dirty = false
	var draw_size := Vector2(image.get_width() * zoom, image.get_height() * zoom)
	var offset := (size - draw_size) * 0.5
	# Checkerboard.
	var checker := 8
	for y in range(0, int(draw_size.y), checker):
		for x in range(0, int(draw_size.x), checker):
			var c := Color("#242a36") if ((x / checker) + (y / checker)) % 2 == 0 else Color("#1b202b")
			draw_rect(Rect2(offset + Vector2(x, y), Vector2(checker, checker)), c)
	draw_texture_rect(_texture, Rect2(offset, draw_size), false)
	if show_grid and zoom >= 4:
		var grid_color := Color(0.35, 0.45, 0.6, 0.28)
		for x in range(0, image.get_width() + 1):
			draw_line(offset + Vector2(x * zoom, 0), offset + Vector2(x * zoom, draw_size.y), grid_color)
		for y in range(0, image.get_height() + 1):
			draw_line(offset + Vector2(0, y * zoom), offset + Vector2(draw_size.x, y * zoom), grid_color)
	if show_origin:
		var o := offset + Vector2(origin) * zoom
		draw_line(o - Vector2(10, 0), o + Vector2(10, 0), Color("#ffd45e"), 1.0)
		draw_line(o - Vector2(0, 10), o + Vector2(0, 10), Color("#ffd45e"), 1.0)
	if show_frame and frame_rect.size.x > 0:
		draw_rect(Rect2(offset + Vector2(frame_rect.position) * zoom, Vector2(frame_rect.size) * zoom), Color("#7fd1ff"), false, 1.5)
	for box in hitboxes:
		if box is Dictionary:
			var r: Rect2i = box.get("rect", Rect2i())
			var color := Color("#ff7a7a") if String(box.get("type", "hit")) == "hit" else Color("#6ee7a8")
			draw_rect(Rect2(offset + Vector2(r.position) * zoom, Vector2(r.size) * zoom), color, false, 2.0)

func _gui_input(event: InputEvent) -> void:
	if image == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = clampi(zoom + 1, 1, 32)
			custom_minimum_size = Vector2(image.get_width() * zoom, image.get_height() * zoom)
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = clampi(zoom - 1, 1, 32)
			custom_minimum_size = Vector2(image.get_width() * zoom, image.get_height() * zoom)
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if edit_mode == "hitbox" and mb.button_index == MOUSE_BUTTON_LEFT:
				var p := _to_pixel(mb.position)
				if p.x >= 0:
					if mb.pressed:
						_hitbox_start = p
					elif _hitbox_start.x >= 0:
						var rect := Rect2i(_hitbox_start, p - _hitbox_start).abs()
						if rect.size.x > 0 and rect.size.y > 0:
							hitbox_added.emit(rect)
						_hitbox_start = Vector2i(-1, -1)
				accept_event()
				return
			if edit_mode == "paint":
				if mb.pressed:
					push_undo()
					_erasing = mb.button_index == MOUSE_BUTTON_RIGHT
					_painting = true
					_paint_at(mb.position)
				else:
					_painting = false
					_erasing = false
				accept_event()
			return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var p := _to_pixel(mm.position)
		if p.x >= 0:
			pixel_hovered.emit(p.x, p.y)
			if _painting:
				_paint_at(mm.position)
		queue_redraw()
		accept_event()

func _to_pixel(local_pos: Vector2) -> Vector2i:
	if image == null:
		return Vector2i(-1, -1)
	var draw_size := Vector2(image.get_width() * zoom, image.get_height() * zoom)
	var offset := (size - draw_size) * 0.5
	var p := (local_pos - offset) / float(zoom)
	if p.x < 0 or p.y < 0 or p.x >= image.get_width() or p.y >= image.get_height():
		return Vector2i(-1, -1)
	return Vector2i(int(floor(p.x)), int(floor(p.y)))

func _paint_at(local_pos: Vector2) -> void:
	var p := _to_pixel(local_pos)
	if p.x < 0 or p == _last_pixel:
		return
	_last_pixel = p
	var c := Color(0, 0, 0, 0) if _erasing else active_color
	image.set_pixel(p.x, p.y, c)
	_dirty = true
	modified.emit()
	queue_redraw()

func pick_at(local_pos: Vector2) -> void:
	var p := _to_pixel(local_pos)
	if p.x < 0:
		return
	var c := image.get_pixel(p.x, p.y)
	color_picked.emit(c)
