@tool
extends Control
## Two-character hit/hurtbox canvas for the collision editor.

signal box_selected(index: int)
signal box_moved(index: int, rect: Rect2i)

var sprite: RetroSprite
var animation: RetroAnimation
var player_state: String = "IDLE"
var player_frame: int = 0
var opponent_state: String = "IDLE"
var opponent_frame: int = 0
var player_pos: Vector2i = Vector2i(24, 24)
var opponent_pos: Vector2i = Vector2i(204, 24)
var zoom: int = 2
var show_boxes: bool = true
var show_sprites: bool = true
var show_opponent: bool = true
var contacts: Array = []
var selected_box: int = -1
var _textures: Dictionary = {}
var _drag_index: int = -1
var _drag_start: Vector2i = Vector2i.ZERO

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(380, 260)

func set_data(p_sprite: RetroSprite, p_animation: RetroAnimation, p_state: String, p_frame: int) -> void:
	sprite = p_sprite
	animation = p_animation
	player_state = p_state
	player_frame = p_frame
	queue_redraw()

func set_opponent(p_sprite: RetroSprite, p_animation: RetroAnimation, p_state: String, p_frame: int) -> void:
	sprite = p_sprite
	animation = p_animation
	opponent_state = p_state
	opponent_frame = p_frame
	queue_redraw()

func set_positions(p_player: Vector2i, p_opponent: Vector2i) -> void:
	player_pos = p_player
	opponent_pos = p_opponent
	queue_redraw()

func set_contacts(p_contacts: Array) -> void:
	contacts = p_contacts
	queue_redraw()

func set_selected(index: int) -> void:
	selected_box = index
	queue_redraw()

func _get_frame_image(state: String, frame_index: int) -> Image:
	if animation == null or sprite == null:
		return null
	var s: Dictionary = animation.get_state(state)
	var frames: Array = s.get("frames", [])
	if frame_index < 0 or frame_index >= frames.size():
		return null
	var f: Dictionary = frames[frame_index]
	var sprite_frame := int(f.get("sprite_frame", 0))
	if sprite_frame < 0 or sprite_frame >= sprite.get_frames().size():
		return null
	return sprite.render_frame(sprite_frame)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#10141c"))
	var line := Color(1, 1, 1, 0.05)
	for x in range(0, int(size.x), 32):
		draw_line(Vector2(x, 0), Vector2(x, size.y), line)
	for y in range(0, int(size.y), 32):
		draw_line(Vector2(0, y), Vector2(size.x, y), line)
	if animation == null or sprite == null:
		draw_string(ThemeDB.fallback_font, Vector2(12, 24), "Load a sprite + animation to edit hitboxes.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8b98ad"))
		return
	var p_frame: Dictionary = animation.get_state_frame(player_state, player_frame)
	if p_frame.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(12, 24), "State '%s' has no frame %d." % [player_state, player_frame], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffd45e"))
		return
	var p_img := _get_frame_image(player_state, player_frame)
	if show_sprites and p_img:
		var key := player_state + ":" + str(player_frame)
		if not _textures.has(key) or _textures[key] == null:
			_textures[key] = ImageTexture.create_from_image(p_img)
		draw_texture_rect(_textures[key], Rect2(Vector2(player_pos) * zoom, Vector2(p_img.get_width(), p_img.get_height()) * zoom), false)
	var o_img: Image = null
	if show_opponent and show_sprites:
		o_img = _get_frame_image(opponent_state, opponent_frame)
		if o_img:
			var okey := opponent_state + ":" + str(opponent_frame) + ":o"
			if not _textures.has(okey) or _textures[okey] == null:
				_textures[okey] = ImageTexture.create_from_image(o_img)
			draw_texture_rect(_textures[okey], Rect2(Vector2(opponent_pos) * zoom, Vector2(o_img.get_width(), o_img.get_height()) * zoom), false)
	if show_boxes:
		_draw_boxes(player_state, player_frame, player_pos, false)
		if show_opponent:
			_draw_boxes(opponent_state, opponent_frame, opponent_pos, true)
	for c in contacts:
		var r: Rect2i = c.get("rect", Rect2i())
		draw_rect(Rect2(Vector2(r.position) * zoom, Vector2(r.size) * zoom), Color(1, 0.15, 0.15, 0.75), true)
		draw_rect(Rect2(Vector2(r.position) * zoom, Vector2(r.size) * zoom), Color(1, 0.4, 0.2), false, 2.0)
	var label := "%s F%d  vs  %s F%d  |  zoom %dx" % [player_state, player_frame, opponent_state, opponent_frame, zoom]
	draw_string(ThemeDB.fallback_font, Vector2(8, size.y - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fb4d0"))

func _draw_boxes(state: String, frame: int, pos: Vector2i, opponent: bool) -> void:
	var boxes: Array = animation.get_frame_hitboxes(state, frame)
	for i in range(boxes.size()):
		var b: Dictionary = boxes[i]
		var r: Rect2i = b.get("rect", Rect2i())
		var is_hit := String(b.get("type", "hit")) == "hit"
		var c := Color("#ff7a7a") if is_hit else Color("#6ee7a8")
		if opponent:
			c.a = 0.55
		var p := Vector2(pos + r.position) * zoom
		var s := Vector2(r.size) * zoom
		draw_rect(Rect2(p, s), c, false, 2.0 if not opponent else 1.0)
		if not opponent and i == selected_box:
			draw_rect(Rect2(p + Vector2(2, 2), s - Vector2(4, 4)), Color("#ffd45e"), false, 1.0)

func _to_world(local: Vector2) -> Vector2i:
	return Vector2i((local / zoom).floor())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var w := _to_world(mb.position)
			var boxes: Array = animation.get_frame_hitboxes(player_state, player_frame) if animation else []
			selected_box = -1
			for i in range(boxes.size()):
				var r: Rect2i = boxes[i].get("rect", Rect2i())
				r.position += player_pos
				if r.has_point(w):
					selected_box = i
					_drag_index = i
					_drag_start = w - r.position
					break
			box_selected.emit(selected_box)
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_drag_index = -1
	elif event is InputEventMouseMotion and _drag_index >= 0:
		var w := _to_world((event as InputEventMouseMotion).position)
		var boxes: Array = animation.get_frame_hitboxes(player_state, player_frame)
		if _drag_index < boxes.size():
			var b: Dictionary = boxes[_drag_index]
			var r: Rect2i = b.get("rect", Rect2i())
			r.position = w - _drag_start - player_pos
			b["rect"] = r
			boxes[_drag_index] = b
			animation.set_frame_hitboxes(player_state, player_frame, boxes)
			box_moved.emit(_drag_index, r)
			queue_redraw()
