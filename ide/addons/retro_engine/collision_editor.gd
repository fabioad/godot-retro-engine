@tool
extends VBoxContainer
## Per-frame hit/hurtbox editor with a two-character collision preview and
## native hitbox table export.

signal modified()
signal status(text: String)

const CollisionCanvas = preload("res://addons/retro_engine/collision_canvas.gd")

var project: RetroProject
var platform: String = "snes"
var sprite: RetroSprite
var animation: RetroAnimation
var hitbox_io: RetroHitboxIO
var collision_runtime: RetroCollisionRuntime
var state: String = "IDLE"
var frame: int = 0
var boxes: Array = []
var selected_box: int = -1
var opponent_state: String = "ATTACK"
var opponent_frame: int = 0
var offset_x: int = 160
var runtime_mode: bool = false
var runtime_state: String = ""
var runtime_frame: int = 0

var _canvas
var _state_option: OptionButton
var _opponent_state: OptionButton
var _timeline: HBoxContainer
var _runtime_check: CheckBox
var _play_button: Button
var _timer: Timer
var _playing: bool = false
var _box_list: ItemList
var _type: OptionButton
var _x: SpinBox
var _y: SpinBox
var _w: SpinBox
var _h: SpinBox
var _offset: SpinBox
var _collision: Label
var _info: Label
var _frame_spin: SpinBox
var _opp_frame: SpinBox
var _damage: SpinBox
var _hitstop_a: SpinBox
var _hitstop_d: SpinBox
var _hitstun: SpinBox
var _blockstun: SpinBox
var _invuln: SpinBox
var _hit_id: SpinBox
var _pushback: SpinBox
var _guard: CheckBox

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	add_child(head)
	var title := Label.new()
	title.text = "Hitbox / Hurtbox Timeline + Collision Preview"
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_runtime_check = CheckBox.new()
	_runtime_check.text = "Follow simulator"
	_runtime_check.tooltip_text = "Drive the player state/frame from the Sim tab"
	_runtime_check.toggled.connect(func(v): runtime_mode = v; if v: _apply_runtime_state())
	head.add_child(_runtime_check)
	var sprites_check := CheckBox.new()
	sprites_check.text = "Show sprites"
	sprites_check.button_pressed = true
	sprites_check.tooltip_text = "Draw the selected char sprite behind the hit/hurt boxes"
	sprites_check.toggled.connect(func(v): _canvas.show_sprites = v; _canvas.queue_redraw())
	head.add_child(sprites_check)
	var head2 := HBoxContainer.new()
	add_child(head2)
	var imp_air := Button.new()
	imp_air.text = "Import AIR"
	imp_air.pressed.connect(_import_air)
	head2.add_child(imp_air)
	var exp_air := Button.new()
	exp_air.text = "Export AIR"
	exp_air.pressed.connect(_export_air)
	head2.add_child(exp_air)
	var imp_cns := Button.new()
	imp_cns.text = "Import CNS hitdef"
	imp_cns.pressed.connect(_import_cns)
	head2.add_child(imp_cns)
	var head3 := HBoxContainer.new()
	add_child(head3)
	var export_snes := Button.new()
	export_snes.text = "Export hitboxes SNES"
	export_snes.pressed.connect(_export_snes)
	head3.add_child(export_snes)
	var export_md := Button.new()
	export_md.text = "Export hitboxes SGDK"
	export_md.pressed.connect(_export_sgdk)
	head3.add_child(export_md)
	var gen_col := Button.new()
	gen_col.text = "Generate collision C"
	gen_col.pressed.connect(_export_collision)
	head3.add_child(gen_col)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 150
	body.add_child(left)
	_state_option = OptionButton.new()
	_state_option.item_selected.connect(_on_state_selected)
	left.add_child(_state_option)
	_timeline = HBoxContainer.new()
	_timeline.add_theme_constant_override("separation", 2)
	var tscroll := ScrollContainer.new()
	tscroll.custom_minimum_size.y = 76
	tscroll.add_child(_timeline)
	left.add_child(tscroll)
	var play_row := HBoxContainer.new()
	left.add_child(play_row)
	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.pressed.connect(_toggle_play)
	play_row.add_child(_play_button)
	var prev := Button.new()
	prev.text = "<"
	prev.pressed.connect(func(): _step_frame(-1))
	play_row.add_child(prev)
	var next := Button.new()
	next.text = ">"
	next.pressed.connect(func(): _step_frame(1))
	play_row.add_child(next)
	var add_hit := Button.new()
	add_hit.text = "Add hitbox"
	add_hit.pressed.connect(func(): _add_box("hit"))
	left.add_child(add_hit)
	var add_hurt := Button.new()
	add_hurt.text = "Add hurtbox"
	add_hurt.pressed.connect(func(): _add_box("hurt"))
	left.add_child(add_hurt)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_color_override("font_color", Color("#8b98ad"))
	left.add_child(_info)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	_canvas = CollisionCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.box_selected.connect(_on_box_selected)
	_canvas.box_moved.connect(_on_box_moved)
	center.add_child(_canvas)
	_collision = Label.new()
	_collision.add_theme_font_size_override("font_size", 13)
	center.add_child(_collision)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 210
	body.add_child(side)
	var blabel := Label.new()
	blabel.text = "Selected frame boxes"
	side.add_child(blabel)
	_box_list = ItemList.new()
	_box_list.custom_minimum_size.y = 90
	_box_list.item_selected.connect(_on_box_from_list)
	side.add_child(_box_list)
	var row1 := HBoxContainer.new()
	side.add_child(row1)
	row1.add_child(_field("X"))
	_x = _spin(-512, 512, 0)
	row1.add_child(_x)
	row1.add_child(_field("Y"))
	_y = _spin(-512, 512, 0)
	row1.add_child(_y)
	var row2 := HBoxContainer.new()
	side.add_child(row2)
	row2.add_child(_field("W"))
	_w = _spin(1, 512, 16)
	row2.add_child(_w)
	row2.add_child(_field("H"))
	_h = _spin(1, 512, 16)
	row2.add_child(_h)
	var row3 := HBoxContainer.new()
	side.add_child(row3)
	_type = OptionButton.new()
	_type.add_item("hitbox")
	_type.add_item("hurtbox")
	row3.add_child(_type)
	var apply := Button.new()
	apply.text = "Apply box"
	apply.pressed.connect(_apply_box)
	row3.add_child(apply)
	var del := Button.new()
	del.text = "Delete"
	del.pressed.connect(_delete_box)
	row3.add_child(del)

	var mlabel := Label.new()
	mlabel.text = "Move properties"
	mlabel.add_theme_color_override("font_color", Color("#7fd1ff"))
	side.add_child(mlabel)
	var mrow1 := HBoxContainer.new()
	side.add_child(mrow1)
	mrow1.add_child(_field("Dmg"))
	_damage = _spin(0, 999, 0)
	mrow1.add_child(_damage)
	mrow1.add_child(_field("HStop A/D"))
	_hitstop_a = _spin(0, 255, 0)
	_hitstop_d = _spin(0, 255, 0)
	mrow1.add_child(_hitstop_a)
	mrow1.add_child(_hitstop_d)
	var mrow2 := HBoxContainer.new()
	side.add_child(mrow2)
	mrow2.add_child(_field("HStun"))
	_hitstun = _spin(0, 255, 0)
	mrow2.add_child(_hitstun)
	mrow2.add_child(_field("BStun"))
	_blockstun = _spin(0, 255, 0)
	mrow2.add_child(_blockstun)
	mrow2.add_child(_field("Inv"))
	_invuln = _spin(0, 255, 0)
	mrow2.add_child(_invuln)
	var mrow3 := HBoxContainer.new()
	side.add_child(mrow3)
	mrow3.add_child(_field("HitID"))
	_hit_id = _spin(0, 65535, 0)
	mrow3.add_child(_hit_id)
	mrow3.add_child(_field("Push"))
	_pushback = _spin(0, 255, 0)
	mrow3.add_child(_pushback)
	var mrow4 := HBoxContainer.new()
	side.add_child(mrow4)
	_guard = CheckBox.new()
	_guard.text = "Guardable"
	_guard.button_pressed = true
	mrow4.add_child(_guard)
	var apply_move := Button.new()
	apply_move.text = "Apply move"
	apply_move.pressed.connect(_apply_move)
	mrow4.add_child(apply_move)

	var sep := HSeparator.new()
	side.add_child(sep)
	var olabel := Label.new()
	olabel.text = "Opponent"
	olabel.add_theme_color_override("font_color", Color("#7fd1ff"))
	side.add_child(olabel)
	_opponent_state = OptionButton.new()
	_opponent_state.item_selected.connect(func(i):
		var key = _opponent_state.get_item_metadata(i)
		if key != null:
			opponent_state = String(key)
			opponent_frame = 0
			_refresh_opponent_canvas())
	side.add_child(_opponent_state)
	var orow := HBoxContainer.new()
	side.add_child(orow)
	orow.add_child(_field("F"))
	_opp_frame = _spin(0, 999, 0)
	_opp_frame.value_changed.connect(func(v): opponent_frame = int(v); _refresh_opponent_canvas())
	orow.add_child(_opp_frame)
	orow.add_child(_field("X"))
	_offset = _spin(-256, 256, 160)
	_offset.value_changed.connect(func(v): offset_x = int(v); _refresh_opponent_canvas())
	orow.add_child(_offset)

	_frame_spin = _spin(0, 999, 0)
	_frame_spin.visible = false
	side.add_child(_frame_spin)

	_timer = Timer.new()
	_timer.wait_time = 1.0 / 60.0
	_timer.timeout.connect(_tick)
	add_child(_timer)

func _field(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _spin(minv: float, maxv: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.value = value
	s.custom_minimum_size.x = 55
	return s

func set_context(p_project: RetroProject, p_platform: String, p_sprite: RetroSprite, p_animation: RetroAnimation) -> void:
	project = p_project
	platform = p_platform
	sprite = p_sprite
	animation = p_animation
	hitbox_io = RetroHitboxIO.new()
	collision_runtime = RetroCollisionRuntime.new()
	if project:
		var profile := project.resolve(".retro/editor/collision_profile.json")
		if FileAccess.file_exists(profile):
			collision_runtime.load(profile)
		else:
			collision_runtime.setup_from_animation(animation)
	else:
		collision_runtime.setup_from_animation(animation)
	collision_runtime.set_platform(platform)
	state = _first_state_with_boxes()
	frame = 0
	opponent_state = state
	opponent_frame = 0
	collision_runtime.setup_from_animation(animation)
	_populate_states()
	_rebuild_timeline()
	_load_frame()
	_load_move()

func apply_moves(p_moves: Array) -> void:
	if collision_runtime == null:
		return
	for m in p_moves:
		var move: Dictionary = m
		var target := String(move.get("state", ""))
		if target.is_empty():
			continue
		collision_runtime.set_move(target, move)
	_load_move()
	modified.emit()

func apply_hitdef(p_state: String, p_hitdef: Dictionary) -> void:
	if collision_runtime == null or p_hitdef.is_empty():
		return
	collision_runtime.apply_hitdef(p_state, p_hitdef)
	if p_state == state:
		_load_move()
	modified.emit()

func set_animation(p_animation: RetroAnimation) -> void:
	animation = p_animation
	if collision_runtime:
		for key in animation.get_states().keys():
			if collision_runtime.get_move(String(key)).is_empty():
				collision_runtime.set_move(String(key), {})
	_populate_states()
	_rebuild_timeline()
	_load_frame()

func set_sprite(p_sprite: RetroSprite) -> void:
	sprite = p_sprite
	_canvas.set_data(sprite, animation, state, frame)
	_refresh_collision()

func set_runtime_state(p_state: String, p_frame: int) -> void:
	runtime_state = p_state
	runtime_frame = p_frame
	if runtime_mode:
		_apply_runtime_state()

func _apply_runtime_state() -> void:
	if animation == null:
		return
	var keys := animation.get_states().keys()
	if not keys.has(runtime_state):
		return
	var s := animation.get_state(runtime_state)
	var frames: Array = s.get("frames", [])
	if frames.is_empty():
		return
	state = runtime_state
	frame = clampi(runtime_frame, 0, frames.size() - 1)
	_select_state_option()
	_rebuild_timeline()
	_load_frame()

func _first_state_with_boxes() -> String:
	if animation == null:
		return "IDLE"
	var fallback := "IDLE"
	for key in animation.get_states().keys():
		var s := animation.get_state(String(key))
		var frames: Array = s.get("frames", [])
		if not frames.is_empty() and fallback == "IDLE":
			fallback = String(key)
		for f in frames:
			if Array(Dictionary(f).get("hitboxes", Array())).size() > 0:
				return String(key)
	return fallback

func _populate_states() -> void:
	_state_option.clear()
	_opponent_state.clear()
	if animation == null:
		return
	var keys: Array = animation.get_states().keys()
	keys.sort_custom(func(a, b):
		var sa := String(a)
		var sb := String(b)
		var oa := 0 if sa in ["IDLE", "WALK", "JUMP", "CROUCH", "ATTACK", "HIT", "BLOCK", "SPECIAL", "SUPER", "THROW"] else 1
		var ob := 0 if sb in ["IDLE", "WALK", "JUMP", "CROUCH", "ATTACK", "HIT", "BLOCK", "SPECIAL", "SUPER", "THROW"] else 1
		if oa != ob:
			return oa < ob
		return sa.naturalnocasecmp_to(sb) < 0)
	for k in keys:
		var key := String(k)
		var frames: Array = animation.get_state(key).get("frames", [])
		if frames.is_empty():
			continue
		var text := "%s  (%df)" % [key, frames.size()]
		_state_option.add_item(text)
		_state_option.set_item_metadata(_state_option.item_count - 1, key)
		_opponent_state.add_item(text)
		_opponent_state.set_item_metadata(_opponent_state.item_count - 1, key)
	if _state_option.item_count == 0:
		state = "IDLE"
		opponent_state = "IDLE"
		return
	if not animation.get_states().has(state):
		state = String(_state_option.get_item_metadata(0))
	if not animation.get_states().has(opponent_state):
		opponent_state = state
	_select_state_option()
	_select_option(_opponent_state, opponent_state)

func _select_state_option() -> void:
	_select_option(_state_option, state)
	_select_option(_opponent_state, opponent_state)

func _select_option(opt: OptionButton, key: String) -> void:
	for i in range(opt.item_count):
		if String(opt.get_item_metadata(i)) == key:
			opt.select(i)
			return
	if opt.item_count > 0:
		opt.select(0)

func _on_state_selected(index: int) -> void:
	if animation == null:
		return
	var key = _state_option.get_item_metadata(index)
	if key == null:
		return
	state = String(key)
	frame = 0
	_rebuild_timeline()
	_load_frame()
	_load_move()
	modified.emit()

func _rebuild_timeline() -> void:
	for c in _timeline.get_children():
		c.queue_free()
	if animation == null:
		return
	var s := animation.get_state(state)
	var frames: Array = s.get("frames", [])
	for i in range(frames.size()):
		var f: Dictionary = frames[i]
		var b := Button.new()
		b.text = "%d\n%df" % [i, int(f.get("duration", 1))]
		b.custom_minimum_size = Vector2(48, 54)
		b.toggle_mode = true
		b.button_pressed = i == frame
		b.pressed.connect(func(): frame = i; _rebuild_timeline(); _load_frame())
		_timeline.add_child(b)
	if frames.is_empty():
		var lbl := Label.new()
		lbl.text = "No frames. Add frames in Animation."
		_timeline.add_child(lbl)

func _load_frame() -> void:
	if animation == null:
		return
	var s := animation.get_state(state)
	var frames: Array = s.get("frames", [])
	if frame < 0 or frame >= frames.size():
		boxes = []
		_info.text = "State %s has no frame %d." % [state, frame]
		_box_list.clear()
		_canvas.set_data(sprite, animation, state, frame)
		_collision.text = "No frame."
		return
	boxes = animation.get_frame_hitboxes(state, frame)
	_info.text = "%s frame %d/%d | %d box(es) | duration %d" % [state, frame, frames.size(), boxes.size(), int(Dictionary(frames[frame]).get("duration", 1))]
	_refresh_box_list()
	_canvas.set_data(sprite, animation, state, frame)
	_canvas.set_opponent(sprite, animation, opponent_state, opponent_frame)
	_canvas.set_positions(Vector2i(24, 24), Vector2i(24 + offset_x, 24))
	_refresh_collision()
	_opp_frame.set_value_no_signal(opponent_frame)
	_offset.set_value_no_signal(offset_x)
	_load_move()

func _refresh_box_list() -> void:
	_box_list.clear()
	for i in range(boxes.size()):
		var b: Dictionary = boxes[i]
		var r: Rect2i = b.get("rect", Rect2i())
		_box_list.add_item("%d %s %d,%d %dx%d" % [i, String(b.get("type", "hit")), r.position.x, r.position.y, r.size.x, r.size.y])
	if selected_box >= 0 and selected_box < boxes.size():
		_box_list.select(selected_box)
		_on_box_from_list(selected_box)

func _on_box_from_list(index: int) -> void:
	if index < 0 or index >= boxes.size():
		return
	selected_box = index
	var b: Dictionary = boxes[index]
	var r: Rect2i = b.get("rect", Rect2i())
	_x.set_value_no_signal(r.position.x)
	_y.set_value_no_signal(r.position.y)
	_w.set_value_no_signal(r.size.x)
	_h.set_value_no_signal(r.size.y)
	_type.select(0 if String(b.get("type", "hit")) == "hit" else 1)
	_canvas.set_selected(index)

func _on_box_selected(index: int) -> void:
	selected_box = index
	if index >= 0 and index < boxes.size():
		_on_box_from_list(index)

func _on_box_moved(index: int, _rect: Rect2i) -> void:
	boxes = animation.get_frame_hitboxes(state, frame)
	selected_box = index
	_refresh_box_list()
	_refresh_collision()
	modified.emit()

func _add_box(kind: String) -> void:
	if animation == null:
		return
	boxes = animation.get_frame_hitboxes(state, frame)
	boxes.append({"rect": Rect2i(4, 4, 16, 16), "type": kind})
	animation.set_frame_hitboxes(state, frame, boxes)
	selected_box = boxes.size() - 1
	_load_frame()
	modified.emit()

func _apply_box() -> void:
	if animation == null or selected_box < 0 or selected_box >= boxes.size():
		return
	var b: Dictionary = boxes[selected_box]
	b["rect"] = Rect2i(int(_x.value), int(_y.value), int(_w.value), int(_h.value))
	b["type"] = "hit" if _type.selected == 0 else "hurt"
	boxes[selected_box] = b
	animation.set_frame_hitboxes(state, frame, boxes)
	_load_frame()
	modified.emit()

func _delete_box() -> void:
	if animation == null or selected_box < 0 or selected_box >= boxes.size():
		return
	boxes.remove_at(selected_box)
	animation.set_frame_hitboxes(state, frame, boxes)
	selected_box = -1
	_load_frame()
	modified.emit()

func _refresh_opponent_canvas() -> void:
	if animation == null:
		return
	_canvas.set_opponent(sprite, animation, opponent_state, opponent_frame)
	_canvas.set_positions(Vector2i(24, 24), Vector2i(24 + offset_x, 24))
	_refresh_collision()

func _refresh_collision() -> void:
	if animation == null:
		return
	var result := animation.collision_test(state, frame, Vector2i(24, 24), opponent_state, opponent_frame, Vector2i(24 + offset_x, 24))
	_canvas.set_contacts(result.get("contacts", []))
	_collision.text = "COLLISION: %s  (%d contacts)" % ["YES" if bool(result.get("hit", false)) else "no", Array(result.get("contacts", [])).size()]
	_collision.add_theme_color_override("font_color", Color("#ff7a7a") if bool(result.get("hit", false)) else Color("#6ee7a8"))

func _step_frame(delta: int) -> void:
	var s := animation.get_state(state) if animation else {}
	var frames: Array = s.get("frames", [])
	if frames.is_empty():
		return
	frame = posmod(frame + delta, frames.size())
	_rebuild_timeline()
	_load_frame()

func _toggle_play() -> void:
	_playing = not _playing
	_play_button.text = "Pause" if _playing else "Play"
	if _playing:
		_timer.start()
	else:
		_timer.stop()

func _tick() -> void:
	if not _playing or animation == null:
		return
	var s := animation.get_state(state)
	var frames: Array = s.get("frames", [])
	if frames.is_empty():
		return
	var duration := int(Dictionary(frames[frame]).get("duration", 1))
	_timer.wait_time = duration / 60.0
	frame = (frame + 1) % frames.size()
	_rebuild_timeline()
	_load_frame()

func _load_move() -> void:
	if collision_runtime == null:
		return
	var m := collision_runtime.get_move(state)
	if m.is_empty():
		return
	_damage.set_value_no_signal(int(m.get("damage", 0)))
	_hitstop_a.set_value_no_signal(int(m.get("hitstop_attacker", 0)))
	_hitstop_d.set_value_no_signal(int(m.get("hitstop_defender", 0)))
	_hitstun.set_value_no_signal(int(m.get("hitstun", 0)))
	_blockstun.set_value_no_signal(int(m.get("blockstun", 0)))
	_invuln.set_value_no_signal(int(m.get("invuln", 0)))
	_hit_id.set_value_no_signal(int(m.get("hit_id", 0)))
	_pushback.set_value_no_signal(int(m.get("pushback", 0)))
	_guard.set_pressed_no_signal(bool(m.get("guard", true)))

func _apply_move() -> void:
	if collision_runtime == null:
		return
	collision_runtime.set_move(state, {
		"damage": int(_damage.value),
		"hitstop_attacker": int(_hitstop_a.value),
		"hitstop_defender": int(_hitstop_d.value),
		"hitstun": int(_hitstun.value),
		"blockstun": int(_blockstun.value),
		"invuln": int(_invuln.value),
		"hit_id": int(_hit_id.value),
		"pushback": int(_pushback.value),
		"guard": _guard.button_pressed,
	})
	modified.emit()

func _import_air() -> void:
	if animation == null:
		return
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.add_filter("*.air", "MUGEN AIR animation")
	dlg.file_selected.connect(func(path):
		var parsed := hitbox_io.parse_air(path)
		if not bool(parsed.get("ok", false)):
			status.emit("AIR parse failed.")
			dlg.queue_free()
			return
		_show_air_import(parsed)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _show_air_import(parsed: Dictionary) -> void:
	var actions: Array = parsed.get("actions", [])
	if actions.is_empty():
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Import AIR action"
	var box := VBoxContainer.new()
	var action_opt := OptionButton.new()
	for a in actions:
		action_opt.add_item("Action %d (%d frames)" % [int(a.get("action", 0)), Array(a.get("frames", [])).size()])
	box.add_child(action_opt)
	var state_opt := OptionButton.new()
	for key in animation.get_states().keys():
		state_opt.add_item(String(key))
	box.add_child(state_opt)
	box.add_child(_field("Select action and target animation state. Existing frames of the target state will be replaced."))
	dlg.add_child(box)
	dlg.confirmed.connect(func():
		var a: Dictionary = actions[action_opt.selected]
		var result := hitbox_io.import_air_frames(a.get("frames", []), animation, state_opt.get_item_text(state_opt.selected))
		state = state_opt.get_item_text(state_opt.selected)
		_populate_states()
		_rebuild_timeline()
		_load_frame()
		modified.emit()
		status.emit("AIR imported: %s" % result)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(520, 220))

func _export_air() -> void:
	if animation == null:
		return
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.add_filter("*.air", "MUGEN AIR animation")
	dlg.current_file = animation.get_name().to_lower().replace(" ", "_") + ".air"
	dlg.file_selected.connect(func(path):
		var r := hitbox_io.export_air(animation, state, 0, path)
		status.emit("AIR exported: %s" % path)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _import_cns() -> void:
	if animation == null:
		return
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.add_filter("*.cns", "MUGEN CNS")
	dlg.file_selected.connect(func(path):
		var parsed := hitbox_io.parse_cns(path)
		if not bool(parsed.get("ok", false)):
			status.emit("CNS parse failed.")
			dlg.queue_free()
			return
		_show_cns_import(parsed)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _show_cns_import(parsed: Dictionary) -> void:
	var defs: Array = parsed.get("hitdefs", [])
	if defs.is_empty():
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Apply CNS HitDef to '%s'" % state
	var opt := OptionButton.new()
	for h in defs:
		opt.add_item("State %d | dmg %d | hitstop %d/%d | hitstun %d" % [int(h.get("state", -1)), int(h.get("damage", 0)), int(h.get("hitstop_attacker", 0)), int(h.get("hitstop_defender", 0)), int(h.get("hitstun", 0))])
	dlg.add_child(opt)
	dlg.confirmed.connect(func():
		var h: Dictionary = defs[opt.selected]
		collision_runtime.apply_hitdef(state, h)
		_load_move()
		modified.emit()
		status.emit("CNS HitDef applied to " + state)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(620, 180))

func _export_collision() -> void:
	if animation == null or collision_runtime == null or project == null:
		return
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.current_dir = project.resolve("src")
	dlg.dir_selected.connect(func(dir):
		var r: Dictionary
		if platform == "snes":
			r = collision_runtime.export_snes(dir, "retro_collision", animation)
		else:
			r = collision_runtime.export_sgdk(dir, "retro_collision", animation)
		status.emit("Collision runtime: " + String(r.get("source", "")))
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func save_session() -> void:
	if project and collision_runtime:
		var dir := project.resolve(".retro/editor")
		DirAccess.make_dir_recursive_absolute(dir)
		collision_runtime.save(dir.path_join("collision_profile.json"))

func _export_snes() -> void:
	if animation == null:
		return
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.add_filter("*.inc", "WLA-DX include")
	dlg.current_file = animation.get_name().to_lower().replace(" ", "_") + "_hitboxes.inc"
	dlg.file_selected.connect(func(path):
		var r := animation.export_hitboxes_snes(path)
		status.emit("Hitboxes exported: %s (%d)" % [path, int(r.get("count", 0))])
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _export_sgdk() -> void:
	if animation == null:
		return
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.add_filter("*.h", "SGDK C header")
	dlg.current_file = animation.get_name().to_lower().replace(" ", "_") + "_hitboxes.h"
	dlg.file_selected.connect(func(path):
		var r := animation.export_hitboxes_sgdk(path)
		status.emit("Hitboxes exported: %s (%d)" % [path, int(r.get("count", 0))])
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)
