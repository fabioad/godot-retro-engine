@tool
extends Control
## Godot Retro Engine main workspace.
##
## The editor is a visual front-end over the real PVSnesLib / SGDK toolchains.
## Every build, ROM inspection and emulator launch delegates to the native SDK
## or emulator installed on the host. Resource conversions are implemented in
## the C++ retro_engine module (see modules/retro_engine).

const SpriteEditor = preload("res://addons/retro_engine/sprite_editor.gd")
const StageEditor = preload("res://addons/retro_engine/stage_editor.gd")
const AnimationEditor = preload("res://addons/retro_engine/animation_editor.gd")
const PaletteEditor = preload("res://addons/retro_engine/palette_editor.gd")
const HardwareMonitor = preload("res://addons/retro_engine/hardware_monitor.gd")
const CodePanel = preload("res://addons/retro_engine/code_panel.gd")
const BuildPanel = preload("res://addons/retro_engine/build_panel.gd")
const NewProjectDialog = preload("res://addons/retro_engine/new_project_dialog.gd")
const I18n = preload("res://addons/retro_engine/i18n.gd")
const InputEditor = preload("res://addons/retro_engine/input_editor.gd")
const StateSimulator = preload("res://addons/retro_engine/state_simulator.gd")
const StateGraphEditor = preload("res://addons/retro_engine/state_graph_editor.gd")
const CollisionEditor = preload("res://addons/retro_engine/collision_editor.gd")
const MugenEditor = preload("res://addons/retro_engine/mugen_editor.gd")
const NativeBridgeEditor = preload("res://addons/retro_engine/native_bridge.gd")
const AudioEditor = preload("res://addons/retro_engine/audio_editor.gd")
const SDKDownloader = preload("res://addons/retro_engine/sdk_downloader.gd")
const WindowControls = preload("res://addons/retro_engine/window_controls.gd")
const StageCanvas = preload("res://addons/retro_engine/stage_canvas.gd")

const CONFIG_PATH := "user://retro_engine.cfg"

var platform: String = "snes"
var mode: String = "mode1"
var project: RetroProject
var projects: Array = []
var resources: Array = []
var current_resource: Dictionary = {}
var sprite_doc: RetroSprite
var stage_doc: RetroStage
var anim_doc: RetroAnimation
var snes_info: Dictionary = {}
var md_info: Dictionary = {}
var emulators: Array = []
var _last_rom: String = ""
var _last_rom_size: int = 0

var config := ConfigFile.new()

var _platform_option: OptionButton
var _mode_option: OptionButton
var _project_option: OptionButton
var _sdk_label: Label
var _emulator_option: OptionButton
var _resource_tree: Tree
var _resource_filter: LineEdit
var _tabs: TabContainer
var _main_split: HBoxContainer
var _status: Label
var _preview
var _preview_scroll_x: HSlider
var _preview_scroll_y: HSlider
var _preview_sprites: CheckBox
var _preview_collisions: CheckBox
var _preview_limits: CheckBox
var sprite_editor
var stage_editor
var animation_editor
var palette_editor
var code_panel
var build_panel
var input_editor
var state_simulator
var state_graph
var collision_editor
var mugen_editor
var native_editor
var audio_editor
var hardware_monitor
var hardware_tab_monitor
var _inspector: RichTextLabel
var _info_title: Label
var _save_timer: Timer
var _new_project_dialog
var _open_as_sprite: Button
var _open_as_stage: Button
var _open_as_palette: Button
var _rom_label: Label

func _ready() -> void:
	if Engine.is_editor_hint():
		theme = EditorInterface.get_editor_theme()
	if OS.has_environment("RETRO_LOCALE"):
		TranslationServer.set_locale(OS.get_environment("RETRO_LOCALE"))
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	config.load(CONFIG_PATH)
	platform = config.get_value("retro", "platform", "snes")
	mode = config.get_value("retro", "mode", "mode1")
	_build_ui()
	call_deferred("_apply_responsive_layout")
	_ensure_workspaces_ignored()
	_detect_sdks()
	_load_projects()
	set_platform(platform)
	_apply_saved_emulator()
	status_message(I18n.t("top.ready"))
	if OS.has_environment("RETRO_SHOT"):
		_auto_screenshot.call_deferred()
	if OS.has_environment("RETRO_TAB"):
		_select_tab_later.call_deferred()
	if OS.has_environment("RETRO_NEW_PROJECT_SHOT"):
		_new_project_shot.call_deferred()
	if OS.has_environment("RETRO_COHERENCE_SHOT"):
		_coherence_shot.call_deferred()

func _select_tab_later() -> void:
	await get_tree().create_timer(2.5).timeout
	_tabs.current_tab = clampi(int(OS.get_environment("RETRO_TAB")), 0, _tabs.get_tab_count() - 1)

func _auto_screenshot() -> void:
	await get_tree().create_timer(4.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("RETRO_SHOT"))
	print("RETRO_SHOT saved ", OS.get_environment("RETRO_SHOT"), " ", img.get_width(), "x", img.get_height())

func _coherence_shot() -> void:
	await get_tree().create_timer(2.0).timeout
	set_platform("megadrive" if platform == "snes" else "snes")
	_tabs.current_tab = 6
	await get_tree().create_timer(0.7).timeout
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_environment("RETRO_COHERENCE_SHOT")
	img.save_png(path)
	print("RETRO_COHERENCE_SHOT saved ", path, " ", img.get_width(), "x", img.get_height())
	get_tree().quit()

func _new_project_shot() -> void:
	await get_tree().create_timer(2.0).timeout
	_open_new_project_dialog()
	await get_tree().create_timer(1.5).timeout
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_environment("RETRO_NEW_PROJECT_SHOT")
	img.save_png(path)
	print("RETRO_NEW_PROJECT_SHOT saved ", path, " ", img.get_width(), "x", img.get_height())
	get_tree().quit()

func _apply_responsive_layout() -> void:
	# Kept as a hook for future layout tweaks; HBoxContainer now handles the
	# three-column layout without the two-child limitation of SplitContainer.
	pass

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	# ---- Top toolbar -----------------------------------------------------
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	root.add_child(top)
	var brand := Label.new()
	brand.text = "RETRO ENGINE"
	brand.add_theme_font_size_override("font_size", 15)
	brand.add_theme_color_override("font_color", Color("#7fd1ff"))
	top.add_child(brand)
	var new_btn := Button.new()
	new_btn.text = I18n.t("top.new_project")
	new_btn.tooltip_text = I18n.t("top.new_project_tip")
	new_btn.pressed.connect(_open_new_project_dialog)
	top.add_child(new_btn)
	var import_btn := Button.new()
	import_btn.text = I18n.t("top.import_project")
	import_btn.tooltip_text = I18n.t("top.import_project_tip")
	import_btn.pressed.connect(_open_import_dialog)
	top.add_child(import_btn)
	top.add_child(VSeparator.new())
	_platform_option = OptionButton.new()
	_platform_option.tooltip_text = I18n.t("top.platform_tip")
	_platform_option.add_item("SNES", 0)
	_platform_option.add_item("Mega Drive", 1)
	_platform_option.item_selected.connect(_on_platform_selected)
	top.add_child(_platform_option)
	_mode_option = OptionButton.new()
	_mode_option.tooltip_text = I18n.t("top.mode_tip")
	_mode_option.item_selected.connect(_on_mode_selected)
	top.add_child(_mode_option)
	_project_option = OptionButton.new()
	_project_option.tooltip_text = I18n.t("top.project_tip")
	_project_option.custom_minimum_size.x = 150
	_project_option.item_selected.connect(_on_project_selected)
	top.add_child(_project_option)
	var sdk_btn := Button.new()
	sdk_btn.text = I18n.t("top.sdk")
	sdk_btn.tooltip_text = I18n.t("top.sdk_tip")
	sdk_btn.pressed.connect(_open_sdk_dialog)
	top.add_child(sdk_btn)
	var top_spacer := _spacer()
	top_spacer.mouse_filter = Control.MOUSE_FILTER_STOP
	top_spacer.tooltip_text = I18n.t("top.maximize_tip")
	top_spacer.gui_input.connect(_on_top_bar_gui_input)
	top.add_child(top_spacer)

	var sdk_row := HBoxContainer.new()
	root.add_child(sdk_row)
	_sdk_label = Label.new()
	_sdk_label.add_theme_color_override("font_color", Color("#9fb4d0"))
	_sdk_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_sdk_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sdk_label.clip_text = true
	_sdk_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sdk_row.add_child(_sdk_label)
	_rom_label = Label.new()
	_rom_label.add_theme_color_override("font_color", Color("#6ee7a8"))
	_rom_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_rom_label.clip_text = true
	_rom_label.custom_minimum_size.x = 140
	sdk_row.add_child(_rom_label)
	_emulator_option = OptionButton.new()
	_emulator_option.tooltip_text = I18n.t("top.emulator_tip")
	_emulator_option.custom_minimum_size.x = 120
	_emulator_option.item_selected.connect(_on_emulator_selected)
	sdk_row.add_child(_emulator_option)
	var download_sdk := Button.new()
	download_sdk.text = I18n.t("top.download_sdks")
	download_sdk.tooltip_text = I18n.t("top.download_sdks_tip")
	download_sdk.pressed.connect(_open_sdk_downloader)
	sdk_row.add_child(download_sdk)
	var export_rom := Button.new()
	export_rom.text = I18n.t("top.export_rom")
	export_rom.tooltip_text = I18n.t("top.export_rom_tip")
	export_rom.pressed.connect(_export_rom)
	sdk_row.add_child(export_rom)

	# ---- Main split ------------------------------------------------------
	var main_split := HBoxContainer.new()
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_theme_constant_override("separation", 4)
	_main_split = main_split
	root.add_child(main_split)

	# Resources.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 175
	main_split.add_child(left)
	var lhead := HBoxContainer.new()
	var ltitle := Label.new()
	ltitle.text = I18n.t("resources.title")
	ltitle.add_theme_font_size_override("font_size", 14)
	ltitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lhead.add_child(ltitle)
	left.add_child(lhead)
	_resource_filter = LineEdit.new()
	_resource_filter.placeholder_text = I18n.t("resources.filter")
	_resource_filter.text_changed.connect(func(_t): _refresh_resource_tree())
	left.add_child(_resource_filter)
	_resource_tree = Tree.new()
	_resource_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_resource_tree.custom_minimum_size.x = 0
	_resource_tree.item_activated.connect(_on_resource_activated)
	_resource_tree.item_selected.connect(_on_resource_selected)
	left.add_child(_resource_tree)
	var open_row := VBoxContainer.new()
	open_row.add_theme_constant_override("separation", 2)
	left.add_child(open_row)
	_open_as_sprite = Button.new()
	_open_as_sprite.text = I18n.t("resources.sprite")
	_open_as_sprite.pressed.connect(func(): _open_selected_as("sprite"))
	open_row.add_child(_open_as_sprite)
	_open_as_stage = Button.new()
	_open_as_stage.text = I18n.t("resources.stage")
	_open_as_stage.pressed.connect(func(): _open_selected_as("stage"))
	open_row.add_child(_open_as_stage)
	_open_as_palette = Button.new()
	_open_as_palette.text = I18n.t("resources.palette")
	_open_as_palette.pressed.connect(func(): _open_selected_as("palette"))
	open_row.add_child(_open_as_palette)
	var readonly_note := Label.new()
	readonly_note.text = I18n.t("resources.note")
	readonly_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readonly_note.add_theme_color_override("font_color", Color("#8b98ad"))
	left.add_child(readonly_note)

	# Center tabs.
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size.x = 0
	main_split.add_child(_tabs)
	_build_preview_tab()
	sprite_editor = SpriteEditor.new()
	sprite_editor.name = "Sprite"
	sprite_editor.modified.connect(_on_document_modified)
	sprite_editor.status.connect(status_message)
	_tabs.add_child(sprite_editor)
	stage_editor = StageEditor.new()
	stage_editor.name = "Stage"
	stage_editor.modified.connect(_on_document_modified)
	stage_editor.status.connect(status_message)
	_tabs.add_child(stage_editor)
	animation_editor = AnimationEditor.new()
	animation_editor.name = "Animation"
	animation_editor.modified.connect(_on_document_modified)
	animation_editor.status.connect(status_message)
	_tabs.add_child(animation_editor)
	palette_editor = PaletteEditor.new()
	palette_editor.name = "Palette"
	palette_editor.palette_changed.connect(_on_palette_changed)
	palette_editor.import_requested.connect(_import_palette)
	palette_editor.export_requested.connect(_export_palette)
	_tabs.add_child(palette_editor)
	code_panel = CodePanel.new()
	code_panel.name = "Code"
	code_panel.status.connect(status_message)
	code_panel.modified.connect(_on_code_modified)
	_tabs.add_child(code_panel)
	build_panel = BuildPanel.new()
	build_panel.name = "Build"
	build_panel.status.connect(status_message)
	build_panel.rom_built.connect(_on_rom_built)
	build_panel.open_error_requested.connect(_open_error)
	build_panel.platform_fix_requested.connect(set_platform)
	_tabs.add_child(build_panel)
	input_editor = InputEditor.new()
	input_editor.name = "Inputs"
	input_editor.modified.connect(_on_document_modified)
	input_editor.input_changed.connect(_on_input_changed)
	input_editor.status.connect(status_message)
	_tabs.add_child(input_editor)
	state_simulator = StateSimulator.new()
	state_simulator.name = "Simulator"
	state_simulator.status.connect(status_message)
	state_simulator.state_changed.connect(_on_sim_state_changed)
	_tabs.add_child(state_simulator)
	state_graph = StateGraphEditor.new()
	state_graph.name = "StateGraph"
	state_graph.modified.connect(_on_graph_modified)
	state_graph.status.connect(status_message)
	_tabs.add_child(state_graph)
	collision_editor = CollisionEditor.new()
	collision_editor.name = "Hitboxes"
	collision_editor.modified.connect(_on_collision_modified)
	collision_editor.status.connect(status_message)
	_tabs.add_child(collision_editor)
	audio_editor = AudioEditor.new()
	audio_editor.name = "Audio"
	audio_editor.status.connect(status_message)
	audio_editor.modified.connect(_on_document_modified)
	_tabs.add_child(audio_editor)
	native_editor = NativeBridgeEditor.new()
	native_editor.name = "Native"
	native_editor.status.connect(status_message)
	native_editor.modified.connect(_on_native_modified)
	_tabs.add_child(native_editor)
	mugen_editor = MugenEditor.new()
	mugen_editor.name = "MUGEN"
	mugen_editor.status.connect(status_message)
	mugen_editor.modified.connect(_on_mugen_modified)
	mugen_editor.graph_built.connect(_on_mugen_graph_built)
	mugen_editor.state_imported.connect(_on_mugen_state_imported)
	mugen_editor.states_imported.connect(_on_mugen_states_imported)
	_tabs.add_child(mugen_editor)
	# Short literal titles keep the workspace usable on 1024px-wide windows;
	# the editor's automatic translation of node names can otherwise expand
	# the tab strip enough to push the hardware dock off-screen.
	_tabs.set_tab_title(0, I18n.t("tabs.preview"))
	_tabs.set_tab_title(1, I18n.t("tabs.sprite"))
	_tabs.set_tab_title(2, I18n.t("tabs.stage"))
	_tabs.set_tab_title(3, I18n.t("tabs.animation"))
	_tabs.set_tab_title(4, I18n.t("tabs.palette"))
	_tabs.set_tab_title(5, I18n.t("tabs.code"))
	_tabs.set_tab_title(6, I18n.t("tabs.build"))
	_tabs.set_tab_title(7, I18n.t("tabs.input"))
	_tabs.set_tab_title(8, I18n.t("tabs.simulator"))
	_tabs.set_tab_title(9, I18n.t("tabs.graph"))
	_tabs.set_tab_title(10, I18n.t("tabs.hitboxes"))
	_tabs.set_tab_title(11, I18n.t("tabs.audio"))
	_tabs.set_tab_title(12, I18n.t("tabs.native"))
	_tabs.set_tab_title(13, I18n.t("tabs.mugen"))

	# Right inspector.
	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size.x = 230
	main_split.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 225
	right.add_theme_constant_override("separation", 6)
	right_scroll.add_child(right)
	_info_title = Label.new()
	_info_title.text = I18n.t("inspector.selection")
	_info_title.add_theme_font_size_override("font_size", 14)
	right.add_child(_info_title)
	_inspector = RichTextLabel.new()
	_inspector.bbcode_enabled = true
	_inspector.fit_content = true
	_inspector.custom_minimum_size.y = 130
	_inspector.selection_enabled = true
	right.add_child(_inspector)
	hardware_monitor = HardwareMonitor.new()
	right.add_child(hardware_monitor)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("#9fb4d0"))
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.clip_text = true
	root.add_child(_status)

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 1.0
	_save_timer.timeout.connect(_save_session_docs)
	add_child(_save_timer)

func _build_preview_tab() -> void:
	var preview_box := VBoxContainer.new()
	preview_box.name = "Preview"
	_tabs.add_child(preview_box)
	var row := HBoxContainer.new()
	preview_box.add_child(row)
	var note := Label.new()
	note.text = I18n.t("preview.note")
	note.add_theme_color_override("font_color", Color("#ffd45e"))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.clip_text = true
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	note.tooltip_text = note.text
	row.add_child(note)
	_preview_sprites = CheckBox.new()
	_preview_sprites.text = I18n.t("preview.sprites")
	_preview_sprites.button_pressed = true
	_preview_sprites.toggled.connect(func(v): _preview.show_sprites = v; _preview.queue_redraw())
	row.add_child(_preview_sprites)
	_preview_collisions = CheckBox.new()
	_preview_collisions.text = I18n.t("preview.collisions")
	_preview_collisions.button_pressed = true
	_preview_collisions.toggled.connect(func(v): _preview.show_collisions = v; _preview.queue_redraw())
	row.add_child(_preview_collisions)
	_preview_limits = CheckBox.new()
	_preview_limits.text = I18n.t("preview.limits")
	_preview_limits.button_pressed = true
	_preview_limits.toggled.connect(func(v): _preview.show_limits = v; _preview.queue_redraw())
	row.add_child(_preview_limits)
	var scroll_row := HBoxContainer.new()
	preview_box.add_child(scroll_row)
	var scroll_note := Label.new()
	scroll_note.text = I18n.t("preview.scroll_x")
	scroll_row.add_child(scroll_note)
	_preview_scroll_x = HSlider.new()
	_preview_scroll_x.min_value = 0
	_preview_scroll_x.max_value = 4096
	_preview_scroll_x.custom_minimum_size.x = 110
	_preview_scroll_x.value_changed.connect(func(_v): _preview.scroll_offset = Vector2(_preview_scroll_x.value, _preview_scroll_y.value); _preview.queue_redraw())
	scroll_row.add_child(_preview_scroll_x)
	var scroll_note_y := Label.new()
	scroll_note_y.text = I18n.t("preview.scroll_y")
	scroll_row.add_child(scroll_note_y)
	_preview_scroll_y = HSlider.new()
	_preview_scroll_y.min_value = 0
	_preview_scroll_y.max_value = 4096
	_preview_scroll_y.custom_minimum_size.x = 110
	_preview_scroll_y.value_changed.connect(func(_v): _preview.scroll_offset = Vector2(_preview_scroll_x.value, _preview_scroll_y.value); _preview.queue_redraw())
	scroll_row.add_child(_preview_scroll_y)
	_preview = StageCanvas.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_box.add_child(_preview)

func _on_top_bar_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.double_click:
		WindowControls.toggle_maximize(get_window())

func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

func _detect_sdks() -> void:
	var saved_snes: String = config.get_value("retro", "sdk_snes", "")
	var saved_md: String = config.get_value("retro", "sdk_md", "")
	if saved_snes != "":
		RetroSDK.configure("snes", saved_snes)
	if saved_md != "":
		RetroSDK.configure("megadrive", saved_md)
	var all: Dictionary = RetroSDK.detect_all()
	snes_info = all.get("snes", {})
	md_info = all.get("megadrive", {})
	_update_sdk_label()

func _update_sdk_label() -> void:
	if platform == "snes":
		if snes_info.is_empty() or not bool(snes_info.get("found", false)):
			_sdk_label.text = I18n.t("top.sdk_snes_missing")
			_sdk_label.add_theme_color_override("font_color", Color("#ff7a7a"))
		else:
			var missing: Array = snes_info.get("missing_required", [])
			var color := Color("#6ee7a8") if missing.is_empty() else Color("#ffd45e")
			_sdk_label.add_theme_color_override("font_color", color)
			_sdk_label.text = I18n.t("top.sdk_snes_status", {
				"version": String(snes_info.get("version", "?")),
				"state": I18n.t("top.sdk_ready") if missing.is_empty() else I18n.t("top.sdk_missing", {"items": ", ".join(PackedStringArray(missing))}),
				"libraries": "" if bool(snes_info.get("has_libraries", false)) else I18n.t("top.sdk_libraries_missing"),
			})
			_sdk_label.tooltip_text = String(snes_info.get("path", ""))
	else:
		if md_info.is_empty() or not bool(md_info.get("found", false)):
			_sdk_label.text = I18n.t("top.sdk_md_missing")
			_sdk_label.add_theme_color_override("font_color", Color("#ff7a7a"))
		else:
			var lin: Dictionary = md_info.get("linux", {})
			var color := Color("#6ee7a8") if bool(lin.get("available", false)) else Color("#ffd45e")
			_sdk_label.add_theme_color_override("font_color", color)
			_sdk_label.text = I18n.t("top.sdk_md_status", {
				"version": String(md_info.get("version", "?")),
				"state": I18n.t("top.sdk_toolchain_ready") if bool(lin.get("available", false)) else I18n.t("top.sdk_m68k_missing"),
				"resources": I18n.t("top.sdk_resources_ready") if bool(lin.get("resource_compiler_available", false)) else I18n.t("top.sdk_resources_missing"),
			})
			_sdk_label.tooltip_text = String(md_info.get("path", ""))
	_refresh_emulators()

func _refresh_emulators() -> void:
	_emulator_option.clear()
	emulators = RetroEmulator.detect(platform)
	if emulators.is_empty():
		_emulator_option.add_item(I18n.t("top.no_emulator"))
		_emulator_option.set_item_disabled(0, true)
	else:
		for e in emulators:
			_emulator_option.add_item(String(e.get("name", e.get("id", "emulator"))))
	var saved := String(config.get_value("retro", "emulator_" + platform, ""))
	for i in range(emulators.size()):
		if String(emulators[i].get("id", "")) == saved:
			_emulator_option.select(i)
			break
	if not emulators.is_empty() and _emulator_option.selected < 0:
		_emulator_option.select(0)
	_apply_saved_emulator()

func _apply_saved_emulator() -> void:
	var id := ""
	if _emulator_option and _emulator_option.selected >= 0 and _emulator_option.selected < emulators.size():
		id = String(emulators[_emulator_option.selected].get("id", ""))
	if build_panel:
		build_panel.set_emulator(id)

func _on_emulator_selected(index: int) -> void:
	if index >= 0 and index < emulators.size():
		var id := String(emulators[index].get("id", ""))
		config.set_value("retro", "emulator_" + platform, id)
		config.save(CONFIG_PATH)
		build_panel.set_emulator(id)
		status_message(I18n.t("top.emulator_selected", {"name": String(emulators[index].get("name", id)), "exe": String(emulators[index].get("executable", ""))}))

func _on_platform_selected(index: int) -> void:
	set_platform("snes" if index == 0 else "megadrive")

func set_platform(p: String) -> void:
	platform = p
	_platform_option.select(0 if p == "snes" else 1)
	_mode_option.clear()
	var modes: Array = RetroSDK.get_modes(p)
	for m in modes:
		_mode_option.add_item(String(m).to_upper() if p == "megadrive" else String(m))
	if p == "snes":
		mode = "mode1" if mode not in ["mode0", "mode1", "mode7"] else mode
		var idx := 0
		for i in range(modes.size()):
			if String(modes[i]) == mode:
				idx = i
		_mode_option.select(idx)
	else:
		mode = "h40" if mode not in ["h40", "h32"] else mode
		_mode_option.select(0 if mode == "h40" else 1)
	sprite_editor.set_platform(p)
	stage_editor.set_platform(p, mode)
	animation_editor.set_platform(p)
	palette_editor.set_platform(p)
	build_panel.set_platform(p)
	if input_editor:
		input_editor.set_platform(p)
	if state_simulator:
		state_simulator.set_platform(p)
	if state_graph:
		state_graph.set_platform(p)
	if collision_editor:
		collision_editor.set_context(project, p, sprite_doc, anim_doc)
	if mugen_editor:
		mugen_editor.set_platform(p)
	if native_editor:
		native_editor.set_platform(p)
	hardware_monitor.set_platform(p, mode)
	_update_sdk_label()
	config.set_value("retro", "platform", p)
	config.set_value("retro", "mode", mode)
	config.save(CONFIG_PATH)
	if project != null and project.get_platform() != p:
		status_message(I18n.t("top.platform_mismatch", {
			"selected": I18n.platform_label(p),
			"name": project.get_name(),
			"project": I18n.platform_label(project.get_platform()),
		}))

func _on_mode_selected(index: int) -> void:
	if platform == "snes":
		mode = ["mode0", "mode1", "mode7"][index] if index < 3 else "mode1"
	else:
		mode = "h40" if index == 0 else "h32"
	if stage_doc:
		stage_doc.set_mode(mode)
	if project:
		project.set_mode(mode)
		project.save()
	if build_panel:
		build_panel.refresh_coherence()
	stage_editor.set_platform(platform, mode)
	if native_editor:
		native_editor.set_mode(mode)
	hardware_monitor.set_platform(platform, mode)
	_refresh_preview()
	config.set_value("retro", "mode", mode)
	config.save(CONFIG_PATH)

func _on_project_selected(index: int) -> void:
	if index >= 0 and index < projects.size():
		_select_project(projects[index])

func _select_project(p: RetroProject) -> void:
	if project != null and project != p:
		_save_session_docs()
	project = p
	var project_platform := project.get_platform()
	var project_mode := project.get_mode()
	if project_platform == "snes" and project_mode not in ["mode0", "mode1", "mode7"]:
		project_mode = "mode1"
	elif project_platform == "megadrive" and project_mode not in ["h40", "h32"]:
		project_mode = "h40"
	mode = project_mode
	resources = project.get_resources()
	_sdk_label.tooltip_text = project.get_sdk_version()
	set_platform(project_platform)
	if project.get_mode() != project_mode:
		project.set_mode(project_mode)
		project.save()
	stage_editor.set_platform(platform, mode)
	hardware_monitor.set_platform(platform, mode)
	_last_rom = project.get_rom_path()
	_last_rom_size = FileAccess.get_size(_last_rom) if FileAccess.file_exists(_last_rom) else 0
	_rom_label.text = "%s  %s" % [_last_rom.get_file(), _size_text(_last_rom_size)] if _last_rom != "" else ""
	build_panel.set_project(project)
	code_panel.set_project(project)
	if audio_editor:
		audio_editor.set_project(project)
	_refresh_resource_tree()
	_refresh_emulators()
	config.set_value("retro", "last_project", project.metadata_path())
	config.save(CONFIG_PATH)
	_restore_session_docs()
	if input_editor:
		input_editor.set_context(project, platform, anim_doc)
	if state_simulator:
		state_simulator.set_context(project, platform, anim_doc, sprite_doc)
		state_simulator.set_input_map(input_editor.get_input_map())
	if state_graph:
		state_graph.set_context(project, platform, input_editor.get_input_map(), anim_doc)
	if collision_editor:
		collision_editor.set_context(project, platform, sprite_doc, anim_doc)
	if mugen_editor:
		mugen_editor.set_context(project, platform, anim_doc, input_editor.get_input_map())
	if native_editor:
		native_editor.set_context(project, platform, mode)
	status_message(I18n.t("top.opened", {"name": project.get_name(), "sdk": project.get_sdk_version(), "count": resources.size()}))

func _load_projects() -> void:
	projects.clear()
	_project_option.clear()
	var paths: Array = config.get_value("retro", "projects", [])
	for path in paths:
		if not FileAccess.file_exists(String(path)):
			continue
		var p := RetroProject.new()
		if p.load(String(path)) == OK:
			projects.append(p)
	for p in projects:
		_project_option.add_item(p.get_name())
	if projects.is_empty():
		_project_option.add_item(I18n.t("top.no_project"))
		_project_option.set_item_disabled(0, true)
		return
	var last := String(config.get_value("retro", "last_project", ""))
	var sel := 0
	for i in range(projects.size()):
		if projects[i].metadata_path() == last:
			sel = i
	_project_option.select(sel)
	_select_project(projects[sel])
	_auto_open_first()

func _auto_open_first() -> void:
	if stage_doc == null and sprite_doc == null:
		# Prefer editable sheets that have their companion .pal/.map, so the
		# first click after import actually renders something.
		var best_stage := -1
		var best_sprite := -1
		for i in range(resources.size()):
			var r: Dictionary = resources[i]
			var has_map := String(r.get("map_path", "")) != "" or FileAccess.file_exists(String(r.get("path", "")).get_basename() + ".map")
			var has_pal := String(r.get("palette_path", "")) != "" or FileAccess.file_exists(String(r.get("path", "")).get_basename() + ".pal")
			if String(r.get("editor", "")) == "stage" and bool(r.get("editable", false)):
				if not has_map and String(r.get("ext", "")) in ["png", "bmp"]:
					continue
				if best_stage < 0 or int(r.get("size", 0)) > int(resources[best_stage].get("size", 0)):
					best_stage = i
			if String(r.get("editor", "")) == "sprite" and bool(r.get("editable", false)):
				if String(r.get("ext", "")) in ["chr", "pic"] and not has_pal:
					continue
				if best_sprite < 0 or int(r.get("size", 0)) > int(resources[best_sprite].get("size", 0)):
					best_sprite = i
		if best_stage >= 0:
			_open_resource(best_stage)
		if best_sprite >= 0:
			_open_resource(best_sprite)

func _refresh_resource_tree() -> void:
	_resource_tree.clear()
	var root := _resource_tree.create_item()
	var categories := {
		"Sprites": [], "Stages": [], "Palettes": [], "Animations": [],
		"Code": [], "Resources": [], "Audio": [], "Read-only": [], "Other": [],
	}
	var category_labels := {
		"Sprites": I18n.t("resources.sprites"),
		"Stages": I18n.t("resources.stages"),
		"Palettes": I18n.t("resources.palettes"),
		"Animations": I18n.t("resources.animations"),
		"Code": I18n.t("resources.code"),
		"Resources": I18n.t("resources.title"),
		"Audio": I18n.t("resources.audio"),
		"Read-only": I18n.t("resources.readonly"),
		"Other": I18n.t("resources.other"),
	}
	var filter := _resource_filter.text.to_lower()
	for i in range(resources.size()):
		var r: Dictionary = resources[i]
		var name := String(r.get("rel_path", ""))
		if filter != "" and not name.to_lower().contains(filter):
			continue
		var editor := String(r.get("editor", "none"))
		var key := "Other"
		if editor == "sprite" or editor == "image":
			key = "Sprites"
		elif editor == "stage":
			key = "Stages"
		elif editor == "palette":
			key = "Palettes"
		elif editor == "animation":
			key = "Animations"
		elif editor == "code":
			key = "Code"
		elif editor == "resources":
			key = "Resources"
		elif editor == "audio":
			key = "Audio"
		elif not bool(r.get("editable", false)):
			key = "Read-only"
		categories[key].append(i)
	for key in ["Sprites", "Stages", "Palettes", "Animations", "Code", "Resources", "Audio", "Read-only", "Other"]:
		var list: Array = categories[key]
		if list.is_empty():
			continue
		var cat := _resource_tree.create_item(root)
		cat.set_text(0, "%s (%d)" % [String(category_labels.get(key, key)), list.size()])
		cat.set_selectable(0, false)
		for idx in list:
			var r: Dictionary = resources[idx]
			var item := _resource_tree.create_item(cat)
			var editable := "E" if bool(r.get("editable", false)) else "RO"
			var extra := ""
			if r.has("width"):
				extra = "  %dx%d" % [int(r.get("width", 0)), int(r.get("height", 0))]
			item.set_text(0, "[%s] %s%s" % [editable, String(r.get("name", "")), extra])
			item.set_tooltip_text(0, String(r.get("rel_path", "")))
			item.set_metadata(0, idx)
			if not bool(r.get("editable", false)):
				item.set_custom_color(0, Color("#8b98ad"))

func _on_resource_selected() -> void:
	var item := _resource_tree.get_selected()
	if item == null:
		return
	var idx = item.get_metadata(0)
	if idx == null:
		return
	var i := int(idx)
	if i < 0 or i >= resources.size():
		return
	current_resource = resources[i]
	code_panel.set_resource(current_resource)
	_show_resource_info(current_resource)

func _show_resource_info(r: Dictionary) -> void:
	_info_title.text = String(r.get("name", I18n.t("inspector.resource")))
	var editable := I18n.t("common.yes") if bool(r.get("editable", false)) else I18n.t("resources.readonly_short")
	var pal := String(r.get("palette_path", ""))
	var map := String(r.get("map_path", ""))
	var txt := "[b]%s[/b]\n" % String(r.get("rel_path", ""))
	txt += "Kind: %s | Editor: %s | Editable: %s\n" % [String(r.get("kind", "")), String(r.get("editor", "")), editable]
	txt += "Size: %s" % _size_text(int(r.get("size", 0)))
	if r.has("width"):
		txt += " | %dx%d px | palette %d" % [int(r.get("width", 0)), int(r.get("height", 0)), int(r.get("palette_size", 0))]
	if not pal.is_empty():
		txt += "\nPalette: " + pal.get_file()
	if not map.is_empty():
		txt += "\nMap: " + map.get_file()
	if String(r.get("note", "")) != "":
		txt += "\n[color=#ffd45e]%s[/color]" % String(r.get("note", ""))
	_inspector.text = txt

func _on_resource_activated() -> void:
	var item := _resource_tree.get_selected()
	if item == null:
		return
	var idx = item.get_metadata(0)
	if idx != null:
		_open_resource(int(idx))

func _open_selected_as(kind: String) -> void:
	var item := _resource_tree.get_selected()
	if item == null:
		return
	var idx = item.get_metadata(0)
	if idx == null:
		return
	_open_resource(int(idx), kind)

func _open_resource(index: int, force_kind: String = "") -> void:
	if index < 0 or index >= resources.size():
		return
	var r: Dictionary = resources[index]
	current_resource = r
	code_panel.set_resource(r)
	_show_resource_info(r)
	var ext := String(r.get("ext", ""))
	var editor := force_kind if force_kind != "" else String(r.get("editor", ""))
	if ext == "sff" or ext == "air":
		_show_readonly_dialog(String(r.get("name", "")), String(r.get("note", "")))
		return
	if ext == "pal" and (editor == "palette" or force_kind == "palette"):
		_open_palette_file(String(r.get("path", "")))
		return
	if ext in ["png", "bmp", "webp", "chr", "pic"]:
		if editor == "stage":
			stage_editor.open_resource(r, project)
			stage_doc = stage_editor.stage
			_tabs.current_tab = 2
			_refresh_preview()
			hardware_monitor.refresh(stage_doc, sprite_doc, anim_doc, _last_rom_size)
		else:
			sprite_editor.open_resource(r, project)
			sprite_doc = sprite_editor.sprite
			_tabs.current_tab = 1
			animation_editor.set_sprite(sprite_doc)
			_refresh_preview()
			hardware_monitor.refresh(stage_doc, sprite_doc, anim_doc, _last_rom_size)
		return
	if editor == "code" or ext in ["c", "h", "cpp", "hpp", "asm", "s", "inc", "res", "py", "sh"]:
		code_panel.open_file(String(r.get("path", "")), 1, 0)
		_tabs.current_tab = 5
		return
	if editor == "audio":
		if audio_editor:
			audio_editor.set_project(project)
			_tabs.current_tab = 11
		status_message("Audio asset opened in the BGM/SFX editor.")
		return
	status_message("Recognized resource, but no visual editor is available for ." + ext)

func _show_readonly_dialog(name: String, note: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Read-only resource"
	dlg.dialog_text = "%s\n\n%s\n\nThe IDE does not pretend this format is editable. The project's own converter produced the generated .chr/.pal/.inc/.map files, which can be inspected and edited separately." % [name, note]
	add_child(dlg)
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered()

func _open_palette_file(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var data := FileAccess.get_file_as_bytes(path)
	var pal: PackedColorArray = RetroGraphics.decode_palette(data, platform == "megadrive", 0)
	palette_editor.set_palette(pal)
	_tabs.current_tab = 4
	status_message("Palette loaded: %s (%d colors)" % [path.get_file(), pal.size()])

func _on_palette_changed(pal: PackedColorArray) -> void:
	if current_resource.get("editor", "") == "palette":
		# Palette changes are written only through the explicit Export action.
		pass
	if sprite_doc:
		sprite_doc.set_palette(pal)
		sprite_editor.set_sprite(sprite_doc, project)
	if stage_doc:
		stage_doc.set_palette(pal)
		stage_editor.set_stage(stage_doc, project)
		_refresh_preview()
	hardware_monitor.refresh(stage_doc, sprite_doc, anim_doc if anim_doc else null, _last_rom_size)

func _import_palette() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.pal", "Palette")
	dlg.file_selected.connect(func(path):
		var data := FileAccess.get_file_as_bytes(path)
		var pal: PackedColorArray = RetroGraphics.decode_palette(data, platform == "megadrive", 0)
		palette_editor.set_palette(pal)
		_on_palette_changed(pal)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _export_palette() -> void:
	var pal: PackedColorArray = palette_editor.get_palette()
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.pal", "Palette")
	dlg.current_file = "palette.pal"
	dlg.file_selected.connect(func(path):
		var bytes: PackedByteArray = RetroGraphics.encode_palette(pal, platform == "megadrive")
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_buffer(bytes)
			f.close()
			status_message("Palette exported: " + path)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _on_document_modified() -> void:
	if sprite_editor and sprite_doc == null:
		sprite_doc = sprite_editor.sprite
	if stage_editor and stage_doc == null:
		stage_doc = stage_editor.stage
	if sprite_editor:
		sprite_doc = sprite_editor.sprite
	if stage_editor:
		stage_doc = stage_editor.stage
	if animation_editor:
		anim_doc = animation_editor.animation
	if input_editor and anim_doc:
		input_editor.set_animation(anim_doc)
	if state_simulator:
		state_simulator.set_animation(anim_doc)
		state_simulator.set_sprite(sprite_doc)
	if state_graph:
		state_graph.set_animation(anim_doc)
	if collision_editor:
		collision_editor.set_animation(anim_doc)
		collision_editor.set_sprite(sprite_doc)
	if mugen_editor:
		mugen_editor.set_animation(anim_doc)
	_refresh_preview()
	hardware_monitor.refresh(stage_doc, sprite_doc, anim_doc, _last_rom_size)
	if _save_timer:
		_save_timer.start()

func _on_collision_modified() -> void:
	if _save_timer:
		_save_timer.start()
	if animation_editor and anim_doc:
		animation_editor.set_animation(anim_doc)
	if state_simulator and anim_doc:
		state_simulator.set_animation(anim_doc)
	if state_graph and anim_doc:
		state_graph.set_animation(anim_doc)
	status_message("Hitbox changes saved to the animation document.")

func _on_sim_state_changed(state: String, frame: int) -> void:
	if collision_editor:
		collision_editor.set_runtime_state(state, frame)

func _on_graph_modified() -> void:
	if _save_timer:
		_save_timer.start()
	status_message("State graph changed.")

func _on_input_changed() -> void:
	if state_simulator and input_editor:
		state_simulator.set_input_map(input_editor.get_input_map())
	if state_graph and input_editor:
		state_graph.set_input_map(input_editor.get_input_map())
	if mugen_editor and input_editor:
		mugen_editor.set_input_map(input_editor.get_input_map())

func _on_mugen_modified() -> void:
	if _save_timer:
		_save_timer.start()
	if mugen_editor:
		mugen_editor.save_session()

func _on_mugen_graph_built(graph, moves: Array) -> void:
	if state_graph and graph:
		state_graph.replace_graph(graph)
	if collision_editor:
		collision_editor.apply_moves(moves)
	if _save_timer:
		_save_timer.start()
	status_message("MUGEN fight graph applied to StateGraph and move profiles.")

func _on_mugen_state_imported(target_state: String) -> void:
	if animation_editor and anim_doc:
		animation_editor.set_animation(anim_doc)
	if input_editor and anim_doc:
		input_editor.set_animation(anim_doc)
	if state_simulator and anim_doc:
		state_simulator.set_animation(anim_doc)
	if state_graph and anim_doc:
		state_graph.set_animation(anim_doc)
	if collision_editor:
		var st: Dictionary = mugen_editor.get_selected_state() if mugen_editor else Dictionary()
		var hd: Dictionary = st.get("hitdef_data", Dictionary())
		if not hd.is_empty():
			collision_editor.apply_hitdef(target_state, hd)
		collision_editor.set_animation(anim_doc)
	if _save_timer:
		_save_timer.start()
	status_message("MUGEN state imported into animation state " + target_state)

func _on_mugen_states_imported(count: int) -> void:
	if animation_editor and anim_doc:
		animation_editor.set_animation(anim_doc)
	if input_editor and anim_doc:
		input_editor.set_animation(anim_doc)
	if state_simulator:
		state_simulator.set_animation(anim_doc)
	if state_graph:
		state_graph.set_animation(anim_doc)
	if collision_editor:
		collision_editor.set_animation(anim_doc)
		collision_editor.set_sprite(sprite_doc)
	_refresh_preview()
	if _save_timer:
		_save_timer.start()
	status_message("MUGEN batch import: %d states added to the animation." % count)

func _on_native_modified() -> void:
	if _save_timer:
		_save_timer.start()
	_refresh_resource_tree()
	status_message(I18n.t("top.native_imported"))

func _on_code_modified() -> void:
	status_message(I18n.t("top.code_edited"))

func _refresh_preview() -> void:
	if _preview == null:
		return
	_preview.set_stage(stage_doc)
	_preview.set_sprite(sprite_doc, anim_doc)
	if anim_doc and anim_doc.get_states().has("IDLE"):
		_preview.animation_state = "IDLE"
	_preview.queue_redraw()

func _save_session_docs() -> void:
	if project == null:
		return
	var dir := project.resolve(".retro/editor")
	DirAccess.make_dir_recursive_absolute(dir)
	if sprite_doc:
		sprite_doc.save(dir.path_join("sprite.json"))
	if stage_doc:
		stage_doc.save(dir.path_join("stage.json"))
	if anim_doc:
		anim_doc.save(dir.path_join("animation.json"))
	if input_editor:
		input_editor.save_session()
	if state_graph:
		state_graph.save_session()
	if collision_editor:
		collision_editor.save_session()
	if mugen_editor:
		mugen_editor.save_session()
	if native_editor:
		native_editor.save_session()
	project.save()

func _restore_session_docs() -> void:
	if project == null:
		return
	var dir := project.resolve(".retro/editor")
	if FileAccess.file_exists(dir.path_join("stage.json")):
		var s := RetroStage.new()
		if s.load(dir.path_join("stage.json")) == OK:
			stage_doc = s
			stage_editor.set_stage(s, project)
	if FileAccess.file_exists(dir.path_join("sprite.json")):
		var sp := RetroSprite.new()
		if sp.load(dir.path_join("sprite.json")) == OK:
			sprite_doc = sp
			sprite_editor.set_sprite(sp, project)
	if FileAccess.file_exists(dir.path_join("animation.json")):
		var a := RetroAnimation.new()
		if a.load(dir.path_join("animation.json")) == OK:
			anim_doc = a
			animation_editor.set_animation(a, project)
	if anim_doc == null:
		anim_doc = RetroAnimation.new()
		anim_doc.set_name((sprite_doc.get_name() if sprite_doc else project.get_name()) + "_anim")
		anim_doc.set_platform(platform)
	animation_editor.set_sprite(sprite_doc)
	animation_editor.set_animation(anim_doc, project)
	_refresh_preview()

func _ensure_workspaces_ignored() -> String:
	## Working copies are created under res://workspaces, inside the IDE's own
	## Godot project. Godot's importer must never scan them: native build
	## artifacts such as WLA-DX/816-tcc .obj files are treated as Wavefront OBJ
	## text, which floods the log with UTF-8 errors and stalls the first scan.
	## The IDE reads these trees through absolute paths, so hiding them is safe.
	var workspace := ProjectSettings.globalize_path("res://workspaces")
	DirAccess.make_dir_recursive_absolute(workspace)
	var marker := workspace.path_join(".gdignore")
	if not FileAccess.file_exists(marker):
		var f := FileAccess.open(marker, FileAccess.WRITE)
		if f:
			f.close()
	return workspace

func _open_new_project_dialog() -> void:
	if _new_project_dialog == null:
		_new_project_dialog = NewProjectDialog.new()
		add_child(_new_project_dialog)
		_new_project_dialog.project_created.connect(_on_new_project_created)
		_new_project_dialog.rom_built.connect(_on_rom_built)
		_new_project_dialog.status.connect(status_message)
		_new_project_dialog.sdk_download_requested.connect(_open_sdk_downloader)
		_new_project_dialog.sdk_configure_requested.connect(_open_sdk_dialog)
	_new_project_dialog.open(_ensure_workspaces_ignored())

func _on_new_project_created(p: RetroProject) -> void:
	if p == null:
		return
	var paths: Array = config.get_value("retro", "projects", [])
	var key := p.metadata_path()
	if not paths.has(key):
		paths.append(key)
		config.set_value("retro", "projects", paths)
	config.set_value("retro", "last_project", key)
	config.save(CONFIG_PATH)
	_load_projects()
	if project != null and code_panel:
		code_panel.set_project(project)
		var main_path := project.get_path().path_join("src/main.c")
		if FileAccess.file_exists(main_path):
			code_panel.open_file(main_path, 1, 0)
			_tabs.current_tab = 5
	status_message(I18n.t("top.new_project_ready", {"path": p.get_path()}))

func _open_import_dialog() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.title = I18n.t("top.import_dialog_title")
	dlg.dir_selected.connect(func(path):
		dlg.queue_free()
		_scan_and_confirm_import(path))
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func _scan_and_confirm_import(path: String) -> void:
	var importer := RetroImporter.new()
	var scan: Dictionary = importer.scan(path, "")
	if not bool(scan.get("ok", false)):
		_alert(I18n.t("top.import_failed"), String(scan.get("error", I18n.t("top.import_error"))))
		return
	var detected := String(scan.get("platform", platform))
	var make_names: Array = []
	for m in scan.get("makefiles", []):
		make_names.append(String(m.get("name", "")))
	var summary := "%s\n%s\n%s\n%s\n%s\n%s\n\n%s" % [
		I18n.t("top.scan_detected", {"platform": I18n.platform_label(detected)}),
		I18n.t("top.scan_build", {"system": String(scan.get("build_system", "")), "file": String(scan.get("build_file", ""))}),
		I18n.t("top.scan_sdk", {"sdk": String(scan.get("sdk_version", I18n.t("top.not_detected")))}),
		I18n.t("top.scan_resources", {"count": int(scan.get("resource_count", 0)), "editable": _count_editable(scan.get("resources", []))}),
		I18n.t("top.scan_sources", {"count": int(scan.get("source_count", 0))}),
		I18n.t("top.scan_rom", {"rom": String(scan.get("rom_path", "")).get_file() if String(scan.get("rom_path", "")) != "" else I18n.t("top.none_built")}),
		I18n.t("top.scan_files", {"files": ", ".join(PackedStringArray(make_names))})]
	var warnings: Array = scan.get("warnings", [])
	if not warnings.is_empty():
		summary += "\n\n%s\n- " % I18n.t("top.scan_readonly") + "\n- ".join(PackedStringArray(warnings.slice(0, 8)))
		summary += "\n\n" + I18n.t("top.scan_note")
	var confirm := ConfirmationDialog.new()
	confirm.title = I18n.t("top.import_title")
	confirm.dialog_text = summary
	var copy_check := CheckBox.new()
	copy_check.text = I18n.t("top.copy_check")
	copy_check.button_pressed = true
	confirm.add_child(copy_check)
	confirm.confirmed.connect(func():
		var workspace := _ensure_workspaces_ignored()
		status_message(I18n.t("top.importing", {"path": path}))
		var p: RetroProject = importer.import_project(path, detected, workspace, copy_check.button_pressed, "")
		if p == null:
			_alert(I18n.t("top.import_failed"), I18n.t("top.import_no_project"))
			confirm.queue_free()
			return
		projects.append(p)
		var paths: Array = config.get_value("retro", "projects", [])
		paths.append(p.metadata_path())
		config.set_value("retro", "projects", paths)
		config.set_value("retro", "last_project", p.metadata_path())
		config.save(CONFIG_PATH)
		_project_option.add_item(p.get_name())
		_project_option.select(_project_option.item_count - 1)
		_select_project(p)
		_auto_open_first()
		status_message(I18n.t("top.imported", {"source": path, "dest": p.get_path()}))
		confirm.queue_free())
	confirm.canceled.connect(func(): confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered(Vector2i(760, 500))

func _count_editable(list: Array) -> int:
	var n := 0
	for r in list:
		if bool(r.get("editable", false)):
			n += 1
	return n

func _open_sdk_downloader() -> void:
	var dlg = SDKDownloader.new()
	add_child(dlg)
	dlg.status.connect(status_message)
	dlg.installed.connect(func(target: String, path: String):
		var probe: Dictionary = RetroSDK.probe_snes(path) if target == "snes" else RetroSDK.probe_megadrive(path)
		if target == "snes":
			snes_info = probe
			config.set_value("retro", "sdk_snes", path)
		else:
			md_info = probe
			config.set_value("retro", "sdk_md", path)
		config.save(CONFIG_PATH)
		_update_sdk_label()
		status_message(I18n.t("top.sdk_detected", {"path": path})))
	dlg.popup_centered(Vector2i(780, 460))

func _open_sdk_dialog() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.title = I18n.t("top.sdk_dialog_title", {"sdk": I18n.t("top.sdk_dialog_snes") if platform == "snes" else I18n.t("top.sdk_dialog_md")})
	dlg.dir_selected.connect(func(path):
		RetroSDK.configure(platform, path)
		var probe: Dictionary = RetroSDK.probe_snes(path) if platform == "snes" else RetroSDK.probe_megadrive(path)
		if not bool(probe.get("found", false)):
			_alert(I18n.t("top.sdk_not_recognized_title"), I18n.t("top.sdk_not_recognized_text", {"path": path}))
			dlg.queue_free()
			return
		if platform == "snes":
			snes_info = probe
			config.set_value("retro", "sdk_snes", path)
		else:
			md_info = probe
			config.set_value("retro", "sdk_md", path)
		config.save(CONFIG_PATH)
		_update_sdk_label()
		status_message(I18n.t("top.sdk_configured", {"path": path}))
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func build_active() -> void:
	_tabs.current_tab = 6
	build_panel.start_build(false, false)

func run_active() -> void:
	build_panel.run_current()

func _on_rom_built(path: String) -> void:
	_last_rom = path
	_last_rom_size = FileAccess.get_size(path)
	_rom_label.text = "%s  %s" % [path.get_file(), _size_text(_last_rom_size)]
	hardware_monitor.refresh(stage_doc, sprite_doc, anim_doc, _last_rom_size)
	status_message(I18n.t("top.rom_built", {"rom": path, "size": _size_text(_last_rom_size)}))

func _export_rom() -> void:
	if project == null or _last_rom == "" or not FileAccess.file_exists(_last_rom):
		_alert(I18n.t("top.no_rom_title"), I18n.t("top.no_rom_text"))
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.sfc,*.smc" if platform == "snes" else "*.md,*.gen,*.bin", "ROM image")
	dlg.current_file = _last_rom.get_file()
	dlg.file_selected.connect(func(path):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var err: int = DirAccess.copy_absolute(_last_rom, path)
		if err == OK:
			# Keep the validated platform profile next to the exported ROM so a
			# later rebuild can reproduce the exact same generation settings.
			var profile := _find_export_profile(_last_rom)
			if not profile.is_empty():
				var profile_out: String = String(path).get_basename() + ".profile.json"
				DirAccess.copy_absolute(profile, profile_out)
				status_message(I18n.t("top.rom_exported_profile", {"path": path, "profile": profile_out.get_file()}))
			else:
				status_message(I18n.t("top.rom_exported", {"path": path}))
		else:
			_alert(I18n.t("top.export_failed_title"), I18n.t("top.export_failed_text", {"path": path}))
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _find_export_profile(rom: String) -> String:
	var dir := rom.get_base_dir()
	var direct := dir.path_join("export_profile.json")
	if FileAccess.file_exists(direct):
		return direct
	# Mega Drive ROMs live in <project>/out/rom.bin.
	var parent := dir.get_base_dir().path_join("export_profile.json")
	return parent if FileAccess.file_exists(parent) else ""

func _open_error(file: String, line: int, column: int) -> void:
	if file.is_empty():
		return
	code_panel.open_file(file, line, column)
	_tabs.current_tab = 5

func status_message(text: String) -> void:
	if _status:
		_status.text = text

func refresh_all() -> void:
	_update_sdk_label()
	_refresh_emulators()
	if project:
		_refresh_resource_tree()
		hardware_monitor.refresh(stage_doc, sprite_doc, anim_doc, _last_rom_size)

func _alert(title: String, text: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = title
	dlg.dialog_text = text
	add_child(dlg)
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered()

func _size_text(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.2f MiB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%.1f KiB" % (bytes / 1024.0)
	return str(bytes) + " B"
