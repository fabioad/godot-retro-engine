@tool
extends VBoxContainer
## Palette editor with console-aware limits and exact-index preservation.

signal palette_changed(palette: PackedColorArray)
signal import_requested()
signal export_requested()

var palette: PackedColorArray = PackedColorArray()
var max_colors: int = 16
var platform: String = "snes"
var _grid: GridContainer
var _picker: ColorPicker
var _selected: int = 0
var _info: Label
var _apply_button: Button

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Palette"
	title.add_theme_font_size_override("font_size", 15)
	header.add_child(title)
	header.add_child(_spacer())
	var import_btn := Button.new()
	import_btn.text = "Import .pal"
	import_btn.pressed.connect(func(): import_requested.emit())
	header.add_child(import_btn)
	var export_btn := Button.new()
	export_btn.text = "Export .pal"
	export_btn.pressed.connect(func(): export_requested.emit())
	header.add_child(export_btn)
	add_child(header)

	_info = Label.new()
	_info.text = "16 colors max"
	_info.add_theme_color_override("font_color", Color("#9fb4d0"))
	add_child(_info)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	_picker = ColorPicker.new()
	_picker.edit_alpha = false
	_picker.color_changed.connect(_on_color_changed)
	add_child(_picker)

	var row := HBoxContainer.new()
	var add_btn := Button.new()
	add_btn.text = "Add color"
	add_btn.pressed.connect(_add_color)
	row.add_child(add_btn)
	var remove_btn := Button.new()
	remove_btn.text = "Remove selected"
	remove_btn.pressed.connect(_remove_color)
	row.add_child(remove_btn)
	_apply_button = Button.new()
	_apply_button.text = "Apply to image (nearest)"
	_apply_button.pressed.connect(_apply_to_image)
	row.add_child(_apply_button)
	add_child(row)

func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

func set_platform(p: String) -> void:
	platform = p
	max_colors = 256 if p == "snes" else 64
	_update_info()

func set_palette(p_palette: PackedColorArray) -> void:
	palette = p_palette
	_selected = 0
	_rebuild()

func get_palette() -> PackedColorArray:
	return palette

func _rebuild() -> void:
	for child in _grid.get_children():
		child.queue_free()
	for i in range(palette.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(20, 20)
		b.tooltip_text = "Index %d  %s" % [i, palette[i].to_html(true)]
		var sb := StyleBoxFlat.new()
		sb.bg_color = palette[i]
		sb.border_color = Color("#ffd45e") if i == _selected else Color("#3b4658")
		sb.set_border_width_all(2 if i == _selected else 1)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.pressed.connect(func(): _select(i))
		_grid.add_child(b)
	# Transparent entry (index 0) is shown with a hatch.
	if palette.size() == 0:
		var lbl := Label.new()
		lbl.text = "No palette loaded"
		_grid.add_child(lbl)
	_update_info()

func _select(i: int) -> void:
	_selected = i
	if i < palette.size():
		_picker.set_pick_color(palette[i])
	_rebuild()

func _on_color_changed(c: Color) -> void:
	if _selected < 0 or _selected >= palette.size():
		return
	palette[_selected] = c
	_rebuild()
	palette_changed.emit(palette)

func _add_color() -> void:
	if palette.size() >= max_colors:
		_info.text = "Palette full (%d colors)" % max_colors
		return
	palette.append(Color.BLACK)
	_selected = palette.size() - 1
	_rebuild()
	palette_changed.emit(palette)

func _remove_color() -> void:
	if palette.size() <= 1:
		return
	palette.remove_at(_selected)
	_selected = clampi(_selected, 0, palette.size() - 1)
	_rebuild()
	palette_changed.emit(palette)

func _apply_to_image() -> void:
	# The active document is handled by the main screen, which listens to
	# palette_changed. This button is a convenient explicit trigger.
	palette_changed.emit(palette)

func _update_info() -> void:
	if _info == null:
		return
	var limit_text := "SNES CGRAM: 256 colors (15-bit BGR555)" if platform == "snes" else "Mega Drive CRAM: 64 colors (9-bit RGB333)"
	_info.text = "%d / %d colors  |  %s" % [palette.size(), max_colors, limit_text]
