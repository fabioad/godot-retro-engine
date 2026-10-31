extends SceneTree
## Terminal main screen regression test.
## Loads the bundled GDTerm GDExtension, starts a real OS shell through the
## VSCode-style TerminalScreen, creates/switches/closes tabs and checks the
## `+`, `-` and Terminals menu paths.

const EXTENSION := "res://addons/gdterm/bin/gdterm.gdextension"
const SCREEN := "res://addons/terminal/terminal_screen.gd"
const MARKER := "/tmp/retro_terminal_test_marker.txt"

var ok := true

func _initialize() -> void:
	await process_frame
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	OS.set_environment("RETRO_TERMINAL_CONFIG", "user://terminal_test.cfg")
	if FileAccess.file_exists(MARKER):
		DirAccess.remove_absolute(MARKER)

	var tab_order: Array = []
	for _i in range(40):
		tab_order = _main_screen_tab_names()
		if tab_order.has("Script") and tab_order.has("Terminal"):
			break
		await process_frame
	var script_index := tab_order.find("Script")
	var terminal_index := tab_order.find("Terminal")
	print("TERMINAL_TAB_ORDER ", tab_order)
	ok = ok and script_index >= 0 and terminal_index == script_index + 1

	var err := GDExtensionManager.load_extension(EXTENSION)
	print("TERMINAL_EXTENSION error=", err, " class=", ClassDB.class_exists("GDTerm"))
	# The editor plugin may have loaded it already (status 2 = already loaded).
	ok = ok and ClassDB.class_exists("GDTerm")

	var screen = load(SCREEN).new()
	get_root().add_child(screen)
	screen.show()
	await process_frame
	screen.ensure_terminal()
	await _wait_for_terminal(screen, 0, 600)
	var first = screen._terms[0]
	var first_term = first.get_node("GDTerm")
	print("TERMINAL_FIRST active=", first_term.is_active(), " tabs=", screen._tabs.tab_count, " focus=", first_term.has_focus())
	ok = ok and first_term.is_active() and screen._tabs.tab_count == 1 and first_term.has_focus()

	# A real shell must execute a command typed through the PTY.
	first_term.send_input("echo TERMINAL_OK > " + MARKER + "\r")
	var marker_ok := false
	for i in range(300):
		await create_timer(0.05).timeout
		if FileAccess.file_exists(MARKER):
			marker_ok = true
			break
	var marker_text := ""
	if FileAccess.file_exists(MARKER):
		marker_text = FileAccess.get_file_as_string(MARKER).strip_edges()
	print("TERMINAL_SHELL marker=", marker_text)
	ok = ok and marker_ok and marker_text == "TERMINAL_OK"

	# + button creates a tab, and the new terminal starts its own shell.
	var plus := _find_button(screen, "+")
	ok = ok and plus != null
	if plus:
		plus.pressed.emit()
	await process_frame
	ok = ok and screen._terms.size() == 2 and screen._tabs.tab_count == 2
	ok = ok and screen._current == 1
	await _wait_for_terminal(screen, 1, 600)
	var second_term = screen._terms[1].get_node("GDTerm")
	print("TERMINAL_ADD tabs=", screen._tabs.tab_count, " active=", second_term.is_active(), " focus=", second_term.has_focus())
	ok = ok and second_term.is_active() and second_term.has_focus()

	# Font size controls affect every open terminal and persist to disk.
	var base_size := int(first_term.get("font_size"))
	print("TERMINAL_FONT base=", base_size, " model=", screen._font_size)
	ok = ok and base_size == screen._font_size
	screen._change_font_size(2)
	await process_frame
	var bigger := clampi(base_size + 2, 12, 48)
	print("TERMINAL_FONT increase=", int(first_term.get("font_size")), " second=", int(second_term.get("font_size")))
	ok = ok and int(first_term.get("font_size")) == bigger and int(second_term.get("font_size")) == bigger
	screen._change_font_size(-4)
	await process_frame
	var smaller := clampi(base_size - 2, 12, 48)
	print("TERMINAL_FONT decrease=", int(first_term.get("font_size")))
	ok = ok and int(first_term.get("font_size")) == smaller
	screen._set_font_size(999)
	ok = ok and int(first_term.get("font_size")) == 48
	screen._set_font_size(0)
	ok = ok and int(first_term.get("font_size")) == 12
	screen._set_font_size(base_size)
	await process_frame
	ok = ok and int(first_term.get("font_size")) == base_size and int(second_term.get("font_size")) == base_size
	var fcfg := ConfigFile.new()
	ok = ok and fcfg.load("user://terminal_test.cfg") == OK and int(fcfg.get_value("terminal", "font_size", -1)) == base_size
	var font_texts := []
	var fpopup: PopupMenu = screen._font_menu.get_popup()
	for i in range(fpopup.item_count):
		font_texts.append(fpopup.get_item_text(i))
	print("TERMINAL_FONT menu=", font_texts)
	ok = ok and font_texts.has("Increase Font  (Ctrl+=)") and font_texts.has("Decrease Font  (Ctrl+-)") and font_texts.has("Reset Font  (Ctrl+0)")
	var shortcut_before := int(first_term.get("font_size"))
	var shortcut_event := InputEventKey.new()
	shortcut_event.keycode = KEY_EQUAL
	shortcut_event.ctrl_pressed = true
	shortcut_event.pressed = true
	Input.parse_input_event(shortcut_event)
	await process_frame
	print("TERMINAL_FONT shortcut=", int(first_term.get("font_size")))
	ok = ok and int(first_term.get("font_size")) == clampi(shortcut_before + 2, 12, 48)
	screen._set_font_size(base_size)
	await process_frame

	# Tab switching keeps both terminals alive.
	screen._tabs.current_tab = 0
	await process_frame
	ok = ok and screen._current == 0 and screen._terms[0].visible and not screen._terms[1].visible
	print("TERMINAL_SWITCH current=", screen._current, " visible0=", screen._terms[0].visible, " visible1=", screen._terms[1].visible, " focus0=", first_term.has_focus())
	ok = ok and first_term.has_focus()

	# The new tab must still be reachable after switching away from it.
	screen._tabs.current_tab = 1
	await process_frame
	print("TERMINAL_RETURN current=", screen._current, " visible1=", screen._terms[1].visible, " focus1=", second_term.has_focus())
	ok = ok and screen._current == 1 and screen._terms[1].visible and second_term.has_focus()
	screen._tabs.current_tab = 0
	await process_frame
	ok = ok and screen._current == 0

	# - button closes the current terminal only.
	var minus := _find_button(screen, "−")
	ok = ok and minus != null
	if minus:
		minus.pressed.emit()
	await process_frame
	print("TERMINAL_CLOSE terms=", screen._terms.size(), " tabs=", screen._tabs.tab_count)
	ok = ok and screen._terms.size() == 1 and screen._tabs.tab_count == 1

	# Terminals menu exposes create/close/select entries.
	var popup: PopupMenu = screen._menu.get_popup()
	var menu_text := []
	for i in range(popup.item_count):
		menu_text.append(popup.get_item_text(i))
	print("TERMINAL_MENU ", menu_text)
	ok = ok and menu_text.has("New Terminal") and menu_text.has("Close Current Terminal") and menu_text.has("Terminal 1")
	screen._on_menu_id(1000)
	await process_frame
	ok = ok and screen._terms.size() == 2
	screen._on_menu_id(1001)
	await process_frame
	ok = ok and screen._terms.size() == 1
	screen._menu.get_popup().id_pressed.emit(1000)
	await process_frame
	ok = ok and screen._terms.size() == 2
	print("TERMINAL_MENU_ACTIONS terms=", screen._terms.size())

	# Closing everything returns to the empty state without crashing.
	while not screen._terms.is_empty():
		screen._close_current()
		await process_frame
	print("TERMINAL_EMPTY terms=", screen._terms.size(), " empty_visible=", screen._empty.visible)
	ok = ok and screen._terms.is_empty() and screen._tabs.tab_count == 0 and screen._empty.visible

	if FileAccess.file_exists(MARKER):
		DirAccess.remove_absolute(MARKER)
	var test_cfg := ProjectSettings.globalize_path("user://terminal_test.cfg")
	if FileAccess.file_exists(test_cfg):
		DirAccess.remove_absolute(test_cfg)
	TranslationServer.set_locale(previous_locale)
	print("TERMINAL_TEST ", "PASS" if ok else "FAIL")
	screen.queue_free()
	await process_frame
	quit(0 if ok else 1)

func _main_screen_tab_names() -> Array:
	for node in get_root().find_children("*", "HBoxContainer", true, false):
		if not (node is HBoxContainer):
			continue
		var names: Array = []
		var has_script := false
		var has_terminal := false
		for child in node.get_children():
			if child is Button:
				var button := child as Button
				names.append(String(button.name))
				if button.name == "Script" or button.text == "Script":
					has_script = true
				elif button.name == "Terminal" or button.text == "Terminal":
					has_terminal = true
		if has_script and has_terminal:
			return names
	return []

func _wait_for_terminal(screen: Control, index: int, frames: int) -> void:
	for i in range(frames):
		await process_frame
		if index >= screen._terms.size():
			return
		var gd = screen._terms[index].get_node_or_null("GDTerm")
		if gd and gd.is_active():
			return

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found:
			return found
	return null
