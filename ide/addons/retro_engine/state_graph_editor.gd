@tool
extends VBoxContainer
## Visual state graph editor with compound conditions, cooldown, priority
## and animation-duration auto transitions. Exports a standalone C runtime.

signal modified()
signal status(text: String)

var project: RetroProject
var platform: String = "snes"
var input_map: RetroInputMap
var animation: RetroAnimation
var graph: RetroStateGraph

var _graph_edit: GraphEdit
var _node_state: LineEdit
var _node_duration: SpinBox
var _transition_list: ItemList
var _from: OptionButton
var _to: OptionButton
var _op: OptionButton
var _cooldown: SpinBox
var _priority: SpinBox
var _auto: CheckBox
var _cond_box: VBoxContainer
var _cond_data: Array = []
var _current_transition: String = ""
var _selected_node: String = ""
var _validation: RichTextLabel
var _sync_durations: CheckBox

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	add_child(head)
	var title := Label.new()
	title.text = "State Graph / Condition & Cooldown Runtime"
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var add_node := Button.new()
	add_node.text = "Add state"
	add_node.pressed.connect(_add_node)
	head.add_child(add_node)
	var rebuild := Button.new()
	rebuild.text = "From Inputs"
	rebuild.tooltip_text = "Rebuild nodes/transitions from the current Inputs map (overwrites graph)"
	rebuild.pressed.connect(_rebuild_from_inputs)
	head.add_child(rebuild)
	var gen := Button.new()
	gen.text = "Generate C"
	gen.pressed.connect(_export_c)
	head.add_child(gen)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	add_child(body)
	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_edit.minimap_enabled = false
	_graph_edit.show_grid = true
	_graph_edit.snapping_enabled = true
	_graph_edit.connection_request.connect(_on_connection_request)
	_graph_edit.disconnection_request.connect(_on_disconnection_request)
	_graph_edit.delete_nodes_request.connect(_on_delete_nodes)
	_graph_edit.node_selected.connect(_on_node_selected)
	body.add_child(_graph_edit)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 235
	body.add_child(scroll)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 225
	side.add_theme_constant_override("separation", 3)
	scroll.add_child(side)

	var nlabel := Label.new()
	nlabel.text = "Selected state"
	nlabel.add_theme_color_override("font_color", Color("#7fd1ff"))
	side.add_child(nlabel)
	_node_state = LineEdit.new()
	_node_state.placeholder_text = "IDLE"
	side.add_child(_node_state)
	var nrow := HBoxContainer.new()
	side.add_child(nrow)
	var dlabel := Label.new()
	dlabel.text = "Duration"
	nrow.add_child(dlabel)
	_node_duration = SpinBox.new()
	_node_duration.min_value = 0
	_node_duration.max_value = 65535
	_node_duration.custom_minimum_size.x = 75
	nrow.add_child(_node_duration)
	var apply_node := Button.new()
	apply_node.text = "Apply state"
	apply_node.pressed.connect(_apply_node)
	side.add_child(apply_node)
	_sync_durations = CheckBox.new()
	_sync_durations.text = "Sync animation durations"
	_sync_durations.button_pressed = true
	_sync_durations.toggled.connect(func(_v): _sync_node_durations(); modified.emit())
	side.add_child(_sync_durations)

	var sep := HSeparator.new()
	side.add_child(sep)
	var tlabel := Label.new()
	tlabel.text = "Transitions"
	tlabel.add_theme_color_override("font_color", Color("#7fd1ff"))
	side.add_child(tlabel)
	_transition_list = ItemList.new()
	_transition_list.custom_minimum_size.y = 80
	_transition_list.item_selected.connect(_on_transition_selected)
	side.add_child(_transition_list)
	var trow := HBoxContainer.new()
	side.add_child(trow)
	var add_t := Button.new()
	add_t.text = "New transition"
	add_t.pressed.connect(_add_transition)
	trow.add_child(add_t)
	var del_t := Button.new()
	del_t.text = "Delete"
	del_t.pressed.connect(_delete_transition)
	trow.add_child(del_t)

	var frow := HBoxContainer.new()
	side.add_child(frow)
	var fl := Label.new()
	fl.text = "From"
	frow.add_child(fl)
	_from = OptionButton.new()
	_from.custom_minimum_size.x = 120
	frow.add_child(_from)
	var trow2 := HBoxContainer.new()
	side.add_child(trow2)
	var tl := Label.new()
	tl.text = "To"
	trow2.add_child(tl)
	_to = OptionButton.new()
	_to.custom_minimum_size.x = 120
	trow2.add_child(_to)

	var crow := HBoxContainer.new()
	side.add_child(crow)
	var ol := Label.new()
	ol.text = "Match"
	crow.add_child(ol)
	_op = OptionButton.new()
	_op.add_item("ALL")
	_op.add_item("ANY")
	crow.add_child(_op)
	_auto = CheckBox.new()
	_auto.text = "Auto"
	_auto.tooltip_text = "Fire when the source state animation duration ends"
	_auto.toggled.connect(_on_auto_toggled)
	crow.add_child(_auto)

	var numrow := HBoxContainer.new()
	side.add_child(numrow)
	var cl := Label.new()
	cl.text = "Cooldown"
	numrow.add_child(cl)
	_cooldown = SpinBox.new()
	_cooldown.min_value = 0
	_cooldown.max_value = 65535
	_cooldown.custom_minimum_size.x = 60
	numrow.add_child(_cooldown)
	var pl := Label.new()
	pl.text = "Prio"
	numrow.add_child(pl)
	_priority = SpinBox.new()
	_priority.min_value = 0
	_priority.max_value = 255
	_priority.custom_minimum_size.x = 55
	numrow.add_child(_priority)

	var cclabel := Label.new()
	cclabel.text = "Conditions"
	side.add_child(cclabel)
	_cond_box = VBoxContainer.new()
	side.add_child(_cond_box)
	var addc := Button.new()
	addc.text = "Add condition"
	addc.pressed.connect(_add_condition)
	side.add_child(addc)
	var apply_t := Button.new()
	apply_t.text = "Apply transition"
	apply_t.pressed.connect(_apply_transition)
	side.add_child(apply_t)

	var vlabel := Label.new()
	vlabel.text = "Validation"
	vlabel.add_theme_color_override("font_color", Color("#7fd1ff"))
	side.add_child(vlabel)
	_validation = RichTextLabel.new()
	_validation.bbcode_enabled = true
	_validation.fit_content = true
	_validation.custom_minimum_size.y = 90
	side.add_child(_validation)

func set_context(p_project: RetroProject, p_platform: String, p_input: RetroInputMap, p_animation: RetroAnimation) -> void:
	project = p_project
	platform = p_platform
	input_map = p_input
	animation = p_animation
	graph = RetroStateGraph.new()
	var loaded := false
	if project:
		var path := project.resolve(".retro/editor/state_graph.json")
		if FileAccess.file_exists(path):
			graph.load(path)
			loaded = true
		else:
			graph.setup_from_input_map(input_map)
	else:
		graph.setup_from_input_map(input_map)
	graph.set_platform(platform)
	if input_map:
		input_map.set_platform(platform)
	if not loaded:
		_sync_node_durations()
	_rebuild_graph()

func set_platform(p_platform: String) -> void:
	platform = p_platform
	if graph:
		graph.set_platform(platform)

func set_input_map(p_input: RetroInputMap) -> void:
	input_map = p_input
	if graph:
		_refresh_validation()

func set_animation(p_animation: RetroAnimation) -> void:
	animation = p_animation
	var mugen_graph := graph != null and String(graph.get_metadata().get("source", "")) == "mugen"
	if _sync_durations and _sync_durations.button_pressed and not mugen_graph:
		_sync_node_durations()
	_refresh_node_titles()

func get_graph() -> RetroStateGraph:
	return graph

func replace_graph(p_graph: RetroStateGraph) -> void:
	graph = p_graph
	if graph:
		graph.set_platform(platform)
	_rebuild_graph()
	modified.emit()
	status.emit("State graph replaced (%d nodes, %d transitions)." % [
		graph.get_nodes().size() if graph else 0,
		graph.get_transitions().size() if graph else 0])

func save_session() -> void:
	if project and graph:
		var dir := project.resolve(".retro/editor")
		DirAccess.make_dir_recursive_absolute(dir)
		graph.save(dir.path_join("state_graph.json"))

func _sync_node_durations() -> void:
	if graph == null or animation == null:
		return
	var states := animation.get_states()
	for n in graph.get_nodes():
		var state := String(n.get("state", ""))
		if not states.has(state):
			continue  # Do not zero imported/MUGEN-only states.
		var dur := animation.total_duration(state)
		graph.update_node(String(n.get("id", "")), {"duration": dur})
	_refresh_node_titles()

func _rebuild_graph() -> void:
	_graph_edit.clear_connections()
	for child in _graph_edit.get_children():
		if child is GraphNode:
			_graph_edit.remove_child(child)
			child.queue_free()
	if graph == null:
		return
	for n in graph.get_nodes():
		var nid := String(n.get("id", ""))
		var gn := GraphNode.new()
		gn.name = nid
		gn.title = "%s  [%df]" % [String(n.get("state", "")), int(n.get("duration", 0))]
		gn.position_offset = Vector2(int(n.get("x", 0)), int(n.get("y", 0)))
		gn.set_slot(0, true, 0, Color("#7fd1ff"), true, 0, Color("#6ee7a8"))
		var lbl := Label.new()
		lbl.name = "Info"
		lbl.text = "state: " + String(n.get("state", ""))
		lbl.add_theme_color_override("font_color", Color("#9fb4d0"))
		gn.add_child(lbl)
		gn.position_offset_changed.connect(_on_node_moved.bind(nid))
		_graph_edit.add_child(gn)
	# Connections: one visual edge per pair (multiple conditions are edited in
	# the transition list, not duplicated as overlapping GraphEdit edges).
	var seen := {}
	for t in graph.get_transitions():
		var from := String(t.get("from", ""))
		var to := String(t.get("to", ""))
		var key := from + "|" + to
		if seen.has(key):
			continue
		seen[key] = true
		_graph_edit.connect_node(from, 0, to, 0)
	_refresh_from_to()
	_refresh_transitions()
	_refresh_validation()

func _refresh_node_titles() -> void:
	if graph == null:
		return
	for n in graph.get_nodes():
		var nid := String(n.get("id", ""))
		var gn := _graph_edit.get_node_or_null(NodePath(nid))
		if gn is GraphNode:
			gn.title = "%s  [%df]" % [String(n.get("state", "")), int(n.get("duration", 0))]

func _refresh_from_to() -> void:
	_from.clear()
	_to.clear()
	if graph == null:
		return
	for n in graph.get_nodes():
		var nid := String(n.get("id", ""))
		_from.add_item(nid)
		_to.add_item(nid)

func _refresh_transitions() -> void:
	_transition_list.clear()
	if graph == null:
		return
	for t in graph.get_transitions():
		var text := "%s -> %s  [%s]" % [String(t.get("from", "")), String(t.get("to", "")), "auto" if bool(t.get("auto", false)) else String(t.get("op", "ALL"))]
		var seq_count := 0
		for c in Array(t.get("conditions", [])):
			if Dictionary(c).has("sequence"):
				seq_count += 1
		if seq_count > 0:
			text += " seq%d" % seq_count
		_transition_list.add_item(text)
		_transition_list.set_item_tooltip(_transition_list.item_count - 1, String(t.get("id", "")))

func _refresh_validation() -> void:
	if graph == null:
		return
	var v := graph.validate(input_map)
	var text := ""
	for e in v.get("errors", []):
		text += "[color=#ff7a7a]- %s[/color]\n" % String(e)
	for w in v.get("warnings", []):
		text += "[color=#ffd45e]- %s[/color]\n" % String(w)
	if text.is_empty():
		text = "[color=#6ee7a8]Graph valid.[/color]"
	_validation.text = text

func _on_node_moved(nid: String) -> void:
	var gn := _graph_edit.get_node_or_null(NodePath(nid))
	if gn is GraphNode and graph:
		graph.update_node(nid, {"x": int(gn.position_offset.x), "y": int(gn.position_offset.y)})
		modified.emit()

func _on_node_selected(node: Node) -> void:
	_selected_node = String(node.name)
	var n := graph.get_node(_selected_node) if graph else {}
	_node_state.text = String(n.get("state", ""))
	_node_duration.set_value_no_signal(int(n.get("duration", 0)))

func _add_node() -> void:
	if graph == null:
		return
	var count := graph.get_nodes().size() + 1
	graph.add_node("STATE_%d" % count, Vector2(40 + (count % 4) * 200, 40 + (count / 4) * 120), 0)
	_rebuild_graph()
	modified.emit()
	status.emit("State added.")

func _apply_node() -> void:
	if graph == null or _selected_node.is_empty():
		return
	graph.update_node(_selected_node, {"state": _node_state.text.strip_edges(), "duration": int(_node_duration.value)})
	_rebuild_graph()
	modified.emit()

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if graph == null:
		return
	var conditions: Array = []
	if input_map and input_map.get_actions().size() > 0:
		conditions.append({"action": String(input_map.get_actions()[0].get("id", "")), "mode": "pressed"})
	graph.add_transition({
		"from": String(from_node), "to": String(to_node),
		"conditions": conditions, "op": "all", "cooldown": 0,
		"priority": 0, "auto": false,
	})
	_graph_edit.connect_node(from_node, from_port, to_node, to_port)
	_rebuild_graph()
	modified.emit()
	status.emit("Transition created; edit its conditions on the right.")

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if graph == null:
		return
	graph.remove_transitions_between(String(from_node), String(to_node))
	_graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
	_rebuild_graph()
	modified.emit()

func _on_delete_nodes(nodes: Array) -> void:
	if graph == null:
		return
	for n in nodes:
		graph.remove_node(String(n))
	_rebuild_graph()
	modified.emit()

func _add_transition() -> void:
	if graph == null or graph.get_nodes().size() < 2:
		return
	var from := String(graph.get_nodes()[0].get("id", ""))
	var to := String(graph.get_nodes()[1].get("id", ""))
	var conditions: Array = []
	if input_map and input_map.get_actions().size() > 0:
		conditions.append({"action": String(input_map.get_actions()[0].get("id", "")), "mode": "pressed"})
	graph.add_transition({"from": from, "to": to, "conditions": conditions, "op": "all", "cooldown": 0, "priority": 0, "auto": false})
	_rebuild_graph()
	modified.emit()

func _on_transition_selected(index: int) -> void:
	if graph == null:
		return
	var trans := graph.get_transitions()
	if index < 0 or index >= trans.size():
		return
	var t: Dictionary = trans[index]
	_current_transition = String(t.get("id", ""))
	_select_option(_from, String(t.get("from", "")))
	_select_option(_to, String(t.get("to", "")))
	_op.select(1 if String(t.get("op", "all")) == "any" else 0)
	_cooldown.set_value_no_signal(int(t.get("cooldown", 0)))
	_priority.set_value_no_signal(int(t.get("priority", 0)))
	_auto.button_pressed = bool(t.get("auto", false))
	_cond_data = []
	for c in t.get("conditions", []):
		var cond: Dictionary = c
		if cond.has("sequence"):
			_cond_data.append(cond.duplicate(true))
		else:
			_cond_data.append({"action": String(cond.get("action", "")), "mode": String(cond.get("mode", "pressed"))})
	_rebuild_conditions()

func _select_option(opt: OptionButton, text: String) -> void:
	for i in range(opt.item_count):
		if opt.get_item_text(i) == text:
			opt.select(i)
			return
	if opt.item_count > 0:
		opt.select(0)

func _rebuild_conditions() -> void:
	for c in _cond_box.get_children():
		c.queue_free()
	for i in range(_cond_data.size()):
		var row := HBoxContainer.new()
		if Dictionary(_cond_data[i]).has("sequence"):
			var seq_label := Label.new()
			seq_label.text = "SEQ %s (%d steps)" % [
				String(Dictionary(_cond_data[i]).get("command", "command")),
				Array(Dictionary(_cond_data[i]).get("sequence", [])).size()]
			seq_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			seq_label.add_theme_color_override("font_color", Color("#7fd1ff"))
			row.add_child(seq_label)
			var seq_del := Button.new()
			seq_del.text = "x"
			seq_del.pressed.connect(_remove_condition.bind(i))
			row.add_child(seq_del)
			_cond_box.add_child(row)
			continue
		var action := OptionButton.new()
		if input_map:
			for a in input_map.get_actions():
				action.add_item(String(a.get("id", "")))
		_select_option(action, String(_cond_data[i].get("action", "")))
		action.item_selected.connect(func(_idx): _cond_data[i]["action"] = action.get_item_text(_idx))
		row.add_child(action)
		var mode := OptionButton.new()
		mode.add_item("pressed")
		mode.add_item("held")
		mode.add_item("released")
		_select_option(mode, String(_cond_data[i].get("mode", "pressed")))
		mode.item_selected.connect(func(idx): _cond_data[i]["mode"] = ["pressed", "held", "released"][idx])
		row.add_child(mode)
		var del := Button.new()
		del.text = "x"
		del.pressed.connect(_remove_condition.bind(i))
		row.add_child(del)
		_cond_box.add_child(row)
	_cond_box.visible = not _auto.button_pressed

func _on_auto_toggled(on: bool) -> void:
	if _cond_box:
		_cond_box.visible = not on

func _add_condition() -> void:
	if input_map == null or input_map.get_actions().is_empty():
		return
	_cond_data.append({"action": String(input_map.get_actions()[0].get("id", "")), "mode": "pressed"})
	_rebuild_conditions()

func _remove_condition(index: int) -> void:
	if index >= 0 and index < _cond_data.size():
		_cond_data.remove_at(index)
		_rebuild_conditions()

func _apply_transition() -> void:
	if graph == null or _current_transition.is_empty():
		return
	var data := {
		"from": _from.get_item_text(_from.selected),
		"to": _to.get_item_text(_to.selected),
		"conditions": _cond_data,
		"op": "any" if _op.selected == 1 else "all",
		"cooldown": int(_cooldown.value),
		"priority": int(_priority.value),
		"auto": _auto.button_pressed,
	}
	graph.update_transition(_current_transition, data)
	_rebuild_graph()
	modified.emit()
	status.emit("Transition updated.")

func _delete_transition() -> void:
	if graph == null or _current_transition.is_empty():
		return
	graph.remove_transition(_current_transition)
	_current_transition = ""
	_rebuild_graph()
	modified.emit()

func _rebuild_from_inputs() -> void:
	if graph == null or input_map == null:
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Rebuild graph"
	dlg.dialog_text = "Rebuild nodes and transitions from the current Inputs map? Manual graph edits will be lost."
	dlg.confirmed.connect(func():
		graph.setup_from_input_map(input_map)
		graph.set_platform(platform)
		_sync_node_durations()
		_rebuild_graph()
		modified.emit()
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(460, 180))

func _export_c() -> void:
	if graph == null or input_map == null or project == null:
		return
	var v := graph.validate(input_map)
	if not bool(v.get("ok", false)):
		status.emit("Fix graph errors before exporting.")
		_refresh_validation()
		return
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.current_dir = project.resolve("src")
	dlg.dir_selected.connect(func(dir):
		var result: Dictionary
		if platform == "snes":
			result = graph.export_snes(dir, "retro_state_machine", input_map)
		else:
			result = graph.export_sgdk(dir, "retro_state_machine", input_map)
		status.emit("Graph C generated: " + String(result.get("source", "")))
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)
