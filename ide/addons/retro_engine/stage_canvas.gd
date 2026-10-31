@tool
extends Control
## Renders a tile map / stage preview at integer scale, with scroll,
## parallax layers, collision and per-line sprite overlays.

signal tile_painted(map_x: int, map_y: int, button: int)
signal hovered_tile(map_x: int, map_y: int)

var stage: RetroStage
var sprite: RetroSprite
var animation: RetroAnimation
var animation_state: String = "IDLE"
var animation_time: float = 0.0

var scroll_offset: Vector2 = Vector2.ZERO
var sprite_pos: Vector2 = Vector2(128, 160)
var zoom: int = 2
var show_grid: bool = false
var show_collisions: bool = true
var show_sprites: bool = true
var show_layers: bool = true
var show_limits: bool = true
var paint_mode: bool = false
var selected_tile: int = 0
var selected_palette: int = 0

var _texture: ImageTexture
var _render: Image
var _layer_textures: Array = []
var _layer_images: Array = []
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

func set_animation(p_animation: RetroAnimation) -> void:
	animation = p_animation
	queue_redraw()

func refresh() -> void:
	_dirty = true
	queue_redraw()

func viewport_size() -> Vector2:
	if stage != null and stage.get_platform() == "megadrive":
		return Vector2(320, 224)
	return Vector2(256, 224)

func world_size() -> Vector2:
	if stage == null:
		return Vector2.ZERO
	return Vector2(stage.get_map_size()) * float(stage.get_tile_size())

func layer_parallax(index: int) -> float:
	if stage == null:
		return 1.0
	var layers := stage.get_layers()
	if index < 0 or index >= layers.size():
		return 1.0
	return float(layers[index].get("parallax", 1.0))

## Scroll position for the base map (-1) or one of the authored layers.
func layer_scroll(index: int) -> Vector2:
	if stage == null:
		return Vector2.ZERO
	var raw := scroll_offset * layer_parallax(index)
	var view := viewport_size()
	var world := world_size()
	return Vector2(
		clampf(raw.x, 0, maxf(0, world.x - view.x)),
		clampf(raw.y, 0, maxf(0, world.y - view.y)))

func _ensure_render() -> void:
	if stage == null:
		_render = null
		_texture = null
		_layer_textures.clear()
		_layer_images.clear()
		return
	if _dirty or _render == null:
		_render = stage.render()
		_texture = ImageTexture.create_from_image(_render) if _render != null else null
		_layer_textures.clear()
		_layer_images.clear()
		var base_map := stage.get_map()
		var layers := stage.get_layers()
		for i in range(layers.size()):
			var layer: Dictionary = layers[i]
			var layer_map: PackedByteArray = layer.get("map", PackedByteArray())
			var image: Image = null
			if not layer_map.is_empty():
				if layer_map == base_map:
					image = _render
				else:
					stage.set_map(layer_map)
					image = stage.render()
					stage.set_map(base_map)
			_layer_images.append(image)
			_layer_textures.append(ImageTexture.create_from_image(image) if image != null else null)
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
	var native := viewport_size()
	var scale := float(zoom)
	var view_size := native * scale
	var origin := (size - view_size) * 0.5
	origin = origin.floor()
	# Clip to the console viewport.
	draw_rect(Rect2(origin, view_size), Color.BLACK)
	# Base map first, then every visible authored layer with its own parallax.
	_draw_layer(_texture, layer_scroll(-1), origin, scale)
	if show_layers:
		var layers := stage.get_layers()
		var base_map := stage.get_map()
		for i in range(layers.size()):
			if i >= _layer_textures.size():
				break
			var layer: Dictionary = layers[i]
			if not bool(layer.get("visible", true)):
				continue
			var layer_map: PackedByteArray = layer.get("map", PackedByteArray())
			# An identical duplicate at parallax 1.0 would just repaint the base.
			if layer_map == base_map and absf(layer_parallax(i) - 1.0) < 0.0001:
				continue
			_draw_layer(_layer_textures[i], layer_scroll(i), origin, scale)
	# Frame border.
	draw_rect(Rect2(origin, view_size), Color("#7fd1ff"), false, 2.0)
	# 8x8 / 16x16 grid.
	if show_grid:
		var ts := stage.get_tile_size() * scale
		for i in range(1, int(native.x / stage.get_tile_size())):
			draw_line(origin + Vector2(i * ts, 0), origin + Vector2(i * ts, view_size.y), Color(1, 1, 1, 0.08))
		for j in range(1, int(native.y / stage.get_tile_size())):
			draw_line(origin + Vector2(0, j * ts), origin + Vector2(view_size.x, j * ts), Color(1, 1, 1, 0.08))
	var base_scroll := layer_scroll(-1)
	# Collisions.
	if show_collisions:
		for c in stage.get_collisions():
			var r: Rect2i = c if c is Rect2i else c.get("rect", Rect2i())
			var p := origin + (Vector2(r.position) - base_scroll) * scale
			draw_rect(Rect2(p, Vector2(r.size) * scale), Color(1.0, 0.35, 0.35, 0.75), false, 2.0)
	# Sprite preview.
	if show_sprites and sprite != null:
		var image: Image = null
		var frame_index := sprite_frame_index()
		if frame_index >= 0:
			image = sprite.render_frame(frame_index)
		if image == null and animation != null:
			var sample := animation.sample(animation_state, animation_time)
			if not sample.is_empty() and sprite.get_image() != null:
				var r: Rect2i = sample.get("rect", Rect2i())
				if r.size.x > 0 and r.size.y > 0:
					image = sprite.get_image().get_region(r)
		if image != null:
			var tex := ImageTexture.create_from_image(image)
			var sp := origin + (sprite_pos - base_scroll) * scale
			draw_texture_rect(tex, Rect2(sp, Vector2(image.get_width(), image.get_height()) * scale), false)
			draw_rect(Rect2(sp, Vector2(image.get_width(), image.get_height()) * scale), Color("#ffd45e"), false, 1.0)
	# Sprite-per-line limit indicator (uses the stage collision markers as a
	# conservative sample; real OAM/VDP evaluation is done by the Hardware tab).
	if show_limits:
		var limit := int(spec.get("sprites_per_line", 32))
		var layer_info := ""
		if stage.get_layers().size() > 0:
			layer_info = "  layers %d" % stage.get_layers().size()
		draw_string(ThemeDB.fallback_font, origin + Vector2(6, view_size.y - 8),
			"%s  %dx%d  line limit %d%s" % [String(spec.get("mode", stage.get_mode())), int(native.x), int(native.y), limit, layer_info],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fb4d0"))
	# Hovered tile outline.
	if paint_mode and _last_tile.x >= 0:
		var ts := stage.get_tile_size() * scale
		var tp := origin + (Vector2(_last_tile) * stage.get_tile_size() - base_scroll) * scale
		draw_rect(Rect2(tp, Vector2(ts, ts)), Color("#7fd1ff"), false, 1.5)

func _draw_layer(tex: ImageTexture, offset: Vector2, origin: Vector2, scale: float) -> void:
	if tex == null:
		return
	var native := viewport_size()
	var tex_size := Vector2(tex.get_width(), tex.get_height())
	var src := Vector2(
		clampf(offset.x, 0, maxf(0, tex_size.x - native.x)),
		clampf(offset.y, 0, maxf(0, tex_size.y - native.y)))
	draw_texture_rect_region(tex, Rect2(origin, native * scale), Rect2(src, native))

## Frame index to draw for the current animation/sheet time.
func sprite_frame_index() -> int:
	if sprite == null:
		return -1
	var frames: Array = sprite.get_frames()
	if frames.is_empty():
		return -1
	if animation != null:
		var sample: Dictionary = animation.sample(animation_state, animation_time)
		if not sample.is_empty():
			var si := int(sample.get("sprite_frame", 0))
			if si >= 0 and si < frames.size():
				return si
	var total := 0
	for f in frames:
		total += maxi(1, int(Dictionary(f).get("duration", 1)))
	if total <= 0:
		return 0
	var target := int(animation_time * 60.0) % total
	var acc := 0
	for i in range(frames.size()):
		acc += maxi(1, int(Dictionary(frames[i]).get("duration", 1)))
		if target < acc:
			return i
	return 0

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
	var native := viewport_size()
	var view_size := native * zoom
	var origin := ((size - view_size) * 0.5).floor()
	var src := _clamped_scroll()
	var p := (local_pos - origin) / float(zoom) + src
	var tile := Vector2i(int(floor(p.x / stage.get_tile_size())), int(floor(p.y / stage.get_tile_size())))
	if tile.x < 0 or tile.y < 0 or tile.x >= stage.get_map_size().x or tile.y >= stage.get_map_size().y:
		return Vector2i(-1, -1)
	return tile

func _clamped_scroll() -> Vector2:
	return layer_scroll(-1)
