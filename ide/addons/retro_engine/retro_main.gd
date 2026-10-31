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
const MugenTools = preload("res://addons/retro_engine/mugen_tools.gd")
const MugenDef = preload("res://addons/retro_engine/mugen_def.gd")
const NativeBridgeEditor = preload("res://addons/retro_engine/native_bridge.gd")
const AudioEditor = preload("res://addons/retro_engine/audio_editor.gd")
const SDKDownloader = preload("res://addons/retro_engine/sdk_downloader.gd")
const WindowControls = preload("res://addons/retro_engine/window_controls.gd")
const RomPreview = preload("res://addons/retro_engine/rom_preview.gd")
const PadControls = preload("res://addons/retro_engine/pad_controls.gd")
const IMAGE_EXTS := ["png", "bmp", "webp", "jpg", "jpeg", "tga", "gif"]

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
var _mugen_defs: Array = []
var _mugen_scan_root: String = ""

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
var _game_status: Label
var _game_pause: Button
var _game_speed: OptionButton
var _game_log: RichTextLabel
var _pad
var _preview_pending_start := false
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
var mugen_tools
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
	var audio_menu := MenuButton.new()
	audio_menu.text = I18n.t("top.audio_browser")
	audio_menu.tooltip_text = I18n.t("top.audio_browser_tip")
	var audio_popup := audio_menu.get_popup()
	audio_popup.add_item(I18n.t("top.audio_open"), 0)
	audio_popup.add_item(I18n.t("top.audio_bgm"), 1)
	audio_popup.add_item(I18n.t("top.audio_sfx"), 2)
	audio_popup.add_separator()
	audio_popup.add_item(I18n.t("top.audio_play"), 3)
	audio_popup.add_item(I18n.t("top.audio_stop"), 4)
	audio_popup.id_pressed.connect(_on_audio_menu)
	top.add_child(audio_menu)
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
	animation_editor.sprite_modified.connect(_on_animation_sprite_modified)
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
	mugen_tools = MugenTools.new()
	mugen_tools.name = "MUGEN Tools"
	mugen_tools.status.connect(status_message)
	mugen_tools.modified.connect(_on_document_modified)
	mugen_tools.assets_imported.connect(_on_mugen_assets_imported)
	mugen_tools.page_changed.connect(_on_mugen_page_changed)
	mugen_tools.char_def_requested.connect(_on_mugen_char_def_requested)
	mugen_tools.sound_imported.connect(_on_mugen_sound_imported)
	_tabs.add_child(mugen_tools)
	input_editor = InputEditor.new()
	input_editor.name = "Inputs"
	input_editor.modified.connect(_on_document_modified)
	input_editor.input_changed.connect(_on_input_changed)
	input_editor.status.connect(status_message)
	mugen_tools.add_tool_page("inputs", "Inputs", input_editor)
	state_simulator = StateSimulator.new()
	state_simulator.name = "Simulator"
	state_simulator.status.connect(status_message)
	state_simulator.state_changed.connect(_on_sim_state_changed)
	mugen_tools.add_tool_page("simulator", "Simulator", state_simulator)
	state_graph = StateGraphEditor.new()
	state_graph.name = "StateGraph"
	state_graph.modified.connect(_on_graph_modified)
	state_graph.status.connect(status_message)
	mugen_tools.add_tool_page("graph", "State Graph", state_graph)
	collision_editor = CollisionEditor.new()
	collision_editor.name = "Hitboxes"
	collision_editor.modified.connect(_on_collision_modified)
	collision_editor.status.connect(status_message)
	mugen_tools.add_tool_page("hitboxes", "Hitboxes", collision_editor)
	mugen_editor = MugenEditor.new()
	mugen_editor.name = "MUGEN Import"
	mugen_editor.status.connect(status_message)
	mugen_editor.modified.connect(_on_mugen_modified)
	mugen_editor.graph_built.connect(_on_mugen_graph_built)
	mugen_editor.state_imported.connect(_on_mugen_state_imported)
	mugen_editor.states_imported.connect(_on_mugen_states_imported)
	mugen_tools.add_tool_page("import", "Import / States", mugen_editor)
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
	_tabs.set_tab_title(7, "MUGEN Tools")
	_tabs.set_tab_title(8, I18n.t("tabs.audio"))
	_tabs.set_tab_title(9, I18n.t("tabs.native"))

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
	var note := Label.new()
	note.text = I18n.t("preview.note")
	note.add_theme_color_override("font_color", Color("#ffd45e"))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.tooltip_text = note.text
	preview_box.add_child(note)
	var game_row := HBoxContainer.new()
	preview_box.add_child(game_row)
	var power := Button.new()
	power.text = I18n.t("preview.power")
	power.tooltip_text = I18n.t("preview.power_tip")
	power.pressed.connect(func(): _preview.power_on())
	game_row.add_child(power)
	var build := Button.new()
	build.text = I18n.t("preview.build_rom")
	build.tooltip_text = I18n.t("preview.build_rom_tip")
	build.pressed.connect(_on_preview_build_requested)
	game_row.add_child(build)
	_game_pause = Button.new()
	_game_pause.text = I18n.t("preview.pause")
	_game_pause.tooltip_text = I18n.t("preview.pause_tip")
	_game_pause.pressed.connect(func(): _preview.toggle_pause())
	game_row.add_child(_game_pause)
	var step := Button.new()
	step.text = I18n.t("preview.step")
	step.tooltip_text = I18n.t("preview.step_tip")
	step.pressed.connect(func(): _preview.step_frames(1))
	game_row.add_child(step)
	var step10 := Button.new()
	step10.text = I18n.t("preview.step10")
	step10.pressed.connect(func(): _preview.step_frames(10))
	game_row.add_child(step10)
	var rewind := Button.new()
	rewind.text = I18n.t("preview.rewind")
	rewind.tooltip_text = I18n.t("preview.rewind_tip")
	rewind.pressed.connect(func(): _preview.rewind_frames(1))
	game_row.add_child(rewind)
	var rewind10 := Button.new()
	rewind10.text = I18n.t("preview.rewind10")
	rewind10.pressed.connect(func(): _preview.rewind_frames(10))
	game_row.add_child(rewind10)
	var reset := Button.new()
	reset.text = I18n.t("preview.reset")
	reset.pressed.connect(func(): _preview.reset())
	game_row.add_child(reset)
	var options_row := HBoxContainer.new()
	preview_box.add_child(options_row)
	var audio_check := CheckBox.new()
	audio_check.text = I18n.t("preview.audio")
	audio_check.tooltip_text = I18n.t("preview.audio_tip")
	audio_check.button_pressed = true
	audio_check.toggled.connect(func(v): _preview.set_audio_enabled(v))
	options_row.add_child(audio_check)
	var pause_input := CheckBox.new()
	pause_input.text = I18n.t("preview.pause_after_input")
	pause_input.tooltip_text = I18n.t("preview.pause_after_input_tip")
	pause_input.toggled.connect(func(v): _preview.pause_on_input = v)
	options_row.add_child(pause_input)
	var pause_change := CheckBox.new()
	pause_change.text = I18n.t("preview.pause_on_change")
	pause_change.tooltip_text = I18n.t("preview.pause_on_change_tip")
	pause_change.button_pressed = true
	pause_change.toggled.connect(func(v): _preview.pause_on_change = v)
	options_row.add_child(pause_change)
	var speed_label := Label.new()
	speed_label.text = I18n.t("preview.speed")
	options_row.add_child(speed_label)
	_game_speed = OptionButton.new()
	for label in ["1x", "0.5x", "0.25x", "0.1x"]:
		_game_speed.add_item(label)
	_game_speed.item_selected.connect(func(idx): _preview.set_speed([1.0, 0.5, 0.25, 0.1][clampi(idx, 0, 3)]))
	options_row.add_child(_game_speed)
	_game_status = Label.new()
	_game_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_status.custom_minimum_size.x = 0
	_game_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_game_status.clip_text = true
	_game_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_game_status.add_theme_color_override("font_color", Color("#7fd1ff"))
	options_row.add_child(_game_status)
	var game_hint := Label.new()
	game_hint.text = I18n.t("preview.input_hint")
	game_hint.add_theme_color_override("font_color", Color("#8b98ad"))
	game_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_box.add_child(game_hint)
	_preview = RomPreview.new()
	_preview.name = "RomPreview"
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.status.connect(status_message)
	_preview.state_changed.connect(_on_game_status_changed)
	_preview.pause_changed.connect(_on_game_pause_changed)
	_preview.log_changed.connect(_refresh_game_log)
	_preview.build_requested.connect(_on_preview_build_requested)
	preview_box.add_child(_preview)
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 5)
	preview_box.add_child(bottom_row)
	var log_col := VBoxContainer.new()
	log_col.add_theme_constant_override("separation", 2)
	log_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(log_col)
	var log_row := HBoxContainer.new()
	log_col.add_child(log_row)
	var log_title := Label.new()
	log_title.text = I18n.t("preview.log")
	log_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_title.add_theme_color_override("font_color", Color("#7fd1ff"))
	log_row.add_child(log_title)
	var clear_log := Button.new()
	clear_log.text = I18n.t("preview.clear_log")
	clear_log.pressed.connect(func():
		if _preview:
			_preview.clear_log())
	log_row.add_child(clear_log)
	_game_log = RichTextLabel.new()
	_game_log.custom_minimum_size.y = 72
	_game_log.scroll_following = true
	_game_log.selection_enabled = true
	_game_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_col.add_child(_game_log)
	_pad = PadControls.new()
	_pad.set_preview(_preview)
	_pad.set_platform(platform)
	bottom_row.add_child(_pad)
	_refresh_game_log()
	_tabs.tab_changed.connect(_on_tab_changed)

func _on_tab_changed(index: int) -> void:
	if _preview:
		_preview.set_active(index == 0)

func _on_game_status_changed(text: String) -> void:
	if _game_status:
		_game_status.text = text

func _on_game_pause_changed(is_paused: bool) -> void:
	if _game_pause:
		_game_pause.text = I18n.t("preview.resume") if is_paused else I18n.t("preview.pause")

func _on_preview_build_requested() -> void:
	if project == null:
		status_message(I18n.t("audio.project_missing"))
		return
	_preview_pending_start = true
	_tabs.current_tab = 6
	build_panel.start_build(false, false)

func _refresh_game_log() -> void:
	if _game_log and _preview:
		_game_log.text = _preview.get_log_text()

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
	if _pad:
		_pad.set_platform(p)
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
	if _preview:
		_preview.set_input_map(input_editor.get_input_map() if input_editor else null)
		_preview.set_project(project)
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

static func resource_category(r: Dictionary) -> String:
	var editor := String(r.get("editor", "none"))
	var ext := String(r.get("ext", "")).to_lower()
	if ext.is_empty():
		ext = String(r.get("rel_path", "")).get_extension().to_lower()
	if editor == "sprite":
		return "Sprites"
	if editor == "stage":
		# A plain tileset PNG without a companion map is a tile sheet, not a
		# full stage yet.
		if ext in ["png", "bmp", "webp"] and String(r.get("map_path", "")).is_empty():
			return "Tiles"
		return "Stages"
	if editor == "image" or (editor == "none" and ext in IMAGE_EXTS):
		var lower := String(r.get("rel_path", r.get("name", ""))).to_lower()
		if _looks_like_tileset(lower):
			return "Tiles"
		if _looks_like_sprite_sheet(r):
			return "Sprites"
		return "Images"
	if editor == "palette":
		return "Palettes"
	if editor == "animation":
		return "Animations"
	if editor == "code":
		return "Code"
	if editor == "resources":
		return "Resources"
	if editor == "audio":
		return "Audio"
	if not bool(r.get("editable", false)):
		return "Read-only"
	return "Other"

static func _looks_like_tileset(lower: String) -> bool:
	for hint in ["tile", "tileset", "bg", "background", "stage", "ground", "deco", "parallax", "level", "font"]:
		if lower.contains(hint):
			return true
	return false

static func _looks_like_sprite_sheet(r: Dictionary) -> bool:
	if bool(r.get("has_alpha", false)) or bool(r.get("palette_key", false)):
		return true
	var lower := String(r.get("rel_path", r.get("name", ""))).to_lower()
	for hint in ["sprite", "char", "player", "enemy", "obj", "hero", "npc", "monster", "ghost", "gato", "boss", "skel"]:
		if lower.contains(hint):
			return true
	var w := int(r.get("width", 0))
	var h := int(r.get("height", 0))
	if w > 0 and h > 0 and String(r.get("map_path", "")).is_empty():
		# Horizontal/vertical strips are sprite sheets even when the indexed
		# PNG has no alpha channel (transparency is palette index 0).
		if w >= h * 2 or h >= w * 2:
			return true
	return false

func _refresh_resource_tree() -> void:
	_resource_tree.clear()
	var root := _resource_tree.create_item()
	var categories := {
		"Sprites": [], "Tiles": [], "Images": [], "Stages": [], "Palettes": [], "Animations": [],
		"Code": [], "Resources": [], "Audio": [], "Read-only": [], "Other": [],
	}
	var category_labels := {
		"Sprites": I18n.t("resources.sprites"),
		"Tiles": "Tiles / Tilesets",
		"Images": I18n.t("resources.images"),
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
		var key := resource_category(r)
		categories[key].append(i)
	_scan_mugen_defs()
	var mugen_visible := false
	for d in _mugen_defs:
		if filter == "" or String(d.get("path", "")).to_lower().contains(filter) or String(d.get("name", "")).to_lower().contains(filter):
			mugen_visible = true
			break
	for key in ["Sprites", "Tiles", "Images", "Stages", "Palettes", "Animations", "Code", "Resources", "Audio", "Read-only", "Other"]:
		var list: Array = categories[key]
		if key == "Sprites":
			if list.is_empty() and not mugen_visible:
				continue
			var cat := _resource_tree.create_item(root)
			var count := list.size()
			cat.set_text(0, "%s (%d)" % [String(category_labels.get(key, key)), count] if count > 0 else String(category_labels.get(key, key)))
			cat.set_selectable(0, false)
			_build_mugen_tree(cat, filter)
			for idx in list:
				_add_resource_item(cat, idx)
			continue
		if list.is_empty():
			continue
		var cat := _resource_tree.create_item(root)
		cat.set_text(0, "%s (%d)" % [String(category_labels.get(key, key)), list.size()])
		cat.set_selectable(0, false)
		for idx in list:
			_add_resource_item(cat, idx)

func _add_resource_item(cat: TreeItem, idx: int) -> void:
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

func _scan_mugen_defs() -> void:
	if project == null:
		_mugen_defs.clear()
		_mugen_scan_root = ""
		return
	var root := project.get_path()
	if root == _mugen_scan_root:
		return
	_mugen_scan_root = root
	_mugen_defs.clear()
	var seen: Dictionary = {}
	for d in ["assets/characters", "assets/stages", "chars", "stages", "data", "assets"]:
		_scan_def_dir(root.path_join(d), 0, seen)
	_scan_def_dir(root, 0, seen)

func _scan_def_dir(dir: String, depth: int, seen: Dictionary) -> void:
	if depth > 7 or dir.is_empty():
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	while true:
		var name := da.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var path := dir.path_join(name)
		if da.current_is_dir():
			if name in ["build", "workspaces", "node_modules", "backup", ".godot"]:
				continue
			_scan_def_dir(path, depth + 1, seen)
		elif name.get_extension().to_lower() == "def":
			var key := path.simplify_path()
			if seen.has(key):
				continue
			seen[key] = true
			var def = MugenDef.new()
			if not def.load_file(path):
				continue
			if def.is_character():
				var files := def.character_files()
				_mugen_defs.append({
					"kind": "char", "path": path, "name": def.display_name(),
					"sff": String(files.get("sprite", "")), "anim": String(files.get("anim", "")),
					"snd": String(files.get("sound", "")),
				})
			elif def.is_stage():
				_mugen_defs.append({
					"kind": "stage", "path": path, "name": def.display_name(),
					"sff": def.stage_sprite_file(), "anim": "", "snd": "",
				})
	da.list_dir_end()

func _build_mugen_tree(root: TreeItem, filter: String) -> void:
	if _mugen_defs.is_empty():
		return
	var chars: Array = []
	var stages: Array = []
	for d in _mugen_defs:
		if filter != "" and not String(d.get("path", "")).to_lower().contains(filter) and not String(d.get("name", "")).to_lower().contains(filter):
			continue
		if String(d.get("kind", "")) == "char":
			chars.append(d)
		else:
			stages.append(d)
	if not chars.is_empty():
		var cat := _resource_tree.create_item(root)
		cat.set_text(0, "MUGEN Chars (%d)" % chars.size())
		cat.set_selectable(0, false)
		for d in chars:
			var item := _resource_tree.create_item(cat)
			item.set_text(0, String(d.get("name", d.get("path", "").get_file())))
			item.set_tooltip_text(0, String(d.get("path", "")))
			item.set_metadata(0, {"mugen": "char", "path": d.get("path", ""), "action": -1})
			var anim := _resource_tree.create_item(item)
			anim.set_text(0, "Animations")
			anim.set_metadata(0, {"mugen": "char", "path": d.get("path", ""), "action": -1})
			var sff := _resource_tree.create_item(item)
			sff.set_text(0, "SFF")
			sff.set_metadata(0, {"mugen": "sff", "path": d.get("sff", "")})
			if not String(d.get("snd", "")).is_empty():
				var snd := _resource_tree.create_item(item)
				snd.set_text(0, "SND")
				snd.set_metadata(0, {"mugen": "snd", "path": d.get("snd", "")})
	if not stages.is_empty():
		var cat := _resource_tree.create_item(root)
		cat.set_text(0, "MUGEN Stages (%d)" % stages.size())
		cat.set_selectable(0, false)
		for d in stages:
			var item := _resource_tree.create_item(cat)
			item.set_text(0, String(d.get("name", d.get("path", "").get_file())))
			item.set_tooltip_text(0, String(d.get("path", "")))
			item.set_metadata(0, {"mugen": "stage", "path": d.get("path", "")})
			var layers := _resource_tree.create_item(item)
			layers.set_text(0, "Layers")
			layers.set_metadata(0, {"mugen": "stage", "path": d.get("path", "")})
			var sff := _resource_tree.create_item(item)
			sff.set_text(0, "SFF")
			sff.set_metadata(0, {"mugen": "sff", "path": d.get("sff", "")})

func _on_resource_selected() -> void:
	var item := _resource_tree.get_selected()
	if item == null:
		return
	var idx = item.get_metadata(0)
	if idx == null:
		return
	if idx is Dictionary and idx.has("mugen"):
		_show_mugen_info(idx)
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
	txt += "Kind: %s | Editor: %s | Category: %s | Editable: %s\n" % [String(r.get("kind", "")), String(r.get("editor", "")), resource_category(r), editable]
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
	if idx is Dictionary and idx.has("mugen"):
		_open_mugen_meta(idx)
	elif idx != null:
		_open_resource(int(idx))

func _open_selected_as(kind: String) -> void:
	var item := _resource_tree.get_selected()
	if item == null:
		return
	var idx = item.get_metadata(0)
	if idx is Dictionary and idx.has("mugen"):
		if kind == "stage" or String(idx.get("mugen", "")) == "stage":
			_open_mugen_meta({"mugen": "stage", "path": idx.get("path", "")})
		else:
			_open_mugen_meta({"mugen": "char", "path": idx.get("path", ""), "action": -1})
		return
	if idx == null:
		return
	_open_resource(int(idx), kind)

func _show_mugen_info(meta: Dictionary) -> void:
	var path := String(meta.get("path", ""))
	_info_title.text = path.get_file()
	var kind := String(meta.get("mugen", ""))
	_inspector.text = "[b]%s[/b]\nMUGEN %s\n%s" % [path.get_file(), kind, path]

func _open_mugen_meta(meta: Dictionary) -> void:
	if mugen_tools == null:
		return
	var kind := String(meta.get("mugen", ""))
	var path := String(meta.get("path", ""))
	if path.is_empty():
		return
	_tabs.current_tab = 7
	match kind:
		"char":
			mugen_tools.open_char(path, int(meta.get("action", -1)))
		"stage":
			mugen_tools.open_stage(path)
		"sff":
			mugen_tools.open_sff(path)
		"snd":
			mugen_tools.open_snd(path)

func _on_audio_menu(id: int) -> void:
	match id:
		0:
			_open_audio_browser("")
		1:
			_open_audio_browser("bgm")
		2:
			_open_audio_browser("sfx")
		3:
			if audio_editor != null:
				audio_editor.play_selected()
		4:
			if audio_editor != null:
				audio_editor.stop_preview()

func _open_audio_browser(kind: String) -> void:
	if project == null:
		status_message(I18n.t("audio.project_missing"))
		return
	if audio_editor != null:
		audio_editor.set_project(project)
		audio_editor.set_kind_filter(kind)
		_tabs.current_tab = 8
		audio_editor.focus_search()
	status_message(I18n.t("top.audio_browser_status"))

func _open_resource(index: int, force_kind: String = "") -> void:
	if index < 0 or index >= resources.size():
		return
	var r: Dictionary = resources[index]
	current_resource = r
	code_panel.set_resource(r)
	_show_resource_info(r)
	var ext := String(r.get("ext", "")).to_lower()
	if ext.is_empty():
		ext = String(r.get("path", "")).get_extension().to_lower()
	var editor := force_kind if force_kind != "" else String(r.get("editor", ""))
	if ext == "sff" or ext == "air":
		_show_readonly_dialog(String(r.get("name", "")), String(r.get("note", "")))
		return
	if ext == "pal" and (editor == "palette" or force_kind == "palette"):
		_open_palette_file(String(r.get("path", "")))
		return
	if ext in ["png", "bmp", "webp", "jpg", "jpeg", "tga", "gif", "chr", "pic"]:
		if editor == "stage":
			stage_editor.open_resource(r, project)
			stage_doc = stage_editor.stage
			_tabs.current_tab = 2
			_refresh_preview()
			hardware_monitor.refresh(stage_doc, sprite_doc, anim_doc, _last_rom_size)
		elif editor == "image" or (editor == "none" and ext in IMAGE_EXTS):
			# Never open a floating preview: select the asset in a real editor
			# tab. Tile-like sheets go to the Stage tab; sprite-like sheets go
			# to the Sprite tab, so the Anim tab immediately follows them.
			if resource_category(r) == "Tiles":
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
			audio_editor.select_asset(String(r.get("path", "")), true)
			_tabs.current_tab = 8
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

func _on_animation_sprite_modified() -> void:
	# The Anim tab can auto-slice a full sprite sheet; refresh the Sprite tab
	# and every preview so the new frames are visible immediately.
	if sprite_editor:
		sprite_doc = sprite_editor.sprite
		sprite_editor.set_sprite(sprite_doc, project)
	_refresh_preview()
	hardware_monitor.refresh(stage_doc, sprite_doc, anim_doc, _last_rom_size)
	if _save_timer:
		_save_timer.start()
	status_message("Sprite sheet split into frames by transparency.")

func _on_collision_modified() -> void:
	if _save_timer:
		_save_timer.start()
	if animation_editor and anim_doc:
		animation_editor.set_animation(anim_doc)
	if stage_editor:
		stage_editor.set_sprite(sprite_doc, anim_doc)
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
	if _preview and input_editor:
		_preview.set_input_map(input_editor.get_input_map())

func _on_mugen_sound_imported(path: String) -> void:
	if project == null:
		return
	resources = project.get_resources()
	_refresh_resource_tree()
	if audio_editor:
		audio_editor.set_project(project)
	status_message("MUGEN sound imported: " + path.get_file())

func _on_mugen_char_def_requested(path: String) -> void:
	if mugen_editor and not path.is_empty():
		mugen_editor.load_char_def(path)

func _on_mugen_page_changed(id: String) -> void:
	if mugen_tools == null:
		return
	var imap: RetroInputMap = input_editor.get_input_map() if input_editor else null
	match id:
		"inputs":
			if input_editor:
				input_editor.set_context(project, platform, anim_doc)
		"simulator":
			if state_simulator:
				state_simulator.set_context(project, platform, anim_doc, sprite_doc)
				if imap:
					state_simulator.set_input_map(imap)
		"graph":
			if state_graph:
				state_graph.set_context(project, platform, imap, anim_doc)
		"hitboxes":
			if collision_editor:
				collision_editor.set_context(project, platform, sprite_doc, anim_doc)
		"import":
			if mugen_editor:
				mugen_editor.set_context(project, platform, anim_doc, imap)

func _on_mugen_assets_imported(result: Dictionary) -> void:
	if project == null:
		return
	resources = project.get_resources()
	_refresh_resource_tree()
	_restore_session_docs()
	_on_document_modified()
	if result.has("sprite"):
		_tabs.current_tab = 1
	elif result.has("stage_json"):
		_tabs.current_tab = 2
	status_message("MUGEN assets imported into the project.")

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
	if mugen_tools:
		mugen_tools.set_context(project, platform, anim_doc, sprite_doc,
			input_editor.get_input_map() if input_editor else null)
	if stage_editor:
		stage_editor.set_sprite(sprite_doc, anim_doc)
	if _preview == null:
		return
	_preview.set_platform(platform)
	_preview.set_input_map(input_editor.get_input_map() if input_editor else null)
	_preview.set_project(project)
	if _pad:
		_pad.set_preview(_preview)
		_pad.set_platform(platform)
	_refresh_game_log()

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
	if _preview:
		_preview.set_project(project)
		if _preview_pending_start or _tabs.current_tab == 0:
			_preview_pending_start = false
			_tabs.current_tab = 0

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
