@tool
extends RefCounted
## Native MUGEN AIR animation reader.
##
## Parses `[Begin Action n]` frames, sprite group/number, offsets, ticks,
## H/V flip, blend flags and Clsn1/Clsn2 boxes. Stage DEF files can also embed
## `[Begin action]` blocks; the same parser accepts that text.

var actions: Dictionary = {}
var path: String = ""

func load_file(p_path: String) -> bool:
	path = p_path
	if not FileAccess.file_exists(p_path):
		return false
	return load_text(FileAccess.get_file_as_string(p_path))

func load_text(text: String) -> bool:
	actions.clear()
	var action := -1
	var frames: Array = []
	var pending1: Array = []
	var pending2: Array = []
	var default1: Array = []
	var default2: Array = []
	var mode := ""
	var started := false
	for raw_line in text.split("\n"):
		var line := String(raw_line).strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		var lower := line.to_lower()
		if lower.begins_with("[begin action"):
			if started and action >= 0:
				actions[action] = frames
			action = _action_number(line)
			frames = []
			pending1 = []
			pending2 = []
			default1 = []
			default2 = []
			started = true
			continue
		if action < 0:
			continue
		if lower.begins_with("clsn1default:"):
			default1 = []
			mode = "d1"
			continue
		if lower.begins_with("clsn2default:"):
			default2 = []
			mode = "d2"
			continue
		if lower.begins_with("clsn1:"):
			pending1 = []
			mode = "p1"
			continue
		if lower.begins_with("clsn2:"):
			pending2 = []
			mode = "p2"
			continue
		if lower.begins_with("clsn1[") or lower.begins_with("clsn2["):
			var box := _parse_box(line)
			if box.size.x != 0 or box.size.y != 0:
				if mode == "d1":
					default1.append(box)
				elif mode == "d2":
					default2.append(box)
				elif mode == "p1":
					pending1.append(box)
				elif mode == "p2":
					pending2.append(box)
			continue
		# Frame line: g,n,x,y,ticks,flags...
		var parts := line.split(",")
		if parts.size() < 5:
			continue
		var group := _to_int(parts[0])
		var number := _to_int(parts[1])
		if group < 0 or number < 0:
			continue
		var flags := String(parts[5]).strip_edges().to_upper() if parts.size() > 5 else ""
		var frame: Dictionary = {
			"group": group,
			"number": number,
			"x": _to_int(parts[2]),
			"y": _to_int(parts[3]),
			"ticks": maxi(1, _to_int(parts[4])),
			"flip_h": flags.contains("H"),
			"flip_v": flags.contains("V"),
			"blend": flags.contains("A"),
			"clsn1": pending1.duplicate() if not pending1.is_empty() else default1.duplicate(),
			"clsn2": pending2.duplicate() if not pending2.is_empty() else default2.duplicate(),
		}
		frames.append(frame)
		pending1 = []
		pending2 = []
	if started and action >= 0:
		actions[action] = frames
	return not actions.is_empty()

func action_numbers() -> Array:
	var out: Array = actions.keys()
	out.sort()
	return out

func frame_count(action: int) -> int:
	return Array(actions.get(action, [])).size()

func total_ticks(action: int) -> int:
	var total := 0
	for f in actions.get(action, []):
		total += maxi(1, int(Dictionary(f).get("ticks", 1)))
	return total

func frame_at(action: int, tick: int) -> Dictionary:
	var frames: Array = actions.get(action, [])
	if frames.is_empty():
		return {}
	var total := total_ticks(action)
	if total <= 0:
		return frames[0]
	var t := posmod(tick, total)
	var acc := 0
	for i in range(frames.size()):
		var f: Dictionary = frames[i]
		acc += maxi(1, int(f.get("ticks", 1)))
		if t < acc:
			var out := f.duplicate()
			out["index"] = i
			out["frame_count"] = frames.size()
			return out
	return frames.back()

func _action_number(line: String) -> int:
	var i := line.to_lower().find("action")
	if i < 0:
		return -1
	var rest := line.substr(i + 6).strip_edges()
	rest = rest.trim_prefix("]").strip_edges()
	var n := ""
	for c in rest:
		if (c >= "0" and c <= "9") or c == "-":
			n += c
		elif not n.is_empty():
			break
	return int(n) if not n.is_empty() else -1

func _parse_box(line: String) -> Rect2i:
	var eq := line.find("=")
	if eq < 0:
		return Rect2i()
	var parts := line.substr(eq + 1).split(",")
	if parts.size() < 4:
		return Rect2i()
	var x1 := _to_int(parts[0])
	var y1 := _to_int(parts[1])
	var x2 := _to_int(parts[2])
	var y2 := _to_int(parts[3])
	return Rect2i(mini(x1, x2), mini(y1, y2), absi(x2 - x1), absi(y2 - y1))

static func _to_int(text: String) -> int:
	var s := text.strip_edges()
	if s.is_empty():
		return 0
	var v := 0
	var neg := false
	for c in s:
		if c == "-" and v == 0:
			neg = true
		elif c >= "0" and c <= "9":
			v = v * 10 + int(c)
		else:
			break
	return -v if neg else v
