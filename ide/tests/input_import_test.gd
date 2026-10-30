extends SceneTree
## Godot InputMap -> RetroInputMap import regression.

func _initialize() -> void:
	await process_frame
	var out := "/tmp/retro_input_import_test"
	DirAccess.make_dir_recursive_absolute(out)
	var project := RetroProject.new()
	project.set_name("input_import_test")
	project.set_path(out)
	project.set_source_path(out)
	project.set_platform("snes")
	project.set_mode("mode1")
	var editor = preload("res://addons/retro_engine/input_editor.gd").new()
	get_root().add_child(editor)
	await process_frame
	editor.set_context(project, "snes", null)
	await process_frame

	# A directional key action, a jump button action and the built-in accept
	# action exercise the name mapping, keyboard/gamepad extraction and merge
	# path (ui_accept must update the existing "start" action).
	InputMap.add_action("move_left")
	var left_key := InputEventKey.new()
	left_key.physical_keycode = KEY_A
	InputMap.action_add_event("move_left", left_key)
	InputMap.add_action("jump")
	var jump_pad := InputEventJoypadButton.new()
	jump_pad.button_index = JOY_BUTTON_A
	InputMap.action_add_event("jump", jump_pad)
	InputMap.add_action("ui_accept")
	var enter_key := InputEventKey.new()
	enter_key.physical_keycode = KEY_ENTER
	InputMap.action_add_event("ui_accept", enter_key)

	editor._import_godot_inputmap()
	await process_frame

	var left: Dictionary = editor.input_map.get_action("move_left")
	var jump: Dictionary = editor.input_map.get_action("jump")
	var start: Dictionary = editor.input_map.get_action("start")
	var ok := true
	ok = ok and not left.is_empty() and left.get("snes", []).has("Left") and left.get("md", []).has("Left")
	ok = ok and left.get("keys", []).has("A")
	ok = ok and not jump.is_empty() and jump.get("snes", []).has("A") and jump.get("md", []).has("A")
	ok = ok and jump.get("gamepad", []).has("JOY_A")
	ok = ok and not start.is_empty() and start.get("keys", []).has("Enter")
	ok = ok and String(start.get("state", "")) == "IDLE"
	print("INPUT_IMPORT left=", left)
	print("INPUT_IMPORT jump=", jump)
	print("INPUT_IMPORT start=", start)
	print("INPUT_IMPORT ", "PASS" if ok else "FAIL")

	InputMap.erase_action("move_left")
	InputMap.erase_action("jump")
	InputMap.erase_action("ui_accept")
	editor.queue_free()
	await process_frame
	quit(0 if ok else 1)
