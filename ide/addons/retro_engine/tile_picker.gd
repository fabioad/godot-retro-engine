@tool
extends Control
## Tile picker for a console tile sheet. Displays the real decoded tiles and
## emits the selected absolute tile index.

signal tile_selected(index: int)

var image: Image
var tile_size: int = 8
var tiles_x: int = 16
var selected_index: int = 0
var zoom: int = 2
var _texture: ImageTexture
var _dirty: bool = true

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(200, 160)

func set_tileset(p_image: Image, p_tile_size: int, p_tiles_x: int) -> void:
	image = p_image
	tile_size = p_tile_size
	tiles_x = max(1, p_tiles_x)
	_dirty = true
	queue_redraw()

func set_selected(index: int) -> void:
	selected_index = index
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#11151e"))
	if image == null:
		draw_string(ThemeDB.fallback_font, Vector2(10, 22), "No tileset", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#8b98ad"))
		return
	if _dirty:
		_texture = ImageTexture.create_from_image(image)
		_dirty = false
	var avail_w := size.x - 8
	var z := max(1, int(avail_w / max(1, image.get_width())))
	z = min(z, zoom)
	var draw_size := Vector2(image.get_width() * z, image.get_height() * z)
	var offset := Vector2(4, 4)
	draw_texture_rect(_texture, Rect2(offset, draw_size), false)
	# grid
	for x in range(0, tiles_x + 1):
		draw_line(offset + Vector2(x * tile_size * z, 0), offset + Vector2(x * tile_size * z, draw_size.y), Color(1, 1, 1, 0.10))
	var rows := int(ceil(image.get_height() / float(tile_size)))
	for y in range(0, rows + 1):
		draw_line(offset + Vector2(0, y * tile_size * z), offset + Vector2(draw_size.x, y * tile_size * z), Color(1, 1, 1, 0.10))
	var sx: int = (selected_index % tiles_x) * tile_size * z
	var sy: int = (selected_index / tiles_x) * tile_size * z
	draw_rect(Rect2(offset + Vector2(sx, sy), Vector2(tile_size * z, tile_size * z)), Color("#ffd45e"), false, 2.0)
	custom_minimum_size.y = draw_size.y + 8

func _gui_input(event: InputEvent) -> void:
	if image == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var z := max(1, int((size.x - 8) / max(1, image.get_width())))
			z = min(z, zoom)
			var offset := Vector2(4, 4)
			var p := (mb.position - offset) / float(z * tile_size)
			if p.x >= 0 and p.y >= 0:
				var tx := int(floor(p.x))
				var ty := int(floor(p.y))
				var idx := ty * tiles_x + tx
				var total := int(ceil(image.get_height() / float(tile_size))) * tiles_x
				if idx < total:
					selected_index = idx
					tile_selected.emit(idx)
					queue_redraw()
			accept_event()
