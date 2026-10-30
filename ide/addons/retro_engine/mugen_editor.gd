@tool
extends VBoxContainer
## MUGEN StateDef / ChangeAnim / ChangeState / HitDef import wizard.
## Parses a character CNS + AIR pair, offers assisted state mapping and builds
## a complete fight state graph plus move profiles for the existing editors.

signal modified()
signal status(text: String)
signal graph_built(graph, moves)
signal state_imported(target_state: String)
signal states_imported(count: int)

var project: RetroProject
var platform: String = "snes"
var animation: RetroAnimation
var input_map: RetroInputMap
var importer: RetroMugenImport

var _cns_path: String = ""
var _air_path: String = ""
var _cmd_path: String = ""
var _commands: Dictionary = {}
var _parsed: Dictionary = {}
var _mapping: Dictionary = {}
var _state_by_number: Dictionary = {}
var _selected: int = -1

var _cns_label: Label
var _air_label: Label
var _cmd_label: Label
var _search: LineEdit
var _only_relevant: CheckBox
var _tree: Tree
var _count_label: Label
var _info: RichTextLabel
var _target: LineEdit
var _suggestion: Label
var _anim_target: OptionButton
var _anim_custom: LineEdit
var _build_info: RichTextLabel
var _max_nodes: SpinBox

func _ready() -> void:
	importer = RetroMugenImport.new()
	add_theme_constant_override("separation", 4)

	var head := HBoxContainer.new()
	add_child(head)
	var title := Label.new()
	title.text = "MUGEN State / Animation Import"
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var load_cns := Button.new()
	load_cns.text = "CNS..."
	load_cns.tooltip_text = "Open a MUGEN character .cns (Statedef/ChangeAnim/ChangeState/HitDef)"
	load_cns.pressed.connect(_pick_cns)
	head.add_child(load_cns)
	var load_air := Button.new()
	load_air.text = "AIR..."
	load_air.tooltip_text = "Open the matching .air animation file"
	load_air.pressed.connect(_pick_air)
	head.add_child(load_air)
	var load_cmd := Button.new()
	load_cmd.text = "CMD..."
	load_cmd.tooltip_text = "Optional .cmd file with named command definitions (236236AC, QCF_x, ...)"
	load_cmd.pressed.connect(_pick_cmd)
	head.add_child(load_cmd)
	var parse_btn := Button.new()
	parse_btn.text = "Parse"
	parse_btn.pressed.connect(_parse)
	head.add_child(parse_btn)

	var paths := HBoxContainer.new()
	add_child(paths)
	_cns_label = Label.new()
	_cns_label.text = "CNS: (none)"
	_cns_label.add_theme_color_override("font_color", Color("#9fb4d0"))
	_cns_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cns_label.clip_text = true
	paths.add_child(_cns_label)
	_air_label = Label.new()
	_air_label.text = "AIR: (none)"
	_air_label.add_theme_color_override("font_color", Color("#9fb4d0"))
	_air_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_air_label.clip_text = true
	paths.add_child(_air_label)
	_cmd_label = Label.new()
	_cmd_label.text = "CMD: (none)"
	_cmd_label.add_theme_color_override("font_color", Color("#9fb4d0"))
	_cmd_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cmd_label.clip_text = true
	paths.add_child(_cmd_label)

	var tools := HBoxContainer.new()
	add_child(tools)
	var auto_map := Button.new()
	auto_map.text = "Auto-map"
	auto_map.tooltip_text = "Map every Statedef to a unique project state name"
	auto_map.pressed.connect(_auto_map)
	tools.add_child(auto_map)
	var max_label := Label.new()
	max_label.text = "Max nodes"
	tools.add_child(max_label)
	_max_nodes = SpinBox.new()
	_max_nodes.min_value = 0
	_max_nodes.max_value = 65535
	_max_nodes.value = 0
	_max_nodes.tooltip_text = "0 = import every mapped state; a positive value caps the generated graph"
	_max_nodes.custom_minimum_size.x = 65
	tools.add_child(_max_nodes)
	var build := Button.new()
	build.text = "Build fight graph"
	build.tooltip_text = "Build nodes/transitions from ChangeState triggers and replace the StateGraph"
	build.pressed.connect(_build_graph)
	tools.add_child(build)
	var save_map := Button.new()
	save_map.text = "Save mapping"
	save_map.pressed.connect(save_session)
	tools.add_child(save_map)
	_search = LineEdit.new()
	_search.placeholder_text = "Filter state / name..."
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _populate())
	tools.add_child(_search)
	_only_relevant = CheckBox.new()
	_only_relevant.text = "Only states with changes/HitDef"
	_only_relevant.button_pressed = true
	_only_relevant.toggled.connect(func(_v): _populate())
	tools.add_child(_only_relevant)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var tree_scroll := ScrollContainer.new()
	tree_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tree_scroll)
	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = 7
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "#")
	_tree.set_column_title(1, "Name")
	_tree.set_column_title(2, "Anim")
	_tree.set_column_title(3, "Frames")
	_tree.set_column_title(4, "Chg")
	_tree.set_column_title(5, "Def")
	_tree.set_column_title(6, "Target")
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 78)
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 115)
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(2, 65)
	_tree.set_column_expand(3, false)
	_tree.set_column_custom_minimum_width(3, 55)
	_tree.set_column_expand(4, false)
	_tree.set_column_custom_minimum_width(4, 36)
	_tree.set_column_expand(5, false)
	_tree.set_column_custom_minimum_width(5, 36)
	_tree.set_column_expand(6, true)
	_tree.set_column_custom_minimum_width(6, 160)
	_tree.item_selected.connect(_on_selected)
	_tree.item_edited.connect(_on_edited)
	_tree.custom_minimum_size = Vector2(640, 300)
	tree_scroll.add_child(_tree)

	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = 310
	body.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 300
	side.add_theme_constant_override("separation", 5)
	side_scroll.add_child(side)

	var slabel := Label.new()
	slabel.text = "Selected MUGEN state"
	slabel.add_theme_color_override("font_color", Color("#7fd1ff"))
	side.add_child(slabel)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.custom_minimum_size.y = 150
	side.add_child(_info)

	side.add_child(HSeparator.new())
	var mlabel := Label.new()
	mlabel.text = "Assisted mapping"
	mlabel.add_theme_color_override("font_color", Color("#7fd1ff"))
	side.add_child(mlabel)
	_suggestion = Label.new()
	_suggestion.text = "Suggestion: -"
	_suggestion.add_theme_color_override("font_color", Color("#9fb4d0"))
	side.add_child(_suggestion)
	_target = LineEdit.new()
	_target.placeholder_text = "Target state (e.g. ATTACK)"
	side.add_child(_target)
	var target_row := HBoxContainer.new()
	side.add_child(target_row)
	var use_suggested := Button.new()
	use_suggested.text = "Use suggestion"
	use_suggested.pressed.connect(_use_suggestion)
	target_row.add_child(use_suggested)
	var apply_target := Button.new()
	apply_target.text = "Apply mapping"
	apply_target.pressed.connect(_apply_target)
	target_row.add_child(apply_target)
	var clear_target := Button.new()
	clear_target.text = "Clear"
	clear_target.pressed.connect(_clear_target)
	target_row.add_child(clear_target)

	side.add_child(HSeparator.new())
	var ilabel := Label.new()
	ilabel.text = "Import into animation"
	ilabel.add_theme_color_override("font_color", Color("#7fd1ff"))
	side.add_child(ilabel)
	_anim_target = OptionButton.new()
	side.add_child(_anim_target)
	_anim_custom = LineEdit.new()
	_anim_custom.placeholder_text = "or new state name"
	side.add_child(_anim_custom)
	var import_btn := Button.new()
	import_btn.text = "Import AIR + HitDef"
	import_btn.tooltip_text = "Replace the target animation state frames with this state's AIR action and apply its HitDef move data"
	import_btn.pressed.connect(_import_selected)
	side.add_child(import_btn)
	var import_all := Button.new()
	import_all.text = "Import all mapped states"
	import_all.tooltip_text = "Create every mapped animation state from its AIR action and rebuild the fight graph"
	import_all.pressed.connect(_import_all)
	side.add_child(import_all)

	side.add_child(HSeparator.new())
	var blabel := Label.new()
	blabel.text = "Generated fight graph"
	blabel.add_theme_color_override("font_color", Color("#7fd1ff"))
	side.add_child(blabel)
	_build_info = RichTextLabel.new()
	_build_info.bbcode_enabled = true
	_build_info.fit_content = true
	_build_info.custom_minimum_size.y = 120
	side.add_child(_build_info)

	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", Color("#9fb4d0"))
	add_child(_count_label)

func set_context(p_project: RetroProject, p_platform: String, p_animation: RetroAnimation, p_input: RetroInputMap) -> void:
	project = p_project
	platform = p_platform
	animation = p_animation
	input_map = p_input
	if importer == null:
		importer = RetroMugenImport.new()
	_load_session()
	_refresh_paths()
	_refresh_anim_targets()
	if not _cns_path.is_empty() and not _air_path.is_empty():
		_parse()

func set_platform(p_platform: String) -> void:
	platform = p_platform

func set_animation(p_animation: RetroAnimation) -> void:
	animation = p_animation
	_refresh_anim_targets()

func set_input_map(p_input: RetroInputMap) -> void:
	input_map = p_input

func get_mapping() -> Dictionary:
	return _mapping.duplicate(true)

func get_parsed() -> Dictionary:
	return _parsed

func get_cns_path() -> String:
	return _cns_path

func get_air_path() -> String:
	return _air_path

func get_selected_state() -> Dictionary:
	return _state_by_number.get(_selected, {})

func save_session() -> void:
	if project == null:
		return
	var dir := project.resolve(".retro/editor")
	DirAccess.make_dir_recursive_absolute(dir)
	var data := {
		"format": "godot-retro-engine/mugen-mapping",
		"version": 1,
		"cns": _cns_path,
		"air": _air_path,
		"cmd": _cmd_path,
		"mappings": _mapping,
	}
	var f := FileAccess.open(dir.path_join("mugen_mapping.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func _load_session() -> void:
	if project == null:
		return
	_cns_path = ""
	_air_path = ""
	_cmd_path = ""
	_commands = {}
	_mapping = {}
	var path := project.resolve(".retro/editor/mugen_mapping.json")
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_cns_path = String(data.get("cns", ""))
	_air_path = String(data.get("air", ""))
	_cmd_path = String(data.get("cmd", ""))
	var mappings = data.get("mappings", {})
	if typeof(mappings) == TYPE_DICTIONARY:
		_mapping = mappings.duplicate(true)

func _pick_cns() -> void:
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.add_filter("*.cns, *.cmd, *.def", "MUGEN CNS / command definitions")
	dlg.file_selected.connect(func(path):
		_cns_path = path
		_refresh_paths()
		if not _air_path.is_empty():
			_parse()
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.65)

func _pick_air() -> void:
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.add_filter("*.air", "MUGEN AIR animations")
	dlg.file_selected.connect(func(path):
		_air_path = path
		_refresh_paths()
		if not _cns_path.is_empty():
			_parse()
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.65)

func _pick_cmd() -> void:
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.add_filter("*.cmd", "MUGEN command definitions")
	dlg.file_selected.connect(func(path):
		_cmd_path = path
		_refresh_paths()
		_parse()
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.65)

func _refresh_paths() -> void:
	_cns_label.text = "CNS: " + (_cns_path if not _cns_path.is_empty() else "(none)")
	_air_label.text = "AIR: " + (_air_path if not _air_path.is_empty() else "(none)")
	_cmd_label.text = "CMD: " + (_cmd_path if not _cmd_path.is_empty() else "(none)")
	_cns_label.tooltip_text = _cns_path
	_air_label.tooltip_text = _air_path
	_cmd_label.tooltip_text = _cmd_path

func _parse() -> void:
	if _cns_path.is_empty() or _air_path.is_empty():
		status.emit("Select both a CNS and an AIR file.")
		return
	_parsed = importer.parse_states(_cns_path, _air_path)
	if not bool(_parsed.get("ok", false)):
		status.emit("MUGEN parse failed: " + String(_parsed.get("error", "unknown error")))
		_build_info.text = "[color=#ff7a7a]Parse failed.[/color]"
		return
	_state_by_number = {}
	for st in _parsed.get("states", []):
		_state_by_number[int(st.get("number", -1))] = st
	_commands = {}
	if not _cmd_path.is_empty() and FileAccess.file_exists(_cmd_path):
		var parsed_cmd := importer.parse_commands(_cmd_path)
		if bool(parsed_cmd.get("ok", false)):
			_commands = parsed_cmd.get("commands", {})
	if _mapping.is_empty():
		_auto_map()
	else:
		_populate()
	status.emit("MUGEN parsed: %d states, %d AIR actions, %d commands." % [
		int(_parsed.get("state_count", 0)), int(_parsed.get("air_action_count", 0)), _commands.size()])

func _relevant(st: Dictionary) -> bool:
	var num := int(st.get("number", -1))
	return _mapping.has(str(num)) or Array(st.get("changes", [])).size() > 0 or int(st.get("hitdef_count", 0)) > 0 or num == 0

func _populate() -> void:
	if _tree == null:
		return
	_tree.clear()
	var root := _tree.create_item()
	var query := _search.text.strip_edges().to_lower() if _search else ""
	var shown := 0
	var first_item: TreeItem = null
	var first_active: TreeItem = null
	var states: Array = _parsed.get("states", [])
	for st in states:
		var num := int(st.get("number", -1))
		if _only_relevant.button_pressed and not _relevant(st):
			continue
		var name := String(st.get("name", "State %d" % num))
		if not query.is_empty() and not str(num).contains(query) and not name.to_lower().contains(query):
			continue
		var item := _tree.create_item(root)
		item.set_text(0, str(num))
		item.set_text(1, name)
		item.set_text(2, str(int(st.get("air_action", 0))))
		item.set_text(3, str(int(st.get("air_frames", 0))))
		item.set_text(4, str(Array(st.get("changes", [])).size()))
		item.set_text(5, str(int(st.get("hitdef_count", 0))))
		var key := str(num)
		item.set_text(6, String(_mapping.get(key, "")))
		item.set_cell_mode(6, TreeItem.CELL_MODE_STRING)
		item.set_editable(6, true)
		item.set_metadata(0, num)
		if first_item == null:
			first_item = item
		if first_active == null and int(st.get("hitdef_count", 0)) > 0:
			first_active = item
		shown += 1
	_count_label.text = "%d / %d states shown | %d mapped | build cap %d nodes" % [
		shown, states.size(), _mapping.size(), int(_max_nodes.value) if _max_nodes else 48]
	if _selected >= 0 and _state_by_number.has(_selected):
		_on_selected()
	elif first_item != null:
		var pick := first_active if first_active != null else first_item
		_tree.set_selected(pick, 0)
		_selected = int(pick.get_metadata(0))
		_on_selected()

func _selected_item() -> TreeItem:
	if _tree == null:
		return null
	return _tree.get_selected()

func _on_selected() -> void:
	var item := _selected_item()
	if item == null:
		return
	_selected = int(item.get_metadata(0))
	var st: Dictionary = _state_by_number.get(_selected, {})
	if st.is_empty():
		return
	var changes: Array = st.get("changes", [])
	var defs: Array = st.get("hitdefs", [])
	var text := "[b]%d[/b]  %s\n" % [_selected, String(st.get("name", ""))]
	text += "Anim %d | %d frames | %d hits | %d hurtboxes\n" % [
		int(st.get("air_action", 0)), int(st.get("air_frames", 0)),
		int(st.get("air_hits", 0)), int(st.get("air_hurts", 0))]
	text += "Changes: %d | HitDefs: %d\n" % [changes.size(), defs.size()]
	if not defs.is_empty():
		var hd: Dictionary = st.get("hitdef_data", {})
		text += "[color=#9fb4d0]damage %s | hitstop %d/%d | hitstun %d | guard %s[/color]\n" % [
			String(hd.get("damage_raw", str(hd.get("damage", 0)))),
			int(hd.get("hitstop_attacker", 0)), int(hd.get("hitstop_defender", 0)),
			int(hd.get("hitstun", 0)), String(hd.get("guardflag", "M"))]
	for ch in changes:
		text += "[color=#7fd1ff]-> %s[/color]  %s\n" % [
			String(ch.get("value", "?")), str(Array(ch.get("triggers", [])).slice(0, 2))]
	_info.text = text
	_suggestion.text = "Suggestion: " + String(st.get("suggested", "-"))
	_target.text = String(_mapping.get(str(_selected), ""))
	_refresh_anim_targets()

func _on_edited() -> void:
	var item := _tree.get_edited()
	if item == null:
		return
	var num := int(item.get_metadata(0))
	var value := item.get_text(6).strip_edges()
	if value.is_empty():
		_mapping.erase(str(num))
	else:
		_mapping[str(num)] = value
	save_session()
	modified.emit()
	if num == _selected:
		_target.text = value
	status.emit("Mapping state %d -> %s" % [num, value if not value.is_empty() else "(none)"])

func _use_suggestion() -> void:
	var st: Dictionary = _state_by_number.get(_selected, {})
	if st.is_empty():
		return
	_target.text = String(st.get("suggested", "IDLE"))

func _apply_target() -> void:
	if _selected < 0:
		return
	var value := _target.text.strip_edges()
	if value.is_empty():
		_mapping.erase(str(_selected))
	else:
		_mapping[str(_selected)] = value
	save_session()
	_populate()
	modified.emit()
	status.emit("Mapping state %d -> %s" % [_selected, value if not value.is_empty() else "(none)"])

func _clear_target() -> void:
	if _selected < 0:
		return
	_mapping.erase(str(_selected))
	_target.text = ""
	save_session()
	_populate()
	modified.emit()

func _auto_map() -> void:
	var auto := importer.auto_map_states(_parsed)
	if not bool(auto.get("ok", false)):
		status.emit("Auto-map requires parsed states.")
		return
	var generated: Dictionary = auto.get("mapping", {})
	var used := {}
	for key in _mapping.keys():
		used[String(_mapping[key])] = true
	var added := 0
	for key in generated.keys():
		if _mapping.has(key):
			continue
		var name := String(generated[key])
		if used.has(name):
			name = "%s_%s" % [name, String(key)]
		var suffix := 2
		while used.has(name):
			name = "%s_%s_%d" % [String(generated[key]), String(key), suffix]
			suffix += 1
		_mapping[key] = name
		used[name] = true
		added += 1
	save_session()
	_populate()
	modified.emit()
	status.emit("Auto-mapped %d states (%d total)." % [added, _mapping.size()])

func _refresh_anim_targets() -> void:
	if _anim_target == null:
		return
	var current := _anim_target.get_item_text(_anim_target.selected) if _anim_target.item_count > 0 else ""
	_anim_target.clear()
	if animation == null:
		return
	for key in animation.get_states().keys():
		_anim_target.add_item(String(key))
	if not current.is_empty():
		for i in range(_anim_target.item_count):
			if _anim_target.get_item_text(i) == current:
				_anim_target.select(i)
				break

func _animation_target() -> String:
	var custom := _anim_custom.text.strip_edges()
	if not custom.is_empty():
		return custom
	if _anim_target.item_count > 0 and _anim_target.selected >= 0:
		return _anim_target.get_item_text(_anim_target.selected)
	return ""

func _import_selected() -> void:
	if _selected < 0 or animation == null:
		status.emit("Select a MUGEN state and an animation first.")
		return
	var target := _animation_target()
	if target.is_empty():
		status.emit("Choose a target animation state.")
		return
	var st: Dictionary = _state_by_number.get(_selected, {})
	if int(st.get("air_frames", 0)) <= 0:
		status.emit("State %d has no AIR action frames to import." % _selected)
		return
	var result := importer.import_state(_cns_path, _air_path, _selected, animation, target)
	if bool(result.get("ok", false)):
		_anim_custom.text = target
		_refresh_anim_targets()
		state_imported.emit(target)
		status.emit("Imported state %d (%d frames) into %s." % [
			_selected, int(Dictionary(result.get("import", {})).get("frames", 0)), target])
		modified.emit()
	else:
		status.emit("Import failed: " + String(result.get("error", "unknown error")))

func _import_all() -> void:
	if not bool(_parsed.get("ok", false)) or animation == null:
		status.emit("Parse a CNS/AIR pair and choose an animation first.")
		return
	if _mapping.is_empty():
		_auto_map()
	var result: Dictionary = importer.import_mapped_states(_parsed, _mapping, animation, _air_path)
	if not bool(result.get("ok", false)):
		status.emit("Batch import failed: " + String(result.get("error", "no AIR frames")))
		return
	states_imported.emit(int(result.get("states", 0)))
	_build_graph()
	status.emit("Imported %d states (%d frames, %d hitboxes, %d hurtboxes)." % [
		int(result.get("states", 0)), int(result.get("frames", 0)),
		int(result.get("hit_boxes", 0)), int(result.get("hurt_boxes", 0))])

func _build_graph() -> void:
	if not bool(_parsed.get("ok", false)):
		status.emit("Parse a CNS/AIR pair before building the graph.")
		return
	if _mapping.is_empty():
		_auto_map()
	var built := importer.build_fight_graph(_parsed, _mapping, input_map, int(_max_nodes.value), _commands)
	if not bool(built.get("ok", false)):
		status.emit("Graph build failed: " + String(built.get("error", "unknown error")))
		return
	var warnings: Array = built.get("warnings", [])
	var text := "[color=#6ee7a8]Nodes %d | Transitions %d[/color]\n" % [
		int(built.get("node_count", 0)), int(built.get("transition_count", 0))]
	text += "Auto nodes: %d | Skipped triggers: %d\n" % [
		int(built.get("auto_node_count", 0)), int(built.get("skipped_transitions", 0))]
	if not warnings.is_empty():
		text += "[color=#ffd45e]Warnings:[/color]\n"
		for w in warnings.slice(0, 8):
			text += "- %s\n" % String(w)
	_build_info.text = text
	graph_built.emit(built.get("graph"), built.get("moves", []))
	modified.emit()
	status.emit("Fight graph built: %d nodes, %d transitions, %d moves." % [
		int(built.get("node_count", 0)), int(built.get("transition_count", 0)),
		Array(built.get("moves", [])).size()])
