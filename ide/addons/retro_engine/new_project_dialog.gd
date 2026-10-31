@tool
extends Window
## Creates a new real PVSnesLib / SGDK starter project.

signal project_created(project: RetroProject)
signal rom_built(path: String)
signal status(text: String)
signal sdk_download_requested
signal sdk_configure_requested

const Templates = preload("res://addons/retro_engine/project_templates.gd")
const GameBuild = preload("res://addons/retro_engine/game_build.gd")
const MugenImport = preload("res://addons/retro_engine/mugen_import.gd")
const WindowControls = preload("res://addons/retro_engine/window_controls.gd")
const I18n = preload("res://addons/retro_engine/i18n.gd")

var _platform: OptionButton
var _name: LineEdit
var _location: LineEdit
var _sdk_label: Label
var _log: RichTextLabel
var _create_button: Button
var _build_button: Button
var _project: RetroProject
var _builder: RetroBuilder
var _building := false
var _mugen_char: LineEdit
var _mugen_stage: LineEdit

func _ready() -> void:
	title = I18n.t("new_project.title")
	size = Vector2i(820, 660)
	unresizable = false
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var heading := Label.new()
	heading.text = I18n.t("new_project.heading")
	heading.add_theme_font_size_override("font_size", 15)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	WindowControls.add_controls(head, self, true)

	var form := GridContainer.new()
	form.columns = 2
	root.add_child(form)
	form.add_child(_label(I18n.t("new_project.platform")))
	_platform = OptionButton.new()
	_platform.add_item(I18n.t("new_project.platform_snes"), 0)
	_platform.add_item(I18n.t("new_project.platform_md"), 1)
	_platform.item_selected.connect(_on_platform_changed)
	form.add_child(_platform)
	form.add_child(_label(I18n.t("new_project.name")))
	_name = LineEdit.new()
	_name.text = "my_snes_game"
	form.add_child(_name)
	form.add_child(_label(I18n.t("new_project.destination")))
	var location_row := HBoxContainer.new()
	form.add_child(location_row)
	_location = LineEdit.new()
	_location.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	location_row.add_child(_location)
	var browse := Button.new()
	browse.text = I18n.t("common.browse")
	browse.pressed.connect(_browse)
	location_row.add_child(browse)
	form.add_child(_label("MUGEN char DEF (optional)"))
	var char_row := HBoxContainer.new()
	form.add_child(char_row)
	_mugen_char = LineEdit.new()
	_mugen_char.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mugen_char.placeholder_text = "chars/Kyo/Kyo.def"
	char_row.add_child(_mugen_char)
	var char_browse := Button.new()
	char_browse.text = I18n.t("common.browse")
	char_browse.pressed.connect(func(): _browse_mugen(_mugen_char, "*.def", "MUGEN character DEF"))
	char_row.add_child(char_browse)
	form.add_child(_label("MUGEN stage DEF (optional)"))
	var stage_row := HBoxContainer.new()
	form.add_child(stage_row)
	_mugen_stage = LineEdit.new()
	_mugen_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mugen_stage.placeholder_text = "stages/Esaka.def"
	stage_row.add_child(_mugen_stage)
	var stage_browse := Button.new()
	stage_browse.text = I18n.t("common.browse")
	stage_browse.pressed.connect(func(): _browse_mugen(_mugen_stage, "*.def", "MUGEN stage DEF"))
	stage_row.add_child(stage_browse)

	var note := Label.new()
	note.text = I18n.t("new_project.note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("#9fb4d0"))
	root.add_child(note)

	var sdk_row := HBoxContainer.new()
	root.add_child(sdk_row)
	_sdk_label = Label.new()
	_sdk_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sdk_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sdk_row.add_child(_sdk_label)
	var refresh := Button.new()
	refresh.text = I18n.t("new_project.refresh_sdk")
	refresh.pressed.connect(_refresh_sdk)
	sdk_row.add_child(refresh)
	var download := Button.new()
	download.text = I18n.t("top.download_sdks")
	download.pressed.connect(func(): sdk_download_requested.emit())
	sdk_row.add_child(download)
	var configure := Button.new()
	configure.text = I18n.t("top.sdk")
	configure.pressed.connect(func(): sdk_configure_requested.emit())
	sdk_row.add_child(configure)

	var actions := HBoxContainer.new()
	root.add_child(actions)
	_create_button = Button.new()
	_create_button.text = I18n.t("new_project.create")
	_create_button.pressed.connect(func(): _create(false))
	actions.add_child(_create_button)
	_build_button = Button.new()
	_build_button.text = I18n.t("new_project.create_build")
	_build_button.pressed.connect(func(): _create(true))
	actions.add_child(_build_button)
	var close := Button.new()
	close.text = I18n.t("common.close")
	close.pressed.connect(func(): hide())
	actions.add_child(close)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.selection_enabled = true
	root.add_child(_log)

	_builder = RetroBuilder.new()
	add_child(_builder)
	_builder.log_line.connect(_on_build_log, CONNECT_DEFERRED)
	_builder.build_started.connect(func(cmd): _log.append_text("[color=#7fd1ff]$ %s[/color]\n" % cmd), CONNECT_DEFERRED)
	_builder.build_finished.connect(_on_build_finished, CONNECT_DEFERRED)
	close_requested.connect(func(): hide())
	_refresh_sdk()

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func open(default_dir: String) -> void:
	if not default_dir.is_empty():
		_location.text = default_dir
	_log.clear()
	_project = null
	_refresh_sdk()
	if _platform.selected == 0:
		_name.text = "my_snes_game"
	else:
		_name.text = "my_megadrive_game"
	popup_centered(Vector2i(820, 660))

func _selected_target() -> String:
	return "snes" if _platform.selected == 0 else "megadrive"

func _on_platform_changed(_index: int) -> void:
	var current := _name.text.strip_edges()
	if current.is_empty() or current in ["my_snes_game", "my_megadrive_game"]:
		_name.text = "my_snes_game" if _platform.selected == 0 else "my_megadrive_game"
	_refresh_sdk()

func _refresh_sdk() -> void:
	if _sdk_label == null:
		return
	var target := _selected_target()
	var sdk: Dictionary = RetroSDK.get_sdk(target)
	var ready := false
	if target == "snes":
		ready = bool(sdk.get("ready", false))
	else:
		ready = bool(Dictionary(sdk.get("linux", {})).get("available", false))
	if ready:
		_sdk_label.text = I18n.t("new_project.sdk_ready", {
			"sdk": "PVSnesLib" if target == "snes" else "SGDK",
			"version": String(sdk.get("version", "?")),
			"path": String(sdk.get("path", "")),
		})
		_sdk_label.add_theme_color_override("font_color", Color("#6ee7a8"))
	else:
		_sdk_label.text = I18n.t("new_project.sdk_not_ready", {"sdk": "PVSnesLib" if target == "snes" else "SGDK"})
		_sdk_label.add_theme_color_override("font_color", Color("#ffd45e"))

func _browse_mugen(target: LineEdit, filter: String, title: String) -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.title = title
	dlg.add_filter(filter, title)
	if target != null and not target.text.strip_edges().is_empty():
		dlg.current_dir = target.text.strip_edges().get_base_dir()
	dlg.file_selected.connect(func(path): target.text = path; dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func _browse() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.title = I18n.t("new_project.browse_title")
	dlg.current_dir = _location.text
	dlg.dir_selected.connect(func(path):
		_location.text = path
		dlg.queue_free()
	)
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _create(build_after: bool) -> void:
	if _building:
		return
	var target := _selected_target()
	var name := Templates.slug(_name.text)
	if name.is_empty():
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("new_project.enter_name"))
		return
	var base := _location.text.strip_edges()
	if base.is_empty():
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("new_project.choose_folder"))
		return
	_create_button.disabled = true
	_build_button.disabled = true
	_log.append_text("[color=#7fd1ff]%s[/color]\n" % I18n.t("new_project.creating", {"target": I18n.platform_label(target), "name": name}))
	var result: Dictionary = Templates.create(target, base, name, true)
	if not bool(result.get("ok", false)):
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % String(result.get("error", I18n.t("new_project.creation_failed"))))
		_create_button.disabled = false
		_build_button.disabled = false
		status.emit(I18n.t("new_project.creation_failed"))
		return
	_project = result.get("project")
	var dir := String(result.get("directory", ""))
	_log.append_text("[color=#6ee7a8]%s[/color]\n" % I18n.t("new_project.created", {"path": dir}))
	if _project != null:
		var char_def := _mugen_char.text.strip_edges()
		if not char_def.is_empty():
			var char_result: Dictionary = MugenImport.import_character(_project, char_def, target, 24)
			if bool(char_result.get("ok", false)):
				_log.append_text("[color=#6ee7a8]MUGEN char: %s (%d actions, %d sprites)[/color]\n" % [String(char_result.get("slug", "")), int(char_result.get("actions", 0)), int(char_result.get("sprites", 0))])
			else:
				_log.append_text("[color=#ffd45e]MUGEN char: %s[/color]\n" % String(char_result.get("error", "failed")))
		var stage_def := _mugen_stage.text.strip_edges()
		if not stage_def.is_empty():
			var stage_result: Dictionary = MugenImport.import_stage(_project, stage_def, target)
			if bool(stage_result.get("ok", false)):
				_log.append_text("[color=#6ee7a8]MUGEN stage: %s (%d layers)[/color]\n" % [String(stage_result.get("slug", "")), int(stage_result.get("layers", 0))])
			else:
				_log.append_text("[color=#ffd45e]MUGEN stage: %s[/color]\n" % String(stage_result.get("error", "failed")))
	_log.append_text("%s\n" % I18n.t("new_project.target_animated", {
		"target": I18n.platform_label(target),
		"animated": I18n.t("common.yes") if bool(result.get("animated", false)) else I18n.t("common.no"),
	}))
	_log.append_text("%s\n" % I18n.t("new_project.editable"))
	status.emit(I18n.t("new_project.project_ready", {"path": dir}))
	if _project:
		project_created.emit(_project)
	if not build_after:
		_create_button.disabled = false
		_build_button.disabled = false
		return
	if _project == null:
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("new_project.no_project_object"))
		_create_button.disabled = false
		_build_button.disabled = false
		return
	_building = true
	_log.append_text("[color=#7fd1ff]%s[/color]\n" % I18n.t("new_project.building", {"name": _project.get_name()}))
	var err := _builder.build(_project, "", false, false)
	if err != OK:
		_building = false
		_create_button.disabled = false
		_build_button.disabled = false
		if err == ERR_UNCONFIGURED:
			_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("new_project.sdk_not_ready_build"))
		else:
			_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("new_project.build_could_not_start", {"err": err}))
		status.emit(I18n.t("new_project.build_could_not_start_status"))

func _on_build_log(line: String, level: int) -> void:
	var color := "#c8d4e6"
	if level == 1:
		color = "#ffd45e"
	elif level == 2:
		color = "#ff7a7a"
	_log.append_text("[color=%s]%s[/color]\n" % [color, line.replace("[", "[lb]")])

func _on_build_finished(success: bool, result: Dictionary) -> void:
	_building = false
	_create_button.disabled = false
	_build_button.disabled = false
	var rom := String(result.get("rom_path", ""))
	if success and not rom.is_empty() and _project != null:
		var finalize: Dictionary = GameBuild.finalize_rom(_project, rom)
		if not bool(finalize.get("ok", false)):
			_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("game_build.rom_finalize_failed", {
				"error": String(finalize.get("error", "unknown"))}))
	if success and not rom.is_empty():
		if _project:
			_project.set_rom_path(rom)
			_project.save()
		_log.append_text("[color=#6ee7a8]%s[/color]\n" % I18n.t("new_project.rom_built", {"rom": rom}))
		rom_built.emit(rom)
		status.emit(I18n.t("new_project.rom_built", {"rom": rom}))
	else:
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("new_project.build_failed"))
		status.emit(I18n.t("new_project.build_failed_status"))
