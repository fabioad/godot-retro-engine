@tool
extends EditorPlugin
## Adds a Terminal main screen next to Retro. The terminal engine is GDTerm
## (MIT, PTY + VT100), loaded explicitly so the prebuilt GDExtension is ready
## before the terminal scene is instantiated.

const TerminalScreen = preload("res://addons/terminal/terminal_screen.gd")
const I18n = preload("res://addons/retro_engine/i18n.gd")

var screen: Control

func _enter_tree() -> void:
	if not ClassDB.class_exists("GDTerm"):
		var err := GDExtensionManager.load_extension("res://addons/gdterm/bin/gdterm.gdextension")
		if err != OK:
			push_warning(I18n.t("terminal.extension_warning", {"err": err}))
	screen = TerminalScreen.new()
	screen.name = "Terminal"
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.hide()
	call_deferred("_move_tab_after_script")
	if OS.has_environment("RETRO_TERMINAL_SHOT"):
		_auto_screenshot.call_deferred()

func _move_tab_after_script() -> void:
	# Godot appends plugin main screens after the built-in Game/AssetLib tabs.
	# The editor does not expose a tab-reorder API, so move the Terminal button
	# in the main-screen HBox after Script. The button keeps its existing
	# pressed callable, so every tab still selects the correct plugin.
	for _attempt in range(30):
		var bar := _main_screen_bar()
		if bar != null:
			var script_button: Button = null
			var terminal_button: Button = null
			for child in bar.get_children():
				if child is Button:
					var button := child as Button
					if button.name == "Script" or button.text == "Script":
						script_button = button
					elif button.name == "Terminal" or button.text == "Terminal":
						terminal_button = button
			if script_button != null and terminal_button != null:
				if terminal_button.get_index() != script_button.get_index() + 1:
					bar.move_child(terminal_button, script_button.get_index() + 1)
				return
		await get_tree().process_frame

func _main_screen_bar() -> HBoxContainer:
	for node in get_tree().root.find_children("*", "HBoxContainer", true, false):
		if node is HBoxContainer:
			var found_script := false
			var found_terminal := false
			for child in node.get_children():
				if child is Button:
					var button := child as Button
					if button.name == "Script" or button.text == "Script":
						found_script = true
					elif button.name == "Terminal" or button.text == "Terminal":
						found_terminal = true
			if found_script and found_terminal:
				return node as HBoxContainer
	return null

func _auto_screenshot() -> void:
	await get_tree().create_timer(3.0).timeout
	if OS.has_environment("RETRO_TERMINAL_FOCUS"):
		get_window().size = Vector2i(1920, 1080)
		EditorInterface.set_distraction_free_mode(true)
		await get_tree().create_timer(1.0).timeout
	EditorInterface.set_main_screen_editor("Terminal")
	await get_tree().create_timer(2.0).timeout
	if OS.has_environment("RETRO_TERMINAL_TABS"):
		for i in range(int(OS.get_environment("RETRO_TERMINAL_TABS"))):
			screen._add_terminal()
			await get_tree().create_timer(1.0).timeout
	if OS.has_environment("RETRO_TERMINAL_CMD") and not screen._terms.is_empty():
		var gd = screen._terms[screen._current].get_node_or_null("GDTerm")
		print("TERMINAL_CMD terms=", screen._terms.size(), " current=", screen._current, " active=", gd.is_active() if gd else false, " cmd=", OS.get_environment("RETRO_TERMINAL_CMD"))
		if gd != null:
			gd.send_input(OS.get_environment("RETRO_TERMINAL_CMD") + "\r")
	var shot_delay := 4.0
	if OS.has_environment("RETRO_TERMINAL_SHOT_DELAY"):
		shot_delay = maxf(0.0, float(OS.get_environment("RETRO_TERMINAL_SHOT_DELAY")))
	await get_tree().create_timer(shot_delay).timeout
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_environment("RETRO_TERMINAL_SHOT")
	img.save_png(path)
	print("RETRO_TERMINAL_SHOT saved ", path, " ", img.get_width(), "x", img.get_height())
	get_tree().quit()

func _exit_tree() -> void:
	if screen:
		screen.close_all()
		screen.queue_free()
		screen = null

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if screen:
		screen.visible = visible
		if visible:
			screen.ensure_terminal()

func _get_plugin_name() -> String:
	return "Terminal"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Terminal", "EditorIcons")
