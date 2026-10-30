@tool
extends Window
## Build options for generated native / cross-platform games.

signal status(text: String)
signal rom_built(path: String)

const GameBuild = preload("res://addons/retro_engine/game_build.gd")
const WindowControls = preload("res://addons/retro_engine/window_controls.gd")
const I18n = preload("res://addons/retro_engine/i18n.gd")
const CONFIG_PATH := "user://retro_engine.cfg"

var project: RetroProject
var platform: String = "snes"
var emulator_id: String = ""
var builder: RetroBuilder
var _project: RetroProject = null
var _rom: String = ""
var _mode: OptionButton
var _name: LineEdit
var _splash: CheckBox
var _log: RichTextLabel
var _generate_button: Button
var _build_button: Button
var _run_button: Button
var _warning: Label
var _mode_error := ""
var _sdk_ready := false

func _ready() -> void:
	title = I18n.t("game_build.title")
	size = Vector2i(760, 560)
	unresizable = false
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 5)
	add_child(root)
	var head_row := HBoxContainer.new()
	root.add_child(head_row)
	var heading := Label.new()
	heading.text = I18n.t("game_build.heading")
	heading.add_theme_font_size_override("font_size", 14)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(heading)
	WindowControls.add_controls(head_row, self, true)
	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_label(I18n.t("game_build.build")))
	_mode = OptionButton.new()
	_mode.add_item(I18n.t("game_build.mode_native_snes"), 0)
	_mode.set_item_metadata(0, "native_snes")
	_mode.add_item(I18n.t("game_build.mode_native_md"), 1)
	_mode.set_item_metadata(1, "native_megadrive")
	_mode.add_item(I18n.t("game_build.mode_snes_md"), 2)
	_mode.set_item_metadata(2, "snes_megadrive")
	_mode.add_item(I18n.t("game_build.mode_md_snes"), 3)
	_mode.set_item_metadata(3, "megadrive_snes")
	_mode.custom_minimum_size.x = 280
	_mode.item_selected.connect(func(_index): _refresh_warnings())
	row.add_child(_mode)
	row.add_child(_label(I18n.t("game_build.name")))
	_name = LineEdit.new()
	_name.text = "retro_native_demo"
	_name.custom_minimum_size.x = 180
	row.add_child(_name)
	_splash = CheckBox.new()
	_splash.text = I18n.t("game_build.splash")
	_splash.button_pressed = true
	_splash.tooltip_text = I18n.t("game_build.splash_tip")
	row.add_child(_splash)
	var actions := HBoxContainer.new()
	root.add_child(actions)
	_generate_button = Button.new()
	_generate_button.text = I18n.t("game_build.generate")
	_generate_button.pressed.connect(_generate)
	actions.add_child(_generate_button)
	_build_button = Button.new()
	_build_button.text = I18n.t("game_build.generate_build")
	_build_button.pressed.connect(_generate_and_build)
	actions.add_child(_build_button)
	_run_button = Button.new()
	_run_button.text = I18n.t("game_build.run")
	_run_button.disabled = true
	_run_button.pressed.connect(_run)
	actions.add_child(_run_button)
	var close := Button.new()
	close.text = I18n.t("game_build.close")
	close.pressed.connect(hide)
	actions.add_child(close)
	_warning = Label.new()
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.add_theme_color_override("font_color", Color("#ffd45e"))
	_warning.visible = false
	root.add_child(_warning)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.selection_enabled = true
	root.add_child(_log)
	builder = RetroBuilder.new()
	add_child(builder)
	builder.log_line.connect(_on_log, CONNECT_DEFERRED)
	builder.build_finished.connect(_on_finished, CONNECT_DEFERRED)
	builder.build_started.connect(func(cmd): _log.append_text("[color=#7fd1ff]$ %s[/color]\n" % cmd), CONNECT_DEFERRED)
	close_requested.connect(func(): hide())
	_load_saved_options()

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func open(p_project: RetroProject, p_platform: String, p_emulator: String) -> void:
	project = p_project
	platform = p_platform
	emulator_id = p_emulator
	var base := "retro_native_demo" if project == null else _slug(project.get_name())
	_name.text = base
	_log.clear()
	_log.append_text("%s\n%s\n\n" % [
		I18n.t("game_build.source_project", {"project": I18n.t("common.none") if project == null else project.get_name()}),
		I18n.t("game_build.platform", {"platform": I18n.platform_label(platform)})])
	_refresh_warnings()
	popup_centered(Vector2i(760, 560))

func _load_saved_options() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	var saved_mode := String(cfg.get_value("game_build", "mode", "native_snes"))
	for i in range(_mode.item_count):
		if String(_mode.get_item_metadata(i)) == saved_mode:
			_mode.select(i)
			break
	_splash.button_pressed = bool(cfg.get_value("game_build", "splash", true))

func _save_options() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("game_build", "mode", _selected_mode())
	cfg.set_value("game_build", "splash", _splash.button_pressed)
	cfg.save(CONFIG_PATH)

func _slug(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	return out.strip_edges().trim_prefix("_").trim_suffix("_") if not out.is_empty() else "retro_native"

func _selected_mode() -> String:
	return String(_mode.get_item_metadata(_mode.selected))

func _refresh_warnings() -> void:
	if _warning == null:
		return
	var target := GameBuild.target_for_mode(_selected_mode())
	var errors: Array = []
	var warnings: Array = []
	if project == null:
		errors.append(I18n.t("game_build.no_source_project"))
	else:
		var source_platform := project.get_platform()
		if _selected_mode() == "snes_megadrive" and source_platform != "snes":
			errors.append(I18n.t("game_build.mode_requires_snes"))
		elif _selected_mode() == "megadrive_snes" and source_platform != "megadrive":
			errors.append(I18n.t("game_build.mode_requires_md"))
		if platform != source_platform:
			warnings.append(I18n.t("game_build.platform_mismatch", {
				"selected": I18n.platform_label(platform),
				"project": I18n.platform_label(source_platform),
			}))
	var ready := false
	if target == "snes":
		var sdk: Dictionary = RetroSDK.get_sdk("snes")
		ready = bool(sdk.get("ready", false))
		if not ready:
			warnings.append(I18n.t("game_build.sdk_snes_not_ready"))
	elif target == "megadrive":
		var sdk: Dictionary = RetroSDK.get_sdk("megadrive")
		ready = bool(Dictionary(sdk.get("linux", {})).get("available", false))
		if not ready:
			warnings.append(I18n.t("game_build.sdk_md_not_ready"))
	else:
		errors.append(I18n.t("game_build.unknown_mode", {"mode": _selected_mode()}))
	_sdk_ready = ready
	_mode_error = String(errors[0]) if not errors.is_empty() else ""
	var text := ""
	for error in errors:
		text += I18n.t("game_build.error_prefix", {"text": String(error)}) + "\n"
	for warning in warnings:
		text += I18n.t("game_build.warning_prefix", {"text": String(warning)}) + "\n"
	_warning.text = text.strip_edges()
	_warning.visible = not text.strip_edges().is_empty()

func _generate() -> Dictionary:
	_refresh_warnings()
	if not _mode_error.is_empty():
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % _mode_error)
		status.emit(I18n.t("game_build.mode_incoherent_status"))
		return {}
	if project == null:
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("game_build.no_project"))
		return {}
	var name := _slug(_name.text.strip_edges())
	if name.is_empty():
		name = "retro_native"
	_save_options()
	var out_root := project.resolve("builds")
	var result: Dictionary = GameBuild.generate(_selected_mode(), project, out_root, name, _splash.button_pressed)
	if not bool(result.get("ok", false)):
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("game_build.generation_failed", {"error": String(result.get("error", "unknown"))}))
		status.emit(I18n.t("game_build.generation_failed_status"))
		return {}
	_project = result.get("project")
	_rom = String(result.get("rom", ""))
	_build_button.disabled = false
	_run_button.disabled = true
	_log.append_text("[color=#6ee7a8]%s[/color]\n" % I18n.t("game_build.generated", {"path": String(result.get("directory", ""))}))
	_log.append_text("%s\n" % I18n.t("game_build.target_splash", {
		"target": I18n.platform_label(String(result.get("target", ""))),
		"splash": I18n.t("common.yes") if _splash.button_pressed else I18n.t("common.no"),
	}))
	var profile: Dictionary = result.get("profile", {})
	if not profile.is_empty():
		_log.append_text("%s\n" % I18n.t("game_build.export_profile", {
			"id": String(profile.get("profile_id", "")),
			"version": int(profile.get("profile_version", 0)),
			"path": String(profile.get("path", "")),
		}))
	_log.append_text("%s\n" % I18n.t("game_build.rom_after", {"rom": _rom}))
	var port: Dictionary = result.get("port", {})
	if not port.is_empty():
		_log.append_text("%s\n" % I18n.t("game_build.native_port", {"path": String(port.get("directory", ""))}))
	_log.append_text("\n")
	status.emit(I18n.t("game_build.generated_status", {"target": I18n.platform_label(String(result.get("target", "")))}))
	return result

func _generate_and_build() -> void:
	var result := _generate()
	if result.is_empty() or _project == null:
		return
	_refresh_warnings()
	if not _sdk_ready:
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("game_build.sdk_blocked"))
		status.emit(I18n.t("game_build.sdk_blocked_status"))
		return
	if builder.is_building():
		_log.append_text("[color=#ffd45e]%s[/color]\n" % I18n.t("game_build.build_already"))
		return
	_build_button.disabled = true
	_generate_button.disabled = true
	_log.append_text("[color=#7fd1ff]%s[/color]\n" % I18n.t("game_build.build_started", {"name": _project.get_name()}))
	var err := builder.build(_project, "", false, false)
	if err != OK:
		if err == ERR_UNCONFIGURED:
			_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("game_build.sdk_not_ready"))
		else:
			_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("game_build.build_could_not_start", {"err": err}))
		_build_button.disabled = false
		_generate_button.disabled = false

func _run() -> void:
	if _rom.is_empty() or not FileAccess.file_exists(_rom):
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("game_build.launch_failed"))
		return
	var result: Dictionary = RetroEmulator.launch(_rom, emulator_id)
	if bool(result.get("ok", false)):
		_log.append_text("[color=#6ee7a8]%s[/color]\n" % I18n.t("game_build.launched", {"rom": _rom}))
	else:
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % String(result.get("error", I18n.t("game_build.launch_failed"))))

func _on_log(line: String, level: int) -> void:
	var color := "#c8d4e6"
	if level == 1: color = "#ffd45e"
	elif level == 2: color = "#ff7a7a"
	_log.append_text("[color=%s]%s[/color]\n" % [color, line.replace("[", "[lb]")])

func _on_finished(success: bool, result: Dictionary) -> void:
	_build_button.disabled = false
	_generate_button.disabled = false
	var rom := String(result.get("rom_path", ""))
	if not rom.is_empty():
		_rom = rom
		_run_button.disabled = false
		rom_built.emit(rom)
	if success:
		_log.append_text("[color=#6ee7a8]%s[/color]\n" % I18n.t("game_build.rom_built", {"rom": rom}))
		status.emit(I18n.t("game_build.build_succeeded"))
	else:
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("game_build.build_failed"))
		status.emit(I18n.t("game_build.build_failed_status"))
