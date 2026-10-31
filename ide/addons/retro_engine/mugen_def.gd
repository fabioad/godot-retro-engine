@tool
extends RefCounted
## MUGEN .def (character/stage) reader. Keeps section order, [Files] paths and
## [BG] layer definitions used by the native stage preview.

var path: String = ""
var sections: Dictionary = {}
var section_order: Array = []
var bg_layers: Array = []
var raw_text: String = ""

func load_file(p_path: String) -> bool:
	path = p_path
	sections.clear()
	section_order.clear()
	bg_layers.clear()
	raw_text = ""
	if not FileAccess.file_exists(p_path):
		return false
	raw_text = FileAccess.get_file_as_string(p_path)
	var current := ""
	var current_dict: Dictionary = {}
	for raw in raw_text.split("\n"):
		var line := String(raw).strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		if line.begins_with("["):
			if not current.is_empty():
				sections[current] = current_dict
			var close := line.find("]")
			current = line.substr(1, close - 1).strip_edges() if close > 0 else line.trim_prefix("[").strip_edges()
			section_order.append(current)
			current_dict = {}
			if current.to_lower().begins_with("bg ") or current.to_lower() == "bg":
				var layer: Dictionary = {"section": current}
				current_dict = layer
				bg_layers.append(layer)
			elif current.to_lower().begins_with("begin action"):
				current = ""
				current_dict = {}
			continue
		var eq := line.find("=")
		if eq < 0 or current.is_empty():
			continue
		var key := line.substr(0, eq).strip_edges().to_lower()
		var value := line.substr(eq + 1).strip_edges()
		var comment := value.find(";")
		if comment >= 0:
			value = value.substr(0, comment).strip_edges()
		value = value.trim_prefix("\"").trim_suffix("\"")
		current_dict[key] = value
		if current.to_lower().begins_with("bg ") or current.to_lower() == "bg":
			bg_layers[bg_layers.size() - 1][key] = value
	if not current.is_empty():
		sections[current] = current_dict
	return not sections.is_empty()

func is_character() -> bool:
	var files := files()
	return files.has("sprite") and (files.has("anim") or files.has("cns") or files.has("cmd"))

func is_stage() -> bool:
	return not bg_layers.is_empty() or sections.has("BGdef")

func info() -> Dictionary:
	return sections.get("Info", sections.get("info", {}))

func files() -> Dictionary:
	return sections.get("Files", sections.get("files", {}))

func get_value(section: String, key: String, def: String = "") -> String:
	var s: Dictionary = sections.get(section, {})
	return String(s.get(key.to_lower(), def))

func character_files() -> Dictionary:
	var f := files()
	return {
		"sprite": _resolve(f.get("sprite", "")),
		"anim": _resolve(f.get("anim", "")),
		"sound": _resolve(f.get("sound", "")),
		"cmd": _resolve(f.get("cmd", "")),
		"cns": _resolve(f.get("cns", f.get("st", ""))),
		"st": _resolve(f.get("st", "")),
	}

func stage_sprite_file() -> String:
	var f := sections.get("BGdef", sections.get("bgdef", {}))
	return _resolve(String(f.get("spr", f.get("sprite", ""))))

func music_file() -> String:
	var m := sections.get("Music", sections.get("music", {}))
	var p := String(m.get("bgmusic", ""))
	if p.is_empty():
		return ""
	return _resolve(p)

func display_name() -> String:
	var i := info()
	return String(i.get("displayname", i.get("name", path.get_file().get_basename())))

func _resolve(value: String) -> String:
	if value.is_empty() or path.is_empty():
		return value
	value = value.replace("\\", "/")
	if value.is_absolute_path():
		return value
	var base := path.get_base_dir()
	var candidates: Array = [
		base.path_join(value).simplify_path(),
		base.get_base_dir().path_join(value).simplify_path(),
	]
	for c in candidates:
		if FileAccess.file_exists(String(c)):
			return String(c)
	return String(candidates[0])
