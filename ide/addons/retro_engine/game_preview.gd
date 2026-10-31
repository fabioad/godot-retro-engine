@tool
extends "res://addons/retro_engine/stage_canvas.gd"
## Editor-side game boot/screen simulator for the Preview tab.
##
## It powers on like a console, shows a boot logo, an attract/title screen and
## a gameplay screen, and logs commands and screen transitions. The simulation
## is frame-locked at 60 Hz so Pause + Step can be used to inspect fades and
## transition frames. It is an editor preview, not an emulator: use Build + Run
## for the real ROM.

signal status(text: String)
signal status_changed(text: String)
signal screen_changed(from_screen: String, to_screen: String, trigger: String, at_frame: int)
signal command_detected(action: String, at_frame: int)
signal pause_changed(is_paused: bool)
signal log_changed()

const TICK_HZ := 60.0
const POWER_ON_FRAMES := 18
const BOOT_FRAMES := 90
const FLOOR_Y := 160.0
const MAX_LOG := 240

const SCREEN_OFF := "OFF"
const SCREEN_BOOT := "BOOT"
const SCREEN_TITLE := "TITLE"
const SCREEN_GAME := "GAMEPLAY"
const SCREEN_PAUSE := "PAUSE"

var project: RetroProject
var platform := "snes"
var screen := SCREEN_OFF
var frame := 0
var screen_frame := 0
var paused := false
var pause_on_transition := false
var speed := 1.0
var transition_frames := 24
var input_enabled := true
var last_command := ""
var events: Array = []
var player_pos := Vector2(128, FLOOR_Y)
var player_vy := 0.0
var player_grounded := true

var _input_map: RetroInputMap
var _timer: Timer
var _boot_progress := 0.0
var _title_blink := 0
var _fade := 0.0
var _transition_phase := ""
var _pending_screen := ""
var _pending_trigger := ""
var _transition_frame := 0
var _held_actions: Dictionary = {}
var _state_frame := 0
var _user_sprites := true
var _user_collisions := true
var _user_limits := true

func _ready() -> void:
	super._ready()
	focus_mode = Control.FOCUS_ALL
	_timer = Timer.new()
	_timer.wait_time = 1.0 / TICK_HZ
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_timer.start()
	power_on()

func _exit_tree() -> void:
	if _timer != null:
		_timer.stop()

func set_platform(p_platform: String) -> void:
	platform = p_platform
	if _input_map != null:
		_input_map.set_platform(platform)
	player_pos = _player_home()
	sprite_pos = player_pos
	queue_redraw()

func set_input_map(p_map: RetroInputMap) -> void:
	if p_map == null:
		_input_map = RetroInputMap.new()
		_input_map.setup_defaults(platform)
	else:
		_input_map = p_map
	_input_map.set_platform(platform)

func set_stage(p_stage: RetroStage) -> void:
	super.set_stage(p_stage)
	if p_stage != null and screen == SCREEN_OFF and frame == 0:
		power_on()
	queue_redraw()

func set_sprite(p_sprite: RetroSprite, p_animation: RetroAnimation = null) -> void:
	super.set_sprite(p_sprite, p_animation)
	queue_redraw()

func set_sprites_visible(value: bool) -> void:
	_user_sprites = value
	_apply_visibility()
	queue_redraw()

func set_collisions_visible(value: bool) -> void:
	_user_collisions = value
	_apply_visibility()
	queue_redraw()

func set_limits_visible(value: bool) -> void:
	_user_limits = value
	_apply_visibility()
	queue_redraw()

func set_speed(value: float) -> void:
	speed = clampf(value, 0.05, 4.0)
	if _timer != null:
		_timer.wait_time = 1.0 / (TICK_HZ * speed)

func power_on(clear := true) -> void:
	if clear:
		events.clear()
		frame = 0
	screen = SCREEN_OFF
	screen_frame = 0
	paused = false
	last_command = ""
	_boot_progress = 0.0
	_title_blink = 0
	_fade = 0.0
	_transition_phase = ""
	_pending_screen = ""
	_pending_trigger = ""
	_transition_frame = 0
	animation_state = "IDLE"
	animation_time = 0.0
	_state_frame = 0
	_held_actions.clear()
	player_pos = _player_home()
	player_vy = 0.0
	player_grounded = true
	sprite_pos = player_pos
	_apply_visibility()
	_log_event("POWER ON")
	pause_changed.emit(false)
	_emit_status()
	queue_redraw()

func reset() -> void:
	power_on(true)

func toggle_pause() -> void:
	set_pause(not paused)

func set_pause(value: bool) -> void:
	if paused == value:
		return
	paused = value
	_log_event("pause ON" if paused else "resume")
	pause_changed.emit(paused)
	_emit_status()
	queue_redraw()

func step_frames(count: int = 1) -> void:
	var n := maxi(1, count)
	for _i in range(n):
		_tick()
	queue_redraw()

func command(action_id: String) -> void:
	if _input_map == null:
		return
	var a := _input_map.get_action(action_id)
	if a.is_empty():
		return
	last_command = action_id
	_log_event("command " + action_id)
	command_detected.emit(action_id, frame)
	var lower := action_id.to_lower()
	if lower.contains("start") or _has_key(a, "Enter") or _has_key(a, "Start"):
		_on_start_command()
		_emit_status()
		queue_redraw()
		return
	if lower.contains("select") or lower.contains("reset"):
		_on_select_command()
		_emit_status()
		queue_redraw()
		return
	if screen == SCREEN_GAME:
		var next_state := String(a.get("state", ""))
		if not next_state.is_empty():
			animation_state = next_state
			_state_frame = 0
			animation_time = 0.0
		if _is_hold_action(a, lower):
			_held_actions[action_id] = true
	_emit_status()
	queue_redraw()

func release_action(action_id: String) -> void:
	_held_actions.erase(action_id)
	if screen == SCREEN_GAME and _input_map != null:
		var a := _input_map.get_action(action_id)
		var state_name := String(a.get("state", ""))
		if state_name == animation_state and not _is_action_held_for_state(state_name):
			animation_state = "IDLE"
			_state_frame = 0
			animation_time = 0.0
	_emit_status()
	queue_redraw()

func get_log_text() -> String:
	var lines := PackedStringArray()
	for entry in events:
		lines.append("[%05d] %s" % [int(entry.get("frame", 0)), String(entry.get("text", ""))])
	return "\n".join(lines)

func clear_log() -> void:
	events.clear()
	log_changed.emit()
	queue_redraw()

func get_status_text() -> String:
	var text := "%s | frame %d" % [screen, frame]
	if not _transition_phase.is_empty():
		text += " | fade %d%%" % int(round(_fade * 100.0))
	if paused:
		text += " | PAUSED"
	return text

func _on_timer() -> void:
	if paused or not is_visible_in_tree():
		return
	_tick()

func _tick() -> void:
	frame += 1
	if not _transition_phase.is_empty():
		_advance_transition()
		_emit_status()
		queue_redraw()
		return
	match screen:
		SCREEN_OFF:
			if frame >= POWER_ON_FRAMES:
				_switch_screen(SCREEN_BOOT, "power on")
		SCREEN_BOOT:
			screen_frame += 1
			_boot_progress = clampf(float(screen_frame) / float(BOOT_FRAMES), 0.0, 1.0)
			if screen_frame >= BOOT_FRAMES:
				_begin_transition(SCREEN_TITLE, "boot complete")
		SCREEN_TITLE:
			screen_frame += 1
			_title_blink += 1
			animation_state = "IDLE"
			animation_time += 1.0 / TICK_HZ
		SCREEN_GAME:
			_tick_gameplay()
		SCREEN_PAUSE:
			screen_frame += 1
	_emit_status()
	queue_redraw()

func _tick_gameplay() -> void:
	screen_frame += 1
	animation_time += 1.0 / TICK_HZ
	_state_frame += 1
	var move := 0
	if _held_any(["left"]):
		move -= 1
	if _held_any(["right"]):
		move += 1
	if move != 0:
		player_pos.x = clampf(player_pos.x + move * 1.4, 8.0, _playfield_size().x - 8.0)
	if _held_any(["up", "jump"]) and player_grounded:
		player_vy = -4.2
		player_grounded = false
	if not player_grounded:
		player_vy += 0.35
		player_pos.y += player_vy
		if player_pos.y >= FLOOR_Y:
			player_pos.y = FLOOR_Y
			player_vy = 0.0
			player_grounded = true
		else:
			animation_state = "JUMP"
			_state_frame = 0
	elif animation_state == "JUMP":
		animation_state = "IDLE"
		_state_frame = 0
	sprite_pos = player_pos
	var duration := _state_duration(animation_state)
	var limit := duration if duration > 0 else 30
	if not _is_action_held_for_state(animation_state) and _state_frame >= limit:
		animation_state = "IDLE"
		_state_frame = 0
		animation_time = 0.0

func _on_start_command() -> void:
	match screen:
		SCREEN_OFF:
			_switch_screen(SCREEN_BOOT, "start")
		SCREEN_BOOT:
			_begin_transition(SCREEN_TITLE, "start")
		SCREEN_TITLE:
			_begin_transition(SCREEN_GAME, "start")
		SCREEN_GAME:
			_begin_transition(SCREEN_PAUSE, "start")
		SCREEN_PAUSE:
			_begin_transition(SCREEN_GAME, "start")

func _on_select_command() -> void:
	if screen == SCREEN_GAME or screen == SCREEN_PAUSE:
		_begin_transition(SCREEN_TITLE, "select")
	elif screen == SCREEN_TITLE:
		_begin_transition(SCREEN_BOOT, "select")

func _begin_transition(to_screen: String, trigger: String) -> void:
	if not _transition_phase.is_empty() or to_screen == screen:
		return
	_pending_screen = to_screen
	_pending_trigger = trigger
	_transition_phase = "out"
	_transition_frame = 0
	_fade = 0.0
	_log_event("%s -> %s (%s)" % [screen, to_screen, trigger])
	screen_changed.emit(screen, to_screen, trigger, frame)
	status.emit("Screen transition: %s -> %s (%s)" % [screen, to_screen, trigger])
	if pause_on_transition:
		set_pause(true)
	queue_redraw()

func _advance_transition() -> void:
	_transition_frame += 1
	var half := maxi(1, transition_frames)
	if _transition_phase == "out":
		_fade = minf(1.0, float(_transition_frame) / float(half))
		if _transition_frame >= half:
			_switch_screen(_pending_screen, _pending_trigger, false)
			_transition_phase = "in"
			_transition_frame = 0
	else:
		_fade = maxf(0.0, 1.0 - float(_transition_frame) / float(half))
		if _transition_frame >= half:
			_fade = 0.0
			_transition_phase = ""
			_pending_screen = ""
			_pending_trigger = ""

func _switch_screen(to_screen: String, trigger: String, log_change := true) -> void:
	var old_screen := screen
	screen = to_screen
	screen_frame = 0
	animation_state = "IDLE"
	animation_time = 0.0
	_state_frame = 0
	_held_actions.clear()
	player_pos = _player_home()
	player_vy = 0.0
	player_grounded = true
	sprite_pos = player_pos
	_apply_visibility()
	if log_change:
		_log_event("%s -> %s (%s)" % [old_screen, to_screen, trigger])
		screen_changed.emit(old_screen, to_screen, trigger, frame)

func _apply_visibility() -> void:
	var in_game := screen == SCREEN_GAME or screen == SCREEN_PAUSE
	show_sprites = _user_sprites and in_game
	show_collisions = _user_collisions and in_game
	show_limits = _user_limits and in_game

func _emit_status() -> void:
	status_changed.emit(get_status_text())

func _log_event(text: String) -> void:
	events.append({"frame": frame, "text": text})
	while events.size() > MAX_LOG:
		events.pop_front()
	log_changed.emit()

func _state_duration(state_name: String) -> int:
	if _input_map == null:
		return 0
	var states := _input_map.get_states()
	var idx := states.find(state_name)
	if idx >= 0 and idx < _input_map.get_state_durations().size():
		return int(_input_map.get_state_durations()[idx])
	return 0

func _is_action_held_for_state(state_name: String) -> bool:
	if _input_map == null:
		return false
	for action_id in _held_actions.keys():
		var a := _input_map.get_action(String(action_id))
		if String(a.get("state", "")) == state_name:
			return true
	return false

func _held_any(ids: Array) -> bool:
	for action_id in ids:
		if _held_actions.has(action_id):
			return true
		for held in _held_actions.keys():
			if String(held).to_lower().contains(String(action_id)):
				return true
	return false

func _is_hold_action(a: Dictionary, lower_id: String) -> bool:
	if bool(a.get("hold", false)) or String(a.get("type", "button")) == "hold":
		return true
	for token in ["left", "right", "up", "down", "jump", "crouch"]:
		if lower_id.contains(token):
			return true
	return false

func _playfield_size() -> Vector2:
	return Vector2(256, 224) if platform == "snes" else Vector2(320, 224)

func _player_home() -> Vector2:
	var playfield := _playfield_size()
	return Vector2(playfield.x * 0.5, FLOOR_Y)

func _has_key(a: Dictionary, needle: String) -> bool:
	var wanted := _norm_key(needle)
	for key in a.get("keys", []):
		if _norm_key(String(key)) == wanted:
			return true
	return false

func _norm_key(value: String) -> String:
	return value.strip_edges().replace(" ", "").replace("_", "").to_upper()

func _action_for_key(key: String) -> String:
	if _input_map == null:
		return ""
	var wanted := _norm_key(key)
	for a in _input_map.get_actions():
		for k in a.get("keys", []):
			if _norm_key(String(k)) == wanted:
				return String(a.get("id", ""))
	return ""

func _action_for_pad(pad_name: String) -> String:
	if _input_map == null:
		return ""
	var wanted := _norm_key(pad_name)
	for a in _input_map.get_actions():
		for g in a.get("gamepad", []):
			if _norm_key(String(g)) == wanted:
				return String(a.get("id", ""))
	return ""

func _find_start_id() -> String:
	if _input_map == null:
		return ""
	for a in _input_map.get_actions():
		var id := String(a.get("id", ""))
		var label := String(a.get("label", ""))
		if id.to_lower().contains("start") or label.to_lower().contains("start"):
			return id
		if _has_key(a, "Enter") or _has_key(a, "Start"):
			return id
	return ""

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

func _input(event: InputEvent) -> void:
	if not input_enabled or not is_visible_in_tree():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.echo:
			return
		var code := ke.keycode if ke.keycode != KEY_NONE else ke.physical_keycode
		var key := OS.get_keycode_string(code)
		var normalized := _norm_key(key)
		if ke.pressed and normalized == "P":
			toggle_pause()
			get_viewport().set_input_as_handled()
			return
		if ke.pressed and normalized == "F8":
			step_frames(1)
			get_viewport().set_input_as_handled()
			return
		if ke.pressed and normalized == "F9":
			step_frames(10)
			get_viewport().set_input_as_handled()
			return
		if ke.pressed and normalized == "R" and screen == SCREEN_OFF:
			power_on()
			get_viewport().set_input_as_handled()
			return
		var action := _action_for_key(key)
		if action.is_empty() and ke.pressed and normalized in ["ENTER", "KPENTER", "SPACE"]:
			action = _find_start_id()
		if action.is_empty():
			return
		if ke.pressed:
			command(action)
		else:
			release_action(action)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		var pad_name := _joy_name(jb.button_index)
		var action := _action_for_pad(pad_name)
		if action.is_empty() and jb.button_index == JOY_BUTTON_START and jb.pressed:
			action = _find_start_id()
		if action.is_empty() and jb.button_index == JOY_BUTTON_BACK and jb.pressed:
			toggle_pause()
			get_viewport().set_input_as_handled()
			return
		if action.is_empty():
			return
		if jb.pressed:
			command(action)
		else:
			release_action(action)
		get_viewport().set_input_as_handled()

func _view_rect() -> Rect2:
	var plat := stage.get_platform() if stage != null else platform
	var native := Vector2(256, 224) if plat == "snes" else Vector2(320, 224)
	var view_size := native * float(zoom)
	var origin := ((size - view_size) * 0.5).floor()
	return Rect2(origin, view_size)

func _draw() -> void:
	super._draw()
	var view := _view_rect()
	if view.size.x <= 0.0 or view.size.y <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var unit := clampf(float(zoom), 1.0, 3.0)
	match screen:
		SCREEN_OFF:
			_draw_off(view, font, unit)
		SCREEN_BOOT:
			_draw_boot(view, font, unit)
		SCREEN_TITLE:
			_draw_title(view, font, unit)
		SCREEN_GAME:
			_draw_gameplay(view, font, unit)
		SCREEN_PAUSE:
			_draw_pause_screen(view, font, unit)
	if _fade > 0.0:
		draw_rect(view, Color(0, 0, 0, clampf(_fade, 0.0, 1.0)))
	if paused:
		_draw_pause_badge(view, font, unit)
	draw_rect(view, Color("#7fd1ff"), false, 2.0)

func _draw_center(font: Font, view: Rect2, text: String, y_ratio: float, font_size: int, color: Color) -> void:
	var y := view.position.y + view.size.y * y_ratio
	draw_string(font, Vector2(view.position.x, y), text, HORIZONTAL_ALIGNMENT_CENTER,
		view.size.x, font_size, color)

func _draw_box(view: Rect2, color: Color) -> void:
	draw_rect(view, color)

func _draw_off(view: Rect2, font: Font, unit: float) -> void:
	_draw_box(view, Color(0.01, 0.012, 0.02))
	_draw_center(font, view, "POWER OFF", 0.46, int(22 * unit), Color("#9fb4d0"))
	_draw_center(font, view, "Press Power or R to boot", 0.56, int(10 * unit), Color("#6f8299"))

func _draw_boot(view: Rect2, font: Font, unit: float) -> void:
	_draw_box(view, Color.BLACK)
	_draw_center(font, view, "GODOT", 0.36, int(34 * unit), Color("#e8f3ff"))
	_draw_center(font, view, "RETRO ENGINE", 0.45, int(18 * unit), Color("#7fd1ff"))
	_draw_center(font, view, "%s  //  BOOT SIMULATION" % platform.to_upper(), 0.55,
		int(10 * unit), Color("#9fb4d0"))
	var bar := Rect2(view.position.x + view.size.x * 0.22, view.position.y + view.size.y * 0.66,
		view.size.x * 0.56, maxf(4.0, 4.0 * unit))
	draw_rect(bar, Color("#1b2530"))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * _boot_progress, bar.size.y)), Color("#7fd1ff"))
	_draw_center(font, view, "BOOTING %d%%" % int(round(_boot_progress * 100.0)), 0.74,
		int(9 * unit), Color("#9fb4d0"))

func _draw_title(view: Rect2, font: Font, unit: float) -> void:
	draw_rect(view, Color(0.01, 0.02, 0.05, 0.58))
	var title := project.get_name() if project != null else "RETRO GAME"
	if title.strip_edges().is_empty():
		title = "RETRO GAME"
	_draw_center(font, view, title.to_upper(), 0.32, int(26 * unit), Color("#ffe38a"))
	_draw_center(font, view, "PRESS START", 0.58, int(15 * unit),
		Color("#e8f3ff") if (_title_blink % 60) < 40 else Color("#43536a"))
	_draw_center(font, view, "Start = Enter / pad Start   P = pause   F8 = 1 frame", 0.86,
		int(8 * unit), Color("#9fb4d0"))

func _draw_gameplay(view: Rect2, font: Font, unit: float) -> void:
	var hud := Rect2(view.position + Vector2(4, 4), Vector2(view.size.x - 8, maxf(14.0, 12.0 * unit)))
	draw_rect(hud, Color(0, 0, 0, 0.62))
	var text := "GAMEPLAY  F%05d  STATE %s" % [frame, animation_state]
	if not last_command.is_empty():
		text += "  LAST %s" % last_command
	draw_string(font, hud.position + Vector2(3, hud.size.y - 3), text,
		HORIZONTAL_ALIGNMENT_LEFT, hud.size.x - 6, int(8 * unit), Color("#9fe7c0"))
	var foot := "START = PAUSE SCREEN   P = FREEZE   F8 = STEP"
	draw_string(font, Vector2(view.position.x + 4, view.end.y - 5), foot,
		HORIZONTAL_ALIGNMENT_LEFT, view.size.x - 8, int(7 * unit), Color("#8b98ad"))

func _draw_pause_screen(view: Rect2, font: Font, unit: float) -> void:
	draw_rect(view, Color(0.01, 0.02, 0.05, 0.62))
	_draw_center(font, view, "PAUSED", 0.42, int(26 * unit), Color("#ffd45e"))
	_draw_center(font, view, "START TO RESUME", 0.56, int(12 * unit), Color("#e8f3ff"))
	_draw_center(font, view, "P = freeze frame   F8 = 1 frame   F9 = 10 frames", 0.78,
		int(8 * unit), Color("#9fb4d0"))

func _draw_pause_badge(view: Rect2, font: Font, unit: float) -> void:
	var text := "PAUSED  F%05d" % frame
	var w := maxf(90.0, 66.0 * unit)
	var badge := Rect2(view.end.x - w - 6.0, view.position.y + 6.0, w, maxf(14.0, 12.0 * unit))
	draw_rect(badge, Color(0.08, 0.05, 0.01, 0.88))
	draw_rect(badge, Color("#ffd45e"), false, 1.0)
	draw_string(font, badge.position + Vector2(4, badge.size.y - 3), text,
		HORIZONTAL_ALIGNMENT_LEFT, badge.size.x - 8, int(8 * unit), Color("#ffd45e"))
