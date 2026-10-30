@tool
extends VBoxContainer
## Code browser: indexes C functions and assembly labels, edits sources with
## backups, and stores explicit code<->resource associations in project JSON.

signal status(text: String)
signal modified()

var project: RetroProject
var current_resource: Dictionary = {}
var current_file: String = ""
var _tree: Tree
var _code: CodeEdit
var _search: LineEdit
var _file_label: Label
var _assoc_note: LineEdit
var _assoc_list: ItemList
var _symbols: Array = []

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	add_child(top)
	_search = LineEdit.new()
	_search.placeholder_text = "Filter symbols..."
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _rebuild_tree())
	top.add_child(_search)
	var reindex := Button.new()
	reindex.text = "Reindex"
	reindex.pressed.connect(_reindex)
	top.add_child(reindex)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	split.add_child(left)
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_activated.connect(_on_symbol_activated)
	left.add_child(_tree)

	var editor := VBoxContainer.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(editor)
	var file_row := HBoxContainer.new()
	editor.add_child(file_row)
	_file_label = Label.new()
	_file_label.text = "No file open"
	_file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_row.add_child(_file_label)
	var save_btn := Button.new()
	save_btn.text = "Save (backup first)"
	save_btn.pressed.connect(_save_current)
	file_row.add_child(save_btn)
	var reload_btn := Button.new()
	reload_btn.text = "Reload"
	reload_btn.pressed.connect(func(): if current_file != "": open_file(current_file, 1, 0))
	file_row.add_child(reload_btn)

	_code = CodeEdit.new()
	_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code.gutters_draw_line_numbers = true
	_code.highlight_current_line = true
	_code.syntax_highlighter = CodeHighlighter.new()
	var hl := CodeHighlighter.new()
	hl.number_color = Color("#7fd1ff")
	hl.symbol_color = Color("#ffd45e")
	hl.function_color = Color("#6ee7a8")
	hl.member_variable_color = Color("#c8a8ff")
	_code.syntax_highlighter = hl
	editor.add_child(_code)

	var assoc_row := HBoxContainer.new()
	editor.add_child(assoc_row)
	_assoc_note = LineEdit.new()
	_assoc_note.placeholder_text = "Association note (e.g. player idle animation)"
	_assoc_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assoc_row.add_child(_assoc_note)
	var assoc_btn := Button.new()
	assoc_btn.text = "Associate caret symbol -> selected resource"
	assoc_btn.pressed.connect(_add_association)
	assoc_row.add_child(assoc_btn)

	_assoc_list = ItemList.new()
	_assoc_list.custom_minimum_size.y = 70
	editor.add_child(_assoc_list)

func set_project(p: RetroProject) -> void:
	project = p
	_reindex()
	_refresh_associations()

func set_resource(res: Dictionary) -> void:
	current_resource = res
	_rebuild_tree()

func _reindex() -> void:
	_symbols.clear()
	_tree.clear()
	if project == null:
		return
	var index := RetroCodeIndex.new()
	_symbols = index.scan_project(project)
	_rebuild_tree()
	status.emit("Indexed %d symbols" % _symbols.size())

func _rebuild_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var filter := _search.text.to_lower()
	var by_file: Dictionary = {}
	for s in _symbols:
		var rel := String(s.get("rel_path", String(s.get("file", "")).get_file()))
		if filter != "" and not (String(s.get("name", "")).to_lower().contains(filter) or rel.to_lower().contains(filter)):
			continue
		if not by_file.has(rel):
			by_file[rel] = _tree.create_item(root)
			by_file[rel].set_text(0, rel)
			by_file[rel].set_selectable(0, false)
		var item := _tree.create_item(by_file[rel])
		item.set_text(0, "%s  [%s]  :%d" % [String(s.get("name", "")), String(s.get("kind", "")), int(s.get("line", 0))])
		item.set_metadata(0, s)

func _on_symbol_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var s = item.get_metadata(0)
	if s is Dictionary:
		open_file(String(s.get("file", "")), int(s.get("line", 1)), 0)

func open_file(path: String, line: int = 1, column: int = 0) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		status.emit("File not found: " + path)
		return
	var index := RetroCodeIndex.new()
	var preview: Dictionary = index.preview(path, 0, 100000)
	if not bool(preview.get("ok", false)):
		status.emit("Could not read " + path)
		return
	current_file = path
	_code.text = String(preview.get("text", ""))
	_file_label.text = path
	_code.set_caret_line(max(0, line - 1))
	if column > 0:
		_code.set_caret_column(column)
	_code.center_viewport_to_caret()
	status.emit("Opened %s:%d" % [path.get_file(), line])

func _save_current() -> void:
	if current_file.is_empty() or project == null:
		return
	var backup_dir := project.resolve(".retro/backups")
	DirAccess.make_dir_recursive_absolute(backup_dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	var backup := backup_dir.path_join(current_file.get_file() + "." + stamp + ".bak")
	DirAccess.copy_absolute(current_file, backup)
	var f := FileAccess.open(current_file, FileAccess.WRITE)
	if f == null:
		status.emit("Cannot write " + current_file)
		return
	f.store_string(_code.text)
	f.close()
	status.emit("Saved %s (backup: %s)" % [current_file, backup.get_file()])
	modified.emit()

func _add_association() -> void:
	if project == null or current_resource.is_empty():
		status.emit("Select a resource in the Resources tree first.")
		return
	var line := _code.get_caret_line()
	var symbol := ""
	# Find the nearest label/function on or above the caret.
	for i in range(line, -1, -1):
		if i < _code.get_line_count():
			var text := _code.get_line(i).strip_edges()
			if text.contains("(") and not text.ends_with(";") and not text.begins_with("//"):
				symbol = text.split("(")[0].strip_edges()
				break
			if text.ends_with(":") and not text.begins_with("."):
				symbol = text.trim_suffix(":")
				break
	var assoc := {
		"resource": String(current_resource.get("rel_path", "")),
		"resource_path": String(current_resource.get("path", "")),
		"symbol": symbol,
		"file": current_file,
		"line": line + 1,
		"note": _assoc_note.text,
	}
	project.add_association(assoc)
	project.save()
	_refresh_associations()
	status.emit("Associated %s -> %s" % [String(current_resource.get("name", "")), symbol])

func _refresh_associations() -> void:
	_assoc_list.clear()
	if project == null:
		return
	for a in project.get_associations():
		_assoc_list.add_item("%s -> %s:%d  %s" % [String(a.get("resource", "")), String(a.get("file", "")).get_file(), int(a.get("line", 0)), String(a.get("note", ""))])
