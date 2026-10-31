@tool
extends VBoxContainer
## MUGEN Tools: one tab for character/stage assets, SFF sprites, AIR frames,
## SND auditioning, stage layers and the existing import/hitbox/simulator tools.

signal modified()
signal status(text: String)
signal assets_imported(result: Dictionary)

const SffBank = preload("res://addons/retro_engine/mugen_sff.gd")
const AirAnim = preload("res://addons/retro_engine/mugen_air.gd")
const MugenDef = preload("res://addons/retro_engine/mugen_def.gd")
const SndBank = preload("res://addons/retro_engine/mugen_snd.gd")
const CharPreview = preload("res://addons/retro_engine/mugen_preview.gd")
const StagePreview = preload("res://addons/retro_engine/mugen_stage_preview.gd")
const MugenImport = preload("res://addons/retro_engine/mugen_import.gd")

var project: RetroProject
var platform: String = "snes"
var animation: RetroAnimation
var sprite: RetroSprite
var input_map: RetroInputMap

var _toolbar: HFlowContainer
var _content: PanelContainer
var _pages: Dictionary = {}
var _buttons: Dictionary = {}
var _current: String = ""

# Character page.
var _char_path: Label
var _char_actions: ItemList
var _char_sounds: ItemList
var _char_preview
var _char_play: Button
var _char_loop: CheckBox
var _char_boxes: CheckBox
var _char_label: Label
var _char_info: RichTextLabel
var _char_def
var _char_air
var _char_sff
var _char_snd
var _char_action := 0
var _char_playing := false

# Stage page.
var _stage_path: Label
var _stage_layers: ItemList
var _stage_preview
var _stage_play: Button
var _stage_auto: CheckBox
var _stage_camera: HSlider
var _stage_camera_label: Label
var _stage_info: RichTextLabel
var _stage_def
var _stage_sff
var _stage_air
var _stage_time := 0.0
var _stage_cam := 0.0
var _stage_dir := 1.0
var _stage_bound_l := -216.0
var _stage_bound_r := 216.0
var _stage_auto_scroll := false

# SFF page.
var _sff_path: Label
var _sff_list: ItemList
var _sff_filter: LineEdit
var _sff_preview: TextureRect
var _sff_info: RichTextLabel
var _sff_bank
var _sff_entries: Array = []

# Sound page.
var _snd_path: Label
var _snd_list: ItemList
var _snd_player: AudioStreamPlayer
var _snd_info: RichTextLabel
var _snd_bank

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_toolbar = HFlowContainer.new()
	_toolbar.add_theme_constant_override("separation", 3)
	add_child(_toolbar)
	_content = PanelContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_content)
	_snd_player = AudioStreamPlayer.new()
	add_child(_snd_player)
	_add_page("char", "Char / Anim", _build_char_page())
	_add_page("stage", "Stage Layers", _build_stage_page())
	_add_page("sff", "SFF Sprites", _build_sff_page())
	_add_page("sounds", "Sounds", _build_snd_page())
	show_page("char")
	set_process(true)

func set_context(p_project: RetroProject, p_platform: String, p_animation: RetroAnimation, p_sprite: RetroSprite, p_input: RetroInputMap) -> void:
	project = p_project
	platform = p_platform
	animation = p_animation
	sprite = p_sprite
	input_map = p_input

func add_tool_page(id: String, title: String, control: Control) -> void:
	_add_page(id, title, control)

func show_page(id: String) -> void:
	if not _pages.has(id):
		return
	for key in _pages.keys():
		var page: Control = _pages[key]
		page.visible = key == id
	_current = id
	for key in _buttons.keys():
		var b: Button = _buttons[key]
		b.button_pressed = key == id
	# Refresh asset lists when entering a page.
	if id == "sff" and _sff_bank != null:
		_populate_sff()
	elif id == "sounds" and _snd_bank != null:
		_populate_snd()

func _add_page(id: String, title: String, control: Control) -> void:
	var button := Button.new()
	button.text = title
	button.toggle_mode = true
	button.flat = true
	button.pressed.connect(func(): show_page(id))
	_toolbar.add_child(button)
	_buttons[id] = button
	control.visible = false
	_content.add_child(control)
	_pages[id] = control

func _build_char_page() -> Control:
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	split.add_child(left)
	var open_def := Button.new()
	open_def.text = "Open char DEF..."
	open_def.pressed.connect(_pick_char_def)
	left.add_child(open_def)
	_char_path = Label.new()
	_char_path.text = "No character loaded"
	_char_path.clip_text = true
	_char_path.add_theme_color_override("font_color", Color("#9fb4d0"))
	left.add_child(_char_path)
	var alabel := Label.new()
	alabel.text = "AIR actions"
	left.add_child(alabel)
	_char_actions = ItemList.new()
	_char_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_char_actions.item_selected.connect(_on_char_action)
	left.add_child(_char_actions)
	var slabel := Label.new()
	slabel.text = "SND sounds (double-click to play)"
	left.add_child(slabel)
	_char_sounds = ItemList.new()
	_char_sounds.custom_minimum_size.y = 110
	_char_sounds.item_activated.connect(_on_char_sound)
	left.add_child(_char_sounds)
	var import_char := Button.new()
	import_char.text = "Import char to project"
	import_char.tooltip_text = "Convert this char's SFF/AIR to a native sprite + animation in the current project"
	import_char.pressed.connect(_import_char)
	left.add_child(import_char)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(center)
	_char_preview = CharPreview.new()
	_char_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(_char_preview)
	var controls := HFlowContainer.new()
	center.add_child(controls)
	_char_play = Button.new()
	_char_play.text = "Play"
	_char_play.pressed.connect(_toggle_char_play)
	controls.add_child(_char_play)
	var stop := Button.new()
	stop.text = "Stop"
	stop.pressed.connect(_stop_char)
	controls.add_child(stop)
	var step := Button.new()
	step.text = "Step"
	step.pressed.connect(_step_char)
	controls.add_child(step)
	_char_loop = CheckBox.new()
	_char_loop.text = "Loop"
	_char_loop.button_pressed = true
	_char_loop.toggled.connect(func(v): _char_preview.loop = v)
	controls.add_child(_char_loop)
	_char_boxes = CheckBox.new()
	_char_boxes.text = "Hitboxes"
	_char_boxes.button_pressed = true
	_char_boxes.toggled.connect(func(v): _char_preview.show_boxes = v; _char_preview.queue_redraw())
	controls.add_child(_char_boxes)
	_char_label = Label.new()
	_char_label.add_theme_color_override("font_color", Color("#cfe0f5"))
	center.add_child(_char_label)

	var right := ScrollContainer.new()
	right.custom_minimum_size.x = 260
	split.add_child(right)
	_char_info = RichTextLabel.new()
	_char_info.bbcode_enabled = true
	_char_info.fit_content = true
	_char_info.custom_minimum_size.x = 245
	right.add_child(_char_info)
	return split

func _build_stage_page() -> Control:
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	split.add_child(left)
	var open_def := Button.new()
	open_def.text = "Open stage DEF..."
	open_def.pressed.connect(_pick_stage_def)
	left.add_child(open_def)
	_stage_path = Label.new()
	_stage_path.text = "No stage loaded"
	_stage_path.clip_text = true
	_stage_path.add_theme_color_override("font_color", Color("#9fb4d0"))
	left.add_child(_stage_path)
	var ll := Label.new()
	ll.text = "BG layers"
	left.add_child(ll)
	_stage_layers = ItemList.new()
	_stage_layers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_stage_layers)
	var import_stage := Button.new()
	import_stage.text = "Import stage to project"
	import_stage.tooltip_text = "Render this stage's layers and convert them to a native RetroStage in the current project"
	import_stage.pressed.connect(_import_stage)
	left.add_child(import_stage)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(center)
	_stage_preview = StagePreview.new()
	_stage_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(_stage_preview)
	var controls := HFlowContainer.new()
	center.add_child(controls)
	_stage_play = Button.new()
	_stage_play.text = "Play"
	_stage_play.pressed.connect(_toggle_stage_play)
	controls.add_child(_stage_play)
	_stage_auto = CheckBox.new()
	_stage_auto.text = "Auto camera"
	_stage_auto.toggled.connect(func(v): _stage_auto_scroll = v)
	controls.add_child(_stage_auto)
	_stage_camera = HSlider.new()
	_stage_camera.min_value = -216
	_stage_camera.max_value = 216
	_stage_camera.value = 0
	_stage_camera.custom_minimum_size.x = 180
	_stage_camera.value_changed.connect(func(v): _set_stage_camera(v))
	controls.add_child(_stage_camera)
	_stage_camera_label = Label.new()
	_stage_camera_label.text = "x 0"
	controls.add_child(_stage_camera_label)
	var right := ScrollContainer.new()
	right.custom_minimum_size.x = 230
	split.add_child(right)
	_stage_info = RichTextLabel.new()
	_stage_info.bbcode_enabled = true
	_stage_info.fit_content = true
	_stage_info.custom_minimum_size.x = 215
	right.add_child(_stage_info)
	return split

func _build_sff_page() -> Control:
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	box.add_child(top)
	var open := Button.new()
	open.text = "Open SFF..."
	open.pressed.connect(_pick_sff)
	top.add_child(open)
	_sff_path = Label.new()
	_sff_path.text = "No SFF loaded"
	_sff_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sff_path.clip_text = true
	_sff_path.add_theme_color_override("font_color", Color("#9fb4d0"))
	top.add_child(_sff_path)
	_sff_filter = LineEdit.new()
	_sff_filter.placeholder_text = "Filter group,number..."
	_sff_filter.custom_minimum_size.x = 180
	_sff_filter.text_changed.connect(func(_t): _populate_sff())
	top.add_child(_sff_filter)
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	_sff_list = ItemList.new()
	_sff_list.custom_minimum_size.x = 230
	_sff_list.item_selected.connect(_on_sff_selected)
	split.add_child(_sff_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_sff_preview = TextureRect.new()
	_sff_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sff_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sff_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sff_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_sff_preview)
	_sff_info = RichTextLabel.new()
	_sff_info.bbcode_enabled = true
	_sff_info.fit_content = true
	_sff_info.custom_minimum_size.y = 70
	right.add_child(_sff_info)
	return box

func _build_snd_page() -> Control:
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	box.add_child(top)
	var open := Button.new()
	open.text = "Open SND..."
	open.pressed.connect(_pick_snd)
	top.add_child(open)
	_snd_path = Label.new()
	_snd_path.text = "No SND loaded"
	_snd_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_snd_path.clip_text = true
	_snd_path.add_theme_color_override("font_color", Color("#9fb4d0"))
	top.add_child(_snd_path)
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	_snd_list = ItemList.new()
	_snd_list.item_activated.connect(_on_snd_activated)
	split.add_child(_snd_list)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 280
	split.add_child(right)
	var play := Button.new()
	play.text = "Play selected"
	play.pressed.connect(_play_selected_snd)
	right.add_child(play)
	_snd_info = RichTextLabel.new()
	_snd_info.bbcode_enabled = true
	_snd_info.fit_content = true
	right.add_child(_snd_info)
	return box

# --------------------------------------------------------------------------
# Public loading API (also used by the resource tree)
# --------------------------------------------------------------------------
func open_char(def_path: String, action: int = -1) -> bool:
	var def = MugenDef.new()
	if not def.load_file(def_path) or not def.is_character():
		status.emit("Not a MUGEN character DEF: " + def_path)
		return false
	var files: Dictionary = def.character_files()
	if not FileAccess.file_exists(String(files.get("sprite", ""))):
		status.emit("Character SFF not found: " + String(files.get("sprite", "")))
		return false
	var sff = SffBank.new()
	if not sff.load_file(String(files["sprite"])):
		status.emit(sff.error_message())
		return false
	var air = AirAnim.new()
	air.load_file(String(files.get("anim", "")))
	var snd = SndBank.new()
	snd.load_file(String(files.get("sound", "")))
	_char_def = def
	_char_sff = sff
	_char_air = air
	_char_snd = snd
	_char_path.text = def_path
	_char_actions.clear()
	for a in air.action_numbers():
		var n := int(a)
		_char_actions.add_item("Action %d  (%d frames)" % [n, air.frame_count(n)])
		_char_actions.set_item_metadata(_char_actions.item_count - 1, n)
	_char_sounds.clear()
	for e in snd.entries:
		var entry: Dictionary = e
		_char_sounds.add_item("%d,%d  %d B" % [int(entry.get("group", 0)), int(entry.get("number", 0)), int(entry.get("size", 0))])
		_char_sounds.set_item_metadata(_char_sounds.item_count - 1, [int(entry.get("group", 0)), int(entry.get("number", 0))])
	_char_info.text = "[b]%s[/b]\n%s\n\nSFF: %d sprites\nAIR: %d actions\nSND: %d sounds\n\nSprite: %s\nAnim: %s\nSound: %s" % [
		def.display_name(), def_path.get_file(), sff.sprite_count(), air.actions.size(), snd.entry_count(),
		String(files.get("sprite", "")).get_file(), String(files.get("anim", "")).get_file(), String(files.get("sound", "")).get_file()]
	var chosen := action
	if chosen < 0 and not air.action_numbers().is_empty():
		chosen = int(air.action_numbers()[0])
	_select_char_action(chosen)
	show_page("char")
	status.emit("MUGEN char loaded: " + def.display_name())
	return true

func open_stage(def_path: String) -> bool:
	var def = MugenDef.new()
	if not def.load_file(def_path) or not def.is_stage():
		status.emit("Not a MUGEN stage DEF: " + def_path)
		return false
	var sff_path := def.stage_sprite_file()
	var sff = SffBank.new()
	if sff_path.is_empty() or not sff.load_file(sff_path):
		status.emit("Stage SFF not found: " + sff_path)
		return false
	var air = AirAnim.new()
	air.load_text(def.raw_text)
	_stage_def = def
	_stage_sff = sff
	_stage_air = air
	_stage_path.text = def_path
	_stage_layers.clear()
	for i in range(def.bg_layers.size()):
		var l: Dictionary = def.bg_layers[i]
		var kind := String(l.get("type", "normal"))
		var ref := String(l.get("spriteno", ""))
		if kind == "anim":
			ref = "action " + String(l.get("actionno", "?"))
		_stage_layers.add_item("%02d  %s  %s  delta %s" % [i, kind, ref, String(l.get("delta", ""))])
	var cam: Dictionary = def.sections.get("Camera", def.sections.get("camera", {}))
	_stage_bound_l = float(String(cam.get("boundleft", "-216")))
	_stage_bound_r = float(String(cam.get("boundright", "216")))
	_stage_camera.min_value = _stage_bound_l
	_stage_camera.max_value = _stage_bound_r
	_stage_camera.set_value_no_signal(0)
	_stage_cam = 0.0
	_stage_time = 0.0
	_stage_preview.set_stage(def, sff, air)
	_stage_preview.set_camera(0, 0)
	_stage_preview.set_time_ticks(0)
	_stage_info.text = "[b]%s[/b]\n%s\n\nLayers: %d\nActions: %d\nSFF: %d sprites\n\nCamera %.0f..%.0f" % [
		def.display_name(), def_path.get_file(), def.bg_layers.size(), air.actions.size(), sff.sprite_count(), _stage_bound_l, _stage_bound_r]
	show_page("stage")
	status.emit("MUGEN stage loaded: " + def.display_name())
	return true

func open_sff(sff_path: String) -> bool:
	var bank = SffBank.new()
	if not bank.load_file(sff_path):
		status.emit(bank.error_message())
		return false
	_sff_bank = bank
	_sff_path.text = sff_path
	_populate_sff()
	show_page("sff")
	status.emit("SFF loaded: %d sprites" % bank.sprite_count())
	return true

func open_snd(snd_path: String) -> bool:
	var bank = SndBank.new()
	if not bank.load_file(snd_path):
		status.emit("Could not read SND: " + snd_path)
		return false
	_snd_bank = bank
	_snd_path.text = snd_path
	_populate_snd()
	show_page("sounds")
	status.emit("SND loaded: %d sounds" % bank.entry_count())
	return true

func current_page() -> String:
	return _current

# --------------------------------------------------------------------------
# Character page callbacks
# --------------------------------------------------------------------------
func _pick_char_def() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.def", "MUGEN character DEF")
	dlg.file_selected.connect(func(p): open_char(p); dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func _pick_stage_def() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.def", "MUGEN stage DEF")
	dlg.file_selected.connect(func(p): open_stage(p); dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func _pick_sff() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.sff", "MUGEN SFF")
	dlg.file_selected.connect(func(p): open_sff(p); dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func _pick_snd() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.snd", "MUGEN SND")
	dlg.file_selected.connect(func(p): open_snd(p); dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func _on_char_action(index: int) -> void:
	if _char_actions.item_count == 0:
		return
	_select_char_action(int(_char_actions.get_item_metadata(index)))

func _select_char_action(action: int) -> void:
	_char_action = action
	if _char_sff != null and _char_air != null:
		_char_preview.set_char(_char_sff, _char_air, action)
	else:
		_char_preview.set_action(action)
	_char_playing = false
	_char_play.text = "Play"
	_char_preview.playing = false
	_char_preview.set_process(false)
	_char_label.text = "Action %d  %d frames  %d ticks" % [action, _char_air.frame_count(action) if _char_air else 0, _char_air.total_ticks(action) if _char_air else 0]
	if not _char_air:
		return
	for i in range(_char_actions.item_count):
		if int(_char_actions.get_item_metadata(i)) == action:
			_char_actions.select(i)
			break

func _toggle_char_play() -> void:
	if _char_air == null:
		return
	_char_playing = not _char_playing
	_char_preview.playing = _char_playing
	_char_preview.set_process(_char_playing)
	_char_play.text = "Pause" if _char_playing else "Play"

func _stop_char() -> void:
	_char_playing = false
	_char_preview.playing = false
	_char_preview.set_process(false)
	_char_preview.set_time_ticks(0)
	_char_play.text = "Play"

func _step_char() -> void:
	if _char_air == null:
		return
	var total: int = _char_air.total_ticks(_char_action)
	_char_preview.set_time_ticks(fmod(_char_preview.time_ticks + 1.0, maxf(1.0, total)))

func _on_char_sound(index: int) -> void:
	if _char_snd == null:
		return
	var meta = _char_sounds.get_item_metadata(index)
	if meta is Array and meta.size() >= 2:
		_play_stream(_char_snd.stream_for(int(meta[0]), int(meta[1])))

func _import_char() -> void:
	if project == null:
		status.emit("Open a SNES/Mega Drive project first.")
		return
	if _char_def == null:
		status.emit("Open a MUGEN char first.")
		return
	var result: Dictionary = MugenImport.import_character(project, _char_def.path, platform, 24)
	if bool(result.get("ok", false)):
		status.emit("Imported MUGEN char: %s (%d actions, %d sprites)" % [String(result.get("slug", "")), int(result.get("actions", 0)), int(result.get("sprites", 0))])
		assets_imported.emit(result)
	else:
		status.emit("MUGEN char import failed: " + String(result.get("error", "unknown")))

func _import_stage() -> void:
	if project == null:
		status.emit("Open a SNES/Mega Drive project first.")
		return
	if _stage_def == null:
		status.emit("Open a MUGEN stage first.")
		return
	var result: Dictionary = MugenImport.import_stage(project, _stage_def.path, platform)
	if bool(result.get("ok", false)):
		status.emit("Imported MUGEN stage: %s (%d layers flattened)" % [String(result.get("slug", "")), int(result.get("layers", 0))])
		assets_imported.emit(result)
	else:
		status.emit("MUGEN stage import failed: " + String(result.get("error", "unknown")))

# --------------------------------------------------------------------------
# Stage page callbacks
# --------------------------------------------------------------------------
func _toggle_stage_play() -> void:
	_stage_auto_scroll = not _stage_auto_scroll
	_stage_auto.set_pressed_no_signal(_stage_auto_scroll)
	_stage_play.text = "Pause" if _stage_auto_scroll else "Play"

func _stage_playing() -> bool:
	return _stage_auto_scroll

func _set_stage_camera(value: float) -> void:
	_stage_cam = value
	_stage_preview.set_camera(_stage_cam, 0)
	_stage_camera_label.text = "x %.0f" % _stage_cam

func _process(delta: float) -> void:
	if _char_air and _char_preview and _char_preview.playing:
		var total: int = _char_air.total_ticks(_char_action)
		if total > 0 and _char_preview.time_ticks >= total and not _char_preview.loop:
			_char_playing = false
			_char_preview.playing = false
			_char_preview.set_process(false)
			_char_play.text = "Play"
		_char_label.text = "Action %d  tick %.0f / %d" % [_char_action, _char_preview.time_ticks, total]
	if _stage_def and _stage_preview:
		if _stage_auto_scroll:
			_stage_time += delta * 60.0
			_stage_cam += delta * 80.0 * _stage_dir
			if _stage_cam >= _stage_bound_r:
				_stage_cam = _stage_bound_r
				_stage_dir = -1.0
			elif _stage_cam <= _stage_bound_l:
				_stage_cam = _stage_bound_l
				_stage_dir = 1.0
			_stage_camera.set_value_no_signal(_stage_cam)
			_stage_camera_label.text = "x %.0f" % _stage_cam
			_stage_preview.set_camera(_stage_cam, 0)
			_stage_preview.set_time_ticks(_stage_time)

# --------------------------------------------------------------------------
# SFF page
# --------------------------------------------------------------------------
func _populate_sff() -> void:
	if _sff_bank == null:
		return
	_sff_list.clear()
	var filter := _sff_filter.text.strip_edges().to_lower() if _sff_filter else ""
	_sff_entries.clear()
	for i in range(_sff_bank.sprite_count()):
		var sp: Dictionary = _sff_bank.sprite_at(i)
		var text := "%d,%d  %dx%d" % [int(sp.get("group", 0)), int(sp.get("number", 0)), int(sp.get("width", 0)), int(sp.get("height", 0))]
		if not filter.is_empty() and not text.to_lower().contains(filter):
			continue
		_sff_entries.append(i)
		_sff_list.add_item(text)
		_sff_list.set_item_metadata(_sff_list.item_count - 1, i)
	if _sff_list.item_count > 0:
		_sff_list.select(0)
		_on_sff_selected(0)

func _on_sff_selected(index: int) -> void:
	if _sff_bank == null or index < 0 or index >= _sff_list.item_count:
		return
	var i := int(_sff_list.get_item_metadata(index))
	var sp: Dictionary = _sff_bank.sprite_at(i)
	var img: Image = _sff_bank.render(i)
	if img:
		_sff_preview.texture = ImageTexture.create_from_image(img)
	_sff_info.text = "[b]Sprite %d,%d[/b]\nindex %d | %dx%d | axis %s | format %s\npixels %d | palette %d" % [
		int(sp.get("group", 0)), int(sp.get("number", 0)), i,
		int(sp.get("width", 0)), int(sp.get("height", 0)), str(sp.get("axis", Vector2i.ZERO)),
		str(sp.get("format", "v1/pcx")), int(sp.get("pixels", PackedByteArray()).size()),
		int(sp.get("palette", PackedColorArray()).size())]

# --------------------------------------------------------------------------
# Sound page
# --------------------------------------------------------------------------
func _populate_snd() -> void:
	if _snd_bank == null:
		return
	_snd_list.clear()
	for e in _snd_bank.entries:
		var entry: Dictionary = e
		_snd_list.add_item("%d,%d  %d B" % [int(entry.get("group", 0)), int(entry.get("number", 0)), int(entry.get("size", 0))])
		_snd_list.set_item_metadata(_snd_list.item_count - 1, [int(entry.get("group", 0)), int(entry.get("number", 0))])

func _on_snd_activated(index: int) -> void:
	_play_snd_index(index)

func _play_selected_snd() -> void:
	if _snd_list.get_selected_items().is_empty():
		return
	_play_snd_index(_snd_list.get_selected_items()[0])

func _play_snd_index(index: int) -> void:
	if _snd_bank == null or index < 0 or index >= _snd_list.item_count:
		return
	var meta = _snd_list.get_item_metadata(index)
	if meta is Array and meta.size() >= 2:
		_play_stream(_snd_bank.stream_for(int(meta[0]), int(meta[1])))

func _play_stream(stream: AudioStreamWAV) -> void:
	if stream == null:
		status.emit("Sound has no playable WAV payload.")
		return
	_snd_player.stream = stream
	_snd_player.play()
	status.emit("Playing MUGEN sound @ %d Hz" % stream.mix_rate)
