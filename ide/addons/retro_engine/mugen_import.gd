@tool
extends RefCounted
## Converts MUGEN characters/stages into native Godot Retro Engine project
## documents (RetroSprite + RetroAnimation + RetroStage) and registers them.

const SffBank = preload("res://addons/retro_engine/mugen_sff.gd")
const AirAnim = preload("res://addons/retro_engine/mugen_air.gd")
const MugenDef = preload("res://addons/retro_engine/mugen_def.gd")

const COMMON_ACTIONS := [0, 1, 5, 6, 10, 11, 12, 20, 21, 40, 41, 42, 100, 200]

static func import_character(project: RetroProject, def_path: String, target: String, max_actions: int = 24) -> Dictionary:
	if project == null:
		return {"ok": false, "error": "Open a project first."}
	var def = MugenDef.new()
	if not def.load_file(def_path) or not def.is_character():
		return {"ok": false, "error": "Not a MUGEN character DEF: " + def_path}
	var files: Dictionary = def.character_files()
	var sff = SffBank.new()
	if not sff.load_file(String(files.get("sprite", ""))):
		return {"ok": false, "error": "Cannot read SFF: " + String(files.get("sprite", ""))}
	var air = AirAnim.new()
	air.load_file(String(files.get("anim", "")))
	var actions := _choose_actions(air, max_actions)
	if actions.is_empty():
		return {"ok": false, "error": "No AIR actions to import."}
	# Unique sprites used by the selected actions.
	var keys: Array = []
	var key_index: Dictionary = {}
	var key_image: Dictionary = {}
	for action in actions:
		if keys.size() >= 256:
			break
		for frame in air.actions.get(action, []):
			if keys.size() >= 256:
				break
			var f: Dictionary = frame
			var key := "%d,%d" % [int(f.get("group", 0)), int(f.get("number", 0))]
			if key_index.has(key):
				continue
			var idx: int = sff.find_index(int(f.get("group", 0)), int(f.get("number", 0)))
			if idx < 0:
				continue
			var img: Image = sff.render(idx)
			if img == null or img.get_width() > 512 or img.get_height() > 512:
				continue
			key_index[key] = keys.size()
			key_image[key] = {"index": idx, "image": img}
			keys.append(key)
	if keys.is_empty():
		return {"ok": false, "error": "No renderable sprites in the selected actions."}
	var cell_w := 0
	var cell_h := 0
	for key in keys:
		var img: Image = key_image[key]["image"]
		cell_w = maxi(cell_w, img.get_width())
		cell_h = maxi(cell_h, img.get_height())
	cell_w = maxi(cell_w, 8)
	cell_h = maxi(cell_h, 8)
	var cols := clampi(int(ceil(sqrt(float(keys.size())))), 1, 16)
	var rows := int(ceil(float(keys.size()) / float(cols)))
	var atlas := Image.create_empty(cols * cell_w, rows * cell_h, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var frame_rects: Dictionary = {}
	var axis_cells: Dictionary = {}
	for i in range(keys.size()):
		var key: String = keys[i]
		var data: Dictionary = key_image[key]
		var img: Image = data["image"]
		var col := i % cols
		var row := i / cols
		var ox := col * cell_w + (cell_w - img.get_width()) / 2
		var oy := row * cell_h + (cell_h - img.get_height())
		atlas.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(ox, oy))
		frame_rects[key] = Rect2i(col * cell_w, row * cell_h, cell_w, cell_h)
		var sprite: Dictionary = sff.sprite_at(int(data["index"]))
		var axis: Vector2i = sprite.get("axis", Vector2i.ZERO)
		axis_cells[key] = Vector2i((cell_w - img.get_width()) / 2 + axis.x, cell_h - img.get_height() + axis.y)
	var palette := RetroGraphics.extract_palette(atlas, 16, true)
	atlas = RetroGraphics.map_to_palette(atlas, palette, true)
	var slug := _slug(def.display_name())
	var sprite := RetroSprite.new()
	sprite.set_platform(target)
	sprite.set_name(slug + "_sprite")
	sprite.set_bpp(4)
	sprite.set_image(atlas)
	sprite.set_palette(palette)
	sprite.set_origin(Vector2i(cell_w / 2, cell_h))
	for i in range(keys.size()):
		var key: String = keys[i]
		sprite.add_frame(key.replace(",", "_"), frame_rects[key], 6)
	var anim := RetroAnimation.new()
	anim.set_platform(target)
	anim.set_name(slug + "_anim")
	anim.set_fps(60)
	var states := anim.get_states()
	for key in states.keys():
		var st: Dictionary = states[key]
		st["frames"] = []
		states[key] = st
	var used_states: Dictionary = {}
	for action in actions:
		var frames: Array = air.actions.get(action, [])
		if frames.is_empty():
			continue
		var state_name := _state_name(int(action), used_states)
		used_states[state_name] = true
		var out: Array = []
		for frame in frames:
			var f: Dictionary = frame
			var key := "%d,%d" % [int(f.get("group", 0)), int(f.get("number", 0))]
			if not key_index.has(key):
				continue
			var axis_cell: Vector2i = axis_cells[key]
			var hitboxes: Array = []
			for box in f.get("clsn1", []):
				var r: Rect2i = box
				hitboxes.append({"rect": Rect2i(r.position + axis_cell, r.size), "type": "hit"})
			for box in f.get("clsn2", []):
				var r: Rect2i = box
				hitboxes.append({"rect": Rect2i(r.position + axis_cell, r.size), "type": "hurt"})
			out.append({
				"sprite_frame": int(key_index[key]),
				"duration": maxi(1, int(f.get("ticks", 1))),
				"rect": frame_rects[key],
				"hitboxes": hitboxes,
				"events": [],
			})
		if out.is_empty():
			continue
		var st: Dictionary = states.get(state_name, {"name": state_name, "loop": true, "next": "", "frames": []})
		st["frames"] = out
		st["loop"] = true
		st["next"] = ""
		states[state_name] = st
	anim.set_states(states)
	var art_dir := project.resolve("art/mugen/" + slug)
	DirAccess.make_dir_recursive_absolute(art_dir)
	var sprite_png := art_dir.path_join(slug + "_sprite.png")
	var sprite_json := art_dir.path_join(slug + "_sprite.json")
	var anim_json := art_dir.path_join(slug + "_anim.json")
	sprite.export_png_asset(sprite_png)
	sprite.save(sprite_json)
	anim.save(anim_json)
	sprite.save(project.resolve(".retro/editor/sprite.json"))
	anim.save(project.resolve(".retro/editor/animation.json"))
	_register(project, [
		{"path": sprite_png, "editor": "sprite", "kind": "image", "note": "MUGEN character atlas"},
		{"path": sprite_json, "editor": "sprite", "kind": "data", "note": "MUGEN character sprite document"},
		{"path": anim_json, "editor": "animation", "kind": "data", "note": "MUGEN character AIR animation"},
	])
	return {"ok": true, "slug": slug, "sprite": sprite, "animation": anim,
		"sprite_png": sprite_png, "sprite_json": sprite_json, "anim_json": anim_json,
		"actions": actions.size(), "sprites": keys.size(), "palette": palette.size()}

static func import_stage(project: RetroProject, def_path: String, target: String) -> Dictionary:
	if project == null:
		return {"ok": false, "error": "Open a project first."}
	var def = MugenDef.new()
	if not def.load_file(def_path) or not def.is_stage():
		return {"ok": false, "error": "Not a MUGEN stage DEF: " + def_path}
	var sff = SffBank.new()
	if not sff.load_file(def.stage_sprite_file()):
		return {"ok": false, "error": "Cannot read stage SFF: " + def.stage_sprite_file()}
	var air = AirAnim.new()
	air.load_text(def.raw_text)
	var logical := Vector2(320, 240)
	var canvas := Image.create_empty(int(logical.x), int(logical.y), false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 1))
	var layers: Array = def.bg_layers.duplicate()
	layers.sort_custom(func(a, b): return int(a.get("layerno", 0)) < int(b.get("layerno", 0)))
	for layer in layers:
		var l: Dictionary = layer
		var group := 0
		var number := 0
		if String(l.get("type", "normal")) == "anim":
			var action := _to_int(String(l.get("actionno", "")))
			var fr: Dictionary = air.frame_at(action, 0)
			if fr.is_empty():
				continue
			group = int(fr.get("group", 0))
			number = int(fr.get("number", 0))
		else:
			var pair := _pair(String(l.get("spriteno", "")))
			group = int(pair.x)
			number = int(pair.y)
		var idx: int = sff.find_index(group, number)
		if idx < 0:
			continue
		var img: Image = sff.render(idx)
		if img == null:
			continue
		var start := _pair(String(l.get("start", "0,0")))
		var delta := _pair(String(l.get("delta", "1,1")))
		var axis: Vector2i = sff.sprite_at(idx).get("axis", Vector2i.ZERO)
		var pos := Vector2i(int(start.x), int(start.y)) - axis
		_blit_clipped(canvas, img, pos)
	var native := Vector2(256, 224) if target == "snes" else Vector2(320, 224)
	canvas.resize(int(native.x), int(native.y), Image.INTERPOLATE_NEAREST)
	var slug := _slug(def.display_name())
	var art_dir := project.resolve("art/mugen/" + slug)
	DirAccess.make_dir_recursive_absolute(art_dir)
	var bridge := RetroNativeBridge.new()
	var result: Dictionary = bridge.import_stage_image(
		canvas, slug + "_stage", art_dir, target,
		"mode1" if target == "snes" else "h40", 8,
		1024 if target == "snes" else 2048, 16, def_path)
	if not bool(result.get("ok", false)):
		return {"ok": false, "error": String(result.get("error", "stage conversion failed"))}
	var stage_json := String(result.get("stage_json", ""))
	if not stage_json.is_empty() and FileAccess.file_exists(stage_json):
		var stage := RetroStage.new()
		if stage.load(stage_json) == OK:
			stage.save(project.resolve(".retro/editor/stage.json"))
	_register(project, [
		{"path": stage_json, "editor": "stage", "kind": "data", "note": "MUGEN stage document"},
	])
	var extra: Array = []
	var tileset_png := String(result.get("tileset_png", ""))
	if not tileset_png.is_empty():
		extra.append({"path": tileset_png, "editor": "stage", "kind": "image", "note": "MUGEN stage tileset"})
	var snes: Dictionary = result.get("snes", {})
	for key in ["chr", "pal", "map", "inc"]:
		var p := String(snes.get(key, ""))
		if not p.is_empty():
			extra.append({"path": p, "editor": "stage" if key != "inc" else "code",
				"kind": "data", "note": "MUGEN stage SNES export"})
	var sgdk: Dictionary = result.get("sgdk", {})
	for key in ["png", "res"]:
		var p := String(sgdk.get(key, ""))
		if not p.is_empty():
			extra.append({"path": p, "editor": "stage" if key == "png" else "resources",
				"kind": "image" if key == "png" else "data", "note": "MUGEN stage SGDK export"})
	_register(project, extra)
	return {"ok": true, "slug": slug, "stage_json": stage_json, "layers": layers.size(),
		"result": result}

static func _choose_actions(air: AirAnim, max_actions: int) -> Array:
	var out: Array = []
	for a in COMMON_ACTIONS:
		if air.actions.has(int(a)):
			out.append(int(a))
	if out.is_empty():
		out = air.action_numbers().slice(0, maxi(1, max_actions))
	elif max_actions > 0 and out.size() > max_actions:
		out = out.slice(0, max_actions)
	return out

static func _state_name(action: int, used: Dictionary) -> String:
	var name := ""
	match action:
		0: name = "IDLE"
		20: name = "WALK"
		40: name = "JUMP"
		100: name = "ATTACK"
		200: name = "SPECIAL"
		_: name = "ACTION_%d" % action
	if used.has(name):
		name = "ACTION_%d" % action
	return name

static func _register(project: RetroProject, entries: Array) -> void:
	var resources: Array = project.get_resources()
	var known: Dictionary = {}
	for r in resources:
		known[String(r.get("path", ""))] = true
	var changed := false
	for e in entries:
		var item: Dictionary = e
		var path := String(item.get("path", ""))
		if path.is_empty() or not FileAccess.file_exists(path) or known.has(path):
			continue
		var rel := path.trim_prefix(project.get_path().path_join(""))
		resources.append({
			"id": rel.replace("/", "_"),
			"rel_path": rel,
			"path": path,
			"name": path.get_file(),
			"ext": path.get_extension().to_lower(),
			"kind": String(item.get("kind", "data")),
			"editor": String(item.get("editor", "none")),
			"editable": true,
			"size": FileAccess.get_size(path),
			"note": String(item.get("note", "Imported from MUGEN")),
			"group": String(item.get("editor", "none")),
			"mugen_import": true,
		})
		known[path] = true
		changed = true
	if changed:
		project.set_resources(resources)
		project.save()

static func _blit_clipped(dst: Image, src: Image, pos: Vector2i) -> void:
	var x0 := maxi(0, -pos.x)
	var y0 := maxi(0, -pos.y)
	var x1 := mini(src.get_width(), dst.get_width() - pos.x)
	var y1 := mini(src.get_height(), dst.get_height() - pos.y)
	if x1 <= x0 or y1 <= y0:
		return
	var region := src.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
	dst.blend_rect(region, Rect2i(0, 0, region.get_width(), region.get_height()), Vector2i(pos.x + x0, pos.y + y0))

static func _pair(text: String) -> Vector2:
	var parts := text.split(",")
	if parts.size() < 2:
		return Vector2.ZERO
	return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))

static func _to_int(text: String) -> int:
	var s := text.strip_edges()
	if s.is_empty():
		return -1
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

static func _slug(name: String) -> String:
	var out := ""
	for c in name.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "mugen"
