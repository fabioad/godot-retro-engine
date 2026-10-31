@tool
extends EditorPlugin

const RetroMainScreen = preload("res://addons/retro_engine/retro_main.gd")
const WindowControls = preload("res://addons/retro_engine/window_controls.gd")

var main_screen: Control
var toolbar: HBoxContainer
var platform_selector: OptionButton
var _titlebar_controls: Control
var _titlebar_node: Control
var _applied_title: String = ""
var _title_timer: Timer

func _enter_tree() -> void:
	main_screen = RetroMainScreen.new()
	EditorInterface.get_editor_main_screen().add_child(main_screen)
	main_screen.hide()
	_build_toolbar()
	set_process_input(true)
	call_deferred("_install_titlebar_double_click")
	# Land directly in the Retro workspace on startup.
	call_deferred("_select_retro_screen")
	call_deferred("_apply_window_title")
	call_deferred("_sync_platform_toolbar")
	call_deferred("_install_title_watch")
	_title_timer = Timer.new()
	_title_timer.wait_time = 2.0
	_title_timer.autostart = true
	_title_timer.timeout.connect(_apply_window_title)
	add_child(_title_timer)

func _select_retro_screen() -> void:
	await get_tree().create_timer(1.5).timeout
	if DisplayServer.get_name() != "headless":
		var screen := DisplayServer.screen_get_size()
		var w := mini(1600, maxi(900, screen.x - 80))
		var h := mini(1000, maxi(650, screen.y - 80))
		DisplayServer.window_set_size(Vector2i(w, h))
		DisplayServer.window_set_position(Vector2i(40, 30))
	EditorInterface.set_main_screen_editor("Retro")
	if main_screen:
		main_screen.visible = true
	_apply_window_title()

func _install_titlebar_double_click() -> void:
	if _titlebar_node != null:
		return
	var titles := get_tree().root.find_children("*", "EditorTitleBar", true, false)
	if titles.is_empty():
		return
	_titlebar_node = titles[0]
	if not _titlebar_node.gui_input.is_connected(_on_titlebar_gui_input):
		_titlebar_node.gui_input.connect(_on_titlebar_gui_input)

func _on_titlebar_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed or not mb.double_click:
		return
	# Always handle this ourselves and consume the event: some shells
	# (Noctalia) advertise the native feature but do not implement it.
	WindowControls.toggle_maximize(get_window())
	if _titlebar_node != null:
		_titlebar_node.accept_event()

func _input(event: InputEvent) -> void:
	# The editor titlebar's empty areas are spacers/non-client regions in some
	# shells, so the Control gui_input signal is not always delivered. Handle
	# the double-click at plugin input level and skip interactive widgets.
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed or not mb.double_click:
		return
	if _titlebar_node == null:
		return
	var point := mb.position
	if not _titlebar_node.get_global_rect().has_point(point):
		point = mb.global_position
	if not _titlebar_node.get_global_rect().has_point(point):
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered is Button or hovered is LineEdit or hovered is TextEdit or hovered is SpinBox:
		return
	WindowControls.toggle_maximize(get_window())
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if _titlebar_node != null and _titlebar_node.gui_input.is_connected(_on_titlebar_gui_input):
		_titlebar_node.gui_input.disconnect(_on_titlebar_gui_input)
	_titlebar_node = null
	var win := get_window()
	if win != null and win.title_changed.is_connected(_on_window_title_changed):
		win.title_changed.disconnect(_on_window_title_changed)
	if toolbar:
		remove_control_from_container(CONTAINER_TOOLBAR, toolbar)
		toolbar.queue_free()
		toolbar = null
	if _title_timer:
		_title_timer.stop()
		_title_timer.queue_free()
		_title_timer = null
	if main_screen:
		main_screen.queue_free()
		main_screen = null

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if main_screen:
		main_screen.visible = visible
		if visible:
			main_screen.refresh_all()
			call_deferred("_apply_window_title")

func _install_title_watch() -> void:
	var win := get_window()
	if win != null and not win.title_changed.is_connected(_on_window_title_changed):
		win.title_changed.connect(_on_window_title_changed)
	_apply_window_title()

func _sync_platform_toolbar() -> void:
	if platform_selector == null or main_screen == null:
		return
	var index := 0 if main_screen.platform == "snes" else 1
	if platform_selector.selected != index:
		platform_selector.select(index)

func _apply_window_title() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_sync_platform_toolbar()
	var win := get_window()
	if win == null:
		return
	var version := _plugin_version()
	var build := _build_code()
	var title := "Godot Retro Engine %s (build %s) - Godot Engine" % [version, build]
	_applied_title = title
	if win.title != title:
		win.title = title
	# The editor's own _update_title() writes directly through DisplayServer,
	# without changing Window.title. Re-assert the OS title from the timer.
	DisplayServer.window_set_title(title)

func _on_window_title_changed() -> void:
	var win := get_window()
	if win != null and win.title != _applied_title:
		call_deferred("_apply_window_title")

func _plugin_version() -> String:
	var path := "res://addons/retro_engine/plugin.cfg"
	if FileAccess.file_exists(path):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var trimmed := line.strip_edges()
			if trimmed.begins_with("version="):
				return trimmed.substr(8).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return "0.0.0"

func _build_code() -> String:
	var stamp := ""
	var stamp_path := "res://.package_stamp"
	if FileAccess.file_exists(stamp_path):
		stamp = FileAccess.get_file_as_string(stamp_path).strip_edges()
	if stamp.is_empty():
		stamp = OS.get_environment("GODOT_RETRO_BUILD").strip_edges()
	if stamp.is_empty():
		return "dev"
	var parts := stamp.split("-")
	if parts.size() >= 2 and not parts[1].is_empty():
		return parts[1]
	return stamp

func _get_plugin_name() -> String:
	return "Retro"

func _get_plugin_icon() -> Texture2D:
	# Use a built-in editor icon so the plugin has no external dependency.
	return EditorInterface.get_editor_theme().get_icon("Sprite2D", "EditorIcons")

func _build_toolbar() -> void:
	toolbar = HBoxContainer.new()
	toolbar.name = "RetroToolbar"
	toolbar.add_theme_constant_override("separation", 2)
	toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	toolbar.gui_input.connect(_on_titlebar_gui_input)
	var label := Label.new()
	label.text = "Retro:"
	toolbar.add_child(label)
	platform_selector = OptionButton.new()
	platform_selector.add_item("SNES", 0)
	platform_selector.add_item("Mega Drive", 1)
	platform_selector.tooltip_text = "Active retro platform"
	platform_selector.item_selected.connect(_on_platform_toolbar)
	toolbar.add_child(platform_selector)
	var build_button := Button.new()
	build_button.text = "Build"
	build_button.tooltip_text = "Build the active retro project"
	build_button.pressed.connect(_on_build_toolbar)
	toolbar.add_child(build_button)
	var run_button := Button.new()
	run_button.text = "Run"
	run_button.tooltip_text = "Run the last built ROM in an emulator"
	run_button.pressed.connect(_on_run_toolbar)
	toolbar.add_child(run_button)
	toolbar.add_child(VSeparator.new())
	var controls := WindowControls.add_controls(toolbar, get_window(), false)
	var controls_panel: Control = controls.get_parent()
	controls_panel.name = "RetroTitleBarControls"
	_titlebar_controls = controls_panel
	add_control_to_container(CONTAINER_TOOLBAR, toolbar)

func _on_platform_toolbar(index: int) -> void:
	if main_screen:
		main_screen.set_platform("snes" if index == 0 else "megadrive")

func _on_build_toolbar() -> void:
	if main_screen:
		main_screen.build_active()

func _on_run_toolbar() -> void:
	if main_screen:
		main_screen.run_active()
