@tool
extends VBoxContainer
## Build / run / debug panel backed by the real SDK toolchains.

signal status(text: String)
signal rom_built(path: String)
signal open_error_requested(file: String, line: int, column: int)
signal platform_fix_requested(platform: String)

const GameBuildDialog = preload("res://addons/retro_engine/game_build_dialog.gd")
const GameBuild = preload("res://addons/retro_engine/game_build.gd")
const ProjectChecks = preload("res://addons/retro_engine/project_checks.gd")
const I18n = preload("res://addons/retro_engine/i18n.gd")

var project: RetroProject
var platform: String = "snes"
var emulator_id: String = ""
var builder: RetroBuilder
var _log: RichTextLabel
var _errors: ItemList
var _stats: Label
var _buttons: HBoxContainer
var _build_button: Button
var _clean_button: Button
var _run_button: Button
var _debug_button: Button
var _cancel_button: Button
var _fix_platform: Button
var _coherence: RichTextLabel
var _coherence_row: HBoxContainer
var _rom_path: String = ""

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_buttons = HBoxContainer.new()
	add_child(_buttons)
	_build_button = Button.new()
	_build_button.text = I18n.t("build.build_snes")
	_build_button.pressed.connect(func(): start_build(false, false))
	_buttons.add_child(_build_button)
	var rebuild := Button.new()
	rebuild.text = I18n.t("build.rebuild")
	rebuild.pressed.connect(func(): start_build(true, false))
	_buttons.add_child(rebuild)
	var game_build := Button.new()
	game_build.text = I18n.t("build.game_build")
	game_build.tooltip_text = I18n.t("build.game_build_tip")
	game_build.pressed.connect(_open_game_build)
	_buttons.add_child(game_build)
	_clean_button = Button.new()
	_clean_button.text = I18n.t("build.clean")
	_clean_button.pressed.connect(clean)
	_buttons.add_child(_clean_button)
	_debug_button = Button.new()
	_debug_button.text = I18n.t("build.debug")
	_debug_button.pressed.connect(func(): start_build(false, true))
	_buttons.add_child(_debug_button)
	var attach_button := Button.new()
	attach_button.text = I18n.t("build.attach")
	attach_button.tooltip_text = I18n.t("build.attach_tip")
	attach_button.pressed.connect(debug_current)
	_buttons.add_child(attach_button)
	_run_button = Button.new()
	_run_button.text = I18n.t("build.run")
	_run_button.pressed.connect(run_current)
	_buttons.add_child(_run_button)
	_cancel_button = Button.new()
	_cancel_button.text = I18n.t("common.cancel")
	_cancel_button.disabled = true
	_cancel_button.pressed.connect(func(): if builder: builder.cancel())
	_buttons.add_child(_cancel_button)

	_stats = Label.new()
	_stats.add_theme_color_override("font_color", Color("#9fb4d0"))
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_stats)
	_coherence_row = HBoxContainer.new()
	_coherence_row.add_theme_constant_override("separation", 6)
	_coherence_row.visible = false
	add_child(_coherence_row)
	_coherence = RichTextLabel.new()
	_coherence.bbcode_enabled = true
	_coherence.fit_content = true
	_coherence.selection_enabled = true
	_coherence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coherence_row.add_child(_coherence)
	_fix_platform = Button.new()
	_fix_platform.tooltip_text = I18n.t("build.use_platform_tip")
	_fix_platform.visible = false
	_fix_platform.pressed.connect(_on_fix_platform)
	_coherence_row.add_child(_fix_platform)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_log)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 380
	split.add_child(side)
	var elabel := Label.new()
	elabel.text = I18n.t("build.diagnostics")
	side.add_child(elabel)
	_errors = ItemList.new()
	_errors.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_errors.item_activated.connect(_on_error_activated)
	side.add_child(_errors)
	var note := Label.new()
	note.text = I18n.t("build.note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("#8b98ad"))
	side.add_child(note)

	builder = RetroBuilder.new()
	builder.name = "RetroBuilder"
	add_child(builder)
	builder.build_started.connect(_on_build_started, CONNECT_DEFERRED)
	builder.log_line.connect(_on_log_line, CONNECT_DEFERRED)
	builder.build_finished.connect(_on_build_finished, CONNECT_DEFERRED)
	if OS.has_environment("RETRO_GAME_BUILD_DEMO") and Engine.is_editor_hint():
		call_deferred("_auto_game_build_demo")

func _auto_game_build_demo() -> void:
	await get_tree().create_timer(3.0).timeout
	if project:
		_open_game_build()

func _open_game_build() -> void:
	if project == null:
		status.emit(I18n.t("build.import_first"))
		return
	var dlg = GameBuildDialog.new()
	add_child(dlg)
	dlg.status.connect(func(t): status.emit(t))
	dlg.rom_built.connect(func(path): rom_built.emit(path))
	dlg.open(project, platform, emulator_id)

func set_platform(p: String) -> void:
	platform = p
	_build_button.text = I18n.t("build.build_snes") if p == "snes" else I18n.t("build.build_md")
	_refresh_coherence()

func set_project(p: RetroProject) -> void:
	project = p
	if project:
		_rom_path = project.get_rom_path()
		_stats.text = "%s\n%s\n%s\n%s" % [
			I18n.t("build.project", {"name": project.get_name()}),
			I18n.t("build.sdk", {"sdk": project.get_sdk_version()}),
			I18n.t("build.build", {"system": project.get_build_system(), "file": project.get_build_file()}),
			I18n.t("build.rom", {"rom": _rom_path})]
	else:
		_stats.text = I18n.t("build.no_project")
	_refresh_coherence()

func _refresh_coherence() -> void:
	if _coherence == null:
		return
	if project == null:
		_coherence.text = ""
		_coherence_row.visible = false
		_fix_platform.visible = false
		return
	var check: Dictionary = ProjectChecks.inspect(project, platform, project.get_mode())
	var text := ""
	for error in check.get("errors", []):
		text += "[color=#ff7a7a]%s[/color]\n" % I18n.t("build.error", {"text": ProjectChecks.text(error)})
	for warning in check.get("warnings", []):
		text += "[color=#ffd45e]%s[/color]\n" % I18n.t("build.warning", {"text": ProjectChecks.text(warning)})
	_coherence.text = text
	_coherence_row.visible = not text.is_empty()
	_coherence.visible = not text.is_empty()
	_fix_platform.visible = project != null and project.get_platform() != platform
	if project != null:
		_fix_platform.text = I18n.t("build.use_platform", {"platform": I18n.platform_label(project.get_platform())})

func _on_fix_platform() -> void:
	if project != null:
		platform_fix_requested.emit(project.get_platform())

func refresh_coherence() -> void:
	_refresh_coherence()

func set_emulator(id: String) -> void:
	emulator_id = id

func _sdk_problem() -> String:
	if project == null:
		return ""
	var system := project.get_build_system()
	var generated := bool(project.get_metadata().get("generated_game", false))
	if system not in ["pvsneslib", "sgdk"] and not (generated and system == "make"):
		return ""
	var platform := project.get_platform()
	var path := project.get_sdk_path()
	if path.is_empty():
		path = String(RetroSDK.get_sdk(platform).get("path", ""))
	if path.is_empty():
		return I18n.t("build.no_sdk", {"sdk": "PVSnesLib" if platform == "snes" else "SGDK"})
	var probe: Dictionary = RetroSDK.probe_snes(path) if platform == "snes" else RetroSDK.probe_megadrive(path)
	if not bool(probe.get("found", false)):
		return I18n.t("build.sdk_not_recognized", {"path": path})
	if not bool(probe.get("ready", false)):
		if platform == "megadrive":
			return I18n.t("build.sdk_md_no_gcc")
		return I18n.t("build.sdk_snes_incomplete")
	return ""

func start_build(clean_first: bool, debug: bool) -> void:
	if project == null:
		status.emit(I18n.t("build.import_first"))
		return
	var check: Dictionary = ProjectChecks.inspect(project, platform, project.get_mode())
	_refresh_coherence()
	if not bool(check.get("ok", false)):
		_log.clear()
		for error in check.get("errors", []):
			_append_log("[color=#ff7a7a]%s[/color]" % I18n.t("build.error", {"text": ProjectChecks.text(error)}))
		var errors: Array = check.get("errors", [])
		var reason: String = ProjectChecks.text(errors[0]) if not errors.is_empty() else I18n.t("build.coherence_failed")
		status.emit(I18n.t("build.build_blocked", {"reason": reason}))
		return
	var sdk_problem := _sdk_problem()
	if not sdk_problem.is_empty():
		_log.clear()
		_append_log("[color=#ff7a7a]%s[/color]" % sdk_problem)
		status.emit(sdk_problem)
		return
	if builder.is_building():
		return
	_log.clear()
	_errors.clear()
	for warning in check.get("warnings", []):
		_append_log("[color=#ffd45e]%s[/color]" % I18n.t("build.warning", {"text": ProjectChecks.text(warning)}))
	_stats.text = I18n.t("build.building", {"name": project.get_name()})
	_cancel_button.disabled = false
	_build_button.disabled = true
	_clean_button.disabled = true
	_debug_button.disabled = true
	var target := project.get_build_target()
	var err: int = builder.build(project, target, clean_first, debug)
	if err != OK:
		_append_log("[color=#ff7a7a]%s[/color]" % I18n.t("build.could_not_start", {"err": err}))
		status.emit(I18n.t("build.could_not_start", {"err": err}))

func clean() -> void:
	if project == null or builder == null:
		return
	var check: Dictionary = ProjectChecks.inspect(project, platform, project.get_mode())
	_refresh_coherence()
	if not bool(check.get("ok", false)):
		for error in check.get("errors", []):
			_append_log("[color=#ff7a7a]%s[/color]" % I18n.t("build.error", {"text": ProjectChecks.text(error)}))
		var errors: Array = check.get("errors", [])
		var reason: String = ProjectChecks.text(errors[0]) if not errors.is_empty() else I18n.t("build.coherence_failed")
		status.emit(I18n.t("build.clean_blocked", {"reason": reason}))
		return
	var sdk_problem := _sdk_problem()
	if not sdk_problem.is_empty():
		_append_log("[color=#ff7a7a]%s[/color]" % sdk_problem)
		status.emit(sdk_problem)
		return
	_log.clear()
	_errors.clear()
	_cancel_button.disabled = false
	var err: int = builder.build(project, "__clean_only__", false, false)
	if err != OK:
		_append_log("[color=#ff7a7a]%s[/color]" % I18n.t("build.clean_could_not_start", {"err": err}))

func run_current() -> void:
	if project == null:
		status.emit(I18n.t("build.import_first"))
		return
	var rom := project.get_rom_path()
	if rom.is_empty() or not FileAccess.file_exists(rom):
		rom = _rom_path
	if rom.is_empty() or not FileAccess.file_exists(rom):
		status.emit(I18n.t("build.no_rom"))
		return
	var r: Dictionary = RetroEmulator.launch(rom, emulator_id)
	if bool(r.get("ok", false)):
		status.emit(I18n.t("build.launching", {"rom": rom.get_file(), "emulator": String(r.get("emulator", "emulator"))}))
		_append_log("[color=#6ee7a8]%s[/color]" % I18n.t("build.launched", {"rom": rom, "emulator": String(r.get("emulator", ""))}))
	else:
		_append_log("[color=#ff7a7a]%s[/color]" % String(r.get("error", I18n.t("build.launch_failed"))))
		status.emit(String(r.get("error", I18n.t("build.launch_failed"))))

func debug_current() -> void:
	if project == null:
		return
	var rom := project.get_rom_path()
	if rom.is_empty():
		rom = _rom_path
	var r: Dictionary = RetroEmulator.launch_debug(rom, emulator_id)
	if bool(r.get("ok", false)):
		status.emit(I18n.t("build.debug_launched", {"rom": rom.get_file()}))
	else:
		_append_log("[color=#ff7a7a]%s[/color]" % String(r.get("error", I18n.t("build.debug_failed"))))
		status.emit(String(r.get("error", I18n.t("build.debug_failed"))))

func _on_build_started(command: String) -> void:
	_append_log("[color=#7fd1ff]$ %s[/color]" % command)

func _on_log_line(line: String, level: int) -> void:
	var color := "#c8d4e6"
	if level == 1:
		color = "#ffd45e"
	elif level == 2:
		color = "#ff7a7a"
	_append_log("[color=%s]%s[/color]" % [color, line.replace("[", "[lb]")])

func _append_log(text: String) -> void:
	if _log:
		_log.append_text(text + "\n")

func _on_build_finished(success: bool, result: Dictionary) -> void:
	_cancel_button.disabled = true
	_build_button.disabled = false
	_clean_button.disabled = false
	_debug_button.disabled = false
	var rom := String(result.get("rom_path", ""))
	if success and not rom.is_empty() and project != null:
		var finalize: Dictionary = GameBuild.finalize_rom(project, rom)
		if not bool(finalize.get("ok", false)):
			_append_log("[color=#ff7a7a]%s[/color]" % I18n.t("game_build.rom_finalize_failed", {
				"error": String(finalize.get("error", "unknown"))}))
		elif bool(finalize.get("trimmed", false)):
			_append_log("[color=#6ee7a8]%s[/color]" % I18n.t("game_build.rom_trimmed", {
				"size": String(result.get("rom_size_human", ""))}))
	if not rom.is_empty():
		_rom_path = rom
		if project:
			project.set_rom_path(rom)
			project.save()
		rom_built.emit(rom)
	_errors.clear()
	for e in result.get("errors", []):
		var d: Dictionary = e
		var text := "%s:%d:%d  %s" % [String(d.get("file", "")).get_file(), int(d.get("line", 0)), int(d.get("column", 0)), String(d.get("message", ""))]
		_errors.add_item(text)
		_errors.set_item_metadata(_errors.item_count - 1, d)
	var stats := I18n.t("build.result", {
		"result": I18n.t("build.success") if success else I18n.t("build.failed"),
		"exit": int(result.get("exit_code", -1)),
		"size": String(result.get("rom_size_human", "no ROM")),
		"errors": int(result.get("error_count", 0)),
		"warnings": int(result.get("warning_count", 0)),
	})
	_stats.text = stats
	if success:
		_append_log("[color=#6ee7a8]%s[/color]" % stats)
		status.emit(I18n.t("build.succeeded", {"rom": rom}))
	else:
		_append_log("[color=#ff7a7a]%s[/color]" % stats)
		status.emit(I18n.t("build.failed_status"))

func _on_error_activated(index: int) -> void:
	var d = _errors.get_item_metadata(index)
	if d is Dictionary:
		open_error_requested.emit(String(d.get("file", "")), int(d.get("line", 0)), int(d.get("column", 0)))
