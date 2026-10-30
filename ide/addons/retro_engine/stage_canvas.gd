@tool
extends Control
## Renders a tile map / stage preview at integer scale, with scroll,
## parallax, collision and per-line sprite overlays.

signal tile_painted(map_x: int, map_y: int, button: int)
signal hovered_tile(map_x: int, map_y: int)

var stage: RetroStage
var sprite: RetroSprite
var animation: RetroAnimation
var animation_state: String = "IDLE"
var animation_time: float = 0.0

var scroll_offset: Vector2 = Vector2.ZERO
var zoom: int = 2
var show_grid: bool = false
var show_collisions: bool = true
var show_sprites: bool = true
var show_limits: bool = true
var paint_mode: bool = false
var selected_tile: int = 0
var selected_palette: int = 0

var _texture: ImageTexture
var _render: Image
var _dirty: bool = true

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(240, 160)

func set_stage(p_stage: RetroStage) -> void:
	stage = p_stage
	_dirty = true
	queue_redraw()

func set_sprite(p_sprite: RetroSprite, p_animation: RetroAnimation = null) -> void:
	sprite = p_sprite
	animation = p_animation
	queue_redraw()

func refresh() -> void:
	_dirty = true
	queue_redraw()

func _ensure_render() -> void:
	if stage == null:
		_render = null
		_texture = null
		return
	if _dirty or _render == null:
		_render = stage.render()
		if _render != null:
			_texture = ImageTexture.create_from_image(_render)
		_dirty = false

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0e1118"))
	if stage == null:
		draw_string(ThemeDB.fallback_font, Vector2(16, 30), "Import/select a stage resource to preview it.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#8b98ad"))
		return
	_ensure_render()
	if _render == null:
		draw_string(ThemeDB.fallback_font, Vector2(16, 30), "Stage has no tileset/map.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ff9a9a"))
		return
	var spec: Dictionary = RetroHardware.specs(stage.get_platform(), stage.get_mode())
	var native := Vector2(256, 224) if stage.get_platform() == "snes" else Vector2(320, 224)
	var viewport_size := native
	var scale := float(zoom)
	var view_size := viewport_size * scale
	var origin := (size - view_size) * 0.5
	origin = origin.floor()
	# Clip to the console viewport.
	draw_rect(Rect2(origin, view_size), Color.BLACK)
	var src_rect := Rect2(scroll_offset, viewport_size)
	var tex_size := Vector2(_render.get_width(), _render.get_height())
	# Handle maps smaller than the viewport by clamping.
	var src_valid := Rect2(
		Vector2(clampf(src_rect.position.x, 0, maxf(0, tex_size.x - viewport_size.x)), clampf(src_rect.position.y, 0, maxf(0, tex_size.y - viewport_size.y))),
		viewport_size)
	draw_texture_rect_region(_texture, Rect2(origin, view_size), src_valid)
	# Frame border.
	draw_rect(Rect2(origin, view_size), Color("#7fd1ff"), false, 2.0)
	# 8x8 / 16x16 grid.
	if show_grid:
		var ts := stage.get_tile_size() * scale
		for i in range(1, int(viewport_size.x / stage.get_tile_size())):
			draw_line(origin + Vector2(i * ts, 0), origin + Vector2(i * ts, view_size.y), Color(1, 1, 1, 0.08))
		for j in range(1, int(viewport_size.y / stage.get_tile_size())):
			draw_line(origin + Vector2(0, j * ts), origin + Vector2(view_size.x, j * ts), Color(1, 1, 1, 0.08))
	# Collisions.
	if show_collisions:
		for c in stage.get_collisions():
			var r: Rect2i = c if c is Rect2i else c.get("rect", Rect2i())
			var p := origin + (Vector2(r.position) - src_valid.position) * scale
			draw_rect(Rect2(p, Vector2(r.size) * scale), Color(1.0, 0.35, 0.35, 0.75), false, 2.0)
	# Sprite preview.
	if show_sprites and sprite != null:
		var frame_rect := Rect2i()
		if animation != null:
			var sample := animation.sample(animation_state, animation_time)
			if not sample.is_empty():
				frame_rect = sample.get("rect", Rect2i())
		if frame_rect.size.x <= 0 and sprite.get_frames().size() > 0:
			frame_rect = sprite.get_frames()[0].get("rect", Rect2i())
		if frame_rect.size.x > 0:
			var crop := sprite.render_frame(0)
			var all_frames := sprite.get_frames()
			for i in range(all_frames.size()):
				var fr: Rect2i = all_frames[i].get("rect", Rect2i())
				if fr == frame_rect:
					crop = sprite.render_frame(i)
					break
			if crop != null:
				var tex := ImageTexture.create_from_image(crop)
				var sp := origin + (Vector2(128, 160) - src_valid.position) * scale
				draw_texture_rect(tex, Rect2(sp, Vector2(crop.get_width(), crop.get_height()) * scale), false)
				draw_rect(Rect2(sp, Vector2(crop.get_width(), crop.get_height()) * scale), Color("#ffd45e"), false, 1.0)
	# Sprite-per-line limit indicator (uses the stage collision markers as a
	# conservative sample; real OAM/VDP evaluation is done by the Hardware tab).
	if show_limits:
		var limit := int(spec.get("sprites_per_line", 32))
		draw_string(ThemeDB.fallback_font, origin + Vector2(6, view_size.y - 8),
			"%s  %dx%d  line limit %d" % [String(spec.get("mode", stage.get_mode())), int(native.x), int(native.y), limit],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fb4d0"))
	# Hovered tile outline.
	if paint_mode and _last_tile.x >= 0:
		var ts := stage.get_tile_size() * scale
		var tp := origin + (Vector2(_last_tile) * stage.get_tile_size() - src_valid.position) * scale
		draw_rect(Rect2(tp, Vector2(ts, ts)), Color("#7fd1ff"), false, 1.5)

var _last_tile: Vector2i = Vector2i(-1, -1)
var _painting: bool = false

func _gui_input(event: InputEvent) -> void:
	if stage == null:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var tile := _to_tile(mm.position)
		if tile != _last_tile:
			_last_tile = tile
			if tile.x >= 0:
				hovered_tile.emit(tile.x, tile.y)
			queue_redraw()
		if _painting:
			if tile.x >= 0:
				tile_painted.emit(tile.x, tile.y, MOUSE_BUTTON_LEFT)
		accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = clampi(zoom + 1, 1, 8)
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = clampi(zoom - 1, 1, 8)
			queue_redraw()
		elif paint_mode and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			_painting = mb.pressed
			if mb.pressed:
				var tile := _to_tile(mb.position)
				if tile.x >= 0:
					tile_painted.emit(tile.x, tile.y, mb.button_index)
			accept_event()

func _to_tile(local_pos: Vector2) -> Vector2i:
	if stage == null:
		return Vector2i(-1, -1)
	var native := Vector2(256, 224) if stage.get_platform() == "snes" else Vector2(320, 224)
	var view_size := native * zoom
	var origin := ((size - view_size) * 0.5).floor()
	var src := _clamped_scroll()
	var p := (local_pos - origin) / float(zoom) + src
	var tile := Vector2i(int(floor(p.x / stage.get_tile_size())), int(floor(p.y / stage.get_tile_size())))
	if tile.x < 0 or tile.y < 0 or tile.x >= stage.get_map_size().x or tile.y >= stage.get_map_size().y:
		return Vector2i(-1, -1)
	return tile

func _clamped_scroll() -> Vector2:
	if stage == null:
		return Vector2.ZERO
	var native := Vector2(256, 224) if stage.get_platform() == "snes" else Vector2(320, 224)
	var tex := Vector2(stage.get_map_size().x * stage.get_tile_size(), stage.get_map_size().y * stage.get_tile_size())
	return Vector2(clampf(scroll_offset.x, 0, maxf(0, tex.x - native.x)), clampf(scroll_offset.y, 0, maxf(0, tex.y - native.y)))
