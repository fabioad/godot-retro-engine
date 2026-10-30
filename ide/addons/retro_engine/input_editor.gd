@tool
extends VBoxContainer
## Visual input mapper and animation-state association editor.

signal modified()
signal input_changed()
signal status(text: String)

var project: RetroProject
var platform: String = "snes"
var animation: RetroAnimation
var input_map: RetroInputMap

var _list: ItemList
var _id: LineEdit
var _label: LineEdit
var _type: OptionButton
var _state: OptionButton
var _next: OptionButton
var _hold: CheckBox
var _priority: SpinBox
var _keyboard: LineEdit
var _gamepad: LineEdit
var _snes_boxes: Dictionary = {}
var _md_boxes: Dictionary = {}
var _mask_snes: Label
var _mask_md: Label
var _validation: RichTextLabel
var _summary: Label
var _form: VBoxContainer
var _current_id: String = ""
var _syncing: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var header := HBoxContainer.new()
	add_child(header)
	var title := Label.new()
	title.text = "Input Mapping / State Associations"
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var add_btn := Button.new()
	add_btn.text = "New action"
	add_btn.pressed.connect(_add_action)
	header.add_child(add_btn)
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.pressed.connect(_delete_action)
	header.add_child(del_btn)
	var import_btn := Button.new()
	import_btn.text = "Import Godot InputMap"
	import_btn.tooltip_text = "Map project InputMap actions/events to SNES and Mega Drive buttons"
	import_btn.pressed.connect(_import_godot_inputmap)
	header.add_child(import_btn)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 130
	body.add_child(left)
	var hint := Label.new()
	hint.text = "Actions"
	left.add_child(hint)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	left.add_child(_list)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_color_override("font_color", Color("#9fb4d0"))
	left.add_child(_summary)

	var form_scroll := ScrollContainer.new()
	form_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(form_scroll)
	_form = VBoxContainer.new()
	_form.custom_minimum_size = Vector2(0, 0)
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override("separation", 4)
	form_scroll.add_child(_form)

	var basic := GridContainer.new()
	basic.columns = 2
	_form.add_child(basic)
	basic.add_child(_field_label("Action id"))
	_id = LineEdit.new()
	_id.placeholder_text = "attack_a"
	basic.add_child(_id)
	basic.add_child(_field_label("Label"))
	_label = LineEdit.new()
	basic.add_child(_label)
	basic.add_child(_field_label("Type"))
	_type = OptionButton.new()
	_type.add_item("Button / press")
	_type.add_item("Hold")
	_type.add_item("Axis X")
	_type.add_item("Axis Y")
	basic.add_child(_type)
	basic.add_child(_field_label("Animation state"))
	_state = OptionButton.new()
	basic.add_child(_state)
	basic.add_child(_field_label("After action -> state"))
	_next = OptionButton.new()
	basic.add_child(_next)
	basic.add_child(_field_label("Flags"))
	var flags_row := HBoxContainer.new()
	_hold = CheckBox.new()
	_hold.text = "Require hold"
	flags_row.add_child(_hold)
	flags_row.add_child(_field_label("Priority"))
	_priority = SpinBox.new()
	_priority.min_value = 0
	_priority.max_value = 255
	_priority.custom_minimum_size.x = 60
	flags_row.add_child(_priority)
	basic.add_child(flags_row)

	var snes_label := Label.new()
	snes_label.text = "SNES buttons (PVSnesLib KEY_* / padsCurrent bits)"
	snes_label.add_theme_color_override("font_color", Color("#7fd1ff"))
	_form.add_child(snes_label)
	var snes_grid := GridContainer.new()
	snes_grid.columns = 4
	_form.add_child(snes_grid)
	for b in RetroInputMap.snes_buttons():
		var cb := CheckBox.new()
		cb.text = String(b)
		_snes_boxes[String(b)] = cb
		snes_grid.add_child(cb)

	var md_label := Label.new()
	md_label.text = "Mega Drive buttons (SGDK BUTTON_*)"
	md_label.add_theme_color_override("font_color", Color("#7fd1ff"))
	_form.add_child(md_label)
	var md_grid := GridContainer.new()
	md_grid.columns = 4
	_form.add_child(md_grid)
	for b in RetroInputMap.megadrive_buttons():
		var cb := CheckBox.new()
		cb.text = String(b)
		_md_boxes[String(b)] = cb
		md_grid.add_child(cb)

	var host := GridContainer.new()
	host.columns = 2
	_form.add_child(host)
	host.add_child(_field_label("Keyboard (IDE/test)"))
	_keyboard = LineEdit.new()
	_keyboard.placeholder_text = "Z, Space, Left..."
	host.add_child(_keyboard)
	host.add_child(_field_label("Gamepad (IDE/test)"))
	_gamepad = LineEdit.new()
	_gamepad.placeholder_text = "JOY_B, JOY_X..."
	host.add_child(_gamepad)

	_mask_snes = Label.new()
	_mask_snes.add_theme_color_override("font_color", Color("#6ee7a8"))
	_form.add_child(_mask_snes)
	_mask_md = Label.new()
	_mask_md.add_theme_color_override("font_color", Color("#6ee7a8"))
	_form.add_child(_mask_md)

	var action_row := HBoxContainer.new()
	_form.add_child(action_row)
	var apply := Button.new()
	apply.text = "Apply changes"
	apply.pressed.connect(_commit_fields)
	action_row.add_child(apply)
	var revert := Button.new()
	revert.text = "Reload selected"
	revert.pressed.connect(func(): _on_selected(_list.get_selected_items()[0] if not _list.get_selected_items().is_empty() else 0))
	action_row.add_child(revert)

	var export_label := Label.new()
	export_label.text = "Export / state-machine table"
	export_label.add_theme_color_override("font_color", Color("#7fd1ff"))
	_form.add_child(export_label)
	var exports := GridContainer.new()
	exports.columns = 2
	_form.add_child(exports)
	var h_snes := Button.new()
	h_snes.text = "SNES .h"
	h_snes.pressed.connect(func(): _export("snes_h"))
	exports.add_child(h_snes)
	var i_snes := Button.new()
	i_snes.text = "SNES .inc"
	i_snes.pressed.connect(func(): _export("snes_inc"))
	exports.add_child(i_snes)
	var h_md := Button.new()
	h_md.text = "SGDK .h"
	h_md.pressed.connect(func(): _export("md_h"))
	exports.add_child(h_md)
	var save_btn := Button.new()
	save_btn.text = "Save JSON"
	save_btn.pressed.connect(func(): _export("json"))
	exports.add_child(save_btn)
	var sm_btn := Button.new()
	sm_btn.text = "State machine C"
	sm_btn.tooltip_text = "Generate retro_input.h + retro_state_machine.c/.h without touching existing game code"
	sm_btn.pressed.connect(_export_state_machine)
	exports.add_child(sm_btn)

	var note := Label.new()
	note.text = "The generated table contains the raw console mask, target animation state, next state, hold flag and priority. The editor never rewrites your game code; include/use the generated table explicitly."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("#8b98ad"))
	_form.add_child(note)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 160
	body.add_child(right)
	var vlabel := Label.new()
	vlabel.text = "Validation"
	right.add_child(vlabel)
	_validation = RichTextLabel.new()
	_validation.bbcode_enabled = true
	_validation.fit_content = true
	_validation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_validation.custom_minimum_size.y = 180
	right.add_child(_validation)
	var sm := Label.new()
	sm.text = "State machine preview"
	sm.add_theme_color_override("font_color", Color("#7fd1ff"))
	right.add_child(sm)
	var _state_preview := RichTextLabel.new()
	_state_preview.bbcode_enabled = true
	_state_preview.fit_content = true
	_state_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_state_preview.custom_minimum_size.y = 180
	right.add_child(_state_preview)
	_state_preview.name = "StatePreview"

func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func set_context(p_project: RetroProject, p_platform: String, p_animation: RetroAnimation) -> void:
	project = p_project
	platform = p_platform
	animation = p_animation
	_reload()

func set_platform(p_platform: String) -> void:
	platform = p_platform
	if input_map:
		input_map.set_platform(platform)

func set_animation(p_animation: RetroAnimation) -> void:
	animation = p_animation
	if input_map:
		_sync_states_and_durations()
		_rebuild_state_options()
		_refresh_validation()
	_refresh_state_preview()

func _sync_states_and_durations() -> void:
	if input_map == null:
		return
	var states: Array = []
	var durations: Array = []
	if animation and animation.get_states().size() > 0:
		for key in animation.get_states().keys():
			states.append(String(key))
			durations.append(animation.total_duration(String(key)))
	else:
		states = RetroInputMap.default_states()
		for s in states:
			durations.append(0)
	input_map.set_states(states)
	input_map.set_state_durations(durations)

func get_input_map() -> RetroInputMap:
	return input_map

func save_session() -> void:
	if input_map and project:
		var dir := project.resolve(".retro/editor")
		DirAccess.make_dir_recursive_absolute(dir)
		input_map.save(dir.path_join("input_map.json"))

func _reload() -> void:
	if project == null:
		input_map = RetroInputMap.new()
		input_map.setup_defaults(platform)
		_rebuild_list()
		return
	var path := project.resolve(".retro/editor/input_map.json")
	input_map = RetroInputMap.new()
	if FileAccess.file_exists(path):
		input_map.load(path)
	else:
		input_map.setup_defaults(platform)
	_sync_states_and_durations()
	input_map.set_platform(platform)
	_rebuild_list()
	_refresh_state_preview()

func _rebuild_list() -> void:
	_list.clear()
	if input_map == null:
		return
	var actions := input_map.get_actions()
	for i in range(actions.size()):
		var a: Dictionary = actions[i]
		_list.add_item("%s  ->  %s" % [String(a.get("id", "")), String(a.get("state", "IDLE"))])
		_list.set_item_tooltip(_list.item_count - 1, "%s (%s) -> %s" % [String(a.get("id", "")), String(a.get("label", "")), String(a.get("state", "IDLE"))])
	if _list.item_count > 0:
		_list.select(0)
		_on_selected(0)
	_summary.text = "%d actions | platform %s | %d states" % [actions.size(), platform.to_upper(), input_map.get_states().size()]

func _rebuild_state_options() -> void:
	var current_state := _selected_value(_state)
	var current_next := _selected_value(_next)
	_state.clear()
	_next.clear()
	_next.add_item("(none)")
	var states := input_map.get_states() if input_map else RetroInputMap.default_states()
	for s in states:
		_state.add_item(String(s))
		_next.add_item(String(s))
	_select_option_text(_state, current_state)
	_select_option_text(_next, current_next)

func _selected_value(opt: OptionButton) -> String:
	if opt == null or opt.selected < 0 or opt.selected >= opt.item_count:
		return ""
	return opt.get_item_text(opt.selected)

func _select_option_text(opt: OptionButton, text: String) -> void:
	for i in range(opt.item_count):
		if opt.get_item_text(i) == text:
			opt.select(i)
			return
	if opt.item_count > 0:
		opt.select(0)

func _on_selected(index: int) -> void:
	var actions := input_map.get_actions()
	if index < 0 or index >= actions.size():
		return
	_syncing = true
	var a: Dictionary = actions[index]
	_current_id = String(a.get("id", ""))
	_id.text = _current_id
	_label.text = String(a.get("label", ""))
	_keyboard.text = ", ".join(PackedStringArray(a.get("keys", [])))
	_gamepad.text = ", ".join(PackedStringArray(a.get("gamepad", [])))
	_hold.button_pressed = bool(a.get("hold", false))
	_priority.set_value_no_signal(int(a.get("priority", 0)))
	_type.select(_type_index(String(a.get("type", "button"))))
	_rebuild_state_options()
	_select_option_text(_state, String(a.get("state", "IDLE")))
	_select_option_text(_next, String(a.get("next", "")))
	var snes: Array = a.get("snes", [])
	var md: Array = a.get("md", [])
	for b in _snes_boxes.keys():
		(_snes_boxes[b] as CheckBox).button_pressed = snes.has(b)
	for b in _md_boxes.keys():
		(_md_boxes[b] as CheckBox).button_pressed = md.has(b)
	_update_masks()
	_syncing = false
	_refresh_validation()

func _type_index(t: String) -> int:
	if t == "hold":
		return 1
	if t == "axis_x":
		return 2
	if t == "axis_y":
		return 3
	return 0

func _type_value(i: int) -> String:
	return ["button", "hold", "axis_x", "axis_y"][clampi(i, 0, 3)]

func _collect_checked(boxes: Dictionary) -> Array:
	var out: Array = []
	for b in boxes.keys():
		if (boxes[b] as CheckBox).button_pressed:
			out.append(String(b))
	return out

func _commit_fields() -> void:
	if input_map == null:
		return
	var new_id := _id.text.strip_edges().to_lower().replace(" ", "_")
	if new_id.is_empty():
		status.emit("Action id cannot be empty.")
		return
	var old_id := _current_id
	var a := {
		"id": new_id,
		"label": _label.text,
		"type": _type_value(_type.selected),
		"state": _selected_value(_state),
		"next": "" if _next.selected <= 0 else _next.get_item_text(_next.selected),
		"hold": _hold.button_pressed,
		"priority": int(_priority.value),
		"snes": _collect_checked(_snes_boxes),
		"md": _collect_checked(_md_boxes),
		"keys": _split_list(_keyboard.text),
		"gamepad": _split_list(_gamepad.text),
	}
	if old_id != new_id and input_map.action_index(new_id) >= 0:
		status.emit("Action id '%s' already exists." % new_id)
		return
	input_map.update_action(old_id, a)
	_current_id = new_id
	_rebuild_list()
	var keep := input_map.action_index(new_id)
	if keep >= 0:
		_list.select(keep)
		_on_selected(keep)
	_refresh_validation()
	_refresh_state_preview()
	modified.emit()
	input_changed.emit()
	status.emit("Updated action '%s'." % new_id)

func _split_list(text: String) -> Array:
	var out: Array = []
	for part in text.split(",", false):
		var p := String(part).strip_edges()
		if not p.is_empty():
			out.append(p)
	return out

func _update_masks() -> void:
	if input_map == null or _current_id.is_empty():
		return
	_mask_snes.text = "SNES mask: " + input_map.mask_text(_current_id, "snes")
	_mask_md.text = "MD mask:   " + input_map.mask_text(_current_id, "megadrive")

func _import_godot_inputmap() -> void:
	if input_map == null:
		return
	var imported := 0
	var skipped := 0
	var actions := InputMap.get_actions()
	for action in actions:
		var action_name := String(action)
		if action_name.begins_with("ui_") and action_name not in ["ui_left", "ui_right", "ui_up", "ui_down", "ui_accept", "ui_cancel"]:
			skipped += 1
			continue
		var key := action_name.trim_prefix("ui_").to_lower()
		var id := key
		if action_name == "ui_accept":
			id = "start"
		elif action_name == "ui_cancel":
			id = "select"
		if id.is_empty():
			continue
		var mapped := _map_action_buttons(action_name)
		var keys: Array = []
		var gamepad: Array = []
		for event in InputMap.action_get_events(action_name):
			if event is InputEventKey:
				var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
				var key_text := OS.get_keycode_string(code)
				if not key_text.is_empty():
					keys.append(key_text)
			elif event is InputEventJoypadButton:
				gamepad.append(_joy_button_name(event.button_index))
			elif event is InputEventJoypadMotion:
				gamepad.append("AXIS_%d%s" % [event.axis, "+" if event.axis_value > 0.0 else "-"])
		var existing := input_map.get_action(id)
		var data := {
			"id": id,
			"label": String(existing.get("label", action_name.capitalize())),
			"type": String(existing.get("type", "button")),
			"state": String(existing.get("state", "IDLE")),
			"next": String(existing.get("next", "")),
			"hold": bool(existing.get("hold", false)),
			"priority": int(existing.get("priority", 0)),
			"snes": mapped["snes"],
			"md": mapped["md"],
			"keys": keys,
			"gamepad": gamepad,
		}
		if existing.is_empty():
			input_map.add_action(data)
		else:
			input_map.update_action(id, data)
		imported += 1
	_rebuild_list()
	_refresh_validation()
	_refresh_state_preview()
	modified.emit()
	input_changed.emit()
	status.emit("Imported %d Godot InputMap actions (%d UI actions skipped)." % [imported, skipped])

func _map_action_buttons(action_name: String) -> Dictionary:
	var key := action_name.trim_prefix("ui_").to_lower()
	var snes: Array = []
	var md: Array = []
	if key in ["left", "move_left", "walk_left"] or key.ends_with("_left"):
		_add_button_pair(snes, md, "Left", "Left")
	elif key in ["right", "move_right", "walk_right"] or key.ends_with("_right"):
		_add_button_pair(snes, md, "Right", "Right")
	elif key in ["up", "move_up", "walk_up"] or key.ends_with("_up"):
		_add_button_pair(snes, md, "Up", "Up")
	elif key in ["down", "move_down", "walk_down", "crouch"] or key.ends_with("_down"):
		_add_button_pair(snes, md, "Down", "Down")
	elif key in ["accept", "start", "pause", "menu", "enter"]:
		_add_button_pair(snes, md, "Start", "Start")
	elif key in ["cancel", "select", "back", "mode"]:
		_add_button_pair(snes, md, "Select", "MODE")
	elif key in ["jump"]:
		_add_button_pair(snes, md, "A", "A")
	elif key in ["attack", "attack_a", "a", "fire", "shoot", "action"] or key.ends_with("_attack"):
		_add_button_pair(snes, md, "B", "A")
	elif key in ["attack_b", "b", "run", "dash"]:
		_add_button_pair(snes, md, "Y", "B")
	elif key in ["attack_c", "c", "special", "magic"]:
		_add_button_pair(snes, md, "X", "C")
	elif key in ["item", "y"]:
		_add_button_pair(snes, md, "Y", "Y")
	elif key in ["x"]:
		_add_button_pair(snes, md, "X", "X")
	elif key in ["guard", "block", "shield", "shoulder_left", "l", "lb", "bumper_left"]:
		_add_button_pair(snes, md, "L", "Y")
	elif key in ["throw", "shoulder_right", "r", "rb", "bumper_right"]:
		_add_button_pair(snes, md, "R", "Z")
	elif key in ["z"]:
		_add_button_pair(snes, md, "R", "Z")
	return {"snes": snes, "md": md}

func _add_button_pair(snes: Array, md: Array, snes_button: String, md_button: String) -> void:
	if not snes.has(snes_button):
		snes.append(snes_button)
	if not md.has(md_button):
		md.append(md_button)

func _joy_button_name(index: int) -> String:
	const NAMES := {
		0: "JOY_A", 1: "JOY_B", 2: "JOY_X", 3: "JOY_Y", 4: "JOY_BACK",
		5: "JOY_GUIDE", 6: "JOY_START", 7: "JOY_LEFT_STICK", 8: "JOY_RIGHT_STICK",
		9: "JOY_LEFT_SHOULDER", 10: "JOY_RIGHT_SHOULDER", 11: "JOY_DPAD_UP",
		12: "JOY_DPAD_DOWN", 13: "JOY_DPAD_LEFT", 14: "JOY_DPAD_RIGHT",
	}
	return String(NAMES.get(index, "JOY_BUTTON_%d" % index))

func _add_action() -> void:
	if input_map == null:
		return
	var n := input_map.get_actions().size() + 1
	input_map.add_action({"id": "action_%d" % n, "label": "Action %d" % n, "state": "IDLE"})
	_rebuild_list()
	_list.select(_list.item_count - 1)
	_on_selected(_list.item_count - 1)
	modified.emit()
	input_changed.emit()

func _delete_action() -> void:
	if input_map == null or _current_id.is_empty():
		return
	input_map.remove_action(_current_id)
	_rebuild_list()
	modified.emit()
	input_changed.emit()

func _refresh_validation() -> void:
	if input_map == null:
		return
	var v := input_map.validate()
	var text := ""
	for e in v.get("errors", []):
		text += "[color=#ff7a7a]- %s[/color]\n" % String(e)
	for w in v.get("warnings", []):
		text += "[color=#ffd45e]- %s[/color]\n" % String(w)
	if text.is_empty():
		text = "[color=#6ee7a8]No conflicts detected.[/color]"
	_validation.text = text

func _refresh_state_preview() -> void:
	if input_map == null:
		return
	var preview := get_node_or_null("StatePreview")
	if preview == null:
		# The preview lives under the right VBox; find it recursively.
		preview = find_child("StatePreview", true, false)
	if preview == null:
		return
	var text := ""
	for a in input_map.get_actions():
		var id := String(a.get("id", ""))
		var state := String(a.get("state", ""))
		var next := String(a.get("next", ""))
		var mask := input_map.mask_text(id, platform)
		var idx := input_map.get_states().find(state)
		var dur := 0
		if idx >= 0 and idx < input_map.get_state_durations().size():
			dur = int(input_map.get_state_durations()[idx])
		text += "[b]%s[/b]  %s  -> [color=#7fd1ff]%s[/color]%s%s\n" % [
			id, mask, state, (" (%df)" % dur) if dur > 0 else "", (" -> " + next) if next != "" else ""]
	preview.text = text

func _export_state_machine() -> void:
	if input_map == null or project == null:
		return
	_sync_states_and_durations()
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.current_dir = project.resolve("src")
	dlg.dir_selected.connect(func(dir):
		var result: Dictionary
		if platform == "snes":
			result = input_map.export_state_machine_snes(dir)
		else:
			result = input_map.export_state_machine_sgdk(dir)
		if bool(result.get("ok", false)):
			status.emit("Generated state machine: %s / %s" % [String(result.get("header", "")), String(result.get("source", ""))])
		else:
			status.emit("State-machine generation failed.")
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _export(kind: String) -> void:
	if input_map == null or project == null:
		return
	# Keep the state list in sync with the active animation before exporting.
	_sync_states_and_durations()
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	var base := "retro_input"
	match kind:
		"snes_h":
			dlg.add_filter("*.h", "PVSnesLib C header")
			dlg.current_file = base + ".h"
		"snes_inc":
			dlg.add_filter("*.inc", "WLA-DX include")
			dlg.current_file = base + ".inc"
		"md_h":
			dlg.add_filter("*.h", "SGDK C header")
			dlg.current_file = base + "_md.h"
		"json":
			dlg.add_filter("*.json", "Retro input map")
			dlg.current_file = "input_map.json"
	dlg.current_dir = project.resolve("src")
	dlg.file_selected.connect(func(path):
		match kind:
			"snes_h":
				input_map.export_snes_header(path)
			"snes_inc":
				input_map.export_snes_inc(path)
			"md_h":
				input_map.export_sgdk_header(path)
			"json":
				input_map.save(path)
		status.emit("Input export: " + path)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)
