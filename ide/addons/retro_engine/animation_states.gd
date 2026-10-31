@tool
extends RefCounted
## Detects animation states from project data.
##
## Two common Mega Drive / SNES layouts are understood:
##  - frame constants such as PL_PLAYER_IDLE0 / PL_PLAYER_WALK0 in .inc files;
##  - Sonic 2 disassembly animation scripts (SonAni_Walk, TailsAni_Run, ...).
##
## The detector never guesses frame boundaries from pixels. When neither
## source exists it returns ok=false and the editor offers the manual
## "Distribute equally" fallback.

static func _walk_dir(root: String, exts: Array, max_depth: int, depth: int = 0) -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var path := root.path_join(name)
		if dir.current_is_dir():
			if depth < max_depth:
				out.append_array(_walk_dir(path, exts, max_depth, depth + 1))
		else:
			if exts.is_empty() or exts.has(name.get_extension().to_lower()):
				out.append(path)
		name = dir.get_next()
	dir.list_dir_end()
	return out

static func _parse_int(text: String) -> int:
	var t := text.strip_edges().replace(",", "")
	if t.is_empty():
		return 0
	var negative := false
	if t.begins_with("-"):
		negative = true
		t = t.substr(1).strip_edges()
	elif t.begins_with("+"):
		t = t.substr(1).strip_edges()
	var value := 0
	if t.begins_with("$"):
		value = t.substr(1).hex_to_int()
	elif t.begins_with("0x") or t.begins_with("0X"):
		value = t.substr(2).hex_to_int()
	elif t.begins_with("%"):
		for i in range(1, t.length()):
			value = (value << 1) | (1 if t[i] == "1" else 0)
	else:
		value = t.to_int()
	return -value if negative else value

static func _frame_dict(sprite: RetroSprite, index: int, duration: int) -> Dictionary:
	if sprite == null:
		return {}
	var frames := sprite.get_frames()
	if index < 0 or index >= frames.size():
		return {}
	var f: Dictionary = frames[index]
	var rect: Rect2i = f.get("rect", Rect2i())
	if rect.size.x <= 0 or rect.size.y <= 0:
		return {}
	return {
		"sprite_frame": index,
		"duration": maxi(1, duration),
		"rect": rect,
		"hitboxes": [],
		"events": [],
	}

static func _state_frames(sprite: RetroSprite, indices: Array, duration: int) -> Array:
	var out: Array = []
	var seen := {}
	for value in indices:
		var index := int(value)
		if seen.has(index):
			continue
		seen[index] = true
		var frame := _frame_dict(sprite, index, duration)
		if not frame.is_empty():
			out.append(frame)
	return out

static func _detect_from_constants(project: RetroProject, sprite: RetroSprite) -> Dictionary:
	var root := project.get_path()
	var files := _walk_dir(root, ["inc", "asm", "h", "c"], 4)
	var define_re := RegEx.new()
	define_re.compile("(?m)^\\s*(?:\\.DEFINE|#define)\\s+([A-Za-z0-9_]+)\\s+([^\\s;]+)")
	var token_re := RegEx.new()
	token_re.compile("(?i)(IDLE|WALK|RUN|JUMP|FALL|CROUCH|HURT|DEAD|WIN)")
	var candidates: Array = []
	for file in files:
		var text := FileAccess.get_file_as_string(String(file))
		if text.is_empty():
			continue
		for m in define_re.search_all(text):
			var name := m.get_string(1)
			var token_match := token_re.search(name)
			if token_match == null:
				continue
			var token := token_match.get_string(1).to_upper()
			var tail := name.substr(token_match.get_end(1)).to_upper()
			if not tail.is_empty() and not tail.is_valid_int():
				continue
			var index := _parse_int(m.get_string(2))
			if index < 0 or index >= sprite.get_frames().size():
				continue
			if token == "HURT":
				token = "HIT"
			candidates.append({
				"prefix": name.substr(0, token_match.get_start(1)),
				"token": token,
				"index": index,
			})
	if candidates.is_empty():
		return {"ok": false}
	# Several unrelated constants may contain words like HIT or WIN. Prefer the
	# prefix that owns the most distinct animation tokens (PL_PLAYER_*, HERO_*).
	var by_prefix := {}
	for candidate in candidates:
		var prefix := String(candidate["prefix"])
		if not by_prefix.has(prefix):
			by_prefix[prefix] = []
		by_prefix[prefix].append(candidate)
	var best_prefix := ""
	var best_score := -1
	var best_tokens := {}
	for prefix in by_prefix.keys():
		var tokens := {}
		var entries: Array = by_prefix[prefix]
		for entry in entries:
			tokens[String(entry["token"])] = true
		var score := tokens.size() * 100 + entries.size()
		if score > best_score:
			best_score = score
			best_prefix = String(prefix)
			best_tokens = tokens
	if best_tokens.size() < 2:
		return {"ok": false}
	var groups := {}
	for entry in by_prefix[best_prefix]:
		var token := String(entry["token"])
		var index := int(entry["index"])
		if not groups.has(token):
			groups[token] = []
		if not Array(groups[token]).has(index):
			groups[token].append(index)
	var order := ["IDLE", "WALK", "RUN", "JUMP", "FALL", "CROUCH", "HIT", "DEAD", "WIN", "ATTACK", "BLOCK", "SPECIAL", "SUPER", "THROW"]
	var states := {}
	for state_name in order:
		if not groups.has(state_name):
			continue
		var indices: Array = groups[state_name]
		indices.sort()
		var frames := _state_frames(sprite, indices, 8 if state_name == "IDLE" else 5)
		if frames.is_empty():
			continue
		states[state_name] = {
			"name": state_name,
			"loop": state_name in ["IDLE", "WALK", "RUN"],
			"next": "",
			"frames": frames,
		}
	for state_name in groups.keys():
		if states.has(state_name):
			continue
		var indices: Array = groups[state_name]
		indices.sort()
		var frames := _state_frames(sprite, indices, 5)
		if frames.is_empty():
			continue
		states[state_name] = {
			"name": state_name,
			"loop": false,
			"next": "",
			"frames": frames,
		}
	if states.size() < 2:
		return {"ok": false}
	return {
		"ok": true,
		"states": states,
		"source": "frame constants",
		"message": "Detected %d states from project frame constants." % states.size(),
	}

static func _collect_dc_b(text: String, r_bytes: Array) -> void:
	var at := text.find("dc.b")
	if at < 0:
		return
	var data := text.substr(at + 4)
	var comment := data.find(";")
	if comment >= 0:
		data = data.substr(0, comment)
	for part in data.split(","):
		var t := String(part).strip_edges()
		if t.is_empty():
			continue
		r_bytes.append(_parse_int(t))

static func _sonic_state_name(raw_name: String) -> String:
	var map := {
		"Wait": "IDLE",
		"Walk": "WALK",
		"Run": "RUN",
		"Roll": "ROLL",
		"Roll2": "ROLL",
		"Push": "PUSH",
		"Duck": "CROUCH",
		"Hurt": "HIT",
		"Hurt2": "HIT",
		"Death": "DEAD",
		"DeathBW": "DEAD",
		"Drown": "DROWN",
		"Spring": "SPRING",
		"Float": "FLOAT",
		"Float2": "FLOAT",
		"Hang": "HANG",
		"Hang2": "HANG",
		"Spindash": "SPINDASH",
		"Slide": "SLIDE",
		"Balance": "BALANCE",
		"Balance2": "BALANCE",
		"Balance3": "BALANCE",
		"Balance4": "BALANCE",
		"LookUp": "LOOK_UP",
		"Blink": "BLINK",
		"GetUp": "GET_UP",
		"Stop": "STOP",
		"Dash2": "DASH",
		"Dash3": "DASH",
		"Bubble": "BUBBLE",
		"Blank": "BLANK",
		"Lying": "LYING",
		"LieDown": "LIE_DOWN",
		"Transform": "TRANSFORM",
	}
	return String(map.get(raw_name, raw_name.to_upper()))

static func _add_sonic_block(current: String, bytes: Array, groups: Dictionary) -> void:
	if current.is_empty() or bytes.size() < 2:
		return
	var frames: Array = []
	for i in range(1, bytes.size()):
		var value := int(bytes[i])
		if value >= 0xFD:
			break
		frames.append(value)
	if frames.is_empty():
		return
	var state_name := _sonic_state_name(current)
	if groups.has(state_name):
		return
	groups[state_name] = frames

static func _detect_sonic_scripts(project: RetroProject, sprite: RetroSprite) -> Dictionary:
	var s2_path := project.get_path().path_join("s2.asm")
	if not FileAccess.file_exists(s2_path):
		return {"ok": false}
	var identity := (sprite.get_name() + " " + sprite.get_source_path()).to_lower()
	var prefix := "TailsAni_" if identity.contains("tails") else "SonAni_"
	var text := FileAccess.get_file_as_string(s2_path)
	if text.is_empty() or not text.contains(prefix):
		prefix = "SonAni_"
		if not text.contains(prefix):
			return {"ok": false}
	var label_re := RegEx.new()
	label_re.compile("^\\s*([A-Za-z0-9_]+):\\s*(.*)$")
	var groups := {}
	var current := ""
	var bytes: Array = []
	var collecting := false
	for line in text.split("\n"):
		var stripped := String(line).strip_edges()
		if stripped.begins_with(";"):
			continue
		var m := label_re.search(stripped)
		if m != null:
			_add_sonic_block(current, bytes, groups)
			var label := m.get_string(1)
			if label.begins_with(prefix):
				current = label.substr(prefix.length())
				bytes = []
				collecting = true
				_collect_dc_b(m.get_string(2), bytes)
			else:
				current = ""
				bytes = []
				collecting = false
			continue
		if not collecting:
			continue
		if stripped.begins_with("dc.b"):
			_collect_dc_b(stripped, bytes)
		elif stripped.begins_with("rev02even") or stripped.begins_with("even") or stripped.is_empty():
			continue
		else:
			_add_sonic_block(current, bytes, groups)
			current = ""
			bytes = []
			collecting = false
	_add_sonic_block(current, bytes, groups)
	if groups.size() < 2:
		return {"ok": false}
	var order := ["IDLE", "WALK", "RUN", "JUMP", "CROUCH", "ROLL", "PUSH", "SPINDASH", "SLIDE", "BALANCE", "LOOK_UP", "BLINK", "GET_UP", "STOP", "SPRING", "FLOAT", "HANG", "DASH", "BUBBLE", "DEAD", "DROWN", "HIT", "LYING", "LIE_DOWN", "BLANK", "TRANSFORM"]
	var states := {}
	for state_name in order:
		if not groups.has(state_name):
			continue
		var indices: Array = groups[state_name]
		indices.sort()
		var duration := 8 if state_name == "IDLE" else (4 if state_name in ["WALK", "RUN", "ROLL"] else 6)
		var frames := _state_frames(sprite, indices, duration)
		if frames.is_empty():
			continue
		states[state_name] = {
			"name": state_name,
			"loop": not state_name in ["DEAD", "DROWN", "HIT"],
			"next": "",
			"frames": frames,
		}
	for state_name in groups.keys():
		if states.has(state_name):
			continue
		var indices: Array = groups[state_name]
		indices.sort()
		var frames := _state_frames(sprite, indices, 6)
		if frames.is_empty():
			continue
		states[state_name] = {
			"name": state_name,
			"loop": false,
			"next": "",
			"frames": frames,
		}
	if states.size() < 2:
		return {"ok": false}
	return {
		"ok": true,
		"states": states,
		"source": "s2.asm animation scripts",
		"message": "Detected %d states from Sonic 2 animation scripts." % states.size(),
	}

static func detect(project: RetroProject, sprite: RetroSprite) -> Dictionary:
	if project == null or sprite == null:
		return {"ok": false, "message": "No project or sprite loaded."}
	if sprite.get_frames().is_empty():
		return {"ok": false, "message": "The sprite has no frames to map."}
	var from_constants := _detect_from_constants(project, sprite)
	if bool(from_constants.get("ok", false)):
		return from_constants
	var from_sonic := _detect_sonic_scripts(project, sprite)
	if bool(from_sonic.get("ok", false)):
		return from_sonic
	return {"ok": false, "message": "No animation state metadata found in the project."}
