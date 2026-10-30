@tool
extends Control
## Animation preview: exact frame crop, hitboxes and origin, at 60 Hz timing.

var sprite: RetroSprite
var animation: RetroAnimation
var state_name: String = "IDLE"
var time: float = 0.0
var zoom: int = 3
var show_boxes: bool = true
var _texture: ImageTexture
var _last_image: Image

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(300, 220)

func set_data(p_sprite: RetroSprite, p_animation: RetroAnimation, p_state: String) -> void:
	sprite = p_sprite
	animation = p_animation
	state_name = p_state
	queue_redraw()

func tick(delta: float) -> void:
	time += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#10141c"))
	if sprite == null or animation == null:
		draw_string(ThemeDB.fallback_font, Vector2(12, 26), "Load a sprite and select an animation state.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8b98ad"))
		return
	var frame := animation.sample(state_name, time)
	if frame.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(12, 26), "State '%s' has no frames." % state_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffd45e"))
		return
	var si := int(frame.get("sprite_frame", 0))
	var image: Image = null
	if si >= 0 and si < sprite.get_frames().size():
		image = sprite.render_frame(si)
	if image == null:
		# Fall back to the rect stored on the animation frame.
		var r: Rect2i = frame.get("rect", Rect2i())
		if r.size.x > 0 and sprite.get_image():
			image = sprite.get_image().get_region(r)
	if image == null:
		return
	if _last_image != image:
		_last_image = image
		_texture = ImageTexture.create_from_image(image)
	var draw_size := Vector2(image.get_width(), image.get_height()) * zoom
	var center := size * 0.5
	var origin := center - draw_size * 0.5
	# Safe-area cross for the console screen.
	draw_line(Vector2(center.x, 0), Vector2(center.x, size.y), Color(1, 1, 1, 0.08))
	draw_line(Vector2(0, center.y), Vector2(size.x, center.y), Color(1, 1, 1, 0.08))
	draw_texture_rect(_texture, Rect2(origin, draw_size), true)
	draw_rect(Rect2(origin, draw_size), Color("#7fd1ff"), false, 1.0)
	if show_boxes:
		for box in frame.get("hitboxes", []):
			var r: Rect2i = box.get("rect", Rect2i())
			var c := Color("#ff7a7a") if String(box.get("type", "hit")) == "hit" else Color("#6ee7a8")
			draw_rect(Rect2(origin + Vector2(r.position) * zoom, Vector2(r.size) * zoom), c, false, 2.0)
	var label := "%s  frame %d  %df @ %dHz" % [state_name, int(frame.get("index", 0)), int(frame.get("duration", 1)), animation.get_fps()]
	draw_string(ThemeDB.fallback_font, Vector2(8, size.y - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fb4d0"))
