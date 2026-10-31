@tool
extends PanelContainer
## Compact on-screen joypad for the real ROM preview.
##
## The button count stays the same for both consoles (D-pad + six action
## buttons + Start/Select-Mode), but the letters follow the active joypad:
## SNES L/X/R + Y/B/A, Mega Drive X/Y/Z + A/B/C. Buttons are deliberately tiny
## so the Preview layout keeps its size.

const FACE_LAYOUT := {
	"snes": ["L", "X", "R", "Y", "B", "A"],
	"megadrive": ["X", "Y", "Z", "A", "B", "C"],
}
const SNES_BITS := {
	"B": 0, "Y": 1, "SELECT": 2, "START": 3,
	"UP": 4, "DOWN": 5, "LEFT": 6, "RIGHT": 7,
	"A": 8, "X": 9, "L": 10, "R": 11,
}
const MD_BITS := {
	"B": 0, "A": 1, "MODE": 2, "START": 3,
	"UP": 4, "DOWN": 5, "LEFT": 6, "RIGHT": 7,
	"C": 8, "Y": 9, "X": 10, "Z": 11,
}

var preview
var platform := "snes"
var _face_buttons: Array[Button] = []
var _start_button: Button
var _select_button: Button

func _ready() -> void:
	custom_minimum_size = Vector2(190, 78)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0c1117")
	style.border_color = Color("#25303c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	add_theme_stylebox_override("panel", style)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)
	add_child(root)
	var title := Label.new()
	title.text = "PAD"
	title.add_theme_font_size_override("font_size", 8)
	title.add_theme_color_override("font_color", Color("#7fd1ff"))
	root.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)
	row.add_child(_build_dpad())
	row.add_child(_build_face())
	row.add_child(_build_start_select())
	_apply_platform()

func set_preview(p_preview) -> void:
	preview = p_preview

func set_platform(p_platform: String) -> void:
	platform = "megadrive" if p_platform == "megadrive" else "snes"
	_apply_platform()

func _build_dpad() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(_spacer())
	grid.add_child(_direction_button("▲", "UP"))
	grid.add_child(_spacer())
	grid.add_child(_direction_button("◀", "LEFT"))
	grid.add_child(_spacer())
	grid.add_child(_direction_button("▶", "RIGHT"))
	grid.add_child(_spacer())
	grid.add_child(_direction_button("▼", "DOWN"))
	grid.add_child(_spacer())
	return grid

func _build_face() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in range(6):
		var button := _small_button("", 19, 19, 8)
		button.button_down.connect(_on_face_down.bind(i, true))
		button.button_up.connect(_on_face_up.bind(i))
		_face_buttons.append(button)
		grid.add_child(button)
	return grid

func _build_start_select() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_start_button = _small_button("START", 34, 16, 6)
	_start_button.button_down.connect(_on_down.bind("START", true))
	_start_button.button_up.connect(_on_up.bind("START"))
	col.add_child(_start_button)
	_select_button = _small_button("SEL", 34, 16, 6)
	_select_button.button_down.connect(_on_down.bind("SEL", true))
	_select_button.button_up.connect(_on_up.bind("SEL"))
	col.add_child(_select_button)
	return col

func _direction_button(text: String, label: String) -> Button:
	var button := _small_button(text, 18, 18, 8)
	button.button_down.connect(_on_down.bind(label, false))
	button.button_up.connect(_on_up.bind(label))
	return button

func _small_button(text: String, width: float, height: float, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, height)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", font_size)
	return button

func _spacer() -> Control:
	var control := Control.new()
	control.custom_minimum_size = Vector2(18, 18)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control

func _apply_platform() -> void:
	if _face_buttons.is_empty():
		return
	var labels: Array = FACE_LAYOUT.get(platform, FACE_LAYOUT["snes"])
	for i in range(_face_buttons.size()):
		var label := String(labels[i])
		var button := _face_buttons[i]
		button.text = label
		button.tooltip_text = ("SNES " if platform == "snes" else "Mega Drive ") + label
		button.add_theme_color_override("font_color", _label_color(label))
	_select_button.text = "SEL" if platform == "snes" else "MODE"
	_select_button.tooltip_text = "Select" if platform == "snes" else "Mode"
	_start_button.tooltip_text = "Start"

func _label_color(label: String) -> Color:
	match label:
		"A": return Color("#ff8a8a")
		"B": return Color("#ffd45e")
		"C": return Color("#7fd1ff")
		"X": return Color("#7fd1ff")
		"Y": return Color("#6ee7a8")
		"Z": return Color("#c792ea")
		"L", "R": return Color("#c8d4e6")
		"START": return Color("#ffd45e")
		"SELECT", "MODE", "SEL": return Color("#9fb4d0")
	return Color("#c8d4e6")

func _mask_for(label: String) -> int:
	var key := label.to_upper()
	if key == "SEL" or key == "SELECT" or key == "MODE":
		key = "MODE" if platform == "megadrive" else "SELECT"
	var table: Dictionary = MD_BITS if platform == "megadrive" else SNES_BITS
	return int(table.get(key, 0))

func _on_face_down(index: int, watch: bool) -> void:
	if index < 0 or index >= _face_buttons.size():
		return
	_on_down(_face_buttons[index].text, watch)

func _on_face_up(index: int) -> void:
	if index < 0 or index >= _face_buttons.size():
		return
	_on_up(_face_buttons[index].text)

func _display_label(label: String) -> String:
	if label == "SEL":
		return "MODE" if platform == "megadrive" else "SELECT"
	return label

func _on_down(label: String, watch: bool) -> void:
	if preview == null:
		return
	preview.press_mask(_mask_for(label), _display_label(label), watch)

func _on_up(label: String) -> void:
	if preview == null:
		return
	preview.release_mask(_mask_for(label), _display_label(label))
