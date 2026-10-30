@tool
extends RefCounted
## Visible minimize / maximize-restore / close controls for the Retro windows.
## Drawn icons are used instead of theme icons because some desktop shells
## (including Noctalia) only expose a close button in the native titlebar.

static func make_icon(kind: String) -> ImageTexture:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.92, 0.95, 1.0, 1.0)
	match kind:
		"minimize":
			for x in range(4, 16):
				for t in range(2):
					img.set_pixel(x, 14 + t, c)
		"maximize":
			for x in range(4, 16):
				for t in range(2):
					img.set_pixel(x, 4 + t, c)
					img.set_pixel(x, 14 + t, c)
			for y in range(4, 16):
				for t in range(2):
					img.set_pixel(4 + t, y, c)
					img.set_pixel(14 + t, y, c)
		"restore":
			for x in range(7, 16):
				for t in range(2):
					img.set_pixel(x, 4 + t, c)
					img.set_pixel(x, 12 + t, c)
			for y in range(4, 13):
				for t in range(2):
					img.set_pixel(7 + t, y, c)
					img.set_pixel(14 + t, y, c)
			for x in range(4, 13):
				for t in range(2):
					img.set_pixel(x, 7 + t, c)
					img.set_pixel(x, 15 + t, c)
			for y in range(7, 16):
				for t in range(2):
					img.set_pixel(4 + t, y, c)
					img.set_pixel(12 + t, y, c)
		_:
			for i in range(5, 16):
				for t in range(2):
					img.set_pixel(i, i + t, c)
					img.set_pixel(19 - i, i + t, c)
	return ImageTexture.create_from_image(img)

static func _button(kind: String, tooltip: String, action: Callable) -> Button:
	var b := Button.new()
	b.icon = make_icon(kind)
	b.expand_icon = true
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(32, 28)
	b.tooltip_text = tooltip
	b.add_theme_color_override("icon_normal_color", Color("#e6edf7"))
	b.add_theme_color_override("icon_hover_color", Color("#ffffff"))
	b.add_theme_color_override("icon_pressed_color", Color("#7fd1ff"))
	b.pressed.connect(action)
	return b

static var _maximized := false
static var _restore_position := Vector2i(40, 30)
static var _restore_size := Vector2i(1600, 1000)

static func is_maximized() -> bool:
	return _maximized

static func toggle_maximize(window: Window) -> void:
	if window == null:
		return
	var window_id := window.get_window_id()
	var screen := DisplayServer.window_get_current_screen(window_id)
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var size := DisplayServer.window_get_size(window_id)
	var is_full := size.x >= usable.size.x - 4 and size.y >= usable.size.y - 4
	if _maximized or is_full:
		window.mode = Window.MODE_WINDOWED
		window.size = _restore_size
		window.position = _restore_position
		_maximized = false
	else:
		_restore_size = size
		_restore_position = DisplayServer.window_get_position(window_id)
		_maximized = true
		# Prefer the compositor's maximize request, but also resize manually so
		# shells that only expose a close button still fill the usable screen.
		window.mode = Window.MODE_WINDOWED
		window.position = usable.position
		window.size = usable.size

static func add_controls(parent: Container, window: Window, close_hides: bool = true) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.name = "WindowControlsPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.13, 0.18, 0.96)
	style.border_color = Color(0.32, 0.42, 0.55, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.name = "WindowControls"
	panel.add_child(row)
	row.add_child(_button("minimize", "Minimize", func():
		if window != null:
			window.mode = Window.MODE_MINIMIZED))
	row.add_child(_button("maximize", "Maximize / Restore", func():
		toggle_maximize(window)))
	row.add_child(_button("close", "Close", func():
		if window == null:
			return
		if close_hides:
			window.hide()
		else:
			window.get_tree().quit()))
	parent.add_child(panel)
	return row
