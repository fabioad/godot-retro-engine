@tool
extends VBoxContainer
## Frame-by-frame animation editor with fighting-game states, per-frame
## hitboxes, events, loops/transitions and 60 Hz preview.

signal modified()
signal status(text: String)
signal sprite_modified()

const AnimPreview = preload("res://addons/retro_engine/anim_preview.gd")
const SpriteSheet = preload("res://addons/retro_engine/sprite_sheet.gd")
const StateDetect = preload("res://addons/retro_engine/animation_states.gd")

var animation: RetroAnimation
var sprite: RetroSprite
var project: RetroProject
var platform: String = "snes"
var current_state: String = "IDLE"
var current_frame: int = 0

var _state_list: ItemList
var _timeline: HBoxContainer
var _preview
var _play_button: Button
var _playing: bool = false
var _time: float = 0.0
var _fps: SpinBox
var _loop: CheckBox
var _transition: OptionButton
var _duration: SpinBox
var _hit_type: OptionButton
var _event_type: LineEdit
var _event_value: LineEdit
var _info: Label
var _frame_info: Label
var _timeline_buttons: Array = []
var _zoom_spin: SpinBox
var _slice_option: OptionButton
var _user_paused: bool = false
var _last_process_ms: int = 0

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 4)
	add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 120
	split.add_child(left)
	var slabel := Label.new()
	slabel.text = "States"
	left.add_child(slabel)
	_state_list = ItemList.new()
	_state_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_state_list.item_selected.connect(_on_state_selected)
	left.add_child(_state_list)
	var add_state := Button.new()
	add_state.text = "Add custom state"
	add_state.pressed.connect(_add_custom_state)
	left.add_child(add_state)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(center)
	var preview_head := HBoxContainer.new()
	center.add_child(preview_head)
	var preview_title := Label.new()
	preview_title.text = "Sprite preview"
	preview_title.add_theme_font_size_override("font_size", 15)
	preview_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_head.add_child(preview_title)
	_slice_option = OptionButton.new()
	_slice_option.add_item("Auto")
	_slice_option.add_item("Horizontal")
	_slice_option.add_item("Vertical")
	_slice_option.add_item("Grid")
	_slice_option.add_item("Whole sheet")
	_slice_option.tooltip_text = "Sprite-sheet split mode. Auto uses transparency and both axes. Choose Horizontal/Vertical/Grid when a frame contains two sprites, or Whole sheet to keep it intact."
	_slice_option.item_selected.connect(_on_slice_mode_selected)
	preview_head.add_child(_slice_option)
	_zoom_spin = _spin(0, 16, 0)
	_zoom_spin.prefix = "Zoom "
	_zoom_spin.tooltip_text = "0 = fit the preview; 1-16 = fixed pixel zoom"
	_zoom_spin.value_changed.connect(func(v):
		_preview.zoom = int(v)
		_preview.auto_fit = int(v) <= 0
		_preview.queue_redraw())
	preview_head.add_child(_zoom_spin)
	_preview = AnimPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(_preview)
	var controls := HBoxContainer.new()
	center.add_child(controls)
	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.pressed.connect(_toggle_play)
	controls.add_child(_play_button)
	var stop := Button.new()
	stop.text = "Stop"
	stop.pressed.connect(_stop)
	controls.add_child(stop)
	controls.add_child(_mk_label("FPS"))
	_fps = _spin(1, 60, 60)
	_fps.value_changed.connect(_on_fps_changed)
	controls.add_child(_fps)
	_loop = CheckBox.new()
	_loop.text = "Loop"
	_loop.button_pressed = true
	_loop.toggled.connect(_on_loop_changed)
	controls.add_child(_loop)
	var controls2 := HBoxContainer.new()
	center.add_child(controls2)
	controls2.add_child(_mk_label("Next"))
	_transition = OptionButton.new()
	_transition.custom_minimum_size.x = 130
	_transition.item_selected.connect(_on_transition_changed)
	controls2.add_child(_transition)
	var hitbox_check := CheckBox.new()
	hitbox_check.text = "Hitboxes"
	hitbox_check.button_pressed = true
	hitbox_check.toggled.connect(func(v): _preview.show_boxes = v; _preview.queue_redraw())
	controls2.add_child(hitbox_check)

	var tl_title := Label.new()
	tl_title.text = "Timeline (frames, duration in console frames)"
	center.add_child(tl_title)
	var tl_scroll := ScrollContainer.new()
	tl_scroll.custom_minimum_size.y = 74
	tl_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	center.add_child(tl_scroll)
	_timeline = HBoxContainer.new()
	_timeline.add_theme_constant_override("separation", 2)
	tl_scroll.add_child(_timeline)

	var frame_controls := HFlowContainer.new()
	center.add_child(frame_controls)
	_mk(frame_controls, "Duration")
	_duration = _spin(1, 999, 6)
	_duration.value_changed.connect(_on_duration_changed)
	frame_controls.add_child(_duration)
	var add_frame := Button.new()
	add_frame.text = "Add frame"
	add_frame.pressed.connect(_add_frame)
	frame_controls.add_child(add_frame)
	var from_sprite := Button.new()
	from_sprite.text = "Frames from sprite"
	from_sprite.tooltip_text = "Replace this state with one frame per sprite frame (use the Sprite tab to split a sheet first)"
	from_sprite.pressed.connect(_add_frames_from_sprite)
	frame_controls.add_child(from_sprite)
	var detect_btn := Button.new()
	detect_btn.text = "Detect states"
	detect_btn.tooltip_text = "Read IDLE/WALK/JUMP frame ranges from project constants or Sonic animation scripts"
	detect_btn.pressed.connect(detect_states)
	frame_controls.add_child(detect_btn)
	var distribute := Button.new()
	distribute.text = "Distribute equally"
	distribute.tooltip_text = "Fallback: split the sprite sheet frames evenly across the state list"
	distribute.pressed.connect(_confirm_distribute_equally)
	frame_controls.add_child(distribute)
	var del_frame := Button.new()
	del_frame.text = "Remove frame"
	del_frame.pressed.connect(_remove_frame)
	frame_controls.add_child(del_frame)
	_mk(frame_controls, "Box")
	_hit_type = OptionButton.new()
	_hit_type.add_item("hit")
	_hit_type.add_item("hurt")
	frame_controls.add_child(_hit_type)
	var add_box := Button.new()
	add_box.text = "Add box to frame"
	add_box.pressed.connect(_add_box)
	frame_controls.add_child(add_box)

	var event_row := HBoxContainer.new()
	center.add_child(event_row)
	_mk(event_row, "Event")
	_event_type = LineEdit.new()
	_event_type.placeholder_text = "sound/command/state"
	_event_type.custom_minimum_size.x = 90
	event_row.add_child(_event_type)
	_event_value = LineEdit.new()
	_event_value.placeholder_text = "value"
	_event_value.custom_minimum_size.x = 100
	event_row.add_child(_event_value)
	var add_event := Button.new()
	add_event.text = "Add event to frame"
	add_event.pressed.connect(_add_event)
	event_row.add_child(add_event)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 210
	split.add_child(right)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_info)
	_frame_info = Label.new()
	_frame_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_frame_info.add_theme_color_override("font_color", Color("#9fb4d0"))
	right.add_child(_frame_info)
	var sep := HSeparator.new()
	right.add_child(sep)
	var exp_inc := Button.new()
	exp_inc.text = "Export SNES .inc"
	exp_inc.pressed.connect(_export_snes)
	right.add_child(exp_inc)
	var exp_h := Button.new()
	exp_h.text = "Export SGDK .h"
	exp_h.pressed.connect(_export_sgdk)
	right.add_child(exp_h)
	var save_btn := Button.new()
	save_btn.text = "Save animation JSON"
	save_btn.pressed.connect(_save_json)
	right.add_child(save_btn)
	var load_btn := Button.new()
	load_btn.text = "Load animation JSON"
	load_btn.pressed.connect(_load_json)
	right.add_child(load_btn)
	var note := Label.new()
	note.text = "Frame durations are in console frames (60.0988 Hz on SNES, 59.92 Hz on Mega Drive). The preview is visual only; use Run to validate timing on the emulated console."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("#8b98ad"))
	right.add_child(note)

	set_process(false)

func _mk(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	parent.add_child(l)

func _mk_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _spin(minv: float, maxv: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.value = value
	s.custom_minimum_size.x = 50
	return s

func set_platform(p: String) -> void:
	platform = p

func set_sprite(doc: RetroSprite) -> void:
	sprite = doc
	_maybe_auto_detect_states()
	_preview.set_data(sprite, animation, current_state)
	_preview.queue_redraw()
	_ensure_playing()

func set_animation(doc: RetroAnimation, p_project: RetroProject = null) -> void:
	var changed := animation != doc
	animation = doc
	project = p_project
	if animation == null:
		_preview.set_data(sprite, null, current_state)
		return
	_fps.set_value_no_signal(animation.get_fps())
	if changed:
		_maybe_auto_detect_states()
	_rebuild_state_list()
	_rebuild_transitions()
	_refresh_timeline()
	_preview.set_data(sprite, animation, current_state)
	_preview.queue_redraw()
	_info.text = "Animation: %s  (%d states, %d fps)" % [animation.get_name(), animation.get_states().size(), animation.get_fps()]
	_update_info()
	_ensure_playing()

func _rebuild_state_list() -> void:
	_state_list.clear()
	if animation == null:
		return
	for k in animation.get_states().keys():
		_state_list.add_item(String(k))
	var preferred := current_state
	if not animation.get_states().has(preferred):
		preferred = ""
		for k in animation.get_states().keys():
			if not Array(animation.get_state(String(k)).get("frames", [])).is_empty():
				preferred = String(k)
				break
	if preferred.is_empty() and _state_list.item_count > 0:
		preferred = _state_list.get_item_text(0)
	if not preferred.is_empty():
		current_state = preferred
		for i in range(_state_list.item_count):
			if _state_list.get_item_text(i) == current_state:
				_state_list.select(i)
				break
		current_frame = 0
		_time = 0.0

func _maybe_auto_detect_states() -> void:
	if animation == null or sprite == null or project == null:
		return
	var meta: Dictionary = animation.get_metadata()
	if bool(meta.get("states_auto_detected", false)):
		return
	var states: Dictionary = animation.get_states()
	var total := 0
	var max_frames := 0
	for k in states.keys():
		var count := Array(Dictionary(states[k]).get("frames", [])).size()
		total += count
		max_frames = maxi(max_frames, count)
	var sprite_frames := sprite.get_frames().size()
	if total > 0 and not (sprite_frames > 0 and max_frames >= sprite_frames):
		return
	var result := StateDetect.detect(project, sprite)
	if bool(result.get("ok", false)):
		animation.set_states(result.get("states", {}))
		meta["states_auto_detected"] = true
		meta["states_source"] = String(result.get("source", ""))
		animation.set_metadata(meta)
		status.emit(String(result.get("message", "States detected.")))
		modified.emit()
	else:
		meta["states_auto_detected"] = true
		meta["states_source"] = "none"
		animation.set_metadata(meta)
		status.emit(String(result.get("message", "No state metadata found.")) + " Use Detect states or Distribute equally.")
	_rebuild_state_list()
	_rebuild_transitions()
	_refresh_timeline()
	_preview.set_data(sprite, animation, current_state)
	_preview.set_time(0.0)
	_update_info()

func detect_states() -> void:
	if animation == null or sprite == null or project == null:
		status.emit("Load a project, sprite and animation first.")
		return
	var result := StateDetect.detect(project, sprite)
	if not bool(result.get("ok", false)):
		status.emit(String(result.get("message", "No state metadata found.")))
		return
	animation.set_states(result.get("states", {}))
	var meta: Dictionary = animation.get_metadata()
	meta["states_auto_detected"] = true
	meta["states_source"] = String(result.get("source", ""))
	animation.set_metadata(meta)
	_rebuild_state_list()
	_rebuild_transitions()
	_refresh_timeline()
	_preview.set_data(sprite, animation, current_state)
	_preview.set_time(0.0)
	_update_info()
	_ensure_playing()
	modified.emit()
	status.emit(String(result.get("message", "States detected.")))

func _confirm_distribute_equally() -> void:
	if animation == null or sprite == null:
		status.emit("Load a sprite and animation first.")
		return
	var names: Array = animation.get_states().keys()
	if names.is_empty():
		names = ["IDLE", "WALK", "JUMP", "CROUCH", "ATTACK", "HIT", "BLOCK", "SPECIAL", "SUPER", "THROW"]
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Distribute %d sprite frames equally across %d states? This replaces the current frame ranges." % [sprite.get_frames().size(), names.size()]
	dlg.confirmed.connect(func():
		_distribute_equally(names)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()

func _distribute_equally(names: Array) -> void:
	var frames: Array = sprite.get_frames()
	var total := frames.size()
	var states_count := names.size()
	if total <= 0 or states_count <= 0:
		status.emit("Nothing to distribute.")
		return
	var states: Dictionary = animation.get_states()
	var base := total / states_count
	var remainder := total % states_count
	var cursor := 0
	for i in range(states_count):
		var state_name := String(names[i])
		var count := base + (1 if i < remainder else 0)
		var list: Array = []
		for _j in range(count):
			if cursor >= total:
				break
			var f: Dictionary = frames[cursor]
			list.append({
				"sprite_frame": cursor,
				"duration": 6,
				"rect": f.get("rect", Rect2i()),
				"hitboxes": [],
				"events": [],
			})
			cursor += 1
		var st: Dictionary = states.get(state_name, {"name": state_name, "loop": true, "next": ""})
		st["name"] = state_name
		st["frames"] = list
		states[state_name] = st
	animation.set_states(states)
	var meta: Dictionary = animation.get_metadata()
	meta["states_auto_detected"] = true
	meta["states_source"] = "equal distribution"
	animation.set_metadata(meta)
	_rebuild_state_list()
	_rebuild_transitions()
	_refresh_timeline()
	_preview.set_data(sprite, animation, current_state)
	_preview.set_time(0.0)
	_update_info()
	_ensure_playing()
	modified.emit()
	status.emit("Distributed %d frames across %d states." % [total, states_count])

func _rebuild_transitions() -> void:
	_transition.clear()
	_transition.add_item("(none)")
	if animation == null:
		return
	for k in animation.get_states().keys():
		_transition.add_item(String(k))
	var st: Dictionary = animation.get_state(current_state)
	var next := String(st.get("next", ""))
	for i in range(_transition.item_count):
		if _transition.get_item_text(i) == next:
			_transition.select(i)
			break

func _on_state_selected(index: int) -> void:
	if animation == null:
		return
	current_state = _state_list.get_item_text(index)
	current_frame = 0
	_time = 0.0
	var st: Dictionary = animation.get_state(current_state)
	_loop.set_pressed_no_signal(bool(st.get("loop", true)))
	_preview.set_data(sprite, animation, current_state)
	_preview.set_time(0.0)
	_rebuild_transitions()
	_refresh_timeline()
	_update_info()
	_user_paused = false
	_ensure_playing()

func _refresh_timeline() -> void:
	_timeline_buttons.clear()
	for c in _timeline.get_children():
		c.queue_free()
	if animation == null:
		return
	var st: Dictionary = animation.get_state(current_state)
	var frames: Array = st.get("frames", [])
	for i in range(frames.size()):
		var f: Dictionary = frames[i]
		var btn := Button.new()
		btn.text = "%d\n%df" % [i, int(f.get("duration", 1))]
		btn.custom_minimum_size = Vector2(52, 50)
		btn.toggle_mode = true
		btn.button_pressed = i == current_frame
		if i == current_frame:
			btn.modulate = Color("#ffd45e")
		btn.pressed.connect(func(): _select_frame(i))
		_timeline.add_child(btn)
		_timeline_buttons.append(btn)
	if frames.is_empty():
		var lbl := Label.new()
		lbl.text = "No frames in this state. Add a frame or use Frames from sprite."
		_timeline.add_child(lbl)

func _set_playhead(i: int) -> void:
	if i == current_frame:
		return
	current_frame = i
	for n in range(_timeline_buttons.size()):
		var btn: Button = _timeline_buttons[n]
		btn.set_pressed_no_signal(n == i)
		btn.modulate = Color("#ffd45e") if n == i else Color.WHITE

func _frame_start_time(index: int) -> float:
	if animation == null:
		return 0.0
	var frames: Array = animation.get_state(current_state).get("frames", [])
	var start := 0
	for i in range(min(index, frames.size())):
		start += maxi(1, int(frames[i].get("duration", 1)))
	return (float(start) + 0.001) / maxf(1.0, float(animation.get_fps()))

func _select_frame(i: int) -> void:
	current_frame = i
	_time = _frame_start_time(i)
	_preview.set_time(_time)
	_set_playhead(i)
	_update_info()
	if animation and animation.get_state(current_state).has("frames"):
		var frames: Array = animation.get_state(current_state)["frames"]
		if i >= 0 and i < frames.size():
			_duration.set_value_no_signal(int(frames[i].get("duration", 1)))

func _update_info() -> void:
	if animation == null:
		return
	var st: Dictionary = animation.get_state(current_state)
	var frames: Array = st.get("frames", [])
	var total := animation.total_duration(current_state)
	_frame_info.text = "State %s | %d frames | %d console frames (%.2fs)\nLoop: %s | Next: %s" % [
		current_state, frames.size(), total, total / 60.0, str(st.get("loop", true)), str(st.get("next", ""))]
	if current_frame >= 0 and current_frame < frames.size():
		var f: Dictionary = frames[current_frame]
		_frame_info.text += "\nFrame %d: sprite frame %d, duration %d, hitboxes %d, events %d" % [
			current_frame, int(f.get("sprite_frame", 0)), int(f.get("duration", 1)),
			Array(f.get("hitboxes", [])).size(), Array(f.get("events", [])).size()]
	elif _preview.resolve_frame().get("source", "") == "sprite_sheet":
		_frame_info.text += "\nPreview is cycling the sprite sheet because this state has no frames."

func _on_duration_changed(v: float) -> void:
	if animation == null:
		return
	animation.set_frame_duration(current_state, current_frame, int(v))
	_refresh_timeline()
	_update_info()
	modified.emit()

func _on_fps_changed(v: float) -> void:
	if animation:
		animation.set_fps(int(v))
		_update_info()
		modified.emit()

func _on_loop_changed(v: bool) -> void:
	if animation:
		animation.set_loop(current_state, v)
		_update_info()
		modified.emit()

func _on_transition_changed(i: int) -> void:
	if animation and i > 0:
		animation.set_transition(current_state, _transition.get_item_text(i))
		_update_info()
		modified.emit()

func _add_frame() -> void:
	if animation == null:
		return
	var sprite_frame := 0
	if sprite and sprite.get_frames().size() > 0:
		sprite_frame = current_frame % sprite.get_frames().size()
	var rect := Rect2i()
	if sprite and sprite_frame < sprite.get_frames().size():
		rect = sprite.get_frames()[sprite_frame].get("rect", Rect2i())
	animation.add_frame(current_state, sprite_frame, int(_duration.value), rect)
	current_frame = animation.get_state(current_state)["frames"].size() - 1
	_refresh_timeline()
	_update_info()
	_ensure_playing()
	modified.emit()

func _remove_frame() -> void:
	if animation == null:
		return
	var st: Dictionary = animation.get_state(current_state)
	var frames: Array = st.get("frames", [])
	if current_frame >= 0 and current_frame < frames.size():
		frames.remove_at(current_frame)
		st["frames"] = frames
		var states := animation.get_states()
		states[current_state] = st
		animation.set_states(states)
		current_frame = clampi(current_frame, 0, max(0, frames.size() - 1))
		_refresh_timeline()
		_update_info()
		_ensure_playing()
		modified.emit()

func _on_slice_mode_selected(index: int) -> void:
	var modes := ["auto", "horizontal", "vertical", "grid", "whole"]
	var mode: String = modes[clampi(index, 0, modes.size() - 1)]
	_preview.set_slice_mode(mode)
	_update_info()
	_ensure_playing()

func _add_frames_from_sprite() -> void:
	if animation == null:
		status.emit("Select or create an animation first.")
		return
	if sprite == null:
		status.emit("Load a sprite first.")
		return
	var before := sprite.get_frames().size()
	var sprite_frames: Array = SpriteSheet.ensure_sprite_frames(sprite, 6, _preview.slice_mode)
	if sprite_frames.size() < 2:
		status.emit("Could not detect separate frames. Check the sprite transparency or split the sheet in the Sprite tab.")
		return
	if sprite_frames.size() != before:
		sprite_modified.emit()
	var states := animation.get_states()
	var st: Dictionary = states.get(current_state, {})
	var out: Array = []
	for i in range(sprite_frames.size()):
		var f: Dictionary = sprite_frames[i]
		out.append({
			"sprite_frame": i,
			"duration": maxi(1, int(f.get("duration", 6))),
			"rect": f.get("rect", Rect2i()),
			"hitboxes": [],
			"events": [],
		})
	st["frames"] = out
	states[current_state] = st
	animation.set_states(states)
	current_frame = 0
	_time = 0.0
	_preview.set_time(0.0)
	_refresh_timeline()
	_update_info()
	_ensure_playing()
	modified.emit()
	status.emit("State %s now has %d frames from the sprite." % [current_state, out.size()])

func _add_box() -> void:
	if animation == null:
		return
	var r := Rect2i(8, 8, 24, 24)
	animation.add_hitbox(current_state, current_frame, r, "hit" if _hit_type.selected == 0 else "hurt")
	_refresh_timeline()
	_update_info()
	modified.emit()

func _add_event() -> void:
	if animation == null:
		return
	animation.add_event(current_state, current_frame, _event_type.text, _event_value.text)
	_refresh_timeline()
	_update_info()
	modified.emit()

func _add_custom_state() -> void:
	if animation == null:
		return
	var dlg := ConfirmationDialog.new()
	var le := LineEdit.new()
	le.placeholder_text = "STATE_NAME"
	dlg.add_child(le)
	dlg.confirmed.connect(func():
		if le.text.strip_edges() != "":
			animation.add_state(le.text.strip_edges().to_upper(), true)
			set_animation(animation, project)
			modified.emit()
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()

func _toggle_play() -> void:
	_playing = not _playing
	_play_button.text = "Pause" if _playing else "Play"
	if _playing:
		_user_paused = false
		if not _preview.resolve_frame().is_empty():
			_last_process_ms = Time.get_ticks_msec()
			set_process(true)
		else:
			_playing = false
			_play_button.text = "Play"
			set_process(false)
	else:
		_user_paused = true
		set_process(false)

func _ensure_playing() -> void:
	if _playing or _user_paused or _preview.resolve_frame().is_empty():
		return
	_playing = true
	_play_button.text = "Pause"
	_last_process_ms = Time.get_ticks_msec()
	set_process(true)

func _stop() -> void:
	_playing = false
	_user_paused = true
	_play_button.text = "Play"
	set_process(false)
	_time = 0.0
	_preview.set_time(0.0)

func _process(_delta: float) -> void:
	if not _playing or _user_paused:
		return
	var now := Time.get_ticks_msec()
	var elapsed := maxf(0.0, float(now - _last_process_ms) / 1000.0)
	_last_process_ms = now
	_advance_time(elapsed)

func _tick() -> void:
	if not _playing:
		return
	_advance_time(1.0 / 60.0)

## Advance with real frame delta instead of a fixed timer tick. This keeps the
## preview playing at the right speed even when the editor is throttled or the
## tab has just regained focus.
func _advance_time(delta: float) -> void:
	_time += maxf(0.0, delta)
	var sheet: bool = _preview.sheet_mode()
	if sheet:
		var sheet_duration: float = _preview.sheet_duration_seconds()
		if sheet_duration > 0.0:
			_time = fmod(_time, sheet_duration)
	elif animation != null:
		var total := animation.total_duration(current_state)
		if total > 0:
			var duration := total / 60.0
			if bool(animation.get_state(current_state).get("loop", true)):
				_time = fmod(_time, duration)
			elif _time >= duration:
				_time = maxf(0.0, duration - 1.0 / 60.0)
				_playing = false
				_play_button.text = "Play"
				set_process(false)
		var sample: Dictionary = animation.sample(current_state, _time)
		if not sample.is_empty():
			_set_playhead(int(sample.get("index", 0)))
	_preview.set_time(_time)

func _export_snes() -> void:
	if animation == null:
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.inc", "Assembler include")
	dlg.current_file = animation.get_name().to_lower().replace(" ", "_") + "_anim.inc"
	dlg.file_selected.connect(func(path):
		var r: Dictionary = animation.export_snes_inc(path)
		status.emit("Exported animation: %s" % path)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _export_sgdk() -> void:
	if animation == null:
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.h", "C header")
	dlg.current_file = animation.get_name().to_lower().replace(" ", "_") + "_anim.h"
	dlg.file_selected.connect(func(path):
		animation.export_sgdk_header(path)
		status.emit("Exported SGDK header: %s" % path)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _save_json() -> void:
	if animation == null:
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.json", "Retro animation")
	dlg.current_file = animation.get_name().to_lower().replace(" ", "_") + ".anim.json"
	dlg.file_selected.connect(func(path):
		animation.save(path)
		status.emit("Saved animation: %s" % path)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _load_json() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.json", "Retro animation")
	dlg.file_selected.connect(func(path):
		var doc := RetroAnimation.new()
		if doc.load(path) == OK:
			set_animation(doc, project)
			status.emit("Loaded animation: %s" % path)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)
