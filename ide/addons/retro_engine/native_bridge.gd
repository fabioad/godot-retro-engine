@tool
extends VBoxContainer
## Native Godot scene/resource bridge.
##
## Traverses the scene currently open in the Godot editor, converts Sprite2D /
## AnimatedSprite2D / Sprite3D / AnimatedSprite3D nodes into RetroSprite and
## RetroAnimation documents, captures 2D/3D views into SNES/Mega Drive tilemaps,
## and writes a C actor table for the native scene. Generated files live in the
## retro project only; the Godot scene/resource is never modified.

signal modified()
signal status(text: String)

const I18n = preload("res://addons/retro_engine/i18n.gd")

# Compact 5x7 font used when a headless capture has to bake Godot Controls
# (labels, buttons, item lists) into the console background.
const UI_FONT := {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
	"0": ["01110", "10011", "10101", "10101", "10101", "11001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
	"6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	":": ["00000", "00100", "00100", "00000", "00100", "00100", "00000"],
	".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
	",": ["00000", "00000", "00000", "00000", "00110", "00100", "01000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"_": ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
	"/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
	"!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
	"?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"],
	"+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
	"(": ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
	")": ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
	"%": ["10001", "10010", "00100", "01000", "10001", "00001", "00000"],
}

var project: RetroProject
var platform: String = "snes"
var mode: String = "mode1"
var bridge: RetroNativeBridge

var _output: LineEdit
var _palette_colors: SpinBox
var _tile_size: SpinBox
var _capture_w: SpinBox
var _capture_h: SpinBox
var _bake_frames: SpinBox
var _profile_option: OptionButton
var _profile_info: Label
var _profile: String = ""
var _log: RichTextLabel
var _assets: Tree
var _last_scene: String = ""
var _last_result: Dictionary = {}
var _include_ui: CheckBox
var _include_nodes: CheckBox
var _include_scripts: CheckBox
var _game_scene: LineEdit
var _game_info: Label

func _ready() -> void:
	bridge = RetroNativeBridge.new()
	add_theme_constant_override("separation", 4)

	var head := HFlowContainer.new()
	add_child(head)
	var title := Label.new()
	title.text = I18n.t("native.title")
	title.add_theme_font_size_override("font_size", 14)
	title.custom_minimum_size.x = 280
	head.add_child(title)
	var current := Button.new()
	current.text = I18n.t("native.import_current")
	current.tooltip_text = I18n.t("native.import_current_tip")
	current.pressed.connect(_import_current_scene)
	head.add_child(current)
	var selected := Button.new()
	selected.text = I18n.t("native.import_selection")
	selected.tooltip_text = I18n.t("native.import_selection_tip")
	selected.pressed.connect(_import_selection)
	head.add_child(selected)
	var capture := Button.new()
	capture.text = I18n.t("native.capture_background")
	capture.tooltip_text = I18n.t("native.capture_background_tip")
	capture.pressed.connect(_capture_background)
	head.add_child(capture)
	var bake := Button.new()
	bake.text = I18n.t("native.bake_3d")
	bake.tooltip_text = I18n.t("native.bake_3d_tip")
	bake.pressed.connect(_bake_3d)
	head.add_child(bake)
	var export3d := Button.new()
	export3d.text = "Export 3D (Super FX / 32X)"
	export3d.tooltip_text = "Write mesh data and a co-processor scaffold for the selected 3D profile."
	export3d.pressed.connect(_export_3d_pack)
	head.add_child(export3d)

	var options := HFlowContainer.new()
	add_child(options)
	options.add_child(_label(I18n.t("native.output")))
	_output = LineEdit.new()
	_output.text = "native"
	_output.custom_minimum_size.x = 130
	_output.tooltip_text = I18n.t("native.output_tip")
	options.add_child(_output)
	options.add_child(_label(I18n.t("native.colors")))
	_palette_colors = _spin(4, 16, 16)
	options.add_child(_palette_colors)
	options.add_child(_label(I18n.t("native.tile")))
	_tile_size = _spin(8, 16, 8)
	options.add_child(_tile_size)
	options.add_child(_label(I18n.t("native.capture")))
	_capture_w = _spin(64, 1024, 256)
	_capture_h = _spin(64, 1024, 224)
	options.add_child(_capture_w)
	options.add_child(_label("x"))
	options.add_child(_capture_h)
	options.add_child(_label(I18n.t("native.frames_3d")))
	_bake_frames = _spin(1, 64, 8)
	options.add_child(_bake_frames)
	options.add_child(_label(I18n.t("native.chip_3d")))
	_profile_option = OptionButton.new()
	_profile_option.add_item(I18n.t("native.none"), 0)
	_profile_option.add_item(I18n.t("native.superfx"), 1)
	_profile_option.add_item(I18n.t("native.svp"), 2)
	_profile_option.add_item("Sega 32X (SH-2)", 3)
	_profile_option.item_selected.connect(_on_profile_selected)
	options.add_child(_profile_option)
	_profile_info = Label.new()
	_profile_info.text = I18n.t("native.reference_none")
	_profile_info.add_theme_color_override("font_color", Color("#9fb4d0"))
	options.add_child(_profile_info)

	var game_row := HFlowContainer.new()
	add_child(game_row)
	game_row.add_child(_label(I18n.t("native.game_scene")))
	_game_scene = LineEdit.new()
	_game_scene.text = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	_game_scene.custom_minimum_size.x = 340
	_game_scene.placeholder_text = "res://scenes/game.tscn"
	_game_scene.tooltip_text = I18n.t("native.game_scene_tip")
	game_row.add_child(_game_scene)
	var use_current := Button.new()
	use_current.text = I18n.t("native.use_current")
	use_current.tooltip_text = I18n.t("native.use_current_tip")
	use_current.pressed.connect(_use_current_game_scene)
	game_row.add_child(use_current)
	var import_game := Button.new()
	import_game.text = I18n.t("native.import_game_scene")
	import_game.tooltip_text = I18n.t("native.import_game_scene_tip")
	import_game.pressed.connect(_import_game_scene)
	game_row.add_child(import_game)
	_game_info = Label.new()
	_game_info.add_theme_color_override("font_color", Color("#9fb4d0"))
	game_row.add_child(_game_info)
	_refresh_game_info()

	var port_row := HFlowContainer.new()
	add_child(port_row)
	port_row.add_child(_label(I18n.t("native.port_bundle")))
	_include_ui = _check(I18n.t("native.ui_layout"), true)
	_include_ui.tooltip_text = I18n.t("native.ui_layout_tip")
	port_row.add_child(_include_ui)
	_include_nodes = _check(I18n.t("native.other_nodes"), true)
	_include_nodes.tooltip_text = I18n.t("native.other_nodes_tip")
	port_row.add_child(_include_nodes)
	_include_scripts = _check(I18n.t("native.scripts"), true)
	_include_scripts.tooltip_text = I18n.t("native.scripts_tip")
	port_row.add_child(_include_scripts)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = false
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_log)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 300
	body.add_child(scroll)
	_assets = Tree.new()
	_assets.columns = 3
	_assets.hide_root = true
	_assets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_assets.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_assets.set_column_title(0, I18n.t("native.asset"))
	_assets.set_column_title(1, I18n.t("native.type"))
	_assets.set_column_title(2, I18n.t("native.path"))
	_assets.set_column_expand(0, true)
	_assets.set_column_expand(1, false)
	_assets.set_column_custom_minimum_width(1, 70)
	_assets.set_column_expand(2, true)
	_assets.custom_minimum_size = Vector2(280, 240)
	scroll.add_child(_assets)
	if OS.has_environment("RETRO_NATIVE_AUTO") and Engine.is_editor_hint():
		call_deferred("_auto_import")

func _auto_import() -> void:
	await get_tree().create_timer(2.0).timeout
	var root: Node = null
	for i in range(40):
		root = EditorInterface.get_edited_scene_root()
		if root != null:
			break
		await get_tree().create_timer(0.25).timeout
	if root == null:
		status.emit(I18n.t("native.no_root"))
		return
	var mode := OS.get_environment("RETRO_NATIVE_AUTO")
	await import_scene(root, mode == "capture", mode == "bake")

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _check(text: String, value: bool) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = value
	return box

func _refresh_game_info() -> void:
	if _game_info == null:
		return
	var path := _game_scene.text.strip_edges() if _game_scene else ""
	if path.is_empty():
		path = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	_game_info.text = I18n.t("native.game", {"path": path}) if not path.is_empty() else I18n.t("native.game_not_configured")

func _spin(minv: float, maxv: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minv
	spin.max_value = maxv
	spin.value = value
	spin.custom_minimum_size.x = 62
	return spin

func set_context(p_project: RetroProject, p_platform: String, p_mode: String) -> void:
	project = p_project
	platform = p_platform
	mode = p_mode
	_load_session()
	var saved := String(project.get_metadata().get("3d_profile", "")) if project else ""
	if not saved.is_empty():
		set_3d_profile(saved)
	elif not _profile.is_empty():
		set_3d_profile(_profile)

func set_mode(p_mode: String) -> void:
	mode = p_mode

func set_platform(p_platform: String) -> void:
	platform = p_platform

func get_last_result() -> Dictionary:
	return _last_result

func save_session() -> void:
	if project == null:
		return
	var dir := project.resolve(".retro/editor")
	DirAccess.make_dir_recursive_absolute(dir)
	var data := {
		"format": "godot-retro-engine/native-links",
		"version": 2,
		"output": _output.text,
		"last_scene": _last_scene,
		"3d_profile": _profile,
		"game_scene": _game_scene.text if _game_scene else "",
		"include_ui": _wants_ui(),
		"include_nodes": _wants_nodes(),
		"include_scripts": _wants_scripts(),
		"assets": _last_result.get("assets", []),
		"stage": _last_result.get("stage", {}),
		"port": _last_result.get("port", {}),
		"mesh_export": _last_result.get("mesh_export", {}),
		"scaffold": _last_result.get("scaffold", {}),
	}
	var f := FileAccess.open(dir.path_join("native_links.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func _load_session() -> void:
	if project == null:
		return
	var path := project.resolve(".retro/editor/native_links.json")
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) == typeof({}):
		_output.text = String(data.get("output", "native"))
		_last_scene = String(data.get("last_scene", ""))
		_profile = String(data.get("3d_profile", ""))
		var game_scene := String(data.get("game_scene", ""))
		if not game_scene.is_empty() and _game_scene:
			_game_scene.text = game_scene
		if _include_ui:
			_include_ui.button_pressed = bool(data.get("include_ui", true))
		if _include_nodes:
			_include_nodes.button_pressed = bool(data.get("include_nodes", true))
		if _include_scripts:
			_include_scripts.button_pressed = bool(data.get("include_scripts", true))
		_refresh_game_info()
		for a in data.get("assets", []):
			_add_asset_row(a)

func get_3d_profile() -> Dictionary:
	return bridge.get_3d_profile(_profile) if not _profile.is_empty() else Dictionary()

func get_3d_profile_id() -> String:
	return _profile

func set_3d_profile(id: String) -> void:
	_profile = id if (id == "superfx" or id == "svp" or id == "sega32x") else ""
	if _profile_option:
		_profile_option.select(1 if _profile == "superfx" else (2 if _profile == "svp" else (3 if _profile == "sega32x" else 0)))
	var profile: Dictionary = bridge.get_3d_profile(_profile) if not _profile.is_empty() else Dictionary()
	if profile.is_empty():
		if _profile_info:
			_profile_info.text = I18n.t("native.reference_none")
		if project:
			var meta := project.get_metadata()
			meta.erase("3d_profile")
			project.set_metadata(meta)
			project.save()
		return
	if _profile_info:
		_profile_info.text = "%s | %s | %s" % [String(profile.get("chip", "")), String(profile.get("clock", "")), String(profile.get("reference", ""))]
	if _capture_w:
		_capture_w.value = int(profile.get("max_capture_w", _capture_w.value))
		_capture_h.value = int(profile.get("max_capture_h", _capture_h.value))
		_palette_colors.value = int(profile.get("palette_colors", _palette_colors.value))
		_bake_frames.value = mini(8, int(profile.get("max_bake_frames", _bake_frames.value)))
	if project:
		var meta := project.get_metadata()
		meta["3d_profile"] = _profile
		project.set_metadata(meta)
		project.save()
	_log.text += "[color=#7fd1ff]%s[/color]\n" % I18n.t("native.reference", {"value": String(profile.get("name", ""))})
	status.emit("3D profile: " + String(profile.get("name", "")))

func _on_profile_selected(index: int) -> void:
	set_3d_profile("superfx" if index == 1 else ("svp" if index == 2 else ("sega32x" if index == 3 else "")))

func _wants_ui() -> bool:
	return _include_ui == null or _include_ui.button_pressed

func _wants_nodes() -> bool:
	return _include_nodes == null or _include_nodes.button_pressed

func _wants_scripts() -> bool:
	return _include_scripts == null or _include_scripts.button_pressed

func _use_current_game_scene() -> void:
	if not Engine.is_editor_hint():
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path.is_empty():
		status.emit(I18n.t("native.game_scene_open_first"))
		return
	_game_scene.text = root.scene_file_path
	_refresh_game_info()

func _import_game_scene() -> void:
	if not Engine.is_editor_hint():
		status.emit(I18n.t("native.game_scene_editor_only"))
		return
	var path := _game_scene.text.strip_edges() if _game_scene else ""
	if path.is_empty():
		path = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if path.is_empty():
		status.emit(I18n.t("native.game_scene_no_config"))
		return
	if not ResourceLoader.exists(path):
		status.emit(I18n.t("native.game_scene_not_found", {"path": path}))
		return
	_game_scene.text = path
	_refresh_game_info()
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != path:
		EditorInterface.open_scene_from_path(path)
		await get_tree().create_timer(0.7).timeout
		root = EditorInterface.get_edited_scene_root()
	if root == null:
		status.emit(I18n.t("native.game_scene_open_failed", {"path": path}))
		return
	await import_scene(root)

func _import_current_scene() -> void:
	if not Engine.is_editor_hint():
		status.emit(I18n.t("native.import_editor_only"))
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		status.emit(I18n.t("native.no_scene"))
		return
	await import_scene(root)

func _import_selection() -> void:
	if not Engine.is_editor_hint():
		status.emit(I18n.t("native.selection_editor_only"))
		return
	var nodes: Array = EditorInterface.get_selection().get_selected_nodes()
	if nodes.is_empty():
		status.emit(I18n.t("native.no_selection"))
		return
	var root: Node = nodes[0]
	await import_scene(root)

func _capture_background() -> void:
	if not Engine.is_editor_hint():
		status.emit(I18n.t("native.capture_editor_only"))
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		status.emit(I18n.t("native.no_scene"))
		return
	await import_scene(root, true, false)

func _bake_3d() -> void:
	if not Engine.is_editor_hint():
		status.emit("3D baking is available in the Godot editor.")
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		status.emit(I18n.t("native.bake_editor_only"))
		return
	if _profile.is_empty():
		set_3d_profile("superfx" if platform == "snes" else "sega32x")
	await import_scene(root, false, true)

func _export_3d_pack() -> void:
	if not Engine.is_editor_hint():
		status.emit("3D export is available in the Godot editor.")
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		status.emit(I18n.t("native.no_scene"))
		return
	if _profile.is_empty():
		set_3d_profile("superfx" if platform == "snes" else "sega32x")
	var result: Dictionary = await import_scene(root, false, false)
	var mesh: Dictionary = result.get("mesh_export", {})
	if bool(mesh.get("ok", false)):
		status.emit("3D pack: %d meshes, %d triangles" % [int(mesh.get("meshes", 0)), int(mesh.get("triangles", 0))])
	else:
		status.emit("No 3D mesh found in the edited scene.")

## Public entry point used by the editor and by headless regression tests.
func import_scene(root: Node, capture_background := false, bake_3d := false) -> Dictionary:
	var result := {"ok": false, "assets": [], "errors": []}
	if root == null:
		result["errors"].append(I18n.t("native.error_no_root"))
		return result
	if project == null:
		result["errors"].append(I18n.t("native.error_no_project"))
		return result
	if bake_3d and _profile.is_empty():
		set_3d_profile("superfx" if platform == "snes" else "sega32x")
	var scene_name := _slug(root.name if not root.name.is_empty() else "native_scene")
	var scene_source := ""
	if Engine.is_editor_hint():
		scene_source = root.scene_file_path if root.scene_file_path else ""
	_last_scene = scene_source
	var out_dir := _output.text.strip_edges()
	if out_dir.is_empty():
		out_dir = "native"
	var dir := project.resolve(out_dir).path_join(scene_name)
	DirAccess.make_dir_recursive_absolute(dir)
	var assets: Array = []
	var cameras: Array = []
	_walk(root, dir, assets, cameras)

	var stage_result: Dictionary = {}
	var bake_result: Dictionary = {}
	if bake_3d:
		var images := await _capture_views(root, Vector2i(int(_capture_w.value), int(_capture_h.value)), int(_bake_frames.value))
		if not images.is_empty():
			bake_result = _import_bake_sheet(scene_name, dir, images, scene_source, assets)
	elif capture_background:
		var images := await _capture_views(root, Vector2i(int(_capture_w.value), int(_capture_h.value)), 1)
		if not images.is_empty():
			stage_result = bridge.import_stage_image(
				images[0], scene_name + "_bg", dir, platform, mode,
				int(_tile_size.value), 1024, int(_palette_colors.value), scene_source)
			if bool(stage_result.get("ok", false)):
				result["stage"] = stage_result
				_register_paths([
					String(stage_result.get("tileset_png", "")),
					String(stage_result.get("stage_json", "")),
					String(Dictionary(stage_result.get("snes", {})).get("chr", "")),
					String(Dictionary(stage_result.get("snes", {})).get("pal", "")),
					String(Dictionary(stage_result.get("snes", {})).get("map", "")),
					String(Dictionary(stage_result.get("snes", {})).get("inc", "")),
					String(Dictionary(stage_result.get("sgdk", {})).get("png", "")),
					String(Dictionary(stage_result.get("sgdk", {})).get("res", "")),
				], "stage", scene_source)
				_add_asset_row({"name": scene_name + "_bg", "type": I18n.t("native.type_stage"), "path": String(Dictionary(stage_result.get("snes", {})).get("map", ""))})
			else:
				result["errors"].append(I18n.t("native.error_background", {"error": String(stage_result.get("error", "failed"))}))

	var layout := bridge.export_scene_layout(
		assets, {"name": scene_name, "source": scene_source,
			"width": int(_capture_w.value), "height": int(_capture_h.value)},
		dir.path_join(scene_name + "_scene.h"), platform)
	if bool(layout.get("ok", false)):
		result["layout"] = layout
		_register_paths([String(layout.get("header", "")), String(layout.get("json", ""))], "code", scene_source)

	var port: Dictionary = {}
	if _wants_ui() or _wants_nodes() or _wants_scripts():
		port = _write_port_bundle(root, scene_name, dir, scene_source, assets, cameras, stage_result, bake_result)
		if bool(port.get("ok", false)):
			result["port"] = port
			_register_paths([
				String(port.get("header", "")), String(port.get("json", "")),
				String(port.get("markdown", "")),
			], "code", scene_source)
			if not String(port.get("scripts_dir", "")).is_empty():
				var sd := DirAccess.open(String(port.get("scripts_dir", "")))
				if sd:
					for file in sd.get_files():
						_register_paths([String(port.get("scripts_dir", "")).path_join(file)], "code", scene_source)
			_add_asset_row({"name": scene_name + " port", "type": I18n.t("native.type_port"), "path": String(port.get("markdown", ""))})
		else:
			result["errors"].append(I18n.t("native.error_port", {"error": String(port.get("error", "failed"))}))

	var extra_log := ""
	if not _profile.is_empty() and (bake_3d or _has_3d_geometry(root)):
		var meshes: Array = _collect_3d_meshes(root) if _has_3d_geometry(root) else []
		var manifest := bridge.export_3d_manifest(_profile,
			{"name": scene_name, "source": scene_source, "width": int(_capture_w.value), "height": int(_capture_h.value)},
			assets, bake_result, dir.path_join(scene_name + "_3d_profile.h"))
		if bool(manifest.get("ok", false)):
			result["profile"] = manifest
			result["meshes"] = meshes
			_register_paths([String(manifest.get("header", "")), String(manifest.get("json", ""))], "code", scene_source)
			var handoff := _write_3d_handoff(scene_name, dir, manifest, bake_result, assets, meshes)
			result["handoff"] = handoff
			result["mesh_export"] = handoff.get("mesh", {})
			result["scaffold"] = handoff.get("scaffold", {})
			var mesh_export: Dictionary = result["mesh_export"]
			if bool(mesh_export.get("ok", false)):
				_register_paths([String(mesh_export.get("header", "")), String(mesh_export.get("json", ""))], "code", scene_source)
			var scaffold: Dictionary = result["scaffold"]
			if bool(scaffold.get("ok", false)):
				for path in scaffold.get("files", []):
					_register_paths([String(path)], "code", scene_source)
			_register_paths([String(handoff.get("markdown", "")), String(handoff.get("json", ""))], "code", scene_source)
			extra_log += "[color=#7fd1ff]3D chip reference: %s[/color]\n" % String(Dictionary(manifest.get("profile", {})).get("name", _profile))
			var mesh_export2: Dictionary = result.get("mesh_export", {})
			if bool(mesh_export2.get("ok", false)):
				extra_log += "3D mesh: %d meshes, %d triangles -> %s\n" % [int(mesh_export2.get("meshes", 0)), int(mesh_export2.get("triangles", 0)), String(mesh_export2.get("header", ""))]
			var scaffold2: Dictionary = result.get("scaffold", {})
			if bool(scaffold2.get("ok", false)):
				extra_log += "Co-processor scaffold: %s\n" % String(scaffold2.get("markdown", ""))
			extra_log += "%s\n" % I18n.t("native.build_handoff", {"path": String(handoff.get("markdown", ""))})
			for w in manifest.get("warnings", []):
				_log.text += "[color=#ffd45e]- %s[/color]\n" % String(w)
	result["ok"] = not assets.is_empty() or not stage_result.is_empty() or not bake_result.is_empty() \
		or bool(layout.get("ok", false)) or bool(port.get("ok", false)) \
		or bool(Dictionary(result.get("mesh_export", {})).get("ok", false)) \
		or bool(Dictionary(result.get("scaffold", {})).get("ok", false))
	result["scene"] = scene_name
	result["directory"] = dir
	result["actors"] = assets.size()
	result["cameras"] = cameras
	result["assets"] = assets
	result["bake"] = bake_result
	if not port.is_empty():
		result["port"] = port
	_last_result = result
	save_session()
	project.save()
	modified.emit()
	status.emit(I18n.t("native.import_status", {
		"actors": assets.size(), "assets": assets.size() + (1 if not stage_result.is_empty() else 0),
		"ui": int(port.get("widgets", 0)), "nodes": int(port.get("nodes", 0)),
		"scripts": int(port.get("scripts", 0)), "dir": dir,
	}))
	_log.text = "[color=#6ee7a8]%s[/color]\n" % I18n.t("native.import_complete")
	_log.text += "%s\n%s\n%s\n" % [
		I18n.t("native.scene", {"name": scene_name}),
		I18n.t("native.directory", {"path": dir}),
		I18n.t("native.actors", {"count": assets.size()}),
	]
	if not stage_result.is_empty():
		_log.text += "%s\n" % I18n.t("native.background", {
			"tiles": int(stage_result.get("tiles", 0)),
			"w": int(stage_result.get("map_w", 0)),
			"h": int(stage_result.get("map_h", 0)),
		})
	if not bake_result.is_empty():
		_log.text += "%s\n" % I18n.t("native.bake", {"count": int(bake_result.get("frames", 0))})
	if not port.is_empty():
		_log.text += "%s\n" % I18n.t("native.port_bundle_log", {
			"widgets": int(port.get("widgets", 0)),
			"nodes": int(port.get("nodes", 0)),
			"scripts": int(port.get("scripts", 0)),
		})
		_log.text += "%s\n" % I18n.t("native.port_report", {"path": String(port.get("markdown", ""))})
	_log.text += extra_log
	for e in result["errors"]:
		_log.text += "[color=#ff7a7a]- %s[/color]\n" % String(e)
	return result

func _collect_3d_meshes(root: Node) -> Array:
	var out: Array = []
	_walk_3d_meshes(root, out, root)
	return out

func _walk_3d_meshes(node: Node, out: Array, base: Node) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		if mesh != null:
			var transform: Transform3D = node.global_transform
			for surface in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				if arrays.is_empty():
					continue
				var src_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if src_vertices.is_empty():
					continue
				var src_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL else PackedVector3Array()
				var src_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else PackedInt32Array()
				if src_indices.is_empty():
					for i in range(src_vertices.size()):
						src_indices.append(i)
				var vertices: Array = []
				var normals: Array = []
				for v in src_vertices:
					var world: Vector3 = transform * v
					vertices.append([snappedf(world.x, 0.0001), snappedf(world.y, 0.0001), snappedf(world.z, 0.0001)])
				for n in src_normals:
					var world_n: Vector3 = (transform.basis * n).normalized()
					normals.append([snappedf(world_n.x, 0.0001), snappedf(world_n.y, 0.0001), snappedf(world_n.z, 0.0001)])
				var indices: Array = []
				for idx in src_indices:
					indices.append(int(idx))
				var color := Color(0.82, 0.82, 0.88)
				var material: Material = node.material_override if node.material_override != null else mesh.surface_get_material(surface)
				var material_name := ""
				if material != null:
					material_name = material.resource_path.get_file() if not material.resource_path.is_empty() else material.get_class()
					if material is BaseMaterial3D:
						color = material.albedo_color
				out.append({"name": str(node.name), "path": _node_path(node, base), "surface": surface,
					"vertices": vertices, "normals": normals, "indices": indices,
					"color": color.to_html(false), "material": material_name,
					"triangle_count": indices.size() / 3,
					"transform": [transform.origin.x, transform.origin.y, transform.origin.z]})
	for child in node.get_children():
		_walk_3d_meshes(child, out, base)

func _mesh_c_array(name: String, values: Array, type_name: String) -> String:
	var out := "static const %s %s[%d] = {\n" % [type_name, name, maxi(1, values.size())]
	if values.is_empty():
		out += "\t0\n"
	else:
		for i in range(values.size()):
			out += "\t" + str(int(values[i]))
			if i + 1 < values.size():
				out += ","
			if (i + 1) % 16 == 0:
				out += "\n"
		out += "\n"
	out += "};\n"
	return out

func _write_mesh_export(scene_name: String, dir: String, meshes: Array) -> Dictionary:
	if meshes.is_empty():
		return {}
	var scale := 256.0
	var json_path := dir.path_join("scene_mesh.json")
	var header_path := dir.path_join("scene_mesh.h")
	var json_meshes: Array = []
	var header := "#ifndef RETRO_SCENE_MESH_H\n#define RETRO_SCENE_MESH_H\n\n"
	header += "#define RETRO_MESH_COUNT %d\n#define RETRO_MESH_SCALE %.1ff\n\n" % [meshes.size(), scale]
	header += "typedef struct {\n    const char *name;\n    const short *vertices;\n    const unsigned short *indices;\n    unsigned int vertex_count;\n    unsigned int index_count;\n    unsigned int color;\n} RetroMesh;\n\n"
	var table_rows: Array = []
	for i in range(meshes.size()):
		var mesh: Dictionary = meshes[i]
		var c_vertices: Array = []
		for v in mesh.get("vertices", []):
			var p: Array = v
			c_vertices.append(clampi(int(round(float(p[0]) * scale)), -32768, 32767))
			c_vertices.append(clampi(int(round(float(p[1]) * scale)), -32768, 32767))
			c_vertices.append(clampi(int(round(float(p[2]) * scale)), -32768, 32767))
		var c_indices: Array = []
		for idx in mesh.get("indices", []):
			c_indices.append(clampi(int(idx), 0, 65535))
		var c_normals: Array = []
		for n in mesh.get("normals", []):
			var p2: Array = n
			c_normals.append(clampi(int(round(float(p2[0]) * 256.0)), -127, 127))
			c_normals.append(clampi(int(round(float(p2[1]) * 256.0)), -127, 127))
			c_normals.append(clampi(int(round(float(p2[2]) * 256.0)), -127, 127))
		var color := Color(String(mesh.get("color", "d0d0e0")))
		var color_int := (int(clampf(color.r, 0.0, 1.0) * 255.0) << 16) | (int(clampf(color.g, 0.0, 1.0) * 255.0) << 8) | int(clampf(color.b, 0.0, 1.0) * 255.0)
		header += _mesh_c_array("mesh%d_vertices" % i, c_vertices, "short")
		header += _mesh_c_array("mesh%d_normals" % i, c_normals, "signed char")
		header += _mesh_c_array("mesh%d_indices" % i, c_indices, "unsigned short")
		header += "\n"
		table_rows.append("\t{ \"%s\", mesh%d_vertices, mesh%d_indices, %d, %d, 0x%06X }" % [
			String(mesh.get("name", "mesh")), i, i, c_vertices.size() / 3, c_indices.size(), color_int])
		json_meshes.append({"name": mesh.get("name", "mesh"), "path": mesh.get("path", ""),
			"surface": mesh.get("surface", 0), "vertices": mesh.get("vertices", []),
			"normals": mesh.get("normals", []), "indices": mesh.get("indices", []),
			"color": mesh.get("color", "d0d0e0"), "material": mesh.get("material", ""),
			"triangle_count": mesh.get("triangle_count", 0), "scale": scale})
	header += "static const RetroMesh retro_meshes[RETRO_MESH_COUNT] = {\n" + ",\n".join(table_rows) + "\n};\n\n#endif\n"
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify({"format": "godot-retro-engine/3d-mesh", "version": 1,
			"scene": scene_name, "scale": scale, "meshes": json_meshes}, "\t"))
		jf.close()
	var hf := FileAccess.open(header_path, FileAccess.WRITE)
	if hf:
		hf.store_string(header)
		hf.close()
	return {"ok": FileAccess.file_exists(json_path) and FileAccess.file_exists(header_path),
		"json": json_path, "header": header_path, "meshes": meshes.size(), "scale": scale,
		"vertices": json_meshes.reduce(func(acc, m): return acc + Array(m.get("vertices", [])).size(), 0),
		"triangles": json_meshes.reduce(func(acc, m): return acc + int(m.get("triangle_count", 0)), 0)}

func _write_3d_scaffold(scene_name: String, dir: String, manifest: Dictionary,
		meshes: Array, mesh_result: Dictionary) -> Dictionary:
	var profile: Dictionary = manifest.get("profile", {})
	var chip := String(profile.get("id", _profile))
	var coop := dir.path_join("coop")
	DirAccess.make_dir_recursive_absolute(coop)
	var md_path := coop.path_join("README.md")
	var md := "# 3D co-processor scaffold — %s\n\n" % scene_name
	md += "Target profile: **%s** (`%s`)\n\n" % [String(profile.get("name", chip)), chip]
	md += "| Item | Value |\n| --- | --- |\n"
	md += "| Chip | %s |\n| Clock | %s |\n| Framebuffer | %s |\n| Target FPS | %d |\n| ROM budget | %s Mbit |\n" % [
		String(profile.get("chip", "")), String(profile.get("clock", "")),
		String(profile.get("framebuffer", "")), int(profile.get("target_fps", 0)),
		str(profile.get("rom_mbit", ""))]
	md += "\n## Comparison\n\n"
	md += "| Feature | SNES Super FX | Mega Drive SVP | Sega 32X |\n| --- | --- | --- | --- |\n"
	md += "| Vendor | Argonaut/Nintendo | Sega/Samsung | Sega |\n"
	md += "| CPU | Custom RISC GSU | SSP160x DSP | 2x Hitachi SH-2 |\n"
	md += "| Clock | up to 21.47 MHz | ~23 MHz | 2x 23 MHz |\n"
	md += "| Main use | polygons and advanced 2D | 3D geometry | 3D geometry and enhanced video |\n"
	md += "| Famous game | Star Fox | Virtua Racing | Virtua Racing Deluxe / Star Wars Arcade |\n"
	md += "| Cartridge | in-cartridge chip | in-cartridge chip | external add-on |\n\n"
	md += "## Exported resources\n\n"
	md += "- `scene_mesh.h` / `scene_mesh.json`: transformed mesh vertices, normals, indices and flat colors.\n"
	md += "- `3d_handoff.json` / `3D_HANDOFF.md`: actor table, bake information and profile budgets.\n"
	md += "- `assets/`: the native sprites, stages and animations imported beside this scaffold.\n\n"
	md += "## Build status\n\n"
	md += "This directory is a **portable scaffold**, not a compiled co-processor ROM. "
	if chip == "superfx":
		md += "A Super FX build needs a GSU assembler/linker, a 65816 host program, a Super FX-aware header and a ROM mapper. The generated `gsu.asm` and `host_65816.c` are starting points for that toolchain.\n"
	elif chip == "sega32x":
		md += "A 32X build needs an SH-2 toolchain, the 32X BIOS/header, a 68000 host and a 32X-aware linker layout. The generated `sh2_master.c`, `sh2_slave.c` and `m68k_host.c` are starting points. The base Mega Drive SGDK project still runs the baked 2D fallback.\n"
	else:
		md += "An SVP build needs the SSP160x/SVP assembler, a 68000 host, an SVP-aware cartridge map and hardware/emulator support. The generated `ssp1601.asm` and `m68k_host.c` are starting points.\n"
	md += "\nThe mesh data uses a fixed-point scale of **%.1f** units per world unit.\n" % float(mesh_result.get("scale", 256.0))
	var mf := FileAccess.open(md_path, FileAccess.WRITE)
	if mf:
		mf.store_string(md)
		mf.close()
	var files: Array = [md_path]
	if chip == "superfx":
		var gsu := coop.path_join("gsu.asm")
		var gf := FileAccess.open(gsu, FileAccess.WRITE)
		if gf:
			gf.store_string("; Super FX / GSU program scaffold\n; Assemble with a GSU toolchain and link with host_65816.c.\n; The mesh data is in scene_mesh.h; convert vertices to GSU fixed point\n; and implement the plot/color commands for your target hardware.\n\n    .include \"gsu_regs.inc\"\n\nstart:\n    ; TODO: clear screen, transform and draw retro_meshes[]\n    stop\n    rts\n")
			gf.close()
			files.append(gsu)
		var host := coop.path_join("host_65816.c")
		var hf := FileAccess.open(host, FileAccess.WRITE)
		if hf:
			hf.store_string("/* 65816 host scaffold for a Super FX cartridge.\n * Include scene_mesh.h and upload the GSU program/data according to your\n * Super FX mapper. The base SNES PVSnesLib path uses the baked sprites. */\n#include <snes.h>\n#include \"../scene_mesh.h\"\n\nint main(void) {\n    /* TODO: map GSU ROM/RAM, start the GSU program and present the framebuffer. */\n    while (1) WaitForVBlank();\n    return 0;\n}\n")
			hf.close()
			files.append(host)
	elif chip == "sega32x":
		var master := coop.path_join("sh2_master.c")
		var mf2 := FileAccess.open(master, FileAccess.WRITE)
		if mf2:
			mf2.store_string("/* SH-2 master scaffold for Sega 32X.\n * Build with an SH-2 toolchain and the 32X runtime; mesh data is in\n * scene_mesh.h. The 68000 host starts both SH-2 CPUs. */\n#include \"scene_mesh.h\"\n\nvoid sh2_master_main(void) {\n    for (;;) {\n        /* TODO: transform, cull, sort and rasterize retro_meshes[]. */\n    }\n}\n")
			mf2.close()
			files.append(master)
		var slave := coop.path_join("sh2_slave.c")
		var sf := FileAccess.open(slave, FileAccess.WRITE)
		if sf:
			sf.store_string("/* SH-2 slave scaffold for Sega 32X. Split geometry or raster\n * work between the two SH-2 CPUs here. */\nvoid sh2_slave_main(void) {\n    for (;;) {\n    }\n}\n")
			sf.close()
			files.append(slave)
		var host32 := coop.path_join("m68k_host.c")
		var h32 := FileAccess.open(host32, FileAccess.WRITE)
		if h32:
			h32.store_string("/* 68000 host scaffold for a Sega 32X build.\n * The base Mega Drive SGDK project runs the baked 2D fallback; a real 32X\n * build needs the 32X BIOS/header, SH-2 images and a 32X linker map. */\nint main(void) {\n    for (;;) {\n        /* TODO: boot the SH-2 master/slave and present the 32X framebuffer. */\n    }\n}\n")
			h32.close()
			files.append(host32)
	else:
		var ssp := coop.path_join("ssp1601.asm")
		var sf2 := FileAccess.open(ssp, FileAccess.WRITE)
		if sf2:
			sf2.store_string("; SVP / SSP160x program scaffold\n; Assemble with an SVP toolchain and link with m68k_host.c.\n; Mesh data is in scene_mesh.h.\n\nstart:\n    ; TODO: transform and rasterize retro_meshes[]\n    nop\n")
			sf2.close()
			files.append(ssp)
		var hostm := coop.path_join("m68k_host.c")
		var hm := FileAccess.open(hostm, FileAccess.WRITE)
		if hm:
			hm.store_string("/* 68000 host scaffold for an SVP cartridge.\n * Include scene_mesh.h and load the SVP program/data; the base Mega Drive\n * SGDK path uses the baked sprites. */\nint main(void) {\n    for (;;) {\n        /* TODO: start the SVP DSP and present the framebuffer. */\n    }\n}\n")
			hm.close()
			files.append(hostm)
	if bool(mesh_result.get("ok", false)):
		files.append(String(mesh_result.get("json", "")))
		files.append(String(mesh_result.get("header", "")))
	return {"ok": true, "directory": coop, "markdown": md_path, "files": files}

func _write_3d_handoff(scene_name: String, dir: String, manifest: Dictionary,
		bake: Dictionary, assets: Array, meshes: Array = []) -> Dictionary:
	var profile: Dictionary = manifest.get("profile", {})
	var chip := String(profile.get("id", _profile))
	var target := String(profile.get("reference", chip))
	var mesh_result := _write_mesh_export(scene_name, dir, meshes)
	var scaffold := _write_3d_scaffold(scene_name, dir, manifest, meshes, mesh_result)
	var md_path := dir.path_join("3D_HANDOFF.md")
	var json_path := dir.path_join("3d_handoff.json")
	var md := "# 3D handoff — %s\n\n" % scene_name
	md += "Target reference: **%s** (%s)\n\n" % [String(profile.get("name", target)), target]
	md += "Chip: %s  \nClock: %s  \nFramebuffer: %s  \nTarget FPS: %d  \n" % [
		String(profile.get("chip", "")), String(profile.get("clock", "")),
		String(profile.get("framebuffer", "")), int(profile.get("target_fps", 0))]
	md += "\n## Co-processor comparison\n\n"
	md += "| Feature | SNES Super FX | Mega Drive SVP | Sega 32X |\n| --- | --- | --- | --- |\n"
	md += "| Vendor | Argonaut/Nintendo | Sega/Samsung | Sega |\n"
	md += "| Architecture | custom RISC GSU | SSP160x DSP | 2x Hitachi SH-2 |\n"
	md += "| Clock | up to 21.47 MHz | ~23 MHz | 2x 23 MHz |\n"
	md += "| Main use | polygons and advanced 2D | 3D geometry | 3D geometry and enhanced video |\n"
	md += "| Famous game | Star Fox | Virtua Racing | Virtua Racing Deluxe / Star Wars Arcade |\n"
	md += "| Cartridge | in-cartridge chip | in-cartridge chip | external add-on |\n"
	md += "\n## Generated base-console assets\n\n"
	md += "- Pre-rendered sprite sheet / `RetroAnimation`: `%s`\n" % str(bake.get("frames", 0)) + " frames\n"
	md += "- Scene actor table and native profile header in this directory.\n"
	md += "- Mesh resource: `scene_mesh.h` / `scene_mesh.json` (%d meshes, %d triangles).\n" % [meshes.size(), int(mesh_result.get("triangles", 0))]
	md += "- Co-processor scaffold: `%s`\n" % String(scaffold.get("markdown", ""))
	md += "- All assets are standard SNES/Mega Drive sprites/tilemaps and run without the co-processor.\n"
	md += "\n## Co-processor path\n\n"
	if chip == "superfx":
		md += "This engine does not embed a GSU assembler or linker. A real Super FX cartridge build needs a GSU toolchain (for example libSFX / a GSU assembler), the 65816 host program, the GSU program and a Super FX-aware ROM header. Use the profile above as the budget/reference.\n"
	elif chip == "sega32x":
		md += "The 32X is an add-on with two SH-2 CPUs and the VDP32X. A real build needs an SH-2 toolchain, the 32X runtime/BIOS header, a 68000 host and a 32X-aware cartridge map. The generated `coop/` directory contains SH-2 and 68000 scaffold files; the base Mega Drive ROM still runs the baked 2D fallback.\n"
	else:
		md += "This engine does not embed an SVP DSP toolchain. A real SVP cartridge build needs the SSP160x/SVP program, the 68000 host program, a 2 MB/128 KB cartridge memory map and an SVP-aware emulator or hardware. Use the profile above as the budget/reference.\n"
	md += "\nThe generated sprite sheets, tilemaps and actor table are the portable part of the pipeline and are complete.\n"
	var f := FileAccess.open(md_path, FileAccess.WRITE)
	if f:
		f.store_string(md)
		f.close()
	var toolchain := "GSU/Super FX toolchain" if chip == "superfx" else ("SH-2/32X toolchain" if chip == "sega32x" else "SVP/SSP160x toolchain")
	var data := {
		"format": "godot-retro-engine/3d-handoff",
		"version": 1,
		"scene": scene_name,
		"profile": profile,
		"bake": bake,
		"assets": assets,
		"meshes": meshes.size(),
		"mesh_export": mesh_result,
		"scaffold": scaffold,
		"base_console_assets": true,
		"co_processor_execution": false,
		"toolchain_required": toolchain,
	}
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify(data, "\t"))
		jf.close()
	return {"ok": FileAccess.file_exists(md_path) and FileAccess.file_exists(json_path),
		"markdown": md_path, "json": json_path, "mesh": mesh_result, "scaffold": scaffold}

func _write_port_bundle(root: Node, scene_name: String, dir: String, source: String,
		assets: Array, cameras: Array, stage: Dictionary, bake: Dictionary) -> Dictionary:
	var widgets: Array = _collect_widgets(root) if _wants_ui() else []
	var nodes: Array = _collect_nodes(root) if _wants_nodes() else []
	var scripts: Array = _collect_scripts(root) if _wants_scripts() else []
	var scripts_dir := ""
	if not scripts.is_empty():
		scripts_dir = dir.path_join("scripts")
		DirAccess.make_dir_recursive_absolute(scripts_dir)
		var copied := {}
		for entry in scripts:
			var src := String(entry.get("script", ""))
			if src.is_empty() or not FileAccess.file_exists(src):
				continue
			var ext := src.get_extension().to_lower()
			if ext not in ["gd", "cs"]:
				continue
			var data := FileAccess.get_file_as_string(src)
			var dst := String(copied.get(src, ""))
			if dst.is_empty():
				var base := src.get_file()
				if base.is_empty():
					base = _slug(String(entry.get("node", "script"))) + "." + ext
				dst = scripts_dir.path_join(base)
				if FileAccess.file_exists(dst) and FileAccess.get_file_as_string(dst) != data:
					var n := 2
					while FileAccess.file_exists(dst):
						dst = scripts_dir.path_join("%s_%d.%s" % [_slug(base.get_basename()), n, ext])
						n += 1
				if not FileAccess.file_exists(dst):
					var f := FileAccess.open(dst, FileAccess.WRITE)
					if f == null:
						continue
					f.store_string(data)
					f.close()
				copied[src] = dst
			entry["exported_script"] = _relative_path(dst)
			entry["script"] = _relative_path(src)
	var data := {
		"format": "godot-retro-engine/native-port",
		"version": 1,
		"scene": scene_name,
		"source": source,
		"platform": platform,
		"mode": mode,
		"generated": Time.get_datetime_string_from_system(),
		"include": {"ui": _wants_ui(), "nodes": _wants_nodes(), "scripts": _wants_scripts()},
		"actors": _normalize_vectors(assets),
		"cameras": _normalize_vectors(cameras),
		"widgets": widgets,
		"nodes": nodes,
		"scripts": scripts,
		"stage": stage,
		"bake": bake,
	}
	var json_path := dir.path_join(scene_name + "_port.json")
	var header_path := dir.path_join(scene_name + "_port.h")
	var md_path := dir.path_join(scene_name + "_port.md")
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf == null:
		return {"ok": false, "error": "could not write " + json_path}
	jf.store_string(JSON.stringify(data, "\t"))
	jf.close()
	var hf := FileAccess.open(header_path, FileAccess.WRITE)
	if hf == null:
		return {"ok": false, "error": "could not write " + header_path}
	hf.store_string(_port_header(data))
	hf.close()
	var mf := FileAccess.open(md_path, FileAccess.WRITE)
	if mf == null:
		return {"ok": false, "error": "could not write " + md_path}
	mf.store_string(_port_markdown(data))
	mf.close()
	var ok := FileAccess.file_exists(json_path) and FileAccess.file_exists(header_path) and FileAccess.file_exists(md_path)
	return {"ok": ok, "header": header_path, "json": json_path, "markdown": md_path,
		"scripts_dir": scripts_dir, "widgets": widgets.size(), "nodes": nodes.size(),
		"scripts": scripts.size(), "actors": assets.size()}

func _collect_widgets(root: Node) -> Array:
	var out: Array = []
	_walk_widgets(root, out, root)
	return out

func _walk_widgets(node: Node, out: Array, base: Node) -> void:
	if node is Control:
		var rect: Rect2 = node.get_global_rect()
		var text := ""
		var text_value = node.get("text")
		if text_value != null:
			text = String(text_value)
		var entry := {
			"name": str(node.name),
			"path": _node_path(node, base),
			"type": node.get_class(),
			"x": int(round(rect.position.x)),
			"y": int(round(rect.position.y)),
			"w": int(round(rect.size.x)),
			"h": int(round(rect.size.y)),
			"text": text,
			"visible": node.is_visible_in_tree(),
			"z": node.z_index,
			"tooltip": node.tooltip_text,
			"script": _script_path(node),
			"modulate": node.modulate.to_html(),
		}
		var font_size: int = node.get_theme_font_size("font_size")
		if font_size > 0:
			entry["font_size"] = int(font_size)
		var bg = node.get_theme_stylebox("panel")
		if bg is StyleBoxFlat:
			entry["bg_color"] = bg.bg_color.to_html()
		if node is ColorRect:
			entry["bg_color"] = node.color.to_html()
		if node is TextureRect:
			entry["texture"] = _resource_path(node.texture)
		elif node is TextureButton:
			entry["texture"] = _resource_path(node.texture_normal)
		elif node is Button:
			entry["texture"] = _resource_path(node.icon)
		if node is ProgressBar:
			entry["value"] = node.value
			entry["max_value"] = node.max_value
		elif node is ItemList:
			var items: Array = []
			for i in range(node.item_count):
				items.append(node.get_item_text(i))
			entry["items"] = items
			var selected_items: PackedInt32Array = node.get_selected_items()
			entry["selected"] = int(selected_items[0]) if not selected_items.is_empty() else -1
		elif node is OptionButton:
			var items: Array = []
			for i in range(node.item_count):
				items.append(node.get_item_text(i))
			entry["items"] = items
			entry["selected"] = node.selected
		elif node is TabContainer:
			var tabs: Array = []
			for i in range(node.get_tab_count()):
				tabs.append(node.get_tab_title(i))
			entry["tabs"] = tabs
		out.append(entry)
	for child in node.get_children():
		_walk_widgets(child, out, base)

func _collect_nodes(root: Node) -> Array:
	var out: Array = []
	_walk_nodes(root, out, root)
	return out

func _walk_nodes(node: Node, out: Array, base: Node) -> void:
	var entry := {
		"name": str(node.name),
		"path": _node_path(node, base),
		"type": node.get_class(),
		"parent": _node_path(node.get_parent(), base) if node.get_parent() != null else "",
		"visible": node.is_visible_in_tree(),
		"script": _script_path(node),
		"groups": _string_array(node.get_groups()),
		"kind": "",
	}
	if node is Node2D:
		entry["position"] = _vec_array(node.position)
		entry["global_position"] = _vec_array(node.global_position)
		entry["rotation"] = node.rotation
		entry["scale"] = _vec_array(node.scale)
	elif node is Node3D:
		entry["position"] = _vec_array(node.position)
		entry["global_position"] = _vec_array(node.global_position)
		entry["rotation"] = _vec_array(node.rotation)
		entry["scale"] = _vec_array(node.scale)
	elif node is Control:
		var rect: Rect2 = node.get_global_rect()
		entry["rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		entry["position"] = [rect.position.x, rect.position.y, 0]
	if node is Marker2D:
		entry["kind"] = "spawn"
	elif node is CollisionShape2D:
		entry["kind"] = "collision"
		_shape_entry(node.shape, entry)
		entry["one_way"] = node.one_way_collision
	elif node is CollisionPolygon2D:
		entry["kind"] = "collision_polygon"
		entry["points"] = _points_array(node.polygon)
		entry["build_mode"] = node.build_mode
	elif node is Area2D:
		entry["kind"] = "area"
		entry["gravity"] = node.gravity
		entry["gravity_direction"] = _vec_array(node.gravity_direction)
		entry["monitoring"] = node.monitoring
		entry["monitorable"] = node.monitorable
		entry["collision_layer"] = node.collision_layer
		entry["collision_mask"] = node.collision_mask
	elif node is CharacterBody2D or node is RigidBody2D or node is StaticBody2D:
		entry["kind"] = "body"
		entry["collision_layer"] = node.collision_layer
		entry["collision_mask"] = node.collision_mask
	elif node is RayCast2D:
		entry["kind"] = "raycast"
		entry["target_position"] = _vec_array(node.target_position)
		entry["enabled"] = node.enabled
	elif node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		entry["kind"] = "audio"
		entry["stream"] = _resource_path(node.stream)
		entry["volume_db"] = node.volume_db
		entry["autoplay"] = node.autoplay
		entry["bus"] = node.bus
	elif node is AnimationPlayer:
		entry["kind"] = "animation"
		entry["animations"] = _string_array(node.get_animation_list())
	elif node is Timer:
		entry["kind"] = "timer"
		entry["wait_time"] = node.wait_time
		entry["one_shot"] = node.one_shot
		entry["autostart"] = node.autostart
	elif node is PointLight2D:
		entry["kind"] = "light2d"
		entry["color"] = node.color.to_html()
		entry["energy"] = node.energy
		entry["texture"] = _resource_path(node.texture)
	elif node is DirectionalLight2D:
		entry["kind"] = "directional_light2d"
		entry["color"] = node.color.to_html()
		entry["energy"] = node.energy
		entry["height"] = node.height
	elif node is Path2D:
		entry["kind"] = "path"
		entry["points"] = _points_array(node.curve.get_baked_points()) if node.curve != null else []
	elif node is Line2D:
		entry["kind"] = "line"
		entry["points"] = _points_array(node.points)
		entry["width"] = node.width
	elif node is Polygon2D:
		entry["kind"] = "polygon"
		entry["points"] = _points_array(node.polygon)
		entry["color"] = node.color.to_html()
	elif node is CanvasLayer:
		entry["kind"] = "canvas_layer"
		entry["layer"] = node.layer
	elif node is Camera2D:
		entry["kind"] = "camera2d"
		entry["zoom"] = _vec_array(node.zoom)
		entry["limit_left"] = node.limit_left
		entry["limit_top"] = node.limit_top
		entry["limit_right"] = node.limit_right
		entry["limit_bottom"] = node.limit_bottom
		entry["enabled"] = node.enabled
	elif node is Camera3D:
		entry["kind"] = "camera3d"
		entry["fov"] = node.fov
		entry["projection"] = node.projection
		entry["size"] = node.size
		entry["current"] = node.current
	elif node is TileMapLayer:
		entry["kind"] = "tilemap"
		entry["cells"] = node.get_used_cells().size()
		entry["map_size"] = _vec_array(node.get_used_rect().size)
		if node.tile_set != null:
			entry["tile_size"] = _vec_array(node.tile_set.tile_size)
	elif node is Sprite2D or node is Sprite3D or node is AnimatedSprite2D or node is AnimatedSprite3D or node is TextureRect or node is TextureButton:
		entry["kind"] = "sprite"
	elif node is MeshInstance3D:
		entry["kind"] = "mesh"
	if String(entry["kind"]).is_empty() and not String(entry["script"]).is_empty():
		entry["kind"] = "script"
	out.append(entry)
	for child in node.get_children():
		_walk_nodes(child, out, base)

func _shape_entry(shape, entry: Dictionary) -> void:
	if shape == null:
		return
	if shape is RectangleShape2D:
		entry["shape"] = "rect"
		entry["size"] = _vec_array(shape.size)
	elif shape is CircleShape2D:
		entry["shape"] = "circle"
		entry["radius"] = shape.radius
	elif shape is CapsuleShape2D:
		entry["shape"] = "capsule"
		entry["radius"] = shape.radius
		entry["height"] = shape.height
	elif shape is SegmentShape2D:
		entry["shape"] = "segment"
		entry["a"] = _vec_array(shape.a)
		entry["b"] = _vec_array(shape.b)
	elif shape is SeparationRayShape2D:
		entry["shape"] = "separation_ray"
		entry["length"] = shape.length
	elif shape is WorldBoundaryShape2D:
		entry["shape"] = "world_boundary"
		entry["normal"] = _vec_array(shape.normal)
		entry["distance"] = shape.distance
	elif shape is ConvexPolygonShape2D:
		entry["shape"] = "convex_polygon"
		entry["points"] = _points_array(shape.points)
	elif shape is ConcavePolygonShape2D:
		entry["shape"] = "concave_polygon"
		entry["segments"] = shape.segments.size()

func _collect_scripts(root: Node) -> Array:
	var out: Array = []
	_walk_scripts(root, out, root)
	return out

func _walk_scripts(node: Node, out: Array, base: Node) -> void:
	var script = node.get_script()
	if script != null:
		var entry := {
			"node": str(node.name),
			"node_path": _node_path(node, base),
			"node_type": node.get_class(),
			"script": _script_path(node),
			"class_name": "",
			"base_type": "",
			"methods": [],
			"signals": [],
			"properties": [],
			"constants": [],
		}
		if script is Script:
			if script.has_method("get_global_name"):
				entry["class_name"] = String(script.get_global_name())
			entry["base_type"] = String(script.get_instance_base_type())
			for m in script.get_script_method_list():
				entry["methods"].append({
					"name": String(m.get("name", "")),
					"args": int(m.get("args", []).size()),
				})
			for sig in script.get_script_signal_list():
				entry["signals"].append({
					"name": String(sig.get("name", "")),
					"args": int(sig.get("args", []).size()),
				})
			for p in script.get_script_property_list():
				var usage := int(p.get("usage", 0))
				if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 or (usage & PROPERTY_USAGE_EDITOR) != 0:
					entry["properties"].append({
						"name": String(p.get("name", "")),
						"type": int(p.get("type", 0)),
						"hint": int(p.get("hint", 0)),
						"hint_string": String(p.get("hint_string", "")),
					})
			var constants = script.get_script_constant_map()
			for key in constants.keys():
				entry["constants"].append({"name": String(key), "value": str(constants[key])})
		out.append(entry)
	for child in node.get_children():
		_walk_scripts(child, out, base)

func _normalize_vectors(items: Array) -> Array:
	var out: Array = []
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			out.append(item)
			continue
		var copy: Dictionary = item.duplicate(true)
		for key in ["position", "rotation", "scale", "global_position", "target_position", "zoom"]:
			if copy.has(key):
				copy[key] = _vec_array(copy[key])
		for key in ["asset", "animation", "stream", "texture"]:
			if copy.has(key):
				copy[key] = _relative_path(String(copy[key]))
		out.append(copy)
	return out

func _vec_array(value) -> Array:
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3i:
		return [value.x, value.y, value.z]
	if value is Vector2i:
		return [value.x, value.y]
	if value is Array:
		return value
	return []

func _points_array(points) -> Array:
	var out: Array = []
	for p in points:
		out.append([p.x, p.y])
	return out

func _string_array(values) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out

func _node_path(node: Node, base: Node = null) -> String:
	if node == null:
		return ""
	var parts: Array = []
	var current: Node = node
	while current != null:
		parts.push_front(String(current.name))
		if base != null and current == base:
			break
		current = current.get_parent()
	return "/".join(parts)

func _relative_path(path: String) -> String:
	if path.is_empty() or project == null:
		return path
	var base := project.get_path().simplify_path()
	var prefix := base + "/"
	var clean := path.simplify_path()
	if clean.begins_with(prefix):
		return clean.trim_prefix(prefix)
	return path

func _script_path(node: Node) -> String:
	var script = node.get_script()
	if script is Script:
		return script.resource_path
	return ""

func _resource_path(resource) -> String:
	if resource is Resource:
		return resource.resource_path
	return ""

func _cstr(value: String) -> String:
	return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")

func _vec3_from(value) -> Array:
	var v := _vec_array(value)
	while v.size() < 3:
		v.append(0)
	return [int(v[0]), int(v[1]), int(v[2])]

func _node_xyz(entry: Dictionary) -> Array:
	var v := _vec3_from(entry.get("position", null))
	if v == [0, 0, 0]:
		var rect = entry.get("rect", [])
		if rect is Array and rect.size() >= 2:
			return [int(rect[0]), int(rect[1]), 0]
	return v

func _port_header(data: Dictionary) -> String:
	var scene := String(data.get("scene", "native"))
	var guard := "RETRO_PORT_" + _slug(scene).to_upper() + "_H"
	var actors: Array = data.get("actors", [])
	var widgets: Array = data.get("widgets", [])
	var nodes: Array = data.get("nodes", [])
	var scripts: Array = data.get("scripts", [])
	var out := "/* Generated by Godot Retro Engine native port export. */\n"
	out += "#ifndef " + guard + "\n#define " + guard + "\n\n"
	out += "#define RETRO_PORT_SCENE \"" + _cstr(scene) + "\"\n"
	out += "#define RETRO_PORT_SOURCE \"" + _cstr(String(data.get("source", ""))) + "\"\n"
	out += "#define RETRO_PORT_PLATFORM \"" + _cstr(String(data.get("platform", ""))) + "\"\n"
	out += "#define RETRO_PORT_ACTOR_COUNT %d\n" % actors.size()
	out += "#define RETRO_PORT_WIDGET_COUNT %d\n" % widgets.size()
	out += "#define RETRO_PORT_NODE_COUNT %d\n" % nodes.size()
	out += "#define RETRO_PORT_SCRIPT_COUNT %d\n\n" % scripts.size()
	out += "typedef struct { const char *name; int x, y, z; unsigned char type; const char *asset; const char *animation; } RetroPortActor;\n"
	out += "typedef struct { const char *name; const char *path; const char *type; int x, y, w, h; const char *text; unsigned char visible; const char *script; } RetroPortWidget;\n"
	out += "typedef struct { const char *name; const char *path; const char *type; const char *parent; const char *kind; const char *script; int x, y, z; unsigned char visible; } RetroPortNode;\n"
	out += "typedef struct { const char *node_path; const char *script; const char *class_name; const char *methods; const char *signals; const char *exported_script; } RetroPortScript;\n\n"
	out += "static const RetroPortActor retro_port_actors[%d] = {\n" % maxi(1, actors.size())
	if actors.is_empty():
		out += "\t{ \"\", 0, 0, 0, 0, \"\", \"\" },\n"
	else:
		for a in actors:
			var pos := _vec3_from(a.get("position", null))
			out += "\t{ \"%s\", %d, %d, %d, %d, \"%s\", \"%s\" },\n" % [
				_cstr(String(a.get("name", ""))), pos[0], pos[1], pos[2],
				int(a.get("type", 0)), _cstr(String(a.get("asset", ""))),
				_cstr(String(a.get("animation", "")))]
	out += "};\n\n"
	out += "static const RetroPortWidget retro_port_widgets[%d] = {\n" % maxi(1, widgets.size())
	if widgets.is_empty():
		out += "\t{ \"\", \"\", \"\", 0, 0, 0, 0, \"\", 0, \"\" },\n"
	else:
		for w in widgets:
			out += "\t{ \"%s\", \"%s\", \"%s\", %d, %d, %d, %d, \"%s\", %d, \"%s\" },\n" % [
				_cstr(String(w.get("name", ""))), _cstr(String(w.get("path", ""))),
				_cstr(String(w.get("type", ""))), int(w.get("x", 0)), int(w.get("y", 0)),
				int(w.get("w", 0)), int(w.get("h", 0)), _cstr(String(w.get("text", ""))),
				1 if bool(w.get("visible", true)) else 0, _cstr(String(w.get("script", "")))]
	out += "};\n\n"
	out += "static const RetroPortNode retro_port_nodes[%d] = {\n" % maxi(1, nodes.size())
	if nodes.is_empty():
		out += "\t{ \"\", \"\", \"\", \"\", \"\", \"\", 0, 0, 0, 0 },\n"
	else:
		for n in nodes:
			var pos := _node_xyz(n)
			out += "\t{ \"%s\", \"%s\", \"%s\", \"%s\", \"%s\", \"%s\", %d, %d, %d, %d },\n" % [
				_cstr(String(n.get("name", ""))), _cstr(String(n.get("path", ""))),
				_cstr(String(n.get("type", ""))), _cstr(String(n.get("parent", ""))),
				_cstr(String(n.get("kind", ""))), _cstr(String(n.get("script", ""))),
				pos[0], pos[1], pos[2], 1 if bool(n.get("visible", true)) else 0]
	out += "};\n\n"
	out += "static const RetroPortScript retro_port_scripts[%d] = {\n" % maxi(1, scripts.size())
	if scripts.is_empty():
		out += "\t{ \"\", \"\", \"\", \"\", \"\", \"\" },\n"
	else:
		for sc in scripts:
			var methods: Array = []
			for m in sc.get("methods", []):
				methods.append(String(m.get("name", "")))
			var signals: Array = []
			for sig in sc.get("signals", []):
				signals.append(String(sig.get("name", "")))
			out += "\t{ \"%s\", \"%s\", \"%s\", \"%s\", \"%s\", \"%s\" },\n" % [
				_cstr(String(sc.get("node_path", ""))), _cstr(String(sc.get("script", ""))),
				_cstr(String(sc.get("class_name", ""))), _cstr(", ".join(methods)),
				_cstr(", ".join(signals)), _cstr(String(sc.get("exported_script", "")))]
	out += "};\n\n#endif\n"
	return out

func _port_markdown(data: Dictionary) -> String:
	var actors: Array = data.get("actors", [])
	var widgets: Array = data.get("widgets", [])
	var nodes: Array = data.get("nodes", [])
	var scripts: Array = data.get("scripts", [])
	var md := "# Native port — %s\n\n" % String(data.get("scene", "native"))
	md += "- Platform: **%s**\n" % String(data.get("platform", ""))
	md += "- Source scene: `%s`\n" % String(data.get("source", ""))
	md += "- Mode: `%s`\n" % String(data.get("mode", ""))
	md += "- Generated: %s\n\n" % String(data.get("generated", ""))
	md += "## Summary\n\n"
	md += "- Sprites/actors: **%d**\n" % actors.size()
	md += "- UI widgets: **%d**\n" % widgets.size()
	md += "- Scene/other nodes: **%d**\n" % nodes.size()
	md += "- Scripts: **%d**\n\n" % scripts.size()
	md += "## Generated runtime\n\n"
	md += "Game Build turns this manifest into a console runtime automatically:\n\n"
	md += "- Spawns every imported `Sprite2D`/`AnimatedSprite2D` at its scene position.\n"
	md += "- Picks the first actor named player/hero as the D-pad player (or a PlayerStart/Start/Spawn marker).\n"
	md += "- Adds gravity, jumping, floor/platform collision and stage bounds.\n"
	md += "- Rect, circle, capsule, convex-polygon and polygon collisions are flattened to AABBs.\n"
	md += "- Plays IDLE/WALK/RUN/JUMP/FALL states on the player and the exported animation on other actors.\n"
	md += "- Follows the player with the BG camera when the stage is larger than the screen and no UI is baked.\n"
	md += "- Bakes the UI into the background and adds a Start/D-pad focus cursor with item selection.\n\n"
	md += "The parts that still require project code are listed at the end.\n\n"
	md += "## Imported assets\n\n"
	if actors.is_empty():
		md += "No sprite/animation assets were imported.\n\n"
	else:
		for a in actors:
			md += "- `%s` type %s → `%s`\n" % [
				String(a.get("name", "")), str(a.get("type", "")), String(a.get("asset", ""))]
		md += "\n"
	md += "## UI widgets\n\n"
	if widgets.is_empty():
		md += "No Control/UI nodes were found (or UI export was disabled).\n\n"
	else:
		md += "| Widget | Type | Rect (x,y,w,h) | Text | Script |\n| --- | --- | --- | --- | --- |\n"
		for w in widgets:
			md += "| %s | %s | %d,%d,%d,%d | %s | %s |\n" % [
				_md_cell(w.get("name", "")), _md_cell(w.get("type", "")),
				int(w.get("x", 0)), int(w.get("y", 0)), int(w.get("w", 0)), int(w.get("h", 0)),
				_md_cell(w.get("text", "")), _md_cell(String(w.get("script", "")).get_file())]
		md += "\n"
	md += "## Other nodes\n\n"
	var listed := 0
	for n in nodes:
		var kind := String(n.get("kind", ""))
		var script := String(n.get("script", ""))
		if kind.is_empty() and script.is_empty():
			continue
		if listed == 0:
			md += "| Node | Type | Kind | Position | Script |\n| --- | --- | --- | --- | --- |\n"
		var pos := _node_xyz(n)
		md += "| %s | %s | %s | %d,%d,%d | %s |\n" % [
			_md_cell(n.get("path", "")), _md_cell(n.get("type", "")), _md_cell(kind),
			pos[0], pos[1], pos[2], _md_cell(script.get_file())]
		listed += 1
	if listed == 0:
		md += "No markers, bodies, collisions, paths, lights, audio or animation nodes were found (or other-node export was disabled).\n"
	md += "\n## Scripts\n\n"
	if scripts.is_empty():
		md += "No GDScript/C# scripts were found (or script export was disabled).\n\n"
	else:
		for sc in scripts:
			var methods: Array = []
			for m in sc.get("methods", []):
				methods.append(String(m.get("name", "")))
			var signals: Array = []
			for sig in sc.get("signals", []):
				signals.append(String(sig.get("name", "")))
			md += "### `%s`\n\n" % String(sc.get("node_path", ""))
			md += "- Source: `%s`\n" % String(sc.get("script", ""))
			md += "- Exported copy: `%s`\n" % String(sc.get("exported_script", ""))
			md += "- Base type: `%s`\n" % String(sc.get("base_type", ""))
			md += "- Methods: `%s`\n" % ", ".join(methods)
			md += "- Signals: `%s`\n\n" % ", ".join(signals)
	md += "## Porting checklist\n\n"
	md += "- [x] Spawn imported sprite/animated actors and play their exported animations.\n"
	md += "- [x] Generate player movement, gravity, jump and AABB collision.\n"
	md += "- [x] Generate the UI focus cursor and item selection.\n"
	if not widgets.is_empty():
		md += "- [ ] Wire button/option callbacks, menu transitions and actions to C.\n"
	if not scripts.is_empty():
		md += "- [ ] Port custom GDScript methods/signals above to C. Scripts are copied as reference; they are not transpiled.\n"
	if not nodes.is_empty():
		md += "- [ ] Map the remaining node kinds (areas, raycasts, lights, paths, audio triggers, timers) to C.\n"
	md += "- [ ] Add parallax/multiple BG layers if the scene needs them; the capture is baked into one BG.\n"
	md += "- [ ] Keep the Godot scene as the source of truth and re-export after changes.\n"
	return md

func _md_cell(value) -> String:
	var text := str(value).replace("|", "\\|").replace("\n", " ").replace("\r", " ")
	if text.length() > 80:
		text = text.substr(0, 77) + "..."
	return text

func _walk(node: Node, dir: String, assets: Array, cameras: Array) -> void:
	if node is Sprite2D or node is Sprite3D or node is TextureRect:
		_add_sprite_asset(node, dir, assets)
	elif node is AnimatedSprite2D or node is AnimatedSprite3D:
		_add_animated_asset(node, dir, assets)
	elif node is Camera2D:
		cameras.append({"name": str(node.name), "type": "camera2d", "position": node.global_position,
			"zoom": node.zoom, "limit_left": node.limit_left, "limit_top": node.limit_top,
			"limit_right": node.limit_right, "limit_bottom": node.limit_bottom})
	elif node is Camera3D:
		cameras.append({"name": str(node.name), "type": "camera3d", "position": node.global_position,
			"rotation": node.global_rotation, "fov": node.fov, "projection": node.projection})
	elif node is CollisionShape2D:
		var shape = node.shape
		if shape is RectangleShape2D:
			var size: Vector2 = shape.size * node.global_scale
			assets.append({"name": str(node.name), "type": 5, "position": Vector3(node.global_position.x, node.global_position.y, 0),
				"asset": "", "animation": "", "width": int(size.x), "height": int(size.y)})
	elif node is CollisionPolygon2D:
		var rect: Rect2 = node.polygon.get_bounding_rect() if node.polygon.size() > 0 else Rect2()
		assets.append({"name": str(node.name), "type": 5, "position": Vector3(node.global_position.x, node.global_position.y, 0),
			"asset": "", "animation": "", "width": int(rect.size.x), "height": int(rect.size.y)})
	elif node is MeshInstance3D:
		var aabb: AABB = node.get_aabb()
		assets.append({"name": str(node.name), "type": 3, "position": node.global_position,
			"asset": "", "animation": "", "width": int(aabb.size.x), "height": int(aabb.size.y), "depth": int(aabb.size.z)})
	elif node is TileMapLayer:
		_import_tilemap(node, dir, assets)
	for child in node.get_children():
		_walk(child, dir, assets, cameras)

func _import_tilemap(node: TileMapLayer, dir: String, assets: Array) -> void:
	var tile_set: TileSet = node.tile_set
	if tile_set == null:
		return
	var used_cells: Array = node.get_used_cells()
	if used_cells.is_empty():
		return
	var tile_size: Vector2i = tile_set.tile_size
	if tile_size.x <= 0 or tile_size.y <= 0:
		tile_size = Vector2i(8, 8)
	var bounds := node.get_used_rect()
	var map_w := maxi(1, bounds.size.x)
	var map_h := maxi(1, bounds.size.y)
	var tile_index := {}
	var tiles: Array = []
	var cells := {}
	for cell in used_cells:
		var source_id := node.get_cell_source_id(cell)
		var atlas := node.get_cell_atlas_coords(cell)
		var source = tile_set.get_source(source_id)
		if not (source is TileSetAtlasSource):
			continue
		var atlas_source: TileSetAtlasSource = source
		var texture = atlas_source.texture
		if texture == null:
			continue
		var key := "%s:%s" % [source_id, atlas]
		if not tile_index.has(key):
			var region: Rect2i = atlas_source.get_tile_texture_region(atlas)
			var image: Image = texture.get_image()
			if image == null:
				continue
			var tile_image := image.get_region(region)
			if tile_image.get_width() != tile_size.x or tile_image.get_height() != tile_size.y:
				tile_image.resize(tile_size.x, tile_size.y, Image.INTERPOLATE_NEAREST)
			tile_index[key] = tiles.size()
			tiles.append(tile_image)
		cells[cell] = {"index": int(tile_index[key]), "h": node.is_cell_flipped_h(cell), "v": node.is_cell_flipped_v(cell)}
	if tiles.is_empty():
		return
	var tiles_x := 16
	var tile_rows := int(ceil(float(tiles.size()) / float(tiles_x)))
	var tileset := Image.create_empty(tiles_x * tile_size.x, maxi(1, tile_rows) * tile_size.y, false, Image.FORMAT_RGBA8)
	tileset.fill(Color(0, 0, 0, 0))
	for i in range(tiles.size()):
		tileset.blit_rect(tiles[i], Rect2i(0, 0, tile_size.x, tile_size.y),
			Vector2i((i % tiles_x) * tile_size.x, int(i / tiles_x) * tile_size.y))
	var stage := RetroStage.new()
	stage.set_name(_slug(str(node.name)))
	stage.set_platform(platform)
	stage.set_mode(mode)
	stage.set_bpp(4)
	stage.set_tile_size(tile_size.x)
	stage.set_tiles_x(tiles_x)
	stage.set_map_size(Vector2i(map_w, map_h))
	var map_data := PackedByteArray()
	map_data.resize(map_w * map_h * 2)
	stage.set_map(map_data)
	stage.set_tileset(tileset)
	stage.set_palette(RetroGraphics.extract_palette(tileset, 16, true))
	stage.set_metadata({"source": _last_scene, "native": true, "tilemap_layer": str(node.name)})
	for cell in cells.keys():
		var info: Dictionary = cells[cell]
		stage.set_tile(cell.x - bounds.position.x, cell.y - bounds.position.y, int(info["index"]), 0,
			1 if bool(info["h"]) else 0, 1 if bool(info["v"]) else 0)
	var name := _slug(str(node.name)) + "_stage"
	var tileset_png := dir.path_join(name + "_tiles.png")
	var stage_json := dir.path_join(name + ".retro_stage.json")
	tileset.save_png(tileset_png)
	var snes: Dictionary = stage.export_snes(dir, name)
	var sgdk: Dictionary = stage.export_sgdk(dir, name)
	stage.save(stage_json)
	_register_paths([tileset_png, stage_json,
		String(Dictionary(snes).get("chr", "")), String(Dictionary(snes).get("pal", "")),
		String(Dictionary(snes).get("map", "")), String(Dictionary(snes).get("inc", "")),
		String(Dictionary(sgdk).get("png", "")), String(Dictionary(sgdk).get("res", ""))], "stage", _last_scene)
	assets.append({"name": str(node.name), "type": 6,
		"position": Vector3(bounds.position.x, bounds.position.y, 0),
		"asset": stage_json, "animation": "", "width": map_w, "height": map_h,
		"tiles": tiles.size()})
	_add_asset_row({"name": str(node.name), "type": I18n.t("native.type_tilemap"), "path": String(Dictionary(snes).get("map", ""))})

func _add_sprite_asset(node: Node, dir: String, assets: Array) -> void:
	var texture = node.get("texture")
	if texture == null:
		return
	var image := _texture_image(texture)
	if image == null:
		return
	var hframes := int(node.get("hframes")) if node.get("hframes") != null else 1
	var vframes := int(node.get("vframes")) if node.get("vframes") != null else 1
	var frame_w := maxi(1, image.get_width() / maxi(1, hframes))
	var frame_h := maxi(1, image.get_height() / maxi(1, vframes))
	var region_enabled := false
	if node.get("region_enabled") != null:
		region_enabled = bool(node.get("region_enabled"))
	if region_enabled:
		var region: Rect2 = node.get("region_rect")
		if region.size.x > 0 and region.size.y > 0:
			frame_w = int(region.size.x)
			frame_h = int(region.size.y)
	var name := _slug(str(node.name))
	var r: Dictionary = bridge.import_image(image, name, dir, platform, frame_w, frame_h,
		int(_palette_colors.value), 4, int(_tile_size.value), _last_scene)
	if not bool(r.get("ok", false)):
		return
	_register_paths([
		String(r.get("png", "")), String(r.get("sprite_json", "")),
		String(Dictionary(r.get("snes", {})).get("chr", "")),
		String(Dictionary(r.get("snes", {})).get("pal", "")),
		String(Dictionary(r.get("snes", {})).get("inc", "")),
		String(Dictionary(r.get("sgdk", {})).get("png", "")),
		String(Dictionary(r.get("sgdk", {})).get("res", "")),
	], "sprite", _last_scene)
	var sprite: RetroSprite = r.get("sprite")
	assets.append({"name": str(node.name), "type": 1,
		"position": _node_position(node), "asset": String(r.get("png", "")),
		"animation": "", "frames": sprite.get_frames().size(),
		"width": image.get_width(), "height": image.get_height(),
		"centered": bool(node.get("centered")) if node.get("centered") != null else true,
		"offset": _vec_array(node.get("offset")) if node.get("offset") != null else [0.0, 0.0]})
	_add_asset_row({"name": str(node.name), "type": I18n.t("native.type_sprite"), "path": String(r.get("png", ""))})

func _add_animated_asset(node: Node, dir: String, assets: Array) -> void:
	var sf = node.get("sprite_frames")
	if sf == null:
		return
	var animations: PackedStringArray = sf.get_animation_names()
	if animations.is_empty():
		return
	var images: Array = []
	var frames: Array = []
	var cell_w := 1
	var cell_h := 1
	for anim in animations:
		var state := _state_name(str(anim))
		var count: int = sf.get_frame_count(anim)
		for i in range(count):
			var texture = sf.get_frame_texture(anim, i)
			var image := _texture_image(texture)
			if image == null:
				continue
			var image_index := images.size()
			images.append(image)
			cell_w = maxi(cell_w, image.get_width())
			cell_h = maxi(cell_h, image.get_height())
			frames.append({"state": state, "image": image_index,
				"duration": maxi(1, int(round(float(sf.get_frame_duration(anim, i)) * 60.0))),
				"loop": bool(sf.get_animation_loop(anim))})
	if images.is_empty():
		return
	var packed := _pack_images(images, cell_w, cell_h)
	var name := _slug(str(node.name))
	var r: Dictionary = bridge.import_image(packed["image"], name, dir, platform, cell_w, cell_h,
		int(_palette_colors.value), 4, int(_tile_size.value), _last_scene)
	if not bool(r.get("ok", false)):
		return
	_register_paths([
		String(r.get("png", "")), String(r.get("sprite_json", "")),
		String(Dictionary(r.get("snes", {})).get("chr", "")),
		String(Dictionary(r.get("snes", {})).get("pal", "")),
		String(Dictionary(r.get("snes", {})).get("inc", "")),
		String(Dictionary(r.get("sgdk", {})).get("png", "")),
		String(Dictionary(r.get("sgdk", {})).get("res", "")),
	], "sprite", _last_scene)
	var anim_doc := RetroAnimation.new()
	anim_doc.set_name(name)
	anim_doc.set_platform(platform)
	anim_doc.set_sprite_id(name)
	for f in frames:
		anim_doc.add_state(String(f["state"]), bool(f["loop"]))
	for f in frames:
		anim_doc.add_frame(String(f["state"]), int(f["image"]), int(f["duration"]), packed["rects"][int(f["image"])])
		anim_doc.set_loop(String(f["state"]), bool(f["loop"]))
	var anim_json := dir.path_join(name + ".retro_animation.json")
	var anim_inc := anim_doc.export_snes_inc(dir.path_join(name + "_anim.inc"), name)
	var anim_h := anim_doc.export_sgdk_header(dir.path_join(name + "_anim.h"), name)
	var anim_save := anim_doc.save(anim_json)
	_register_paths([anim_json, String(anim_inc.get("path", "")), String(anim_h.get("path", ""))], "animation", _last_scene)
	assets.append({"name": str(node.name), "type": 2, "position": _node_position(node),
		"asset": String(r.get("png", "")), "animation": anim_json,
		"frames": images.size(), "width": cell_w, "height": cell_h,
		"animations": animations.size(), "saved": anim_save == OK,
		"current_state": _state_name(String(node.get("animation"))),
		"centered": bool(node.get("centered")) if node.get("centered") != null else true,
		"offset": _vec_array(node.get("offset")) if node.get("offset") != null else [0.0, 0.0]})
	_add_asset_row({"name": str(node.name), "type": I18n.t("native.type_animated"), "path": anim_json})

func _import_bake_sheet(scene_name: String, dir: String, images: Array, source: String, assets: Array) -> Dictionary:
	var cell_w := 1
	var cell_h := 1
	for image in images:
		cell_w = maxi(cell_w, image.get_width())
		cell_h = maxi(cell_h, image.get_height())
	var packed := _pack_images(images, cell_w, cell_h)
	var r: Dictionary = bridge.import_image(packed["image"], scene_name + "_bake", dir, platform,
		cell_w, cell_h, int(_palette_colors.value), 4, int(_tile_size.value), source)
	if not bool(r.get("ok", false)):
		return {}
	_register_paths([
		String(r.get("png", "")), String(r.get("sprite_json", "")),
		String(Dictionary(r.get("snes", {})).get("chr", "")),
		String(Dictionary(r.get("snes", {})).get("pal", "")),
		String(Dictionary(r.get("snes", {})).get("inc", "")),
		String(Dictionary(r.get("sgdk", {})).get("png", "")),
		String(Dictionary(r.get("sgdk", {})).get("res", "")),
	], "sprite", source)
	var anim_doc := RetroAnimation.new()
	anim_doc.set_name(scene_name + "_bake")
	anim_doc.set_platform(platform)
	anim_doc.set_sprite_id(scene_name + "_bake")
	anim_doc.add_state("TURN", true)
	for i in range(images.size()):
		anim_doc.add_frame("TURN", i, 4, packed["rects"][i])
	var anim_json := dir.path_join(scene_name + "_bake.retro_animation.json")
	var anim_inc := anim_doc.export_snes_inc(dir.path_join(scene_name + "_bake_anim.inc"), scene_name + "_bake")
	var anim_h := anim_doc.export_sgdk_header(dir.path_join(scene_name + "_bake_anim.h"), scene_name + "_bake")
	anim_doc.save(anim_json)
	_register_paths([anim_json, String(anim_inc.get("path", "")), String(anim_h.get("path", ""))], "animation", source)
	assets.append({"name": scene_name + "_bake", "type": 2, "position": Vector3.ZERO,
		"asset": String(r.get("png", "")), "animation": anim_json, "frames": images.size(),
		"width": cell_w, "height": cell_h})
	_add_asset_row({"name": scene_name + "_bake", "type": I18n.t("native.type_bake"), "path": String(r.get("png", ""))})
	return {"ok": true, "frames": images.size(), "sprite": r, "animation": anim_json}

func _draw_ui_overlay(root: Node, image: Image) -> void:
	if not _wants_ui() or image == null:
		return
	_walk_ui_overlay(root, image)

func _walk_ui_overlay(node: Node, image: Image) -> void:
	if node is Control and node.is_visible_in_tree():
		_draw_control_software(node, image)
	for child in node.get_children():
		_walk_ui_overlay(child, image)

func _draw_control_software(node: Control, image: Image) -> void:
	if node is TextureRect or node is TextureButton:
		return
	var rect := node.get_global_rect()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	if node is ColorRect:
		_fill_rect_alpha(image, rect, node.color)
		return
	if node is Panel or node is PanelContainer:
		var panel = node.get_theme_stylebox("panel")
		if panel is StyleBoxFlat:
			_fill_rect_alpha(image, rect, panel.bg_color)
			_outline_rect_alpha(image, rect, panel.border_color)
		return
	if node is Button:
		var normal = node.get_theme_stylebox("normal")
		var bg := Color(0.18, 0.22, 0.30, 0.92)
		var border := Color(0.55, 0.62, 0.75, 1.0)
		if normal is StyleBoxFlat:
			bg = normal.bg_color
			border = normal.border_color
		_fill_rect_alpha(image, rect, bg)
		_outline_rect_alpha(image, rect, border)
		var text: String = String(node.text)
		var color: Color = node.get_theme_color("font_color")
		if color == null:
			color = Color.WHITE
		var font_size := node.get_theme_font_size("font_size")
		var scale := 2 if font_size >= 16 else 1
		var tw := _ui_text_width(text, scale)
		var tx := int(rect.position.x) + int((rect.size.x - tw) / 2)
		var ty := int(rect.position.y) + int((rect.size.y - 7 * scale) / 2)
		_draw_ui_text(image, text, tx, ty, scale, color)
		return
	if node is Label:
		var text: String = String(node.text)
		if text.is_empty():
			return
		var color: Color = node.get_theme_color("font_color")
		if color == null:
			color = Color.WHITE
		var font_size := node.get_theme_font_size("font_size")
		var scale := 2 if font_size >= 16 else 1
		var tw := _ui_text_width(text, scale)
		var tx := int(rect.position.x)
		if node.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
			tx += int((rect.size.x - tw) / 2)
		elif node.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			tx += int(rect.size.x - tw)
		_draw_ui_text(image, text, tx, int(rect.position.y), scale, color)
		return
	if node is OptionButton:
		var selected: String = String(node.get_item_text(node.selected)) if node.selected >= 0 else ""
		_fill_rect_alpha(image, rect, Color(0.14, 0.17, 0.23, 0.95))
		_outline_rect_alpha(image, rect, Color(0.55, 0.62, 0.75, 1.0))
		_draw_ui_text(image, selected, int(rect.position.x) + 4, int(rect.position.y) + 4, 1, Color.WHITE)
		return
	if node is ItemList:
		_fill_rect_alpha(image, rect, Color(0.12, 0.15, 0.21, 0.95))
		_outline_rect_alpha(image, rect, Color(0.55, 0.62, 0.75, 1.0))
		var y := int(rect.position.y) + 3
		for i in range(mini(node.item_count, 8)):
			_draw_ui_text(image, node.get_item_text(i), int(rect.position.x) + 4, y, 1, Color.WHITE)
			y += 9

func _ui_text_width(text: String, scale: int) -> int:
	return maxi(0, text.length() * 6 * scale)

func _draw_ui_text(image: Image, text: String, x: int, y: int, scale: int, color: Color) -> void:
	var cursor := x
	for ch in text.to_upper():
		var glyph: Array = UI_FONT.get(ch, [])
		if not glyph.is_empty():
			for gy in range(7):
				for gx in range(5):
					if glyph[gy][gx] == "1":
						for sy in range(scale):
							for sx in range(scale):
								_set_pixel_alpha(image, cursor + gx * scale + sx, y + gy * scale + sy, color)
		cursor += 6 * scale

func _fill_rect_alpha(image: Image, rect: Rect2, color: Color) -> void:
	for yy in range(int(rect.position.y), int(rect.position.y + rect.size.y)):
		for xx in range(int(rect.position.x), int(rect.position.x + rect.size.x)):
			_set_pixel_alpha(image, xx, yy, color)

func _outline_rect_alpha(image: Image, rect: Rect2, color: Color) -> void:
	var x0 := int(rect.position.x)
	var y0 := int(rect.position.y)
	var x1 := int(rect.position.x + rect.size.x) - 1
	var y1 := int(rect.position.y + rect.size.y) - 1
	for xx in range(x0, x1 + 1):
		_set_pixel_alpha(image, xx, y0, color)
		_set_pixel_alpha(image, xx, y1, color)
	for yy in range(y0, y1 + 1):
		_set_pixel_alpha(image, x0, yy, color)
		_set_pixel_alpha(image, x1, yy, color)

func _set_pixel_alpha(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	if color.a >= 0.99:
		image.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))
	else:
		var base := image.get_pixel(x, y)
		var mixed := base.lerp(Color(color.r, color.g, color.b, base.a), color.a)
		mixed.a = maxf(base.a, color.a)
		image.set_pixel(x, y, mixed)

func _capture_views(root: Node, size: Vector2i, frame_count: int) -> Array:
	if not is_inside_tree():
		return []
	if DisplayServer.get_name() == "headless":
		var software_images: Array = _software_capture_views(root, size, frame_count)
		for img in software_images:
			_draw_ui_overlay(root, img)
		return software_images
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	add_child(vp)
	var copy := _capture_copy(root)
	copy.name = "NativeCapture"
	var pivot: Node3D = null
	var camera: Camera3D = _find_camera_3d(copy)
	var is_3d := _has_3d_geometry(copy)
	if is_3d and copy is Node3D:
		vp.add_child(copy)
		# Keep the camera fixed while the geometry rotates; otherwise the
		# camera orbits with the model and every frame looks identical.
		if camera != null and camera != copy:
			camera.reparent(vp)
		pivot = Node3D.new()
		vp.add_child(pivot)
		copy.reparent(pivot)
		var center := _scene_center(copy)
		var radius := maxf(1.0, _scene_radius(copy))
		pivot.position = center
		copy.position = copy.position - center
		if camera == null:
			camera = Camera3D.new()
			camera.position = center + Vector3(0, 0, radius * 2.4)
			camera.look_at(center, Vector3.UP)
			vp.add_child(camera)
	else:
		if copy is Node2D and _find_camera_2d(copy) == null:
			copy.position = Vector2(size) * 1.5
		vp.add_child(copy)
	var images: Array = []
	for i in range(maxi(1, frame_count)):
		if pivot != null:
			pivot.rotation.y = TAU * float(i) / float(maxi(1, frame_count))
		await get_tree().process_frame
		RenderingServer.force_draw()
		await get_tree().process_frame
		await get_tree().create_timer(0.05).timeout
		var image := vp.get_texture().get_image()
		if image != null and not image.is_empty():
			images.append(image)
	vp.queue_free()
	if images.is_empty():
		var fallback_images: Array = _software_capture_views(root, size, frame_count)
		for img in fallback_images:
			_draw_ui_overlay(root, img)
		return fallback_images
	for img in images:
		_draw_ui_overlay(root, img)
	return images

func _capture_copy(root: Node) -> Node:
	var copy := root.duplicate()
	_strip_scripts(copy)
	return copy

func _strip_scripts(node: Node) -> void:
	node.set_script(null)
	node.set_process(false)
	node.set_physics_process(false)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_strip_scripts(child)

func _software_capture_views(root: Node, size: Vector2i, frame_count: int) -> Array:
	if _has_3d_geometry(root):
		return _software_render_3d(root, size, frame_count)
	return [_software_render_2d(root, size)]

func _software_render_2d(root: Node, size: Vector2i) -> Image:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.06, 0.07, 0.1, 1))
	_draw_2d_node(root, image)
	return image

func _draw_2d_node(node: Node, image: Image) -> void:
	if node is TileMapLayer:
		_draw_tilemap_software(node, image)
	elif node is Sprite2D:
		_draw_sprite_software(node, image)
	elif node is AnimatedSprite2D:
		_draw_animated_software(node, image)
	elif node is TextureRect:
		_draw_texture_rect_software(node, image)
	elif node is ColorRect:
		var rect := Rect2i(Vector2i(node.global_position), Vector2i(node.size))
		_fill_rect(image, rect, node.color)
	for child in node.get_children():
		_draw_2d_node(child, image)

func _draw_sprite_software(node: Sprite2D, image: Image) -> void:
	var texture = node.texture
	if texture == null:
		return
	var src := _texture_image(texture)
	if src == null:
		return
	var region := Rect2i(0, 0, src.get_width(), src.get_height())
	if node.region_enabled and node.region_rect.size.x > 0:
		region = Rect2i(node.region_rect)
	var hframes := maxi(1, node.hframes)
	var vframes := maxi(1, node.vframes)
	var frame := clampi(node.frame, 0, hframes * vframes - 1)
	if region.size.x <= 0:
		region.size = Vector2i(src.get_width() / hframes, src.get_height() / vframes)
	var cell := Vector2i(region.size.x / hframes, region.size.y / vframes)
	var source_rect := Rect2i(region.position + Vector2i((frame % hframes) * cell.x, int(frame / hframes) * cell.y), cell)
	_draw_image_software(image, src, source_rect, node.global_position, node.global_transform, node.centered, node.offset,
		node.flip_h, node.flip_v, node.modulate)

func _draw_animated_software(node: AnimatedSprite2D, image: Image) -> void:
	var sf = node.sprite_frames
	if sf == null or sf.get_animation_names().is_empty():
		return
	var anim := node.animation if not node.animation.is_empty() else sf.get_animation_names()[0]
	var texture = sf.get_frame_texture(anim, node.frame)
	var src := _texture_image(texture)
	if src == null:
		return
	_draw_image_software(image, src, Rect2i(0, 0, src.get_width(), src.get_height()), node.global_position,
		node.global_transform, node.centered, node.offset, node.flip_h, node.flip_v, node.modulate)

func _draw_texture_rect_software(node: TextureRect, image: Image) -> void:
	var texture = node.texture
	if texture == null:
		return
	var src := _texture_image(texture)
	if src == null:
		return
	var dest := Rect2i(Vector2i(node.global_position), Vector2i(node.size))
	if dest.size.x <= 0 or dest.size.y <= 0:
		dest.size = src.get_size()
	_draw_image_rect(image, src, Rect2i(0, 0, src.get_width(), src.get_height()), dest, false, false, node.modulate)

func _draw_tilemap_software(node: TileMapLayer, image: Image) -> void:
	var tile_set: TileSet = node.tile_set
	if tile_set == null:
		return
	var tile_size: Vector2i = tile_set.tile_size
	for cell in node.get_used_cells():
		var source_id := node.get_cell_source_id(cell)
		var atlas := node.get_cell_atlas_coords(cell)
		var source = tile_set.get_source(source_id)
		if not (source is TileSetAtlasSource):
			continue
		var atlas_source: TileSetAtlasSource = source
		var texture = atlas_source.texture
		if texture == null:
			continue
		var src := texture.get_image()
		if src == null:
			continue
		var region: Rect2i = atlas_source.get_tile_texture_region(atlas)
		var local: Vector2 = node.map_to_local(cell)
		var world: Vector2 = node.to_global(local)
		var dest := Rect2i(Vector2i(world - Vector2(tile_size) * 0.5), tile_size)
		_draw_image_rect(image, src, region, dest, node.is_cell_flipped_h(cell), node.is_cell_flipped_v(cell), Color.WHITE)

func _draw_image_software(image: Image, src: Image, source_rect: Rect2i, position: Vector2,
		transform: Transform2D, centered: bool, offset: Vector2, flip_h: bool, flip_v: bool, modulate: Color) -> void:
	var scale := Vector2(abs(transform.x.length()), abs(transform.y.length()))
	var size := Vector2(source_rect.size) * scale
	var origin := position + offset - (size * 0.5 if centered else Vector2.ZERO)
	_draw_image_rect(image, src, source_rect, Rect2i(Vector2i(origin), Vector2i(size)), flip_h, flip_v, modulate)

func _draw_image_rect(image: Image, src: Image, source_rect: Rect2i, dest: Rect2i,
		flip_h: bool, flip_v: bool, modulate: Color) -> void:
	if dest.size.x <= 0 or dest.size.y <= 0 or source_rect.size.x <= 0 or source_rect.size.y <= 0:
		return
	for dy in range(dest.size.y):
		var sy := int((dy / maxf(1.0, dest.size.y)) * source_rect.size.y)
		if flip_v:
			sy = source_rect.size.y - 1 - sy
		var py := dest.position.y + dy
		if py < 0 or py >= image.get_height():
			continue
		for dx in range(dest.size.x):
			var sx := int((dx / maxf(1.0, dest.size.x)) * source_rect.size.x)
			if flip_h:
				sx = source_rect.size.x - 1 - sx
			var px := dest.position.x + dx
			if px < 0 or px >= image.get_width():
				continue
			var c := src.get_pixel(source_rect.position.x + sx, source_rect.position.y + sy)
			if c.a <= 0.01:
				continue
			c.a *= modulate.a
			c.r *= modulate.r
			c.g *= modulate.g
			c.b *= modulate.b
			var base := image.get_pixel(px, py)
			image.set_pixel(px, py, base.blend(c))

func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	var x0 := maxi(0, rect.position.x)
	var y0 := maxi(0, rect.position.y)
	var x1 := mini(image.get_width(), rect.position.x + rect.size.x)
	var y1 := mini(image.get_height(), rect.position.y + rect.size.y)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var base := image.get_pixel(x, y)
			image.set_pixel(x, y, base.blend(color))

func _software_render_3d(root: Node, size: Vector2i, frame_count: int) -> Array:
	var meshes: Array = []
	_collect_meshes(root, meshes)
	if meshes.is_empty():
		return []
	var positions: Array = []
	_collect_3d_positions(root, positions)
	var center := _average_positions(positions)
	var radius := 1.0
	for p in positions:
		radius = maxf(radius, center.distance_to(p))
	var camera: Camera3D = _find_camera_3d(root)
	var cam_xform := Transform3D()
	var fov := 75.0
	var ortho := false
	var ortho_size := radius * 2.0
	if camera != null and camera.is_inside_tree():
		cam_xform = camera.global_transform
		fov = camera.fov
		ortho = camera.projection == Camera3D.PROJECTION_ORTHOGONAL
		ortho_size = camera.size
	else:
		cam_xform = Transform3D(Basis(), center + Vector3(0, 0, radius * 2.4)).looking_at(center, Vector3.UP)
	var aspect := float(size.x) / float(maxi(1, size.y))
	var images: Array = []
	var triangle_count := 0
	for frame in range(maxi(1, frame_count)):
		var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.06, 0.07, 0.1, 1))
		var zbuf := PackedFloat32Array()
		zbuf.resize(size.x * size.y)
		zbuf.fill(INF)
		var basis := Basis(Vector3.UP, TAU * float(frame) / float(maxi(1, frame_count)))
		for mesh_node in meshes:
			var mesh: Mesh = mesh_node.mesh
			if mesh == null:
				continue
			var world_xform: Transform3D = mesh_node.global_transform if mesh_node.is_inside_tree() else mesh_node.transform
			for surface in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if verts.is_empty():
					continue
				var indices = arrays[Mesh.ARRAY_INDEX]
				var normals = arrays[Mesh.ARRAY_NORMAL]
				var material = mesh_node.get_active_material(surface)
				var color := Color(0.72, 0.76, 0.82)
				if material is StandardMaterial3D:
					color = material.albedo_color
				var tri_count := int(indices.size() / 3) if indices != null and indices.size() > 0 else int(verts.size() / 3)
				for tri in range(tri_count):
					if triangle_count > 100000:
						break
					var i0 := int(indices[tri * 3]) if indices != null and indices.size() > 0 else tri * 3
					var i1 := int(indices[tri * 3 + 1]) if indices != null and indices.size() > 0 else tri * 3 + 1
					var i2 := int(indices[tri * 3 + 2]) if indices != null and indices.size() > 0 else tri * 3 + 2
					var w0 := world_xform * verts[i0]
					var w1 := world_xform * verts[i1]
					var w2 := world_xform * verts[i2]
					w0 = center + basis * (w0 - center)
					w1 = center + basis * (w1 - center)
					w2 = center + basis * (w2 - center)
					var p0 := _project_point(w0, cam_xform, fov, aspect, size, ortho, ortho_size)
					var p1 := _project_point(w1, cam_xform, fov, aspect, size, ortho, ortho_size)
					var p2 := _project_point(w2, cam_xform, fov, aspect, size, ortho, ortho_size)
					if not bool(p0["ok"]) or not bool(p1["ok"]) or not bool(p2["ok"]):
						continue
					var normal := (w1 - w0).cross(w2 - w0).normalized()
					var light := Vector3(0.35, 0.8, 0.45).normalized()
					var shade := clampf(normal.dot(light) * 0.5 + 0.5, 0.35, 1.0)
					var shaded := Color(color.r * shade, color.g * shade, color.b * shade, 1.0)
					_raster_triangle(image, zbuf, p0, p1, p2, shaded)
					triangle_count += 1
		images.append(image)
	return images

func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)

func _average_positions(positions: Array) -> Vector3:
	if positions.is_empty():
		return Vector3.ZERO
	var total := Vector3.ZERO
	for p in positions:
		total += p
	return total / positions.size()

func _project_point(p: Vector3, cam_xform: Transform3D, fov: float, aspect: float, size: Vector2i,
		ortho: bool, ortho_size: float) -> Dictionary:
	var local := cam_xform.affine_inverse() * p
	var z := -local.z
	if z <= 0.02:
		return {"ok": false}
	var nx: float
	var ny: float
	if ortho:
		nx = local.x / maxf(0.001, ortho_size * aspect)
		ny = local.y / maxf(0.001, ortho_size)
	else:
		var f := 1.0 / tan(deg_to_rad(fov) * 0.5)
		nx = local.x * f / aspect / z
		ny = local.y * f / z
	return {"ok": true, "x": (nx * 0.5 + 0.5) * size.x, "y": (-ny * 0.5 + 0.5) * size.y, "z": z}

func _raster_triangle(image: Image, zbuf: PackedFloat32Array, p0: Dictionary, p1: Dictionary, p2: Dictionary, color: Color) -> void:
	var x0 := float(p0["x"]); var y0 := float(p0["y"]); var z0 := float(p0["z"])
	var x1 := float(p1["x"]); var y1 := float(p1["y"]); var z1 := float(p1["z"])
	var x2 := float(p2["x"]); var y2 := float(p2["y"]); var z2 := float(p2["z"])
	var area := (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
	if absf(area) < 0.0001:
		return
	var minx := maxi(0, int(floor(minf(x0, minf(x1, x2)))))
	var maxx := mini(image.get_width() - 1, int(ceil(maxf(x0, maxf(x1, x2)))))
	var miny := maxi(0, int(floor(minf(y0, minf(y1, y2)))))
	var maxy := mini(image.get_height() - 1, int(ceil(maxf(y0, maxf(y1, y2)))))
	for py in range(miny, maxy + 1):
		for px in range(minx, maxx + 1):
			var fx := px + 0.5
			var fy := py + 0.5
			var w0 := ((y1 - y2) * (fx - x2) + (x2 - x1) * (fy - y2)) / area
			var w1 := ((y2 - y0) * (fx - x2) + (x0 - x2) * (fy - y2)) / area
			var w2 := 1.0 - w0 - w1
			if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
				continue
			var z := w0 * z0 + w1 * z1 + w2 * z2
			var index := py * image.get_width() + px
			if z >= zbuf[index]:
				continue
			zbuf[index] = z
			var base := image.get_pixel(px, py)
			image.set_pixel(px, py, base.blend(color))

func _texture_image(texture) -> Image:
	if texture == null:
		return null
	if texture is AtlasTexture:
		var atlas = texture.atlas
		if atlas == null:
			return null
		var image: Image = atlas.get_image()
		if image == null:
			return null
		var rect: Rect2 = texture.region
		if rect.size.x > 0 and rect.size.y > 0:
			return image.get_region(Rect2i(int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y)))
		return image
	if texture.has_method("get_image"):
		return texture.get_image()
	return null

func _pack_images(images: Array, cell_w: int, cell_h: int) -> Dictionary:
	var cols := mini(8, maxi(1, images.size()))
	var rows := int(ceil(float(images.size()) / float(cols)))
	var atlas := Image.create_empty(cols * cell_w, rows * cell_h, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var rects: Array = []
	for i in range(images.size()):
		var x := (i % cols) * cell_w
		var y := int(i / cols) * cell_h
		var image: Image = images[i]
		atlas.blit_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i(x, y))
		rects.append(Rect2i(x, y, image.get_width(), image.get_height()))
	return {"image": atlas, "rects": rects, "cell_w": cell_w, "cell_h": cell_h}

func _find_camera_3d(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for child in node.get_children():
		var cam := _find_camera_3d(child)
		if cam != null:
			return cam
	return null

func _find_camera_2d(node: Node) -> Camera2D:
	if node is Camera2D:
		return node
	for child in node.get_children():
		var cam := _find_camera_2d(child)
		if cam != null:
			return cam
	return null

func _has_3d_geometry(node: Node) -> bool:
	if node is MeshInstance3D or node is Camera3D or node is Node3D and not (node is Node2D):
		return true
	for child in node.get_children():
		if _has_3d_geometry(child):
			return true
	return false

func _scene_center(node: Node) -> Vector3:
	var positions: Array = []
	_collect_3d_positions(node, positions)
	if positions.is_empty():
		return Vector3.ZERO
	var total := Vector3.ZERO
	for p in positions:
		total += p
	return total / positions.size()

func _scene_radius(node: Node) -> float:
	var positions: Array = []
	_collect_3d_positions(node, positions)
	if positions.is_empty():
		return 1.0
	var center := _scene_center(node)
	var radius := 1.0
	for p in positions:
		radius = maxf(radius, center.distance_to(p))
	return radius

func _collect_3d_positions(node: Node, out: Array) -> void:
	if node is Node3D:
		out.append(node.global_position)
	for child in node.get_children():
		_collect_3d_positions(child, out)

func _node_position(node: Node) -> Vector3:
	if node is Node3D:
		return node.global_position
	if node is Node2D:
		return Vector3(node.global_position.x, node.global_position.y, 0)
	if node is Control:
		return Vector3(node.global_position.x, node.global_position.y, 0)
	return Vector3.ZERO

func _state_name(name: String) -> String:
	var out := ""
	for c in name.to_upper():
		out += c if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") else "_"
	return out if not out.is_empty() else "DEFAULT"

func _slug(name: String) -> String:
	var out := ""
	for c in name.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	return out.strip_edges().trim_prefix("_").trim_suffix("_") if not out.is_empty() else "native"

func _register_paths(paths: Array, role: String, source: String) -> void:
	if project == null:
		return
	var resources := project.get_resources()
	var known := {}
	for r in resources:
		known[String(r.get("path", ""))] = true
	var changed := false
	for path in paths:
		var p := String(path)
		if p.is_empty() or known.has(p) or not FileAccess.file_exists(p):
			continue
		var rel := p.trim_prefix(project.get_path().path_join(""))
		var ext := p.get_extension().to_lower()
		var editor := role
		var kind := "native_asset"
		if ext == "png":
			kind = "image"
			editor = "stage" if role == "stage" else "sprite"
		elif ext == "chr":
			kind = "tiles_4bpp"
		elif ext == "pal":
			kind = "cgram_palette" if platform == "snes" else "cram_palette"
			editor = "palette"
		elif ext == "map":
			kind = "snes_tilemap" if platform == "snes" else "vdp_nametable"
			editor = "stage"
		elif ext == "inc" or ext == "h":
			kind = "assembly_source" if ext == "inc" else "c_source"
			editor = "code"
		elif ext == "json":
			kind = "data"
			editor = role
		elif ext == "res":
			kind = "sgdk_resource_script"
			editor = "resources"
		resources.append({
			"id": rel.replace("/", "_"),
			"rel_path": rel,
			"path": p,
			"name": p.get_file(),
			"ext": ext,
			"kind": kind,
			"editor": editor,
			"editable": true,
			"size": FileAccess.get_size(p),
			"note": "Generated from a Godot native scene",
			"group": editor,
			"native_source": source,
		})
		known[p] = true
		changed = true
	if changed:
		project.set_resources(resources)
		project.save()

func _add_asset_row(asset: Dictionary) -> void:
	if _assets == null:
		return
	var root := _assets.get_root() if _assets.get_root() != null else _assets.create_item()
	var item := _assets.create_item(root)
	item.set_text(0, str(asset.get("name", "")))
	item.set_text(1, str(asset.get("type", "")))
	item.set_text(2, str(asset.get("path", "")))
