@tool
extends VBoxContainer
## Editor-side simulation of the generated state machine:
## console button masks + animation durations + keyboard/gamepad events.

signal status(text: String)
signal state_changed(state: String, frame: int)

const AnimPreview = preload("res://addons/retro_engine/anim_preview.gd")

var project: RetroProject
var platform: String = "snes"
var animation: RetroAnimation
var sprite: RetroSprite
var input_map: RetroInputMap

var _state: String = "IDLE"
var _elapsed: int = 0
var _pending: String = ""
var _last_action: String = ""
var _held: Dictionary = {}
var _pressed: Dictionary = {}
var _frame_hold: Dictionary = {}
var _playing: bool = false
var _timer: Timer

var _actions: ItemList
var _selected: String = ""
var _preview
var _state_label: Label
var _frame_label: Label
var _pending_label: Label
var _mask_label: Label
var _log: RichTextLabel
var _capture: CheckBox
var _auto_tick: CheckBox
var _hold_toggle: CheckBox
var _play_button: Button

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var header := HBoxContainer.new()
	add_child(header)
	var title := Label.new()
	title.text = "State Machine Simulator"
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_capture = CheckBox.new()
	_capture.text = "Keyboard/Gamepad"
	_capture.button_pressed = true
	header.add_child(_capture)
	_auto_tick = CheckBox.new()
	_auto_tick.text = "Auto-end"
	_auto_tick.button_pressed = true
	_auto_tick.tooltip_text = "Use animation durations to apply the pending next state automatically"
	header.add_child(_auto_tick)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 175
	body.add_child(left)
	var alabel := Label.new()
	alabel.text = "Actions"
	left.add_child(alabel)
	_actions = ItemList.new()
	_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_actions.item_selected.connect(_on_action_selected)
	left.add_child(_actions)
	_hold_toggle = CheckBox.new()
	_hold_toggle.text = "Hold selected"
	_hold_toggle.toggled.connect(_on_hold_toggled)
	left.add_child(_hold_toggle)
	var press_btn := Button.new()
	press_btn.text = "Press selected"
	press_btn.pressed.connect(_press_selected)
	left.add_child(press_btn)
	var release_btn := Button.new()
	release_btn.text = "Release all"
	release_btn.pressed.connect(_release_all)
	left.add_child(release_btn)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	_preview = AnimPreview.new()
	_preview.custom_minimum_size = Vector2(260, 220)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(_preview)
	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 18)
	_state_label.add_theme_color_override("font_color", Color("#7fd1ff"))
	center.add_child(_state_label)
	_frame_label = Label.new()
	center.add_child(_frame_label)
	_pending_label = Label.new()
	_pending_label.add_theme_color_override("font_color", Color("#ffd45e"))
	center.add_child(_pending_label)
	_mask_label = Label.new()
	_mask_label.add_theme_font_size_override("font_size", 11)
	_mask_label.add_theme_color_override("font_color", Color("#9fb4d0"))
	center.add_child(_mask_label)

	var controls := HBoxContainer.new()
	center.add_child(controls)
	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.pressed.connect(_toggle_play)
	controls.add_child(_play_button)
	var step := Button.new()
	step.text = "Step"
	step.pressed.connect(_step)
	controls.add_child(step)
	var end := Button.new()
	end.text = "Anim end"
	end.tooltip_text = "Call the explicit animation-end transition"
	end.pressed.connect(_animation_end)
	controls.add_child(end)
	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(_reset)
	controls.add_child(reset)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 190
	body.add_child(right)
	var info := Label.new()
	info.text = "Keyboard/gamepad bindings come from the Inputs editor. Click the preview area or use the action buttons if the editor consumes a shortcut."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", Color("#8b98ad"))
	right.add_child(info)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size.y = 160
	right.add_child(_log)

	_timer = Timer.new()
	_timer.wait_time = 1.0 / 60.0
	_timer.timeout.connect(_tick_play)
	add_child(_timer)

func set_context(p_project: RetroProject, p_platform: String, p_animation: RetroAnimation, p_sprite: RetroSprite) -> void:
	project = p_project
	platform = p_platform
	animation = p_animation
	sprite = p_sprite
	input_map = RetroInputMap.new()
	if project:
		var path := project.resolve(".retro/editor/input_map.json")
		if FileAccess.file_exists(path):
			input_map.load(path)
		else:
			input_map.setup_defaults(platform)
	else:
		input_map.setup_defaults(platform)
	input_map.set_platform(platform)
	_sync_durations()
	_rebuild_actions()
	_reset()

func set_input_map(p_map: RetroInputMap) -> void:
	if p_map == null:
		return
	input_map = p_map
	input_map.set_platform(platform)
	_sync_durations()
	_rebuild_actions()
	_reset()

func set_platform(p_platform: String) -> void:
	platform = p_platform
	if input_map:
		input_map.set_platform(platform)
	_mask_label.text = ""

func set_animation(p_animation: RetroAnimation) -> void:
	animation = p_animation
	_sync_durations()
	_update_ui()
	_preview.set_data(sprite, animation, _state)

func set_sprite(p_sprite: RetroSprite) -> void:
	sprite = p_sprite
	_preview.set_data(sprite, animation, _state)

func _sync_durations() -> void:
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

func _rebuild_actions() -> void:
	_actions.clear()
	if input_map == null:
		return
	var actions := input_map.get_actions()
	for i in range(actions.size()):
		var a: Dictionary = actions[i]
		_actions.add_item(String(a.get("id", "")))
		_actions.set_item_tooltip(i, "%s -> %s" % [String(a.get("label", "")), String(a.get("state", "IDLE"))])
	if _actions.item_count > 0:
		_actions.select(0)
		_on_action_selected(0)

func _on_action_selected(index: int) -> void:
	var actions := input_map.get_actions() if input_map else []
	if index < 0 or index >= actions.size():
		return
	_selected = String(actions[index].get("id", ""))
	_hold_toggle.set_pressed_no_signal(bool(_held.get(_selected, false)))

func _press_selected() -> void:
	if _selected.is_empty():
		return
	var a := input_map.get_action(_selected)
	_pressed[_selected] = true
	if bool(a.get("hold", false)) or String(a.get("type", "button")) == "hold":
		_frame_hold[_selected] = true
	_log_line("press " + _selected)
	_step()

func _on_hold_toggled(on: bool) -> void:
	if _selected.is_empty():
		return
	_held[_selected] = on
	_log_line(("hold " if on else "release ") + _selected)
	_step()

func _release_all() -> void:
	_held.clear()
	_pressed.clear()
	_frame_hold.clear()
	_hold_toggle.set_pressed_no_signal(false)
	_log_line("release all")
	_update_ui()

func _reset() -> void:
	var states := input_map.get_states() if input_map else RetroInputMap.default_states()
	_state = String(states[0]) if states.size() > 0 else "IDLE"
	_elapsed = 0
	_pending = ""
	_last_action = ""
	_held.clear()
	_pressed.clear()
	_frame_hold.clear()
	_playing = false
	_timer.stop()
	if _play_button:
		_play_button.text = "Play"
	_log_line("reset")
	_update_ui()

func _step() -> void:
	if input_map == null:
		return
	var current := 0
	var pressed := 0
	for a in input_map.get_actions():
		var id := String(a.get("id", ""))
		var mask := input_map.action_mask(id, platform)
		if mask == 0:
			continue
		if bool(_held.get(id, false)) or bool(_frame_hold.get(id, false)):
			current |= mask
		if bool(_pressed.get(id, false)):
			pressed |= mask
	var best := ""
	var best_priority := -1
	for a in input_map.get_actions():
		var id := String(a.get("id", ""))
		var mask := input_map.action_mask(id, platform)
		if mask == 0:
			continue
		var is_hold := bool(a.get("hold", false)) or String(a.get("type", "button")) == "hold"
		var value := current if is_hold else pressed
		if (value & mask) != mask:
			continue
		var prio := int(a.get("priority", 0))
		if best.is_empty() or prio > best_priority:
			best = id
			best_priority = prio
	if not best.is_empty():
		var a := input_map.get_action(best)
		var next_state := String(a.get("state", ""))
		if not next_state.is_empty():
			if next_state != _state:
				_elapsed = 0
			_state = next_state
		_pending = String(a.get("next", ""))
		_last_action = best
	_mask_label.text = "current=%04X pressed=%04X" % [current, pressed]
	_pressed.clear()
	_frame_hold.clear()
	if _auto_tick.button_pressed:
		_tick_elapsed()
	_update_ui()

func _tick_elapsed() -> void:
	_elapsed += 1
	var dur := _duration_for(_state)
	if dur > 0 and not _pending.is_empty() and _elapsed >= dur:
		_state = _pending
		_pending = ""
		_elapsed = 0

func _duration_for(state: String) -> int:
	if input_map == null or animation == null:
		return 0
	var states := input_map.get_states()
	var idx := states.find(state)
	if idx >= 0 and idx < input_map.get_state_durations().size():
		return int(input_map.get_state_durations()[idx])
	return 0

func _animation_end() -> void:
	if not _pending.is_empty():
		_state = _pending
		_pending = ""
		_elapsed = 0
		_log_line("animation end -> " + _state)
	_update_ui()

func _toggle_play() -> void:
	_playing = not _playing
	_play_button.text = "Pause" if _playing else "Play"
	if _playing:
		_timer.start()
	else:
		_timer.stop()

func _tick_play() -> void:
	if not _playing:
		return
	_step()

func _update_ui() -> void:
	if _state_label == null:
		return
	_state_label.text = "STATE: " + _state
	var dur := _duration_for(_state)
	_frame_label.text = "Frame: %d%s" % [_elapsed, (" / %d" % dur) if dur > 0 else ""]
	_pending_label.text = ("Pending: " + _pending) if not _pending.is_empty() else "Pending: -"
	_preview.set_data(sprite, animation, _state)
	_preview.set_time(_elapsed / 60.0)
	state_changed.emit(_state, _elapsed)

func _log_line(text: String) -> void:
	if _log:
		_log.append_text("[color=#9fb4d0]" + text.replace("[", "[lb]") + "[/color]\n")

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or input_map == null or not _capture.button_pressed:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var key_name := ""
	var joy_name := ""
	var down := false
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.echo:
			return
		key_name = OS.get_keycode_string(ke.keycode)
		down = ke.pressed
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		joy_name = _joy_name(jb.button_index)
		down = jb.pressed
	else:
		return
	if key_name.is_empty() and joy_name.is_empty():
		return
	var consumed := false
	for a in input_map.get_actions():
		var id := String(a.get("id", ""))
		var keys: Array = a.get("keys", [])
		var pads: Array = a.get("gamepad", [])
		var matched := false
		if not key_name.is_empty():
			for k in keys:
				if String(k).to_upper() == key_name.to_upper():
					matched = true
					break
		if not joy_name.is_empty():
			for g in pads:
				if String(g).to_upper() == joy_name.to_upper():
					matched = true
					break
		if not matched:
			continue
		consumed = true
		if down:
			_pressed[id] = true
			if bool(a.get("hold", false)) or String(a.get("type", "button")) == "hold":
				_held[id] = true
			_log_line(("key down " if not key_name.is_empty() else "pad down ") + id)
			_step()
		else:
			_held.erase(id)
			_log_line(("key up " if not key_name.is_empty() else "pad up ") + id)
			_update_ui()
	if consumed:
		get_viewport().set_input_as_handled()

func _joy_name(index: int) -> String:
	match index:
		JOY_BUTTON_A: return "JOY_A"
		JOY_BUTTON_B: return "JOY_B"
		JOY_BUTTON_X: return "JOY_X"
		JOY_BUTTON_Y: return "JOY_Y"
		JOY_BUTTON_BACK: return "JOY_BACK"
		JOY_BUTTON_START: return "JOY_START"
		JOY_BUTTON_LEFT_SHOULDER: return "JOY_L"
		JOY_BUTTON_RIGHT_SHOULDER: return "JOY_R"
		JOY_BUTTON_DPAD_UP: return "JOY_UP"
		JOY_BUTTON_DPAD_DOWN: return "JOY_DOWN"
		JOY_BUTTON_DPAD_LEFT: return "JOY_LEFT"
		JOY_BUTTON_DPAD_RIGHT: return "JOY_RIGHT"
	return ""
