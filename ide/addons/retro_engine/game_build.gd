@tool
extends RefCounted
## Generates standalone PVSnesLib / SGDK demo projects from native assets or
## from the current retro project, with an optional Godot-logo fade splash.

const LOGO_PATH := "res://addons/retro_engine/assets/godot_splash.png"
const ExportProfiles = preload("res://addons/retro_engine/export_profiles.gd")
const AudioPipeline = preload("res://addons/retro_engine/audio_pipeline.gd")
const RomProfiles = preload("res://addons/retro_engine/rom_profiles.gd")
const SonicStageImport = preload("res://addons/retro_engine/sonic_stage_import.gd")

static func target_for_mode(mode: String) -> String:
	if mode in ["native_snes", "megadrive_snes"]:
		return "snes"
	if mode in ["native_megadrive", "snes_megadrive"]:
		return "megadrive"
	return ""

static func generate(mode: String, source: RetroProject, out_root: String, game_name: String,
		include_splash: bool, source_stage_path := "", rom_settings: Dictionary = {}) -> Dictionary:
	var target := target_for_mode(mode)
	if target.is_empty():
		return {"ok": false, "error": "unknown build mode: " + mode}
	if out_root.is_empty():
		return {"ok": false, "error": "output directory is empty"}
	var profile := ExportProfiles.for_target(target)
	if profile.is_empty():
		return {"ok": false, "error": "no validated export profile for target: " + target}
	var dir := out_root.path_join(game_name)
	DirAccess.make_dir_recursive_absolute(dir.path_join("src"))
	DirAccess.make_dir_recursive_absolute(dir.path_join(".retro"))
	var stage := _find_stage(source, target, source_stage_path)
	if stage == null:
		return {"ok": false, "error": "no stage/image asset available for conversion"}
	var bridge := RetroNativeBridge.new()
	stage = _retarget_stage(stage, target)
	if stage.get_tileset() == null or stage.get_palette().is_empty():
		return {"ok": false, "error": "source stage has no tileset/palette"}
	var splash: RetroStage = null
	if include_splash:
		var logo := Image.load_from_file(LOGO_PATH)
		if logo != null:
			logo.convert(Image.FORMAT_RGBA8)
			# The source PNG is an 800x600 canvas with large transparent
			# margins. Crop to the visible logo first, otherwise scaling the
			# full canvas down to 256x192 wastes most of the tile budget and
			# the logo looks low-resolution.
			var used := logo.get_used_rect()
			if used.size.x > 0 and used.size.y > 0:
				logo = logo.get_region(used)
			# Composite over black before resizing so anti-aliased edges blend
			# towards the actual backdrop instead of becoming semi-transparent
			# and losing thin details such as the "Game engine" subtitle during
			# palette quantization.
			var pixels := logo.get_data()
			for i in range(0, pixels.size(), 4):
				var alpha := pixels[i + 3]
				if alpha < 255:
					pixels[i] = (pixels[i] * alpha + 127) / 255
					pixels[i + 1] = (pixels[i + 1] * alpha + 127) / 255
					pixels[i + 2] = (pixels[i + 2] * alpha + 127) / 255
					pixels[i + 3] = 255
			logo.set_data(logo.get_width(), logo.get_height(), false, Image.FORMAT_RGBA8, pixels)
			# Fit the cropped logo into a 192x192 black canvas, preserving its
			# aspect ratio. On the SNES this fills most of the 224-line screen
			# and roughly doubles the previous 85x91 logo content, making the
			# subtitle and edges much sharper.
			var splash_canvas := int(profile.get("splash_canvas", 192))
			var fit := minf(float(splash_canvas) / float(logo.get_width()),
				float(splash_canvas) / float(logo.get_height()))
			var fit_w := maxi(1, int(round(logo.get_width() * fit)))
			var fit_h := maxi(1, int(round(logo.get_height() * fit)))
			logo.resize(fit_w, fit_h, Image.INTERPOLATE_BILINEAR)
			var canvas := Image.create_empty(splash_canvas, splash_canvas, false, Image.FORMAT_RGBA8)
			canvas.fill(Color.BLACK)
			canvas.blit_rect(logo, Rect2i(0, 0, fit_w, fit_h),
				Vector2i((splash_canvas - fit_w) / 2, (splash_canvas - fit_h) / 2))
			logo = canvas
			var splash_result: Dictionary = bridge.import_stage_image(logo, "godot_splash", dir, target,
				String(profile.get("bg_mode", "mode1")), int(profile.get("tile_size", 8)),
				int(profile.get("max_tiles", 1024)), int(profile.get("palette_colors", 16)), "godot_splash")
			if bool(splash_result.get("ok", false)):
				splash = splash_result.get("stage")
	var audio_dir := dir.path_join("res") if target == "megadrive" else dir.path_join("audio")
	var audio := AudioPipeline.prepare_for_build(_find_audio(source), target, audio_dir)
	if not bool(audio.get("ok", false)):
		return {"ok": false, "error": String(audio.get("error", "audio conversion failed"))}
	var rom: Dictionary = {}
	var rom_estimate := 0
	if target == "snes":
		rom_estimate = _estimate_snes_rom_bytes(stage, splash, audio)
		rom = RomProfiles.resolve(rom_settings, rom_estimate)
		if not bool(rom.get("ok", false)):
			var rom_errors: Array = rom.get("errors", [])
			return {"ok": false, "error": String(rom_errors[0]) if not rom_errors.is_empty() else "invalid SNES ROM settings"}
	else:
		rom_estimate = _estimate_md_rom_bytes(stage, splash, audio)
		rom = RomProfiles.resolve_md(rom_settings, rom_estimate)
		if not bool(rom.get("ok", false)):
			var md_rom_errors: Array = rom.get("errors", [])
			return {"ok": false, "error": String(md_rom_errors[0]) if not md_rom_errors.is_empty() else "invalid Mega Drive ROM settings"}
	var header_path := dir.path_join("src/assets.h")
	var source_path := dir.path_join("src/assets.c")
	var write := _write_assets(header_path, source_path, stage, splash, target, include_splash, rom)
	if not bool(write.get("ok", false)):
		return write
	var port := _find_native_port(source)
	var port_result := _copy_native_port(port, dir)
	var runtime := _native_runtime(source)
	var runtime_result := {}
	var player := _find_player(source, target)
	if not Array(runtime.get("actors", [])).is_empty():
		if target == "snes":
			runtime_result = _write_snes_runtime(dir, runtime, stage)
		else:
			runtime_result = _write_md_runtime(dir, runtime, stage)
		if bool(runtime_result.get("ok", false)):
			player = {}
	var has_runtime := bool(runtime_result.get("ok", false))
	if target == "snes":
		_write_snes_main(dir.path_join("src/main.c"), stage, splash, include_splash, audio, rom, player,
			runtime_result if has_runtime else {})
		if not player.is_empty():
			_write_snes_player(dir, player)
		_write_snes_makefile(dir.path_join("Makefile"), game_name, audio, rom)
		if bool(rom.get("custom_header", false)):
			_write_snes_custom_header(dir, game_name, rom)
		if bool(rom.get("msu1", false)):
			_write_msu1_support(dir, game_name)
	else:
		_write_md_main(dir.path_join("src/main.c"), stage, splash, include_splash, audio, player,
			runtime_result if has_runtime else {})
		_write_md_makefile(dir.path_join("Makefile"), rom)
		_write_md_mapper(dir, rom)
		if not player.is_empty():
			_write_md_player(dir, player)
		# rescomp scans .res files in the project root. The generated C arrays
		# already contain the tiles/palette/map, so remove the temporary SGDK
		# resource scripts produced while building the native stage. The native
		# runtime writes res/sprites.res afterwards.
		_remove_extension(dir, "res")
		_write_md_audio_res(dir, audio)
	var project := RetroProject.new()
	project.set_name(game_name)
	project.set_path(dir)
	project.set_source_path(dir)
	project.set_platform(target)
	project.set_mode(String(profile.get("bg_mode", "mode1")))
	project.set_sdk_path(_short_sdk_path(target, _sdk_path(source, target)))
	var sdk := RetroSDK.get_sdk(target)
	project.set_sdk_version(String(sdk.get("version", "unknown")))
	project.set_build_system("sgdk" if target == "megadrive" else "make")
	project.set_build_file("Makefile")
	project.set_build_target("")
	project.set_clean_target("clean")
	project.set_rom_path(dir.path_join(game_name + ".sfc") if target == "snes" else dir.path_join("out/rom.bin"))
	var meta := project.get_metadata()
	meta["generated_game"] = true
	meta["build_mode"] = mode
	meta["godot_splash"] = include_splash
	meta["source_project"] = source.get_path() if source else ""
	meta["native_port"] = port_result
	meta["native_player"] = not player.is_empty()
	meta["native_runtime"] = runtime_result
	meta["native_actors"] = int(runtime_result.get("actors", 0))
	meta["native_widgets"] = int(runtime_result.get("widgets", 0))
	meta["native_solids"] = int(runtime_result.get("solids", 0))
	if not rom.is_empty():
		meta["rom_profile"] = String(rom.get("profile_id", ""))
		meta["rom_profile_label"] = String(rom.get("profile_label", ""))
		meta["rom_size_id"] = String(rom.get("size_id", ""))
		meta["rom_size_label"] = String(rom.get("size_label", ""))
		meta["rom_size_code"] = int(rom.get("size_code", 0))
		meta["rom_size_bytes"] = int(rom.get("size_bytes", 0))
		meta["rom_header_mode"] = int(rom.get("header_mode", 0))
		meta["rom_estimate_bytes"] = rom_estimate
		meta["rom_mapping"] = String(rom.get("mapping", ""))
		meta["rom_trim_bytes"] = int(rom.get("trim_to", 0))
		meta["msu1"] = bool(rom.get("msu1", false))
		meta["rom_mapper"] = String(rom.get("mapper", ""))
		meta["rom_sizealign"] = int(rom.get("sizealign", 0))
		meta["rom_requires_companion"] = bool(rom.get("requires_companion", false))
		meta["rom_companion"] = String(rom.get("companion", ""))
	var profile_settings := {
		"game_name": game_name,
		"mode": mode,
		"source_project": source.get_path() if source else "",
		"source_stage": source_stage_path,
		"godot_splash": include_splash,
		"map_w": stage.get_map_size().x,
		"map_h": stage.get_map_size().y,
		"map_entries": stage.get_map().size() / 2,
		"sdk_path": project.get_sdk_path(),
		"sdk_version": project.get_sdk_version(),
		"rom": project.get_rom_path(),
		"audio_bgm": String(audio.get("bgm", {}).get("name", "")) if not audio.get("bgm", {}).is_empty() else "",
		"audio_sfx": audio.get("sfx", []).size(),
		"native_port": String(port_result.get("directory", "")),
		"native_player": not player.is_empty(),
		"native_runtime_actors": int(runtime_result.get("actors", 0)),
		"native_runtime_widgets": int(runtime_result.get("widgets", 0)),
		"native_runtime_solids": int(runtime_result.get("solids", 0)),
		"rom_profile": String(rom.get("profile_id", "")),
		"rom_profile_label": String(rom.get("profile_label", "")),
		"rom_size": String(rom.get("size_label", "")),
		"rom_size_code": int(rom.get("size_code", 0)),
		"rom_size_bytes": int(rom.get("size_bytes", 0)),
		"rom_header_mode": int(rom.get("header_mode", 0)),
		"rom_banks": int(rom.get("banks", 0)),
		"rom_mapping": String(rom.get("mapping", "")),
		"rom_trim_bytes": int(rom.get("trim_to", 0)),
		"msu1": bool(rom.get("msu1", false)),
		"rom_mapper": String(rom.get("mapper", "")),
		"rom_sizealign": int(rom.get("sizealign", 0)),
		"rom_requires_companion": bool(rom.get("requires_companion", false)),
		"rom_companion": String(rom.get("companion", ""))
	}
	if splash != null:
		profile_settings["splash_map_w"] = splash.get_map_size().x
		profile_settings["splash_map_h"] = splash.get_map_size().y
		profile_settings["splash_entries"] = splash.get_map().size() / 2
	var written := ExportProfiles.write_profile(dir, target, profile_settings)
	if not bool(written.get("ok", false)):
		return {"ok": false, "error": String(written.get("error", "could not write export profile"))}
	project.set_metadata(meta)
	ExportProfiles.apply_to_project(project, target, written)
	project.save()
	return {"ok": true, "directory": dir, "project": project, "project_path": project.metadata_path(),
		"target": target, "splash": include_splash, "rom": project.get_rom_path(),
		"export_profile": String(written.get("path", "")), "profile": written,
		"stage": stage, "splash_stage": splash, "port": port_result, "player": player,
		"runtime": runtime_result, "rom_settings": rom, "rom_estimate": rom_estimate}

static func _find_native_port(source: RetroProject) -> Dictionary:
	if source == null:
		return {}
	var links := source.resolve(".retro/editor/native_links.json")
	if not FileAccess.file_exists(links):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(links))
	if typeof(data) == TYPE_DICTIONARY:
		var port = data.get("port", {})
		if typeof(port) == TYPE_DICTIONARY:
			return port
	return {}

static func _resolve_project_path(source: RetroProject, path: String) -> String:
	if path.is_empty():
		return ""
	if path.is_absolute_path():
		return path
	return source.resolve(path)

static func _parse_rect_string(value: String) -> Rect2i:
	var re := RegEx.new()
	re.compile("P:\\s*\\((-?\\d+),\\s*(-?\\d+)\\),\\s*S:\\s*\\((-?\\d+),\\s*(-?\\d+)\\)")
	var m := re.search(value)
	if m == null:
		return Rect2i()
	return Rect2i(int(m.get_string(1)), int(m.get_string(2)), int(m.get_string(3)), int(m.get_string(4)))

static func _native_runtime(source: RetroProject) -> Dictionary:
	var runtime := {"actors": [], "solids": [], "widgets": [], "player": -1,
		"spawn_x": 0.0, "spawn_y": 0.0, "has_spawn": false}
	if source == null:
		return runtime
	var port := _find_native_port(source)
	var json_path := String(port.get("json", ""))
	if json_path.is_empty() or not FileAccess.file_exists(json_path):
		return runtime
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return runtime
	var data: Dictionary = parsed
	var actors: Array = []
	var player_index := -1
	for entry in data.get("actors", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var kind := int(entry.get("type", 0))
		if kind not in [1, 2]:
			continue
		var rel := String(entry.get("asset", ""))
		if rel.is_empty():
			continue
		var png := _resolve_project_path(source, rel)
		if png.is_empty() or not FileAccess.file_exists(png):
			continue
		var image := Image.load_from_file(png)
		if image == null:
			continue
		image.convert(Image.FORMAT_RGBA8)
		var sprite_json := png.get_basename() + ".retro_sprite.json"
		var frame_w := int(entry.get("width", 16))
		var frame_h := int(entry.get("height", 16))
		var frames: Array = []
		if FileAccess.file_exists(sprite_json):
			var sd = JSON.parse_string(FileAccess.get_file_as_string(sprite_json))
			if typeof(sd) == TYPE_DICTIONARY:
				frame_w = int(sd.get("frame_width", frame_w))
				frame_h = int(sd.get("frame_height", frame_h))
				for f in sd.get("frames", []):
					if typeof(f) != TYPE_DICTIONARY:
						continue
					var rect := _parse_rect_string(String(f.get("rect", "")))
					if rect.size.x <= 0 or rect.size.y <= 0:
						rect = Rect2i(0, 0, frame_w, frame_h)
					frames.append(rect)
		if frames.is_empty():
			frames.append(Rect2i(0, 0, maxi(1, frame_w), maxi(1, frame_h)))
		var states := {}
		var anim_rel := String(entry.get("animation", ""))
		if not anim_rel.is_empty():
			var anim_path := _resolve_project_path(source, anim_rel)
			if FileAccess.file_exists(anim_path):
				var ad = JSON.parse_string(FileAccess.get_file_as_string(anim_path))
				if typeof(ad) == TYPE_DICTIONARY:
					var state_data = ad.get("states", {})
					if typeof(state_data) == TYPE_DICTIONARY:
						for key in state_data.keys():
							var state = state_data[key]
							if typeof(state) != TYPE_DICTIONARY:
								continue
							var indices: Array = []
							for fr in state.get("frames", []):
								if typeof(fr) != TYPE_DICTIONARY:
									continue
								var sf := int(fr.get("sprite_frame", -1))
								if sf >= 0 and sf < frames.size():
									indices.append(sf)
							if not indices.is_empty():
								states[String(key).to_upper()] = indices
		var pos: Array = entry.get("position", [0.0, 0.0, 0.0])
		var px := float(pos[0]) if pos.size() > 0 else 0.0
		var py := float(pos[1]) if pos.size() > 1 else 0.0
		var off: Array = entry.get("offset", [0.0, 0.0])
		var off_x := float(off[0]) if off.size() > 0 else 0.0
		var off_y := float(off[1]) if off.size() > 1 else 0.0
		var lowered := String(entry.get("name", "")).to_lower()
		if player_index < 0 and (lowered.contains("player") or lowered.contains("hero")):
			player_index = actors.size()
		actors.append({"name": String(entry.get("name", "actor")), "type": kind,
			"x": px, "y": py, "width": maxi(1, frame_w), "height": maxi(1, frame_h),
			"image": image, "frames": frames, "states": states,
			"current_state": String(entry.get("current_state", "")),
			"centered": bool(entry.get("centered", true)),
			"offset_x": off_x, "offset_y": off_y})
	if player_index < 0 and not actors.is_empty():
		player_index = 0
	for n in data.get("nodes", []):
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var nk := String(n.get("kind", ""))
		if nk == "spawn":
			var nm := String(n.get("name", "")).to_lower()
			if nm.contains("player") or nm.contains("start") or nm.contains("spawn"):
				var gp: Array = n.get("global_position", n.get("position", [0.0, 0.0]))
				runtime["spawn_x"] = float(gp[0]) if gp.size() > 0 else 0.0
				runtime["spawn_y"] = float(gp[1]) if gp.size() > 1 else 0.0
				runtime["has_spawn"] = true
		elif nk == "collision" or nk == "collision_polygon":
			var gp2: Array = n.get("global_position", n.get("position", [0.0, 0.0]))
			var gx := float(gp2[0]) if gp2.size() > 0 else 0.0
			var gy := float(gp2[1]) if gp2.size() > 1 else 0.0
			var shape := String(n.get("shape", "rect"))
			var cw := 0.0
			var ch := 0.0
			if nk == "collision_polygon":
				var pts: Array = n.get("points", [])
				if not pts.is_empty():
					var min_x := 1e30
					var min_y := 1e30
					var max_x := -1e30
					var max_y := -1e30
					for pt in pts:
						if typeof(pt) == TYPE_ARRAY and Array(pt).size() >= 2:
							min_x = minf(min_x, float(pt[0]))
							min_y = minf(min_y, float(pt[1]))
							max_x = maxf(max_x, float(pt[0]))
							max_y = maxf(max_y, float(pt[1]))
					if max_x >= min_x and max_y >= min_y:
						gx += (min_x + max_x) * 0.5
						gy += (min_y + max_y) * 0.5
						cw = max_x - min_x
						ch = max_y - min_y
			elif shape == "rect":
				var size: Array = n.get("size", [0.0, 0.0])
				cw = float(size[0]) if size.size() > 0 else 0.0
				ch = float(size[1]) if size.size() > 1 else 0.0
			elif shape == "circle":
				var radius := float(n.get("radius", 0.0))
				cw = radius * 2.0
				ch = radius * 2.0
			elif shape == "capsule":
				var radius2 := float(n.get("radius", 0.0))
				cw = radius2 * 2.0
				ch = float(n.get("height", radius2 * 2.0))
			elif shape == "convex_polygon":
				var pts2: Array = n.get("points", [])
				if not pts2.is_empty():
					var min2 := Vector2(1e30, 1e30)
					var max2 := Vector2(-1e30, -1e30)
					for pt in pts2:
						if typeof(pt) == TYPE_ARRAY and Array(pt).size() >= 2:
							min2.x = minf(min2.x, float(pt[0]))
							min2.y = minf(min2.y, float(pt[1]))
							max2.x = maxf(max2.x, float(pt[0]))
							max2.y = maxf(max2.y, float(pt[1]))
					if max2.x >= min2.x and max2.y >= min2.y:
						cw = max2.x - min2.x
						ch = max2.y - min2.y
			if cw > 0.0 and ch > 0.0:
				runtime["solids"].append({"x": gx - cw * 0.5, "y": gy - ch * 0.5, "w": cw, "h": ch})
	var focusable := ["Button", "OptionButton", "ItemList", "CheckBox", "CheckButton", "LineEdit", "TextEdit"]
	for w in data.get("widgets", []):
		if typeof(w) != TYPE_DICTIONARY:
			continue
		if not bool(w.get("visible", true)):
			continue
		var wt := String(w.get("type", ""))
		if wt not in focusable:
			continue
		var items: Array = w.get("items", [])
		runtime["widgets"].append({"x": int(w.get("x", 0)), "y": int(w.get("y", 0)),
			"w": int(w.get("w", 0)), "h": int(w.get("h", 0)), "type": wt,
			"items": items.size(), "selected": int(w.get("selected", 0)), "text": String(w.get("text", ""))})
	runtime["actors"] = actors
	runtime["player"] = player_index
	return runtime

static func _actor_cell_size(runtime_actor: Dictionary) -> Vector2i:
	var w := int(runtime_actor.get("width", 16))
	var h := int(runtime_actor.get("height", 16))
	return Vector2i(16 if w <= 16 else 32, 16 if h <= 16 else 32)

static func _actor_source_rect(runtime_actor: Dictionary, frame_index: int) -> Rect2i:
	var frames: Array = runtime_actor.get("frames", [])
	if frames.is_empty():
		return Rect2i(0, 0, int(runtime_actor.get("width", 16)), int(runtime_actor.get("height", 16)))
	var idx := clampi(frame_index, 0, frames.size() - 1)
	return frames[idx]

static func _actor_frame_image(runtime_actor: Dictionary, frame_index: int, cell: Vector2i) -> Image:
	var image: Image = runtime_actor.get("image")
	if image == null:
		return null
	var src_rect := _actor_source_rect(runtime_actor, frame_index)
	src_rect.position.x = clampi(src_rect.position.x, 0, maxi(0, image.get_width() - 1))
	src_rect.position.y = clampi(src_rect.position.y, 0, maxi(0, image.get_height() - 1))
	src_rect.size.x = clampi(src_rect.size.x, 1, image.get_width() - src_rect.position.x)
	src_rect.size.y = clampi(src_rect.size.y, 1, image.get_height() - src_rect.position.y)
	var frame := image.get_region(src_rect)
	if frame.get_width() != cell.x or frame.get_height() != cell.y:
		frame.resize(cell.x, cell.y, Image.INTERPOLATE_NEAREST)
	return frame

static func _layout_sprite_atlas(runtime: Dictionary) -> Dictionary:
	const ATLAS_W := 128
	const MAX_H := 256
	var actors: Array = runtime.get("actors", [])
	var player := int(runtime.get("player", -1))
	var order: Array = []
	if player >= 0 and player < actors.size():
		order.append(player)
	for i in range(actors.size()):
		if i != player:
			order.append(i)
	var atlas := Image.create_empty(ATLAS_W, MAX_H, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var placements := {}
	var active: Array = []
	var cursor_rect := Rect2i()
	var cursor_x := 0
	var cursor_y := 0
	var x := 0
	var y := 0
	var row_h := 0
	var max_actors := 30
	for idx in order:
		if active.size() >= max_actors:
			break
		var actor: Dictionary = actors[idx]
		var cell := _actor_cell_size(actor)
		actor["cell_w"] = cell.x
		actor["cell_h"] = cell.y
		var frames: Array = actor.get("frames", [])
		var local := []
		var lx := x
		var ly := y
		var lrow := row_h
		var fits := true
		for f in range(frames.size()):
			if lx + cell.x > ATLAS_W:
				lx = 0
				ly += lrow
				lrow = 0
			if ly + cell.y > MAX_H:
				fits = false
				break
			local.append(Rect2i(lx, ly, cell.x, cell.y))
			lx += cell.x
			lrow = maxi(lrow, cell.y)
		if not fits or local.is_empty():
			actor["skipped"] = true
			continue
		placements[idx] = local
		actor["skipped"] = false
		x = lx
		y = ly
		row_h = lrow
		active.append(idx)
	if not Array(runtime.get("widgets", [])).is_empty() and x + 16 > ATLAS_W:
		x = 0
		y += row_h
		row_h = 0
	if not Array(runtime.get("widgets", [])).is_empty() and y + 16 <= MAX_H:
		cursor_rect = Rect2i(x, y, 16, 16)
		cursor_x = x
		cursor_y = y
		y += 16
	for idx in active:
		var actor: Dictionary = actors[idx]
		var cell := Vector2i(int(actor.get("cell_w", 16)), int(actor.get("cell_h", 16)))
		var rects: Array = placements[idx]
		for f in range(rects.size()):
			var frame := _actor_frame_image(actor, f, cell)
			if frame == null:
				continue
			var dest: Rect2i = rects[f]
			atlas.blit_rect(frame, Rect2i(0, 0, frame.get_width(), frame.get_height()),
				Vector2i(dest.position.x, dest.position.y))
	if cursor_rect.size.x > 0:
		var cursor := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		cursor.fill(Color(0, 0, 0, 0))
		for yy in range(16):
			for xx in range(8):
				if xx <= yy and xx <= (15 - yy):
					cursor.set_pixel(xx, yy, Color("#ff40c0"))
				if xx <= (15 - yy) and xx <= yy:
					cursor.set_pixel(15 - xx, yy, Color("#ff40c0"))
		atlas.blit_rect(cursor, Rect2i(0, 0, 16, 16), Vector2i(cursor_x, cursor_y))
	var content_h := y + row_h
	if cursor_rect.size.x > 0:
		content_h = maxi(content_h, cursor_rect.position.y + cursor_rect.size.y)
	var height := maxi(8, content_h)
	height = ((height + 7) / 8) * 8
	if height > MAX_H:
		height = MAX_H
	var cropped := atlas.get_region(Rect2i(0, 0, ATLAS_W, height))
	return {"image": cropped, "placements": placements, "active": active,
		"cursor": cursor_rect}

static func _tile_for_rect(rect: Rect2i) -> int:
	return (rect.position.y / 8) * 16 + (rect.position.x / 8)

static func _state_frames(actor: Dictionary, state: String) -> Array:
	var states: Dictionary = actor.get("states", {})
	var out: Array = []
	if states.has(state):
		for idx in states[state]:
			out.append(int(idx))
	return out

static func _copy_native_port(port: Dictionary, dir: String) -> Dictionary:
	if port.is_empty():
		return {}
	var out_dir := dir.path_join("port")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var copied: Array = []
	for key in ["header", "json", "markdown"]:
		var src := String(port.get(key, ""))
		if src.is_empty() or not FileAccess.file_exists(src):
			continue
		var dst := out_dir.path_join(src.get_file())
		if DirAccess.copy_absolute(src, dst) == OK:
			copied.append(dst)
	var scripts_src := String(port.get("scripts_dir", ""))
	if not scripts_src.is_empty() and DirAccess.dir_exists_absolute(scripts_src):
		var scripts_dst := out_dir.path_join("scripts")
		DirAccess.make_dir_recursive_absolute(scripts_dst)
		var scripts := DirAccess.open(scripts_src)
		if scripts:
			for file in scripts.get_files():
				if file.get_extension().to_lower() in ["gd", "cs"]:
					var dst := scripts_dst.path_join(file)
					if DirAccess.copy_absolute(scripts_src.path_join(file), dst) == OK:
						copied.append(dst)
	var markdown_src := String(port.get("markdown", ""))
	if not markdown_src.is_empty() and FileAccess.file_exists(markdown_src):
		var porting_md := dir.path_join("PORTING.md")
		var text := "# Porting bundle\n\nThis project includes the native Godot port manifest.\n\n"
		text += "- Report: `port/%s`\n" % markdown_src.get_file()
		text += "- Header: `port/%s`\n" % String(port.get("header", "")).get_file()
		text += "- Scripts: `port/scripts/`\n"
		var f := FileAccess.open(porting_md, FileAccess.WRITE)
		if f:
			f.store_string(text)
			f.close()
			copied.append(porting_md)
	return {"ok": not copied.is_empty(), "directory": out_dir, "files": copied,
		"header": out_dir.path_join(String(port.get("header", "")).get_file()),
		"json": out_dir.path_join(String(port.get("json", "")).get_file())}

static func _find_audio(source: RetroProject) -> Array:
	var out: Array = []
	if source == null:
		return out
	var seen := {}
	var add_asset := func(path: String, fallback_kind: String):
		if path.is_empty() or seen.has(path):
			return
		seen[path] = true
		var data: Dictionary = {}
		if path.get_extension().to_lower() == "json" and FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				data = parsed
		var ext := path.get_extension().to_lower()
		var kind := String(data.get("kind", fallback_kind))
		if kind not in ["bgm", "sfx"]:
			kind = "bgm" if ext in ["mid", "it"] else "sfx"
		var entry := {
			"path": path,
			"name": String(data.get("name", path.get_file().get_basename())),
			"kind": kind,
			"source": String(data.get("source", path)),
			"params": data.get("params", {})
		}
		out.append(entry)
	for r in source.find_resources("audio", true):
		add_asset.call(String(r.get("path", "")), String(r.get("kind", "sfx")))
	for a in source.get_metadata().get("audio_assets", []):
		if typeof(a) == TYPE_DICTIONARY:
			add_asset.call(String(a.get("path", "")), String(a.get("kind", "sfx")))
	return out

static func _short_sdk_path(target: String, actual: String) -> String:
	if actual.is_empty() or not actual.contains(" "):
		return actual
	var candidates: Array = []
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		candidates.append(home.path_join(".local/share/godot-retro-engine/sdks/" + ("snes" if target == "snes" else "megadrive")))
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.is_empty():
		candidates.append(xdg.path_join("godot-retro-engine/sdks/" + ("snes" if target == "snes" else "megadrive")))
	for candidate in candidates:
		if String(candidate).contains(" "):
			continue
		if target == "snes" and FileAccess.file_exists(String(candidate).path_join("devkitsnes/snes_rules")):
			return String(candidate)
		if target == "megadrive" and FileAccess.file_exists(String(candidate).path_join("makefile.gen")):
			return String(candidate)
	return actual

static func _sdk_path(source: RetroProject, target: String) -> String:
	if source != null and source.get_platform() == target and not source.get_sdk_path().is_empty():
		return source.get_sdk_path()
	return String(RetroSDK.get_sdk(target).get("path", ""))

static func _find_stage(source: RetroProject, target: String, explicit: String) -> RetroStage:
	var bridge := RetroNativeBridge.new()
	if not explicit.is_empty():
		var s := _load_stage(explicit, target, bridge, {}, source.get_platform() if source else "snes")
		if s != null:
			return s
	if source != null:
		var links := source.resolve(".retro/editor/native_links.json")
		if FileAccess.file_exists(links):
			var data = JSON.parse_string(FileAccess.get_file_as_string(links))
			if typeof(data) == TYPE_DICTIONARY:
				var native_stage = data.get("stage", {})
				if typeof(native_stage) == TYPE_DICTIONARY:
					var stage_json := String(native_stage.get("stage_json", ""))
					if not stage_json.is_empty() and FileAccess.file_exists(stage_json):
						var s := _load_stage(stage_json, target, bridge)
						if s != null:
							return s
				var assets: Array = data.get("assets", [])
				for i in range(assets.size() - 1, -1, -1):
					var a: Dictionary = assets[i]
					var path := String(a.get("asset", ""))
					if str(a.get("type", "")) == "stage" or path.ends_with(".retro_stage.json"):
						var s := _load_stage(path, target, bridge)
						if s != null:
							return s
		var stage_resources := source.find_resources("stage", true)
		var ordered_stages: Array = []
		for r in stage_resources:
			var p := String(r.get("path", ""))
			if p.ends_with(".retro_stage.json") or p.get_extension().to_lower() == "json":
				ordered_stages.push_front(r)
			else:
				ordered_stages.push_back(r)
		for r in ordered_stages:
			var stage_path := String(r.get("path", ""))
			var s := _load_stage(stage_path, target, bridge, r, source.get_platform())
			if s != null:
				return s
		var image_resources := source.find_resources("sprite", true)
		for r in image_resources:
			var path := String(r.get("path", ""))
			if path.get_extension().to_lower() in ["png", "bmp", "webp"]:
				var s := _stage_from_image(path, target, bridge)
				if s != null:
					return s
		# Sonic 2 disassembly projects have no RetroStage resource: build one
		# from the original Kosinski layout/tile data instead.
		var sonic_stage := SonicStageImport.build(source)
		if sonic_stage != null:
			return sonic_stage
	return null

static func _load_stage(path: String, target: String, bridge: RetroNativeBridge, resource: Dictionary = {},
		source_platform := "snes") -> RetroStage:
	if path.is_empty():
		return null
	var ext := path.get_extension().to_lower()
	if ext == "json":
		var stage := RetroStage.new()
		if stage.load(path) == OK:
			return stage
		return null
	if ext in ["chr", "pic"]:
		var map_path := String(resource.get("map_path", ""))
		var pal_path := String(resource.get("palette_path", ""))
		if map_path.is_empty() or pal_path.is_empty():
			var base := path.get_basename()
			if map_path.is_empty() and FileAccess.file_exists(base + ".map"):
				map_path = base + ".map"
			if pal_path.is_empty() and FileAccess.file_exists(base + ".pal"):
				pal_path = base + ".pal"
		if not map_path.is_empty() and not pal_path.is_empty():
			var stage := RetroStage.new()
			stage.set_platform(source_platform)
			if stage.load_snes(path, map_path, pal_path,
				int(resource.get("map_w", 32)), int(resource.get("map_h", 32)),
				int(resource.get("tile_size", 8)), int(resource.get("bpp", 4)),
				int(resource.get("tiles_x", 16)), bool(resource.get("column_major", false))) == OK:
				return stage
		return null
	if ext == "map":
		var base := path.get_basename()
		var chr_path := base + ".chr"
		if not FileAccess.file_exists(chr_path):
			chr_path = base + ".pic"
		var pal_path := base + ".pal"
		if FileAccess.file_exists(chr_path) and FileAccess.file_exists(pal_path):
			var stage := RetroStage.new()
			stage.set_platform(source_platform)
			if stage.load_snes(chr_path, path, pal_path, 32, 32, 8, 4, 16, false) == OK:
				return stage
		return null
	if ext in ["png", "bmp", "webp"]:
		if not resource.is_empty():
			var map_path := String(resource.get("map_path", ""))
			if not map_path.is_empty():
				var stage := RetroStage.new()
				stage.set_platform(target if target == "megadrive" else "snes")
				if stage.load_image_tileset(path, map_path,
					int(resource.get("map_w", 32)), int(resource.get("map_h", 32)),
					int(resource.get("tile_size", 8))) == OK:
					return stage
		return _stage_from_image(path, target, bridge)
	return null

static func _stage_from_image(path: String, target: String, bridge: RetroNativeBridge) -> RetroStage:
	var image := Image.load_from_file(path)
	if image == null:
		return null
	var result: Dictionary = bridge.import_stage_image(image, path.get_file().get_basename(), path.get_base_dir(),
		target, "mode1" if target == "snes" else "h40", 8, 1024 if target == "snes" else 2048, 16, path)
	return result.get("stage") if bool(result.get("ok", false)) else null

static func _retarget_stage(stage: RetroStage, target: String) -> RetroStage:
	if stage.get_platform() == target:
		return stage
	var copy := RetroStage.new()
	copy.from_dict(stage.to_dict())
	var w := copy.get_map_size().x
	var h := copy.get_map_size().y
	var infos: Array = []
	for y in range(h):
		for x in range(w):
			infos.append(copy.get_tile_info(x, y))
	copy.set_platform(target)
	var map := PackedByteArray()
	map.resize(w * h * 2)
	copy.set_map(map)
	for y in range(h):
		for x in range(w):
			var info: Dictionary = infos[y * w + x]
			copy.set_tile(x, y, int(info.get("tile", 0)), int(info.get("palette", 0)),
				int(info.get("hflip", 0)), int(info.get("vflip", 0)), int(info.get("priority", 0)))
	return copy

static func _write_assets(header_path: String, source_path: String, stage: RetroStage, splash: RetroStage,
		target: String, include_splash: bool, rom: Dictionary = {}) -> Dictionary:
	var game := _stage_data(stage, target)
	var splash_data := _stage_data(splash, target) if splash != null else {}
	var h := "#ifndef RETRO_GAME_ASSETS_H\n#define RETRO_GAME_ASSETS_H\n\n"
	h += "#define GAME_MAP_W %d\n#define GAME_MAP_H %d\n#define GAME_MAP_STRIDE %d\n#define GAME_MAP_BYTES %d\n#define GAME_BG_SIZE %s\n#define GAME_TILE_COUNT %d\n" % [
		int(game["map_w"]), int(game["map_h"]), int(game["map_stride"]), int(game["map_bytes"]),
		String(game["bg_size"]), int(game["tile_count"])]
	if include_splash and not splash_data.is_empty():
		h += "#define RETRO_SPLASH 1\n#define SPLASH_MAP_W %d\n#define SPLASH_MAP_H %d\n#define SPLASH_MAP_STRIDE %d\n#define SPLASH_MAP_BYTES %d\n#define SPLASH_BG_SIZE %s\n#define SPLASH_TILE_COUNT %d\n" % [
			int(splash_data["map_w"]), int(splash_data["map_h"]), int(splash_data["map_stride"]),
			int(splash_data["map_bytes"]), String(splash_data["bg_size"]), int(splash_data["tile_count"])]
	else:
		h += "#define RETRO_SPLASH 0\n"
	if not rom.is_empty():
		h += "#define RETRO_MSU1 %d\n" % (1 if bool(rom.get("msu1", false)) else 0)
		h += "#define RETRO_ROM_HEADER_MODE 0x%02X\n" % int(rom.get("header_mode", 0))
		h += "#define RETRO_ROM_SIZE_BYTES %du\n" % int(rom.get("size_bytes", 0))
		h += "#define RETRO_ROM_PROFILE \"%s\"\n" % String(rom.get("profile_id", ""))
	h += "\n"
	var decl := "unsigned char"
	var word := "unsigned char" if target == "snes" else "unsigned short"
	h += "extern const %s game_tiles[];\nextern const unsigned int game_tiles_size;\n" % decl
	h += "extern const %s game_pal[];\nextern const unsigned int game_pal_size;\n" % word
	h += "extern const %s game_map[];\nextern const unsigned int game_map_size;\n" % word
	if include_splash and not splash_data.is_empty():
		h += "extern const %s splash_tiles[];\nextern const unsigned int splash_tiles_size;\n" % decl
		h += "extern const %s splash_pal[];\nextern const unsigned int splash_pal_size;\n" % word
		h += "extern const %s splash_map[];\nextern const unsigned int splash_map_size;\n" % word
	h += "\n#endif\n"
	var c := "#include \"assets.h\"\n\n"
	var asm_ok := true
	if target == "snes":
		# The PVSnesLib C compiler emits one huge .db line per array; WLA
		# truncates lines above ~1 KB and then fails on the fragment. Keep the
		# big ROM assets in binary files included by a small assembly module.
		asm_ok = _write_snes_blob_assets(source_path.get_base_dir(), game, splash_data, include_splash, rom)
		c += "const unsigned int game_tiles_size = %d;\n" % int(game["tiles"].size())
		c += "const unsigned int game_pal_size = %d;\n" % int(game["pal"].size())
		c += "const unsigned int game_map_size = %d;\n" % int(game["map"].size())
		if include_splash and not splash_data.is_empty():
			c += "const unsigned int splash_tiles_size = %d;\n" % int(splash_data["tiles"].size())
			c += "const unsigned int splash_pal_size = %d;\n" % int(splash_data["pal"].size())
			c += "const unsigned int splash_map_size = %d;\n" % int(splash_data["map"].size())
	else:
		c += _array_decl("game_tiles", game["tiles"], decl) + "\n"
		c += "const unsigned int game_tiles_size = sizeof(game_tiles);\n"
		c += _array_decl("game_pal", game["pal"], word) + "\n"
		c += "const unsigned int game_pal_size = sizeof(game_pal);\n"
		c += _array_decl("game_map", game["map"], word) + "\n"
		c += "const unsigned int game_map_size = sizeof(game_map);\n"
		if include_splash and not splash_data.is_empty():
			c += _array_decl("splash_tiles", splash_data["tiles"], decl) + "\n"
			c += "const unsigned int splash_tiles_size = sizeof(splash_tiles);\n"
			c += _array_decl("splash_pal", splash_data["pal"], word) + "\n"
			c += "const unsigned int splash_pal_size = sizeof(splash_pal);\n"
			c += _array_decl("splash_map", splash_data["map"], word) + "\n"
			c += "const unsigned int splash_map_size = sizeof(splash_map);\n"
	var e1 := _write_text(header_path, h)
	var e2 := _write_text(source_path, c)
	return {"ok": e1 == OK and e2 == OK and asm_ok, "header": header_path, "source": source_path}

static func _write_snes_blob_assets(dir: String, game: Dictionary, splash_data: Dictionary, include_splash: bool,
		rom: Dictionary = {}) -> bool:
	var entries: Array = [
		{"name": "game_tiles", "file": "assets_tiles.bin", "data": _array_to_bytes(game["tiles"])},
		{"name": "game_pal", "file": "assets_pal.bin", "data": _array_to_bytes(game["pal"])},
		{"name": "game_map", "file": "assets_map.bin", "data": _array_to_bytes(game["map"])},
	]
	if include_splash and not splash_data.is_empty():
		entries.append({"name": "splash_tiles", "file": "assets_splash_tiles.bin", "data": _array_to_bytes(splash_data["tiles"])})
		entries.append({"name": "splash_pal", "file": "assets_splash_pal.bin", "data": _array_to_bytes(splash_data["pal"])})
		entries.append({"name": "splash_map", "file": "assets_splash_map.bin", "data": _array_to_bytes(splash_data["map"])})
	return _write_snes_asm_blobs(dir, entries, rom, "assets_data.asm")

## Writes binary assets plus a small WLA module that .incbin's them. The
## PVSnesLib C compiler puts a whole array on one .db line and truncates it at
## 100 KiB (and WLA rejects the fragment), so large assets must not go through
## a C initializer.
static func _write_snes_asm_blobs(dir: String, entries: Array, rom: Dictionary, asm_name: String) -> bool:
	var mapping := String(rom.get("mapping", "lorom"))
	var hi := mapping in ["hirom", "exhirom"]
	var bank_size := 0x10000 if hi else 0x8000
	var slot0 := 0x0000 if hi else 0x8000
	var banks := maxi(1, int(rom.get("banks", 8)))
	var asm := ".MEMORYMAP\n  SLOTSIZE $%X\n  DEFAULTSLOT 0\n  SLOT 0 $%X\n" % [bank_size, slot0]
	asm += "  SLOT 1 $0 $2000\n  SLOT 2 $2000 $E000\n  SLOT 3 $0 $10000\n"
	if hi:
		asm += "  SLOT 4 $6000\n"
	asm += ".ENDME\n.ROMBANKMAP\n  BANKSTOTAL %d\n  BANKSIZE $%X\n  BANKS %d\n.ENDRO\n\n" % [banks, bank_size, banks]
	var ok := true
	for entry in entries:
		var name := String(entry["name"])
		var file := String(entry["file"])
		var bytes: PackedByteArray = entry["data"]
		ok = _write_bytes(dir.path_join(file), bytes) == OK and ok
		asm += ".section \".rodata_%s\" superfree\n" % name
		asm += "%s:\n.incbin \"src/%s\"\n" % [name, file]
		asm += ".export %s\n.ends\n\n" % name
	ok = _write_text(dir.path_join(asm_name), asm) == OK and ok
	return ok

static func _array_to_bytes(values: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(values.size())
	for i in range(values.size()):
		out[i] = int(values[i]) & 0xFF
	return out

static func _stage_data(stage: RetroStage, target: String) -> Dictionary:
	var tileset: Image = stage.get_tileset()
	var palette: PackedColorArray = stage.get_palette()
	if tileset == null or palette.is_empty():
		return {}
	var md := target == "megadrive"
	# Indexed stages (for example imported Mega Drive levels) must keep their
	# original 4bpp indices: the palette has several 16-colour lines and a
	# nearest-colour remap would lose the per-tile palette line.
	var indices: Image = stage.get_tile_indices()
	var tiles := RetroGraphics.encode_tiles_indexed(indices, stage.get_bpp(), stage.get_tile_size(), md) if indices != null \
		else RetroGraphics.encode_tiles(tileset, stage.get_bpp(), palette, stage.get_tile_size(), md)
	var pal := RetroGraphics.encode_palette(palette, md)
	var map := stage.get_map()
	var map_w := stage.get_map_size().x
	var map_h := stage.get_map_size().y
	var tile_count := int(tiles.size() / 32)
	if md:
		var md_blank := -1
		for t in range(tile_count):
			var is_blank := true
			for b in range(32):
				if tiles[t * 32 + b] != 0:
					is_blank = false
					break
			if is_blank:
				md_blank = t
				break
		var md_prepend := md_blank != 0
		var md_tiles := PackedByteArray()
		if md_prepend:
			var zero := PackedByteArray()
			zero.resize(32)
			md_tiles.append_array(zero)
		md_tiles.append_array(tiles)
		var md_map := PackedByteArray()
		md_map.resize(map.size())
		for i in range(0, map.size(), 2):
			var word := (map[i] << 8) | map[i + 1]
			var tile := word & 0x07FF
			if md_prepend:
				if md_blank < 0 or tile != md_blank:
					tile += 1
				else:
					tile = 0
			var shifted := (word & 0xF800) | (tile & 0x07FF)
			md_map[i] = (shifted >> 8) & 0xFF
			md_map[i + 1] = shifted & 0xFF
		return {"tiles": _byte_values(md_tiles), "pal": _u16_words(pal), "map": _u16_words(md_map),
			"tile_count": tile_count + (1 if md_prepend else 0), "map_w": map_w, "map_h": map_h,
			"map_bytes": md_map.size(), "map_stride": map_w, "bg_size": "SC_32x32"}
	# SNES BG maps are allocated as 32/64-tile rows. Pad the source map to the
	# actual BG allocation so rows are not interpreted as a different stride.
	# Reserve a blank tile at the end of the tileset for the padding.
	var blank_tile := PackedByteArray()
	blank_tile.resize(32)
	var blank_source := -1
	for t in range(tile_count):
		var is_blank := true
		for b in range(32):
			if tiles[t * 32 + b] != 0:
				is_blank = false
				break
		if is_blank:
			blank_source = t
			break
	var prepend_blank := blank_source != 0
	var padded_tiles := PackedByteArray()
	if prepend_blank:
		padded_tiles.append_array(blank_tile)
	padded_tiles.append_array(tiles)
	var stride := 32
	var rows := 32
	var bg_size := "SC_32x32"
	if map_w > 32 or map_h > 32:
		stride = 64
		rows = 64 if map_h > 32 else 32
		bg_size = "SC_64x32" if map_h <= 32 else "SC_64x64"
	var padded_map := PackedByteArray()
	padded_map.resize(stride * rows * 2)
	for y in range(mini(map_h, rows)):
		for x in range(mini(map_w, stride)):
			var src := (y * map_w + x) * 2
			var word := map[src] | (map[src + 1] << 8)
			var tile := word & 0x03FF
			if prepend_blank:
				if blank_source < 0 or tile != blank_source:
					tile += 1
				else:
					tile = 0
			var shifted := (word & 0xFC00) | (tile & 0x03FF)
			# A 64-tile-wide SNES BG is stored as two 32x32 screens (left at
			# offset 0, right at 0x800) and a 64x64 BG as four screens. Writing
			# it as 64 contiguous words per row makes rows 1/3 read the second
			# screen and produces stripes.
			var idx := 0
			if stride == 32:
				idx = (y * 32 + x) * 2
			else:
				var screen := (y / 32) * 2 + (x / 32)
				idx = (screen * 1024 + (y % 32) * 32 + (x % 32)) * 2
			padded_map[idx] = shifted & 0xFF
			padded_map[idx + 1] = (shifted >> 8) & 0xFF
	return {"tiles": _byte_values(padded_tiles), "pal": _byte_values(pal), "map": _byte_values(padded_map),
		"tile_count": tile_count + (1 if prepend_blank else 0), "map_w": map_w, "map_h": map_h,
		"map_bytes": padded_map.size(), "map_stride": stride, "bg_size": bg_size}

static func _byte_values(data: PackedByteArray) -> Array:
	var out: Array = []
	for i in range(data.size()):
		out.append(data[i])
	return out

static func _u16_words(data: PackedByteArray) -> Array:
	var out: Array = []
	var i := 0
	while i + 1 < data.size():
		out.append((data[i] << 8) | data[i + 1])
		i += 2
	if i < data.size():
		out.append(data[i] << 8)
	return out

static func _array_decl(name: String, values: Array, type: String) -> String:
	var out := "const %s %s[] = {\n" % [type, name]
	for i in range(values.size()):
		out += "\t" + str(int(values[i]))
		if i + 1 < values.size():
			out += ","
		if (i + 1) % 12 == 0:
			out += "\n"
	out += "\n};\n"
	return out

static func _find_player(source: RetroProject, target: String) -> Dictionary:
	if source == null:
		return {}
	var png_path := ""
	var links := source.resolve(".retro/editor/native_links.json")
	if FileAccess.file_exists(links):
		var data = JSON.parse_string(FileAccess.get_file_as_string(links))
		if typeof(data) == TYPE_DICTIONARY:
			for a in data.get("assets", []):
				if typeof(a) != TYPE_DICTIONARY:
					continue
				if int(a.get("type", 0)) not in [1, 2]:
					continue
				var rel := String(a.get("asset", ""))
				if rel.is_empty():
					continue
				var path := rel if rel.is_absolute_path() else source.resolve(rel)
				if path.get_extension().to_lower() == "png" and FileAccess.file_exists(path):
					png_path = path
					break
	if png_path.is_empty():
		for r in source.find_resources("sprite", true):
			var path := String(r.get("path", ""))
			if path.get_extension().to_lower() == "png" and FileAccess.file_exists(path):
				png_path = path
				break
	if png_path.is_empty():
		return {}
	var image := Image.load_from_file(png_path)
	if image == null:
		return {}
	image.convert(Image.FORMAT_RGBA8)
	var rect := Rect2i(0, 0, image.get_width(), image.get_height())
	var sprite_json := png_path.get_basename() + ".retro_sprite.json"
	if FileAccess.file_exists(sprite_json):
		var sprite := RetroSprite.new()
		if sprite.load(sprite_json) == OK:
			var frames := sprite.get_frames()
			if not frames.is_empty():
				var r: Rect2i = Dictionary(frames[0]).get("rect", rect)
				if r.size.x > 0 and r.size.y > 0:
					rect = r
	rect.position.x = clampi(rect.position.x, 0, maxi(0, image.get_width() - 1))
	rect.position.y = clampi(rect.position.y, 0, maxi(0, image.get_height() - 1))
	rect.size.x = clampi(rect.size.x, 1, image.get_width() - rect.position.x)
	rect.size.y = clampi(rect.size.y, 1, image.get_height() - rect.position.y)
	var frame := image.get_region(rect)
	var w := 16
	var h := 16
	if target == "snes":
		w = 16 if frame.get_width() <= 16 and frame.get_height() <= 16 else 32
		h = 16 if frame.get_width() <= 16 and frame.get_height() <= 16 else 32
	else:
		w = clampi(int(ceil(float(frame.get_width()) / 8.0)) * 8, 8, 64)
		h = clampi(int(ceil(float(frame.get_height()) / 8.0)) * 8, 8, 64)
	if frame.get_width() != w or frame.get_height() != h:
		frame.resize(w, h, Image.INTERPOLATE_NEAREST)
	var quantized := RetroGraphics.quantize(frame, 16, true)
	if quantized == null:
		return {}
	var palette := RetroGraphics.extract_palette(quantized, 16, true)
	while palette.size() < 16:
		palette.push_back(Color(0, 0, 0))
	return {"png": png_path, "json": sprite_json, "image": quantized, "palette": palette,
		"w": w, "h": h, "name": png_path.get_file().get_basename()}

static func _write_snes_player(dir: String, player: Dictionary) -> void:
	var image: Image = player.get("image")
	var palette: PackedColorArray = player.get("palette", PackedColorArray())
	if image == null or palette.is_empty():
		return
	var tiles := RetroGraphics.encode_tiles(image, 4, palette, 8, false)
	var pal := RetroGraphics.encode_palette(palette, false)
	var header := "#ifndef RETRO_PLAYER_H\n#define RETRO_PLAYER_H\n\n#include <snes.h>\n\n"
	header += "#define PLAYER_W %d\n#define PLAYER_H %d\n" % [int(player.get("w", 16)), int(player.get("h", 16))]
	header += "#define PLAYER_TILES_SIZE %d\n#define PLAYER_PAL_SIZE %d\n\n" % [tiles.size(), pal.size()]
	header += "extern const unsigned char player_tiles[PLAYER_TILES_SIZE];\nextern const unsigned char player_pal[PLAYER_PAL_SIZE];\n\n#endif\n"
	var source := "#include \"player.h\"\n\n"
	source += _array_decl("player_tiles", _byte_values(tiles), "unsigned char")
	source += "\n"
	source += _array_decl("player_pal", _byte_values(pal), "unsigned char")
	_write_text(dir.path_join("src/player.h"), header)
	_write_text(dir.path_join("src/player.c"), source)

static func _write_md_player(dir: String, player: Dictionary) -> void:
	var image: Image = player.get("image")
	var palette: PackedColorArray = player.get("palette", PackedColorArray())
	if image == null or palette.is_empty():
		return
	var res_dir := dir.path_join("res")
	DirAccess.make_dir_recursive_absolute(res_dir)
	var png := res_dir.path_join("player.png")
	RetroGraphics.save_indexed_png(png, image, palette)
	var cols := maxi(1, int(player.get("w", 16)) / 8)
	var rows := maxi(1, int(player.get("h", 16)) / 8)
	_write_text(res_dir.path_join("player.res"), "SPRITE player_sprite \"player.png\" %d %d FAST 5\n" % [cols, rows])

static func _u16_array(name: String, values: Array) -> String:
	var out := "static const unsigned short %s[%d] = {\n" % [name, maxi(1, values.size())]
	if values.is_empty():
		out += "\t0\n"
	else:
		for i in range(values.size()):
			out += "\t" + str(int(values[i]))
			if i + 1 < values.size():
				out += ","
			if (i + 1) % 12 == 0:
				out += "\n"
		out += "\n"
	out += "};\n"
	return out

static func _prepare_runtime_assets(runtime: Dictionary) -> Dictionary:
	var layout := _layout_sprite_atlas(runtime)
	var atlas: Image = layout.get("image")
	if atlas == null:
		return {}
	var active: Array = layout.get("active", [])
	if active.is_empty():
		return {}
	var quantized := RetroGraphics.quantize(atlas, 16, true)
	var palette := RetroGraphics.extract_palette(quantized, 16, true)
	while palette.size() < 16:
		palette.push_back(Color(0, 0, 0, 0))
	var tiles := RetroGraphics.encode_tiles(quantized, 4, palette, 8, false)
	var actors: Array = runtime.get("actors", [])
	var placements: Dictionary = layout.get("placements", {})
	var player_original := int(runtime.get("player", -1))
	var packed: Array = []
	var player_packed := -1
	for idx in active:
		var actor: Dictionary = actors[idx]
		var rects: Array = placements.get(idx, [])
		var tile_list: Array = []
		for r in rects:
			tile_list.append(_tile_for_rect(r))
		var cell_w := int(actor.get("cell_w", 16))
		var cell_h := int(actor.get("cell_h", 16))
		var start_x := float(actor.get("x", 0.0))
		var start_y := float(actor.get("y", 0.0))
		if bool(actor.get("centered", true)):
			start_x -= cell_w * 0.5
			start_y -= cell_h * 0.5
		start_x += float(actor.get("offset_x", 0.0))
		start_y += float(actor.get("offset_y", 0.0))
		if idx == player_original and bool(runtime.get("has_spawn", false)):
			start_x = float(runtime.get("spawn_x", start_x)) - cell_w * 0.5
			start_y = float(runtime.get("spawn_y", start_y)) - cell_h * 0.5
		if idx == player_original:
			player_packed = packed.size()
		packed.append({"index": idx, "actor": actor, "tiles": tile_list,
			"x": int(round(start_x)), "y": int(round(start_y)),
			"w": cell_w, "h": cell_h,
			"size": 0 if cell_w <= 16 and cell_h <= 16 else 1,
			"player": idx == player_original})
	var cursor_tile := -1
	var cursor_rect: Rect2i = layout.get("cursor", Rect2i())
	if cursor_rect.size.x > 0:
		cursor_tile = _tile_for_rect(cursor_rect)
	return {"quantized": quantized, "palette": palette, "tiles": tiles,
		"actors": packed, "player": player_packed, "cursor_tile": cursor_tile,
		"cursor_rect": cursor_rect, "image": atlas}

static func _runtime_state_tiles(actor: Dictionary, state: String, tile_list: Array) -> Array:
	var out: Array = []
	for frame_index in _state_frames(actor, state):
		if frame_index >= 0 and frame_index < tile_list.size():
			out.append(int(tile_list[frame_index]))
	return out

static func _runtime_default_tiles(actor: Dictionary, tile_list: Array) -> Array:
	var states: Dictionary = actor.get("states", {})
	var current := String(actor.get("current_state", ""))
	if not current.is_empty():
		var current_frames := _runtime_state_tiles(actor, current, tile_list)
		if not current_frames.is_empty():
			return current_frames
	for state in ["IDLE", "WALK", "RUN", "JUMP", "FALL", "SPIN", "ATTACK"]:
		var frames := _runtime_state_tiles(actor, state, tile_list)
		if not frames.is_empty():
			return frames
	return tile_list.duplicate()

static func _write_snes_runtime(dir: String, runtime: Dictionary, stage: RetroStage) -> Dictionary:
	var prep := _prepare_runtime_assets(runtime)
	if prep.is_empty():
		return {"ok": false, "error": "no native sprite actors fit the SNES OBJ atlas"}
	var actors: Array = prep.get("actors", [])
	if actors.is_empty():
		return {"ok": false, "error": "no native sprite actors"}
	var palette: PackedColorArray = prep.get("palette", PackedColorArray())
	var tiles: PackedByteArray = prep.get("tiles", PackedByteArray())
	var pal_bytes := RetroGraphics.encode_palette(palette, false)
	var cursor_tile := int(prep.get("cursor_tile", -1))
	var player_index := int(prep.get("player", 0))
	if player_index < 0:
		player_index = 0
	var stage_size: Vector2i = stage.get_map_size()
	var widgets: Array = runtime.get("widgets", [])
	var solids: Array = runtime.get("solids", [])
	if solids.is_empty():
		solids = [{"x": 0, "y": 208, "w": 256, "h": 16}]
	var code := "#include <snes.h>\n#include \"assets.h\"\n#include \"runtime.h\"\n\n"
	code += _array_decl("runtime_tiles", _byte_values(tiles), "unsigned char")
	code += _array_decl("runtime_pal", _byte_values(pal_bytes), "unsigned char")
	code += "#define RUNTIME_TILES_SIZE %d\n" % tiles.size()
	code += "#define RUNTIME_PAL_SIZE %d\n" % pal_bytes.size()
	code += "#define RUNTIME_ACTOR_COUNT %d\n" % actors.size()
	code += "#define RUNTIME_WIDGET_COUNT %d\n" % widgets.size()
	code += "#define RUNTIME_SOLID_COUNT %d\n" % solids.size()
	code += "#define RUNTIME_PLAYER %d\n" % player_index
	code += "#define RUNTIME_SCREEN_W 256\n#define RUNTIME_SCREEN_H 224\n"
	code += "#define RUNTIME_WORLD_W (GAME_MAP_W * 8)\n"
	code += "#define RUNTIME_WORLD_H (GAME_MAP_H * 8)\n"
	code += "#define RUNTIME_CURSOR %d\n" % (1 if cursor_tile >= 0 else 0)
	if cursor_tile >= 0:
		code += "#define RUNTIME_CURSOR_OAM (RUNTIME_ACTOR_COUNT * 4)\n"
		code += "#define RUNTIME_CURSOR_TILE %d\n" % cursor_tile
	code += "\n"
	code += "typedef struct {\n"
	code += "    short x, y, w, h;\n"
	code += "    unsigned char size;\n    unsigned char player;\n"
	code += "    unsigned char frame_count;\n    unsigned char default_count;\n"
	code += "    const unsigned short *frames;\n    const unsigned short *default_frames;\n"
	code += "    unsigned char state_len[5];\n    const unsigned short *state_frames[5];\n"
	code += "} RetroActorDef;\n\n"
	for j in range(actors.size()):
		var item: Dictionary = actors[j]
		var actor: Dictionary = item.get("actor", {})
		var tile_list: Array = item.get("tiles", [])
		var default_tiles := _runtime_default_tiles(actor, tile_list)
		if default_tiles.is_empty():
			default_tiles = [0]
		var state_arrays: Array = []
		var state_lens: Array = []
		for s in range(5):
			var st: String = ["IDLE", "WALK", "RUN", "JUMP", "FALL"][s]
			var state_tiles := _runtime_state_tiles(actor, st, tile_list)
			state_arrays.append(state_tiles)
			state_lens.append(state_tiles.size())
		code += _u16_array("actor%d_frames" % j, tile_list)
		code += _u16_array("actor%d_default" % j, default_tiles)
		for s in range(5):
			code += _u16_array("actor%d_state%d" % [j, s], state_arrays[s])
		code += "\n"
	code += "static const RetroActorDef runtime_actors[RUNTIME_ACTOR_COUNT] = {\n"
	for j in range(actors.size()):
		var item: Dictionary = actors[j]
		var actor: Dictionary = item.get("actor", {})
		var tile_list: Array = item.get("tiles", [])
		var default_tiles := _runtime_default_tiles(actor, tile_list)
		if default_tiles.is_empty():
			default_tiles = [0]
		var state_lens: Array = []
		for s in range(5):
			var st: String = ["IDLE", "WALK", "RUN", "JUMP", "FALL"][s]
			state_lens.append(_runtime_state_tiles(actor, st, tile_list).size())
		code += "\t{ %d, %d, %d, %d, %d, %d, %d, %d, actor%d_frames, actor%d_default, { %d, %d, %d, %d, %d }, { actor%d_state0, actor%d_state1, actor%d_state2, actor%d_state3, actor%d_state4 } },\n" % [
			int(item.get("x", 0)), int(item.get("y", 0)), int(item.get("w", 16)), int(item.get("h", 16)),
			int(item.get("size", 0)), 1 if bool(item.get("player", false)) else 0,
			tile_list.size(), default_tiles.size(), j, j,
			int(state_lens[0]), int(state_lens[1]), int(state_lens[2]), int(state_lens[3]), int(state_lens[4]),
			j, j, j, j, j]
	code += "};\n\n"
	if not widgets.is_empty():
		code += "typedef struct {\n    short x, y, w, h;\n    unsigned char kind;\n    unsigned char items;\n    unsigned char selected;\n} RetroWidget;\n\n"
		code += "static RetroWidget runtime_widgets[RUNTIME_WIDGET_COUNT] = {\n"
		for w in widgets:
			var kind := 1 if String(w.get("type", "")) == "ItemList" else (2 if String(w.get("type", "")) == "OptionButton" else 0)
			code += "\t{ %d, %d, %d, %d, %d, %d, %d },\n" % [
				int(w.get("x", 0)), int(w.get("y", 0)), int(w.get("w", 0)), int(w.get("h", 0)),
				kind, int(w.get("items", 0)), int(w.get("selected", 0))]
		code += "};\n\n"
	code += "typedef struct { short x, y, w, h; } RetroSolid;\n"
	code += "static const RetroSolid runtime_solids[RUNTIME_SOLID_COUNT] = {\n"
	for s in solids:
		code += "\t{ %d, %d, %d, %d },\n" % [int(s.get("x", 0)), int(s.get("y", 0)), int(s.get("w", 0)), int(s.get("h", 0))]
	code += "};\n\n"
	code += "static short actor_x[RUNTIME_ACTOR_COUNT];\n"
	code += "static short actor_y[RUNTIME_ACTOR_COUNT];\n"
	code += "static short actor_vx[RUNTIME_ACTOR_COUNT];\n"
	code += "static short actor_vy[RUNTIME_ACTOR_COUNT];\n"
	code += "static unsigned char actor_ground[RUNTIME_ACTOR_COUNT];\n"
	code += "static unsigned char actor_frame[RUNTIME_ACTOR_COUNT];\n"
	code += "static unsigned char actor_timer[RUNTIME_ACTOR_COUNT];\n"
	code += "static unsigned char actor_state[RUNTIME_ACTOR_COUNT];\n"
	code += "static unsigned char actor_facing[RUNTIME_ACTOR_COUNT];\n"
	code += "static unsigned char ui_focus = 0;\nstatic unsigned char ui_active = 0;\nstatic unsigned char ui_flash = 0;\n\n"
	code += "static unsigned char overlap(short ax, short ay, short aw, short ah, short bx, short by, short bw, short bh)\n{\n"
	code += "    return (unsigned char)(ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by);\n}\n\n"
	code += "void runtime_init(void)\n{\n    int i;\n    oamInitGfxSet((u8 *)runtime_tiles, RUNTIME_TILES_SIZE, (u8 *)runtime_pal, RUNTIME_PAL_SIZE, 0, 0x4000, OBJ_SIZE16_L32);\n"
	code += "    setPalette((u16 *)runtime_pal, 128, RUNTIME_PAL_SIZE);\n"
	code += "    for (i = 0; i < RUNTIME_ACTOR_COUNT; i++) {\n"
	code += "        actor_x[i] = runtime_actors[i].x;\n        actor_y[i] = runtime_actors[i].y;\n"
	code += "        actor_vx[i] = 0;\n        actor_vy[i] = 0;\n        actor_ground[i] = 0;\n"
	code += "        actor_frame[i] = 0;\n        actor_timer[i] = 0;\n        actor_state[i] = 0;\n        actor_facing[i] = 0;\n"
	code += "        oamSet(i * 4, actor_x[i], actor_y[i], 3, 0, 0, runtime_actors[i].frames[0], 0);\n"
	code += "        oamSetEx(i * 4, runtime_actors[i].size ? OBJ_LARGE : OBJ_SMALL, OBJ_SHOW);\n"
	code += "    }\n"
	if cursor_tile >= 0:
		code += "#if RUNTIME_CURSOR\n"
		code += "    oamSet(RUNTIME_CURSOR_OAM, 255, 240, 3, 0, 0, RUNTIME_CURSOR_TILE, 0);\n"
		code += "    oamSetEx(RUNTIME_CURSOR_OAM, OBJ_SMALL, OBJ_SHOW);\n"
		code += "#endif\n"
	code += "}\n\n"
	code += "static void update_anim(int i, unsigned char use_state)\n{\n"
	code += "    int s = -1;\n    int count = 0;\n    const unsigned short *list = 0;\n"
	code += "    if (use_state) {\n"
	code += "        if (!actor_ground[i]) s = actor_vy[i] < 0 ? 3 : 4;\n"
	code += "        else if (actor_vx[i] <= -2) s = 2;\n"
	code += "        else if (actor_vx[i] != 0) s = 1;\n"
	code += "        else s = 0;\n"
	code += "    }\n"
	code += "    if (s >= 0 && runtime_actors[i].state_len[s] > 0) {\n"
	code += "        count = runtime_actors[i].state_len[s]; list = runtime_actors[i].state_frames[s];\n"
	code += "    } else if (s >= 0) {\n        int k;\n        for (k = 0; k < 5; k++) {\n"
	code += "            if (runtime_actors[i].state_len[k] > 0) { count = runtime_actors[i].state_len[k]; list = runtime_actors[i].state_frames[k]; break; }\n"
	code += "        }\n        if (!list) { count = runtime_actors[i].default_count; list = runtime_actors[i].default_frames; }\n"
	code += "    } else { count = runtime_actors[i].default_count; list = runtime_actors[i].default_frames; }\n"
	code += "    if (!list || count <= 0) { count = runtime_actors[i].frame_count; list = runtime_actors[i].frames; }\n"
	code += "    if (actor_state[i] != (unsigned char)(s + 1)) { actor_state[i] = (unsigned char)(s + 1); actor_frame[i] = 0; actor_timer[i] = 0; }\n"
	code += "    actor_timer[i]++;\n    if (actor_timer[i] >= 8) { actor_timer[i] = 0; actor_frame[i]++; if (actor_frame[i] >= count) actor_frame[i] = 0; }\n"
	code += "    if (actor_frame[i] >= count) actor_frame[i] = 0;\n"
	code += "    oamSet(i * 4, actor_x[i], actor_y[i], 3, actor_facing[i], 0, list[actor_frame[i]], 0);\n}\n\n"
	code += "static void update_player(unsigned short pad, unsigned short down)\n{\n"
	code += "    int i = RUNTIME_PLAYER;\n    int s;\n    short vx = 0;\n"
	code += "    if (!ui_active) { if (pad & KEY_LEFT) vx = -2; if (pad & KEY_RIGHT) vx = 2; }\n"
	code += "    actor_vx[i] = vx;\n"
	code += "    if (vx < 0) actor_facing[i] = 1; else if (vx > 0) actor_facing[i] = 0;\n"
	code += "    if (!ui_active && (down & (KEY_A | KEY_B | KEY_UP)) && actor_ground[i]) { actor_vy[i] = -10; actor_ground[i] = 0; }\n"
	code += "    actor_x[i] = (short)(actor_x[i] + vx);\n"
	code += "    for (s = 0; s < RUNTIME_SOLID_COUNT; s++) {\n"
	code += "        if (overlap(actor_x[i], actor_y[i], runtime_actors[i].w, runtime_actors[i].h, runtime_solids[s].x, runtime_solids[s].y, runtime_solids[s].w, runtime_solids[s].h)) {\n"
	code += "            if (vx > 0) actor_x[i] = (short)(runtime_solids[s].x - runtime_actors[i].w);\n"
	code += "            else if (vx < 0) actor_x[i] = (short)(runtime_solids[s].x + runtime_solids[s].w);\n"
	code += "            actor_vx[i] = 0;\n        }\n    }\n"
	code += "    actor_vy[i] = (short)(actor_vy[i] + 1);\n    if (actor_vy[i] > 8) actor_vy[i] = 8;\n"
	code += "    actor_y[i] = (short)(actor_y[i] + actor_vy[i]);\n    actor_ground[i] = 0;\n"
	code += "    for (s = 0; s < RUNTIME_SOLID_COUNT; s++) {\n"
	code += "        if (overlap(actor_x[i], actor_y[i], runtime_actors[i].w, runtime_actors[i].h, runtime_solids[s].x, runtime_solids[s].y, runtime_solids[s].w, runtime_solids[s].h)) {\n"
	code += "            if (actor_vy[i] > 0) { actor_y[i] = (short)(runtime_solids[s].y - runtime_actors[i].h); actor_ground[i] = 1; }\n"
	code += "            else if (actor_vy[i] < 0) actor_y[i] = (short)(runtime_solids[s].y + runtime_solids[s].h);\n"
	code += "            actor_vy[i] = 0;\n        }\n    }\n"
	code += "    if (actor_x[i] < 0) actor_x[i] = 0;\n    if (actor_y[i] < 0) actor_y[i] = 0;\n"
	code += "    if (actor_x[i] > RUNTIME_WORLD_W - runtime_actors[i].w) actor_x[i] = (short)(RUNTIME_WORLD_W - runtime_actors[i].w);\n"
	code += "    if (actor_y[i] > RUNTIME_SCREEN_H - runtime_actors[i].h) actor_y[i] = (short)(RUNTIME_SCREEN_H - runtime_actors[i].h);\n}\n\n"
	code += "static void update_ui(unsigned short down)\n{\n"
	code += "#if RUNTIME_WIDGET_COUNT > 0\n"
	code += "    if (down & KEY_START) { ui_active = !ui_active; ui_flash = 0; }\n"
	code += "    if (ui_active) {\n"
	code += "        RetroWidget *w = &runtime_widgets[ui_focus];\n"
	code += "        if (down & KEY_UP) ui_focus = (unsigned char)((ui_focus + RUNTIME_WIDGET_COUNT - 1) % RUNTIME_WIDGET_COUNT);\n"
	code += "        if (down & KEY_DOWN) ui_focus = (unsigned char)((ui_focus + 1) % RUNTIME_WIDGET_COUNT);\n"
	code += "        w = &runtime_widgets[ui_focus];\n"
	code += "        if (w->items > 0) {\n"
	code += "            if (down & KEY_LEFT) w->selected = (unsigned char)((w->selected + w->items - 1) % w->items);\n"
	code += "            if (down & KEY_RIGHT) w->selected = (unsigned char)((w->selected + 1) % w->items);\n"
	code += "        }\n"
	code += "        if (down & (KEY_A | KEY_B)) ui_flash = 30;\n"
	code += "    }\n"
	code += "    if (ui_flash > 0) ui_flash--;\n"
	code += "#else\n    (void)down;\n#endif\n}\n\n"
	code += "static void update_cursor(void)\n{\n"
	code += "#if RUNTIME_CURSOR\n"
	code += "    short cx = 255;\n    short cy = 240;\n"
	code += "#if RUNTIME_WIDGET_COUNT > 0\n"
	code += "    if (ui_active) {\n"
	code += "        RetroWidget *w = &runtime_widgets[ui_focus];\n"
	code += "        cx = (short)(w->x - 18); if (cx < 0) cx = 0;\n"
	code += "        cy = (short)(w->y + (w->kind == 1 ? (3 + w->selected * 9) : ((w->h - 16) / 2)));\n"
	code += "        if (ui_flash > 0 && ((ui_flash >> 2) & 1)) { cx = 255; cy = 240; }\n"
	code += "    }\n"
	code += "#endif\n"
	code += "    oamSet(RUNTIME_CURSOR_OAM, cx, cy, 3, 0, 0, RUNTIME_CURSOR_TILE, 0);\n"
	code += "#endif\n}\n\n"
	code += "static void update_camera(void)\n{\n"
	code += "#if RUNTIME_WIDGET_COUNT == 0\n"
	code += "    short cx = 0, cy = 0;\n"
	code += "    if (RUNTIME_WORLD_W > RUNTIME_SCREEN_W) {\n"
	code += "        cx = (short)(actor_x[RUNTIME_PLAYER] + runtime_actors[RUNTIME_PLAYER].w / 2 - RUNTIME_SCREEN_W / 2);\n"
	code += "        if (cx < 0) cx = 0; if (cx > RUNTIME_WORLD_W - RUNTIME_SCREEN_W) cx = (short)(RUNTIME_WORLD_W - RUNTIME_SCREEN_W);\n"
	code += "    }\n"
	code += "    if (RUNTIME_WORLD_H > RUNTIME_SCREEN_H) {\n"
	code += "        cy = (short)(actor_y[RUNTIME_PLAYER] + runtime_actors[RUNTIME_PLAYER].h / 2 - RUNTIME_SCREEN_H / 2);\n"
	code += "        if (cy < 0) cy = 0; if (cy > RUNTIME_WORLD_H - RUNTIME_SCREEN_H) cy = (short)(RUNTIME_WORLD_H - RUNTIME_SCREEN_H);\n"
	code += "    }\n"
	code += "    bgSetScroll(0, (unsigned short)cx, (unsigned short)cy);\n"
	code += "#endif\n}\n\n"
	code += "void runtime_update(void)\n{\n"
	code += "    unsigned short pad = padsCurrent(0);\n    unsigned short down = padsDown(0);\n    int i;\n"
	code += "    update_ui(down);\n    update_player(pad, down);\n"
	code += "    for (i = 0; i < RUNTIME_ACTOR_COUNT; i++) update_anim(i, (unsigned char)(i == RUNTIME_PLAYER));\n"
	code += "    update_cursor();\n    update_camera();\n}\n"
	var source_path := dir.path_join("src/runtime.c")
	var header_path := dir.path_join("src/runtime.h")
	_write_text(source_path, code)
	var header := "#ifndef RETRO_RUNTIME_H\n#define RETRO_RUNTIME_H\n\n"
	header += "#define RETRO_RUNTIME_ACTORS %d\n#define RETRO_RUNTIME_WIDGETS %d\n\n" % [actors.size(), widgets.size()]
	header += "void runtime_init(void);\nvoid runtime_update(void);\n\n#endif\n"
	_write_text(header_path, header)
	return {"ok": true, "source": source_path, "header": header_path,
		"actors": actors.size(), "widgets": widgets.size(), "solids": solids.size(),
		"tiles": tiles.size() / 32, "cursor": cursor_tile >= 0,
		"stage_w": stage_size.x, "stage_h": stage_size.y}

static func _md_c_slug(value: String, fallback: String) -> String:
	var out := ""
	for c in value.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" else "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else fallback

static func _write_md_runtime(dir: String, runtime: Dictionary, stage: RetroStage) -> Dictionary:
	var prep := _prepare_runtime_assets(runtime)
	if prep.is_empty():
		return {"ok": false, "error": "no native sprite actors for the Mega Drive build"}
	var actors: Array = prep.get("actors", [])
	if actors.is_empty():
		return {"ok": false, "error": "no native sprite actors"}
	var palette: PackedColorArray = prep.get("palette", PackedColorArray())
	var res_dir := dir.path_join("res")
	DirAccess.make_dir_recursive_absolute(res_dir)
	var res_lines: Array = []
	var player_index := int(prep.get("player", 0))
	if player_index < 0:
		player_index = 0
	var stage_size: Vector2i = stage.get_map_size()
	var widgets: Array = runtime.get("widgets", [])
	var solids: Array = runtime.get("solids", [])
	if solids.is_empty():
		solids = [{"x": 0, "y": 208, "w": 320, "h": 16}]
	var sheet_rows: Array = []
	for j in range(actors.size()):
		var item: Dictionary = actors[j]
		var actor: Dictionary = item.get("actor", {})
		var states: Dictionary = actor.get("states", {})
		var rows: Array = []
		if not states.is_empty():
			var order: Array = []
			var current_state := String(actor.get("current_state", ""))
			if not current_state.is_empty() and states.has(current_state) and not Array(states[current_state]).is_empty():
				order.append(current_state)
			for st in ["IDLE", "WALK", "RUN", "JUMP", "FALL"]:
				if states.has(st) and not Array(states[st]).is_empty() and not order.has(st):
					order.append(st)
			for st in states.keys():
				if String(st) not in order and not Array(states[st]).is_empty():
					order.append(String(st))
			for st in order:
				rows.append({"state": String(st), "frames": Array(states[st])})
		if rows.is_empty():
			var all_frames: Array = []
			for f in range(int(actor.get("frames", []).size())):
				all_frames.append(f)
			rows.append({"state": "DEFAULT", "frames": all_frames})
		var cols := 1
		for row in rows:
			cols = maxi(cols, Array(row.get("frames", [])).size())
		var cell_w := int(item.get("w", 16))
		var cell_h := int(item.get("h", 16))
		var sheet := Image.create_empty(maxi(1, cols * cell_w), maxi(1, rows.size() * cell_h), false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0, 0, 0, 0))
		for row_index in range(rows.size()):
			var frames: Array = rows[row_index].get("frames", [])
			for col in range(cols):
				if col >= frames.size():
					continue
				var frame := _actor_frame_image(actor, int(frames[col]), Vector2i(cell_w, cell_h))
				if frame == null:
					continue
				sheet.blit_rect(frame, Rect2i(0, 0, frame.get_width(), frame.get_height()),
					Vector2i(col * cell_w, row_index * cell_h))
		var slug := "actor%d_%s" % [j, _md_c_slug(String(actor.get("name", "sprite")), "sprite")]
		var png := res_dir.path_join(slug + ".png")
		RetroGraphics.save_indexed_png(png, sheet, palette)
		var tw := maxi(1, int(ceil(float(cell_w) / 8.0)))
		var th := maxi(1, int(ceil(float(cell_h) / 8.0)))
		res_lines.append("SPRITE %s_sprite \"%s.png\" %d %d FAST 5" % [slug, slug, tw, th])
		var state_rows := [255, 255, 255, 255, 255]
		for row_index in range(rows.size()):
			var st := String(rows[row_index].get("state", "DEFAULT"))
			var standard := ["IDLE", "WALK", "RUN", "JUMP", "FALL"]
			var pos := standard.find(st)
			if pos >= 0:
				state_rows[pos] = row_index
		if state_rows[0] == 255:
			state_rows[0] = 0
		sheet_rows.append({"name": slug, "rows": rows.size(), "state_rows": state_rows,
			"w": cell_w, "h": cell_h})
	if int(prep.get("cursor_tile", -1)) >= 0:
		var cursor_rect: Rect2i = prep.get("cursor_rect", Rect2i())
		var atlas: Image = prep.get("image")
		if atlas != null and cursor_rect.size.x > 0:
			var cursor := atlas.get_region(cursor_rect)
			RetroGraphics.save_indexed_png(res_dir.path_join("retro_cursor.png"), cursor, palette)
			res_lines.append("SPRITE retro_cursor_sprite \"retro_cursor.png\" 2 2 FAST 0")
	_write_text(res_dir.path_join("sprites.res"), "\n".join(res_lines) + "\n")
	var code := "#include <genesis.h>\n#include \"assets.h\"\n#include \"sprites.h\"\n#include \"runtime.h\"\n\n"
	code += "#define RUNTIME_ACTOR_COUNT %d\n" % actors.size()
	code += "#define RUNTIME_WIDGET_COUNT %d\n" % widgets.size()
	code += "#define RUNTIME_SOLID_COUNT %d\n" % solids.size()
	code += "#define RUNTIME_PLAYER %d\n" % player_index
	var screen_w := 256 if stage_size.x <= 32 else 320
	code += "#define RUNTIME_SCREEN_W %d\n#define RUNTIME_SCREEN_H 224\n" % screen_w
	code += "#define RUNTIME_WORLD_W (GAME_MAP_W * 8)\n"
	code += "#define RUNTIME_WORLD_H (GAME_MAP_H * 8)\n"
	code += "#define RUNTIME_CURSOR %d\n" % (1 if int(prep.get("cursor_tile", -1)) >= 0 else 0)
	code += "\nstatic Sprite *actor_sprites[RUNTIME_ACTOR_COUNT];\n"
	code += "static short actor_x[RUNTIME_ACTOR_COUNT];\nstatic short actor_y[RUNTIME_ACTOR_COUNT];\n"
	code += "static short actor_vx[RUNTIME_ACTOR_COUNT];\nstatic short actor_vy[RUNTIME_ACTOR_COUNT];\n"
	code += "static unsigned char actor_ground[RUNTIME_ACTOR_COUNT];\n"
	code += "static unsigned char actor_facing[RUNTIME_ACTOR_COUNT];\n"
	code += "static unsigned char actor_row[RUNTIME_ACTOR_COUNT];\n"
	code += "static const short actor_w[RUNTIME_ACTOR_COUNT] = {"
	for j in range(actors.size()):
		code += "%d%s" % [int(actors[j].get("w", 16)), "," if j + 1 < actors.size() else ""]
	code += "};\nstatic const short actor_h[RUNTIME_ACTOR_COUNT] = {"
	for j in range(actors.size()):
		code += "%d%s" % [int(actors[j].get("h", 16)), "," if j + 1 < actors.size() else ""]
	code += "};\nstatic const unsigned char actor_rows[RUNTIME_ACTOR_COUNT] = {"
	for j in range(sheet_rows.size()):
		code += "%d%s" % [int(sheet_rows[j].get("rows", 1)), "," if j + 1 < sheet_rows.size() else ""]
	code += "};\nstatic const unsigned char actor_state_rows[RUNTIME_ACTOR_COUNT][5] = {\n"
	for row in sheet_rows:
		var sr: Array = row.get("state_rows", [0, 255, 255, 255, 255])
		code += "\t{ %d, %d, %d, %d, %d },\n" % [int(sr[0]), int(sr[1]), int(sr[2]), int(sr[3]), int(sr[4])]
	code += "};\n\n"
	if not widgets.is_empty():
		code += "typedef struct {\n    short x, y, w, h;\n    unsigned char kind;\n    unsigned char items;\n    unsigned char selected;\n} RetroWidget;\n\n"
		code += "static RetroWidget widgets[RUNTIME_WIDGET_COUNT] = {\n"
		for w in widgets:
			var kind := 1 if String(w.get("type", "")) == "ItemList" else (2 if String(w.get("type", "")) == "OptionButton" else 0)
			code += "\t{ %d, %d, %d, %d, %d, %d, %d },\n" % [
				int(w.get("x", 0)), int(w.get("y", 0)), int(w.get("w", 0)), int(w.get("h", 0)),
				kind, int(w.get("items", 0)), int(w.get("selected", 0))]
		code += "};\n\n"
	code += "typedef struct { short x, y, w, h; } RetroSolid;\n"
	code += "static const RetroSolid solids[RUNTIME_SOLID_COUNT] = {\n"
	for s in solids:
		code += "\t{ %d, %d, %d, %d },\n" % [int(s.get("x", 0)), int(s.get("y", 0)), int(s.get("w", 0)), int(s.get("h", 0))]
	code += "};\n\n"
	code += "static unsigned char ui_focus = 0;\nstatic unsigned char ui_active = 0;\nstatic unsigned char ui_flash = 0;\nstatic unsigned short joy_prev = 0;\n\n"
	code += "static unsigned char overlap(short ax, short ay, short aw, short ah, short bx, short by, short bw, short bh)\n{\n"
	code += "    return (unsigned char)(ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by);\n}\n\n"
	code += "void runtime_init(void)\n{\n    int i;\n    JOY_init();\n    SPR_init();\n"
	code += "    for (i = 0; i < RUNTIME_ACTOR_COUNT; i++) {\n"
	code += "        actor_x[i] = %s;\n" % "0"
	code += "        actor_y[i] = 0;\n"
	code += "    }\n"
	for j in range(actors.size()):
		var item: Dictionary = actors[j]
		code += "    actor_x[%d] = %d;\n    actor_y[%d] = %d;\n" % [j, int(item.get("x", 0)), j, int(item.get("y", 0))]
	code += "    for (i = 0; i < RUNTIME_ACTOR_COUNT; i++) {\n"
	code += "        actor_vx[i] = 0; actor_vy[i] = 0; actor_ground[i] = 0; actor_facing[i] = 0; actor_row[i] = 0;\n"
	code += "    }\n"
	for j in range(actors.size()):
		var slug := String(sheet_rows[j].get("name", "actor%d" % j))
		code += "    actor_sprites[%d] = SPR_addSprite(&%s_sprite, actor_x[%d], actor_y[%d], TILE_ATTR(PAL1, TRUE, FALSE, FALSE));\n" % [j, slug, j, j]
	code += "    PAL_setPalette(PAL1, %s_sprite.palette->data, DMA);\n" % String(sheet_rows[0].get("name", "actor0"))
	if int(prep.get("cursor_tile", -1)) >= 0:
		code += "    cursor = SPR_addSprite(&retro_cursor_sprite, 400, 240, TILE_ATTR(PAL1, TRUE, FALSE, FALSE));\n"
	code += "}\n\n"
	code += "static void update_player(unsigned short joy, unsigned short pressed)\n{\n"
	code += "    int i = RUNTIME_PLAYER;\n    int s;\n    short vx = 0;\n"
	code += "    if (!ui_active) { if (joy & BUTTON_LEFT) vx = -2; if (joy & BUTTON_RIGHT) vx = 2; }\n"
	code += "    actor_vx[i] = vx;\n"
	code += "    if (vx < 0) actor_facing[i] = 1; else if (vx > 0) actor_facing[i] = 0;\n"
	code += "    if (!ui_active && (pressed & (BUTTON_A | BUTTON_B | BUTTON_C | BUTTON_UP)) && actor_ground[i]) { actor_vy[i] = -10; actor_ground[i] = 0; }\n"
	code += "    actor_x[i] = (short)(actor_x[i] + vx);\n"
	code += "    for (s = 0; s < RUNTIME_SOLID_COUNT; s++) {\n"
	code += "        if (overlap(actor_x[i], actor_y[i], actor_w[i], actor_h[i], solids[s].x, solids[s].y, solids[s].w, solids[s].h)) {\n"
	code += "            if (vx > 0) actor_x[i] = (short)(solids[s].x - actor_w[i]);\n"
	code += "            else if (vx < 0) actor_x[i] = (short)(solids[s].x + solids[s].w);\n"
	code += "            actor_vx[i] = 0;\n        }\n    }\n"
	code += "    actor_vy[i] = (short)(actor_vy[i] + 1); if (actor_vy[i] > 8) actor_vy[i] = 8;\n"
	code += "    actor_y[i] = (short)(actor_y[i] + actor_vy[i]); actor_ground[i] = 0;\n"
	code += "    for (s = 0; s < RUNTIME_SOLID_COUNT; s++) {\n"
	code += "        if (overlap(actor_x[i], actor_y[i], actor_w[i], actor_h[i], solids[s].x, solids[s].y, solids[s].w, solids[s].h)) {\n"
	code += "            if (actor_vy[i] > 0) { actor_y[i] = (short)(solids[s].y - actor_h[i]); actor_ground[i] = 1; }\n"
	code += "            else if (actor_vy[i] < 0) actor_y[i] = (short)(solids[s].y + solids[s].h);\n"
	code += "            actor_vy[i] = 0;\n        }\n    }\n"
	code += "    if (actor_x[i] < 0) actor_x[i] = 0;\n    if (actor_y[i] < 0) actor_y[i] = 0;\n"
	code += "    if (actor_x[i] > RUNTIME_WORLD_W - actor_w[i]) actor_x[i] = (short)(RUNTIME_WORLD_W - actor_w[i]);\n"
	code += "    if (actor_y[i] > RUNTIME_SCREEN_H - actor_h[i]) actor_y[i] = (short)(RUNTIME_SCREEN_H - actor_h[i]);\n}\n\n"
	code += "static void update_ui(unsigned short pressed)\n{\n"
	code += "#if RUNTIME_WIDGET_COUNT > 0\n"
	code += "    if (pressed & BUTTON_START) { ui_active = !ui_active; ui_flash = 0; }\n"
	code += "    if (ui_active) {\n"
	code += "        if (pressed & BUTTON_UP) ui_focus = (unsigned char)((ui_focus + RUNTIME_WIDGET_COUNT - 1) % RUNTIME_WIDGET_COUNT);\n"
	code += "        if (pressed & BUTTON_DOWN) ui_focus = (unsigned char)((ui_focus + 1) % RUNTIME_WIDGET_COUNT);\n"
	code += "        if (widgets[ui_focus].items > 0) {\n"
	code += "            if (pressed & BUTTON_LEFT) widgets[ui_focus].selected = (unsigned char)((widgets[ui_focus].selected + widgets[ui_focus].items - 1) % widgets[ui_focus].items);\n"
	code += "            if (pressed & BUTTON_RIGHT) widgets[ui_focus].selected = (unsigned char)((widgets[ui_focus].selected + 1) % widgets[ui_focus].items);\n"
	code += "        }\n"
	code += "        if (pressed & (BUTTON_A | BUTTON_B)) ui_flash = 30;\n"
	code += "    }\n"
	code += "    if (ui_flash > 0) ui_flash--;\n"
	code += "#else\n    (void)pressed;\n#endif\n}\n\n"
	code += "static void update_cursor(void)\n{\n"
	code += "#if RUNTIME_CURSOR\n"
	code += "    short cx = 400;\n    short cy = 240;\n"
	code += "#if RUNTIME_WIDGET_COUNT > 0\n"
	code += "    if (ui_active) {\n"
	code += "        cx = (short)(widgets[ui_focus].x - 18); if (cx < 0) cx = 0;\n"
	code += "        cy = (short)(widgets[ui_focus].y + (widgets[ui_focus].kind == 1 ? (3 + widgets[ui_focus].selected * 9) : ((widgets[ui_focus].h - 16) / 2)));\n"
	code += "        if (ui_flash > 0 && ((ui_flash >> 2) & 1)) { cx = 400; cy = 240; }\n"
	code += "    }\n"
	code += "#endif\n"
	code += "    SPR_setPosition(cursor, cx, cy);\n"
	code += "#endif\n}\n\n"
	code += "static void update_anim(int i, unsigned char use_state)\n{\n"
	code += "    if (use_state) {\n        int s;\n"
	code += "        if (!actor_ground[i]) s = actor_vy[i] < 0 ? 3 : 4;\n"
	code += "        else if (actor_vx[i] <= -2) s = 2;\n"
	code += "        else if (actor_vx[i] != 0) s = 1;\n"
	code += "        else s = 0;\n"
	code += "        if (actor_state_rows[i][s] != 255 && actor_row[i] != actor_state_rows[i][s]) { actor_row[i] = actor_state_rows[i][s]; SPR_setAnim(actor_sprites[i], actor_row[i]); }\n"
	code += "        SPR_setHFlip(actor_sprites[i], actor_facing[i]);\n"
	code += "    } else if (actor_rows[i] > 1 && actor_row[i] != 0) { actor_row[i] = 0; SPR_setAnim(actor_sprites[i], 0); }\n"
	code += "    SPR_setPosition(actor_sprites[i], actor_x[i], actor_y[i]);\n}\n\n"
	code += "static void update_camera(void)\n{\n"
	code += "#if RUNTIME_WIDGET_COUNT == 0\n"
	code += "    short cx = 0, cy = 0;\n"
	code += "    if (RUNTIME_WORLD_W > RUNTIME_SCREEN_W) {\n"
	code += "        cx = (short)(actor_x[RUNTIME_PLAYER] + actor_w[RUNTIME_PLAYER] / 2 - RUNTIME_SCREEN_W / 2);\n"
	code += "        if (cx < 0) cx = 0; if (cx > RUNTIME_WORLD_W - RUNTIME_SCREEN_W) cx = (short)(RUNTIME_WORLD_W - RUNTIME_SCREEN_W);\n"
	code += "    }\n"
	code += "    if (RUNTIME_WORLD_H > RUNTIME_SCREEN_H) {\n"
	code += "        cy = (short)(actor_y[RUNTIME_PLAYER] + actor_h[RUNTIME_PLAYER] / 2 - RUNTIME_SCREEN_H / 2);\n"
	code += "        if (cy < 0) cy = 0; if (cy > RUNTIME_WORLD_H - RUNTIME_SCREEN_H) cy = (short)(RUNTIME_WORLD_H - RUNTIME_SCREEN_H);\n"
	code += "    }\n"
	code += "    VDP_setHorizontalScroll(BG_A, cx);\n    VDP_setVerticalScroll(BG_A, (short)-cy);\n"
	code += "#endif\n}\n\n"
	code += "void runtime_update(void)\n{\n"
	code += "    unsigned short joy = JOY_readJoypad(JOY_1);\n    unsigned short pressed = (unsigned short)(joy & ~joy_prev);\n    int i;\n"
	code += "    joy_prev = joy;\n    update_ui(pressed);\n    update_player(joy, pressed);\n"
	code += "    for (i = 0; i < RUNTIME_ACTOR_COUNT; i++) update_anim(i, (unsigned char)(i == RUNTIME_PLAYER));\n"
	code += "    update_cursor();\n    update_camera();\n    SPR_update();\n}\n"
	if int(prep.get("cursor_tile", -1)) >= 0:
		code = code.replace("static unsigned short joy_prev = 0;\n", "static unsigned short joy_prev = 0;\nstatic Sprite *cursor = NULL;\n")
	var source_path := dir.path_join("src/runtime.c")
	var header_path := dir.path_join("src/runtime.h")
	_write_text(source_path, code)
	var header := "#ifndef RETRO_RUNTIME_H\n#define RETRO_RUNTIME_H\n\n"
	header += "#define RETRO_RUNTIME_ACTORS %d\n#define RETRO_RUNTIME_WIDGETS %d\n\n" % [actors.size(), widgets.size()]
	header += "void runtime_init(void);\nvoid runtime_update(void);\n\n#endif\n"
	_write_text(header_path, header)
	return {"ok": true, "source": source_path, "header": header_path,
		"actors": actors.size(), "widgets": widgets.size(), "solids": solids.size(),
		"tiles": 0, "cursor": int(prep.get("cursor_tile", -1)) >= 0,
		"stage_w": stage_size.x, "stage_h": stage_size.y}


static func _write_snes_main(path: String, stage: RetroStage, splash: RetroStage, include_splash: bool, audio: Dictionary, rom: Dictionary = {}, player: Dictionary = {}, runtime: Dictionary = {}) -> void:
	var has_runtime := bool(runtime.get("ok", false)) and int(runtime.get("actors", 0)) > 0
	var profile := ExportProfiles.for_target("snes")
	var fade_frames := int(profile.get("splash_fade_frames_per_level", 2))
	var hold_frames := int(profile.get("splash_hold_frames", 120))
	var bgm: Dictionary = audio.get("bgm", {})
	var sfx_list: Array = audio.get("sfx", [])
	var has_bgm := not bgm.is_empty()
	var module_name := ""
	var bank_symbol := "SOUNDBANK__"
	if has_bgm:
		module_name = String(bgm.get("soundbank", {}).get("module", "MOD_" + String(bgm.get("name", "bgm")).to_upper()))
		bank_symbol = String(bgm.get("soundbank", {}).get("bank_symbol", "SOUNDBANK__"))
	var code := "#include <snes.h>\n#include \"assets.h\"\n"
	if has_runtime:
		code += "#include \"runtime.h\"\n"
	if not player.is_empty():
		code += "#include \"player.h\"\n"
	if bool(rom.get("msu1", false)):
		code += "#include \"msu1.h\"\n"
	if has_bgm:
		code += "#include \"soundbank.h\"\nextern unsigned char %s;\n" % bank_symbol
	code += "\n"
	code += "static void loadStage(const unsigned char *tiles, const unsigned char *pal, const unsigned char *map,\n"
	code += "        unsigned int tilesSize, unsigned int palSize, unsigned int mapW, unsigned int mapH, unsigned int mapStride, unsigned int mapBytes, u16 mapSize, u8 enable)\n{\n"
	code += "    (void)mapW; (void)mapH; (void)mapStride;\n"
	code += "    setScreenOff();\n"
	code += "    // PVSnesLib's bgInitTileSet() takes non-const pointers even though it\n"
	code += "    // only reads the ROM data; the explicit cast keeps the generated\n"
	code += "    // starter project warning-free with 816-tcc.\n"
	code += "    bgInitTileSet(0, (u8 *)tiles, (u8 *)pal, 0, (u16)tilesSize, (u16)palSize, BG_16COLORS, 0x2000);\n"
	code += "    bgSetMapPtr(0, 0x0000, mapSize);\n"
	code += "    bgSetGfxPtr(0, 0x2000);\n"
	code += "    // The map is padded to the BG allocation (32x32 or 64x32) at build\n"
	code += "    // time, so a single DMA upload is enough. This keeps the transition\n"
	code += "    // from the splash to the game to a single frame.\n"
	code += "    dmaCopyVram((u8 *)map, 0x0000, (u16)mapBytes);\n"
	code += "    WaitForVBlank();\n"
	code += "    bgSetEnable(0);\n"
	code += "    REG_TM = 0x01; /* BG1 only; disable uninitialised OAM/BG2/BG3. */\n"
	code += "    bgSetScroll(0, 0, 0);\n"
	code += "    // Only enable the display after CGRAM/VRAM DMA has completed. The\n"
	code += "    // splash loads with enable=0 so it can write a black palette first.\n"
	code += "    if (enable) setScreenOn();\n}\n\n"
	code += "#if RETRO_SPLASH\n"
	code += "static void showSplash(void)\n{\n    u16 hold;\n"
	code += "    // Load with the display disabled. The hardware brightness fade below\n"
	code += "    // starts from forced blank, so no full-brightness/white frame is ever\n"
	code += "    // shown. setFadeEffectEx() updates REG_INIDISP once per VBlank, which\n"
	code += "    // avoids the tearing caused by writing CGRAM during active display.\n"
	code += "    loadStage(splash_tiles, splash_pal, splash_map, splash_tiles_size, splash_pal_size, SPLASH_MAP_W, SPLASH_MAP_H, SPLASH_MAP_STRIDE, SPLASH_MAP_BYTES, SPLASH_BG_SIZE, 0);\n"
	code += "    bgSetScroll(0, (u16)(-((256 - SPLASH_MAP_W * 8) / 2)), (u16)(-((224 - SPLASH_MAP_H * 8) / 2)));\n"
	code += "    setFadeEffectEx(FADE_IN, %d);\n" % fade_frames
	code += "    for (hold = 0; hold < %d; hold++) WaitForVBlank();\n" % hold_frames
	code += "    setFadeEffectEx(FADE_OUT, %d);\n" % fade_frames
	code += "    setScreenOff();\n}\n"
	code += "#endif\n\n"
	var sfx_brr_arrays: Array = []
	var sfx_sizes := {}
	var sfx_entries: Array = []
	var region := 1
	for i in range(sfx_list.size()):
		var sfx: Dictionary = sfx_list[i]
		var safe := _safe_audio_name(String(sfx.get("name", "sfx%d" % i)))
		var brr_path := String(sfx.get("files", {}).get("brr", ""))
		if brr_path.is_empty() or not FileAccess.file_exists(brr_path):
			continue
		var f := FileAccess.open(brr_path, FileAccess.READ)
		var data := f.get_buffer(f.get_length())
		f.close()
		sfx_brr_arrays.append(safe)
		sfx_sizes[safe] = data.size()
		sfx_entries.append({"name": "sfx_" + safe + "_brr", "file": "sfx_" + safe + "_brr.bin", "data": data})
		code += "extern const unsigned char sfx_%s_brr[];\n" % safe
		region = maxi(region, int((data.size() + 255) / 256) + 2)
	if not sfx_entries.is_empty():
		_write_snes_asm_blobs(path.get_base_dir(), sfx_entries, rom, "sfx_data.asm")
		code += "\n"
	if not sfx_brr_arrays.is_empty():
		code += "static brrsamples sfx_table[%d];\n\n" % sfx_brr_arrays.size()
	if not player.is_empty():
		var ow := int(player.get("w", 16))
		var oh := int(player.get("h", 16))
		var oam := "OBJ_SIZE16_L32" if ow <= 16 and oh <= 16 else "OBJ_SIZE32_L64"
		code += "static s16 player_x = (s16)((256 - PLAYER_W) / 2);\n"
		code += "static s16 player_y = (s16)((224 - PLAYER_H) / 2);\n\n"
		code += "static void initPlayer(void)\n{\n"
		code += "    oamInitGfxSet((u8 *)player_tiles, PLAYER_TILES_SIZE, (u8 *)player_pal, PLAYER_PAL_SIZE, 0, 0x6000, %s);\n" % oam
		code += "    /* Keep the player palette in the OBJ palette area (CGRAM 128). */\n"
		code += "    setPalette((u16 *)player_pal, 128, PLAYER_PAL_SIZE);\n"
		code += "    oamSet(0, player_x, player_y, 3, 0, 0, 0, 0);\n"
		code += "    oamSetEx(0, OBJ_SMALL, OBJ_SHOW);\n}\n\n"
		code += "static void updatePlayer(void)\n{\n"
		code += "    u16 pad = padsCurrent(0);\n"
		code += "    if (pad & KEY_LEFT) player_x -= 2;\n"
		code += "    if (pad & KEY_RIGHT) player_x += 2;\n"
		code += "    if (pad & KEY_UP) player_y -= 2;\n"
		code += "    if (pad & KEY_DOWN) player_y += 2;\n"
		code += "    if (player_x < 0) player_x = 0;\n"
		code += "    if (player_y < 0) player_y = 0;\n"
		code += "    if (player_x > 256 - PLAYER_W) player_x = 256 - PLAYER_W;\n"
		code += "    if (player_y > 224 - PLAYER_H) player_y = 224 - PLAYER_H;\n"
		code += "    oamSet(0, player_x, player_y, 3, 0, 0, 0, 0);\n}\n\n"
	code += "int main(void)\n{\n    consoleInit();\n    setMode(BG_MODE1, 0);\n"
	code += "    // Show BG1 only; uninitialised OAM/BG2/BG3 would otherwise draw stripes.\n"
	code += "    REG_TM = 0x01; REG_TS = 0x00;\n"
	code += "#if RETRO_SPLASH\n    showSplash();\n#endif\n"
	if has_runtime:
		# Prepare the background and all sprite actors while the display is in
		# forced blank. loadStage() leaves BG1-only enabled; restore OBJ after
		# runtime_init() and only then turn the screen on.
		code += "    loadStage(game_tiles, game_pal, game_map, game_tiles_size, game_pal_size, GAME_MAP_W, GAME_MAP_H, GAME_MAP_STRIDE, GAME_MAP_BYTES, GAME_BG_SIZE, 0);\n"
		code += "    runtime_init();\n"
		code += "    REG_TM = 0x11; /* BG1 + OBJ */\n"
		code += "    setScreenOn();\n"
	elif player.is_empty():
		code += "    loadStage(game_tiles, game_pal, game_map, game_tiles_size, game_pal_size, GAME_MAP_W, GAME_MAP_H, GAME_MAP_STRIDE, GAME_MAP_BYTES, GAME_BG_SIZE, 1);\n"
	else:
		# Prepare the background and the sprite while the display is in forced
		# blank. loadStage() leaves BG1-only enabled; restore the OBJ layer
		# after initPlayer() and only then turn the screen on. Writing VRAM
		# while the display is active would drop the sprite tile upload.
		code += "    loadStage(game_tiles, game_pal, game_map, game_tiles_size, game_pal_size, GAME_MAP_W, GAME_MAP_H, GAME_MAP_STRIDE, GAME_MAP_BYTES, GAME_BG_SIZE, 0);\n"
		code += "    initPlayer();\n"
		code += "    REG_TM = 0x11; /* BG1 + OBJ */\n"
		code += "    setScreenOn();\n"
	if bool(rom.get("msu1", false)):
		if not has_bgm:
			code += "#if RETRO_MSU1\n"
			code += "    /* MSU-1 companion enabled: play track 1 if the PCM track exists. */\n"
			code += "    if (msu1_present()) { msu1_set_volume(0xFF); msu1_play(1, 1); }\n"
			code += "#endif\n"
		else:
			code += "#if RETRO_MSU1\n"
			code += "    /* MSU-1 track 1 is available; SPC BGM is used by default. */\n"
			code += "#endif\n"
	if has_bgm or not sfx_brr_arrays.is_empty():
		code += "    spcBoot();\n"
		if has_bgm:
			code += "    spcSetBank((u8 *)&%s);\n" % bank_symbol
			code += "    spcLoad(%s);\n" % module_name
		for i in range(sfx_brr_arrays.size()):
			var sfx_safe := String(sfx_brr_arrays[i])
			code += "    spcSetSoundEntry(15, 8, 6, %d, (u8 *)sfx_%s_brr, &sfx_table[%d]);\n" % [
				int(sfx_sizes.get(sfx_safe, 0)), sfx_safe, i]
		if not sfx_brr_arrays.is_empty():
			code += "    spcSetSoundTableEntry(&sfx_table[0]);\n"
			code += "    spcAllocateSoundRegion(%d);\n" % region
		code += "    spcFlush();\n"
		if has_bgm:
			code += "    spcPlay(0);\n"
	if not sfx_brr_arrays.is_empty() or has_bgm:
		var player_step := "runtime_update(); " if has_runtime else ("updatePlayer(); " if not player.is_empty() else "")
		code += "    { u16 sfx_timer = 0; while (1) { " + player_step + "spcProcess(); if (++sfx_timer >= 120) { sfx_timer = 0;\n"
		if not sfx_brr_arrays.is_empty():
			code += "        spcPlaySound(0);\n"
		code += "    } WaitForVBlank(); } }\n"
	else:
		if has_runtime:
			code += "    while (1) { runtime_update(); WaitForVBlank(); }\n"
		elif player.is_empty():
			code += "    while (1) WaitForVBlank();\n"
		else:
			code += "    while (1) { updatePlayer(); WaitForVBlank(); }\n"
	code += "    return 0;\n}\n"
	_write_text(path, code)

static func _write_md_main(path: String, stage: RetroStage, splash: RetroStage, include_splash: bool, audio: Dictionary, player: Dictionary = {}, runtime: Dictionary = {}) -> void:
	var has_runtime := bool(runtime.get("ok", false)) and int(runtime.get("actors", 0)) > 0
	var profile := ExportProfiles.for_target("megadrive")
	var fade_steps := int(profile.get("splash_fade_steps", 15))
	var hold_frames := int(profile.get("splash_hold_frames", 120))
	var bits: Dictionary = profile.get("splash_palette_bits", {})
	var rshift := int(bits.get("r", [1, 7])[0])
	var rmask := int(bits.get("r", [1, 7])[1])
	var gshift := int(bits.get("g", [5, 7])[0])
	var gmask := int(bits.get("g", [5, 7])[1])
	var bshift := int(bits.get("b", [9, 7])[0])
	var bmask := int(bits.get("b", [9, 7])[1])
	var bgm: Dictionary = audio.get("bgm", {})
	var sfx_list: Array = audio.get("sfx", [])
	var has_audio := not bgm.is_empty() or not sfx_list.is_empty()
	var code := "#include <genesis.h>\n#include \"assets.h\"\n"
	if has_runtime:
		code += "#include \"runtime.h\"\n"
	if not player.is_empty():
		code += "#include \"player.h\"\n"
	if has_audio:
		code += "#include \"audio.h\"\n"
	code += "\n"
	code += "static void loadStage(const unsigned char *tiles, unsigned short tileCount, const unsigned short *pal, const unsigned short *map,\n"
	code += "        unsigned short mapW, unsigned short mapH)\n{\n"
	code += "    VDP_loadTileData((const u32 *)tiles, 0, tileCount, DMA);\n"
	code += "    PAL_setColors(0, (const u16 *)pal, 16, DMA);\n"
	code += "    VDP_clearPlane(BG_A, TRUE);\n"
	code += "    VDP_setTileMapDataRect(BG_A, (const u16 *)map, 0, 0, mapW, mapH, mapW, DMA);\n"
	code += "    VDP_setHorizontalScroll(BG_A, 0);\n    VDP_setVerticalScroll(BG_A, 0);\n}\n\n"
	code += "#if RETRO_SPLASH\n"
	code += "static void fadeSplash(u8 level)\n{\n    u16 i;\n    for (i = 0; i < 16; i++) {\n"
	code += "        u16 c = (u16)splash_pal[i];\n"
	code += "        u16 r = (u16)((((c >> %d) & %d) * level) / %d);\n" % [rshift, rmask, fade_steps]
	code += "        u16 g = (u16)((((c >> %d) & %d) * level) / %d);\n" % [gshift, gmask, fade_steps]
	code += "        u16 b = (u16)((((c >> %d) & %d) * level) / %d);\n" % [bshift, bmask, fade_steps]
	code += "        PAL_setColor(i, (u16)((r << %d) | (g << %d) | (b << %d)));\n    }\n}\n\n" % [rshift, gshift, bshift]
	code += "static void showSplash(void)\n{\n    u8 level; u16 hold;\n"
	code += "    loadStage(splash_tiles, SPLASH_TILE_COUNT, splash_pal, splash_map, SPLASH_MAP_W, SPLASH_MAP_H);\n"
	code += "    SYS_doVBlankProcess();\n"
	code += "    VDP_setHorizontalScroll(BG_A, (s16)(((GAME_MAP_W * 8 <= 256 ? 256 : 320) - SPLASH_MAP_W * 8) / 2));\n"
	code += "    // On Mega Drive a positive vertical scroll moves the plane up, so the\n"
	code += "    // centering offset must be negative.\n"
	code += "    VDP_setVerticalScroll(BG_A, (s16)(-((224 - SPLASH_MAP_H * 8) / 2)));\n"
	code += "    for (level = 0; level <= %d; level++) { fadeSplash(level); SYS_doVBlankProcess(); }\n" % fade_steps
	code += "    for (hold = 0; hold < %d; hold++) SYS_doVBlankProcess();\n" % hold_frames
	code += "    for (level = %d; level > 0; level--) { fadeSplash(level); SYS_doVBlankProcess(); }\n" % fade_steps
	code += "    fadeSplash(0); PAL_setColor(0, 0x0000); SYS_doVBlankProcess();\n}\n"
	code += "#endif\n\n"
	if not player.is_empty():
		var ow := int(player.get("w", 16))
		var oh := int(player.get("h", 16))
		code += "static Sprite *player_spr = NULL;\n"
		code += "static s16 player_x = (s16)((320 - %d) / 2);\n" % ow
		code += "static s16 player_y = (s16)((224 - %d) / 2);\n\n" % oh
		code += "static void initPlayer(void)\n{\n"
		code += "    player_spr = SPR_addSprite(&player_sprite, player_x, player_y, TILE_ATTR(PAL1, TRUE, FALSE, FALSE));\n"
		code += "    PAL_setPalette(PAL1, player_sprite.palette->data, DMA);\n}\n\n"
		code += "static void updatePlayer(void)\n{\n"
		code += "    u16 joy = JOY_readJoypad(JOY_1);\n"
		code += "    if (joy & BUTTON_LEFT) player_x -= 2;\n"
		code += "    if (joy & BUTTON_RIGHT) player_x += 2;\n"
		code += "    if (joy & BUTTON_UP) player_y -= 2;\n"
		code += "    if (joy & BUTTON_DOWN) player_y += 2;\n"
		code += "    if (player_x < 0) player_x = 0;\n"
		code += "    if (player_y < 0) player_y = 0;\n"
		code += "    if (player_x > 320 - %d) player_x = 320 - %d;\n" % [ow, ow]
		code += "    if (player_y > 224 - %d) player_y = 224 - %d;\n" % [oh, oh]
		code += "    SPR_setPosition(player_spr, player_x, player_y);\n"
		code += "    SPR_update();\n}\n\n"
	code += "int main(bool hard)\n{\n    (void)hard;\n"
	if not player.is_empty():
		code += "    JOY_init();\n    SPR_init();\n"
	code += "#if GAME_MAP_W * 8 <= 256\n    VDP_setScreenWidth256();\n#else\n    VDP_setScreenWidth320();\n#endif\n"
	code += "    VDP_setPlaneSize(64, 32, TRUE);\n    VDP_setBackgroundColor(0);\n"
	code += "#if RETRO_SPLASH\n    showSplash();\n#endif\n"
	code += "    loadStage(game_tiles, GAME_TILE_COUNT, game_pal, game_map, GAME_MAP_W, GAME_MAP_H);\n"
	if has_runtime:
		code += "    runtime_init();\n"
	elif not player.is_empty():
		code += "    initPlayer();\n"
	if has_audio:
		var bgm_name := _safe_audio_name(String(bgm.get("name", "bgm"))) if not bgm.is_empty() else ""
		var bgm_vgm := not bgm.is_empty() and not String(bgm.get("files", {}).get("vgm", "")).is_empty()
		var bgm_wav := not bgm.is_empty() and not String(bgm.get("files", {}).get("wav", "")).is_empty()
		if bgm_vgm:
			code += "    XGM2_play(%s);\n" % bgm_name
		elif bgm_wav:
			code += "    XGM2_loadDriver(TRUE);\n"
			code += "    XGM2_playPCMEx(%s, sizeof(%s), SOUND_PCM_CH1, 7, FALSE, TRUE);\n" % [bgm_name, bgm_name]
		else:
			code += "    XGM2_loadDriver(TRUE);\n"
		if not sfx_list.is_empty():
			var sfx_name := _safe_audio_name(String(sfx_list[0].get("name", "sfx")))
			var player_step := "runtime_update(); " if has_runtime else ("updatePlayer(); " if not player.is_empty() else "")
			code += "    { u16 sfx_timer = 0; while (TRUE) { " + player_step + "SYS_doVBlankProcess(); if (++sfx_timer >= 120) { sfx_timer = 0; XGM2_playPCM(%s, sizeof(%s), SOUND_PCM_CH2); } } }\n" % [sfx_name, sfx_name]
		else:
			if has_runtime:
				code += "    while (TRUE) { runtime_update(); SYS_doVBlankProcess(); }\n"
			elif player.is_empty():
				code += "    while (TRUE) SYS_doVBlankProcess();\n"
			else:
				code += "    while (TRUE) { updatePlayer(); SYS_doVBlankProcess(); }\n"
	else:
		if has_runtime:
			code += "    while (TRUE) { runtime_update(); SYS_doVBlankProcess(); }\n"
		elif player.is_empty():
			code += "    while (TRUE) SYS_doVBlankProcess();\n"
		else:
			code += "    while (TRUE) { updatePlayer(); SYS_doVBlankProcess(); }\n"
	code += "    return 0;\n}\n"
	_write_text(path, code)

static func estimate_md_payload(mode: String, source: RetroProject, include_splash := false) -> Dictionary:
	if target_for_mode(mode) != "megadrive" or source == null:
		return {"ok": false, "bytes": 0, "error": "not a Mega Drive source project"}
	var stage := _find_stage(source, "megadrive", "")
	if stage == null:
		return {"ok": false, "bytes": 0, "error": "no stage/image asset available for conversion"}
	var bridge := RetroNativeBridge.new()
	stage = _retarget_stage(stage, "megadrive")
	if stage.get_tileset() == null or stage.get_palette().is_empty():
		return {"ok": false, "bytes": 0, "error": "source stage has no tileset/palette"}
	var bytes := _estimate_md_rom_bytes(stage, null, {"converted": []})
	for asset in _find_audio(source):
		if typeof(asset) != TYPE_DICTIONARY:
			continue
		var path := String(asset.get("source", asset.get("path", "")))
		if not path.is_empty() and FileAccess.file_exists(path):
			bytes += FileAccess.get_size(path)
	if include_splash:
		bytes += 0x8000
	return {"ok": true, "bytes": maxi(bytes, 0x20000)}

static func _estimate_md_rom_bytes(stage: RetroStage, splash: RetroStage, audio: Dictionary) -> int:
	var total := 0x10000
	for item in [stage, splash]:
		if item == null:
			continue
		var data := _stage_data(item, "megadrive")
		total += PackedByteArray(data.get("tiles", PackedByteArray())).size()
		total += PackedByteArray(data.get("pal", PackedByteArray())).size()
		total += PackedByteArray(data.get("map", PackedByteArray())).size()
	for converted in audio.get("converted", []):
		if typeof(converted) != TYPE_DICTIONARY:
			continue
		var files: Dictionary = converted.get("files", {})
		for value in files.values():
			if value is String and FileAccess.file_exists(value):
				total += FileAccess.get_size(value)
	return maxi(total, 0x20000)

static func estimate_snes_payload(mode: String, source: RetroProject, include_splash := false) -> Dictionary:
	if target_for_mode(mode) != "snes" or source == null:
		return {"ok": false, "bytes": 0, "error": "not a SNES source project"}
	var stage := _find_stage(source, "snes", "")
	if stage == null:
		return {"ok": false, "bytes": 0, "error": "no stage/image asset available for conversion"}
	var bridge := RetroNativeBridge.new()
	stage = _retarget_stage(stage, "snes")
	if stage.get_tileset() == null or stage.get_palette().is_empty():
		return {"ok": false, "bytes": 0, "error": "source stage has no tileset/palette"}
	var bytes := _estimate_snes_rom_bytes(stage, null, {"converted": []})
	for asset in _find_audio(source):
		if typeof(asset) != TYPE_DICTIONARY:
			continue
		var path := String(asset.get("source", asset.get("path", "")))
		if not path.is_empty() and FileAccess.file_exists(path):
			bytes += FileAccess.get_size(path)
	if include_splash:
		# The Godot logo is quantized to at most 1024 tiles plus map/palette.
		bytes += 0x8000
	return {"ok": true, "bytes": maxi(bytes, 0x40000)}

static func _estimate_snes_rom_bytes(stage: RetroStage, splash: RetroStage, audio: Dictionary) -> int:
	var total := 0x20000
	for item in [stage, splash]:
		if item == null:
			continue
		var data := _stage_data(item, "snes")
		total += PackedByteArray(data.get("tiles", PackedByteArray())).size()
		total += PackedByteArray(data.get("pal", PackedByteArray())).size()
		total += PackedByteArray(data.get("map", PackedByteArray())).size()
	for converted in audio.get("converted", []):
		if typeof(converted) != TYPE_DICTIONARY:
			continue
		var files: Dictionary = converted.get("files", {})
		for value in files.values():
			if value is String and FileAccess.file_exists(value):
				total += FileAccess.get_size(value)
	return maxi(total, 0x40000)

static func _write_snes_custom_header(dir: String, name: String, rom: Dictionary) -> void:
	var title := name.to_upper().substr(0, 21).rpad(21, " ")
	var mapping := String(rom.get("mapping", "hirom"))
	var fast := bool(rom.get("fast", false))
	var mode := "EXHIROM" if mapping == "exhirom" else "HIROM"
	var speed := "FASTROM" if fast else "SLOWROM"
	var base := "$C0" if fast else "$40"
	var banks := int(rom.get("banks", 128))
	var text := "; Generated by Godot Retro Engine — %s %s\n" % [mode, speed]
	text += ".MEMORYMAP\n"
	text += "  SLOTSIZE $10000\n  DEFAULTSLOT 0\n  SLOT 0 $0000\n"
	text += "  SLOT 1 $0 $2000\n  SLOT 2 $2000 $E000\n  SLOT 3 $0 $10000\n  SLOT 4 $6000\n.ENDME\n"
	text += ".ROMBANKMAP\n  BANKSTOTAL %d\n  BANKSIZE $10000\n  BANKS %d\n.ENDRO\n" % [banks, banks]
	text += ".%s\n.%s\n" % [mode, speed]
	text += ".SNESHEADER\n  ID \"SNES\"\n  NAME \"%s\"\n  %s\n  %s\n" % [title, speed, mode]
	text += "  CARTRIDGETYPE $%02X\n  ROMSIZE $%02X\n  SRAMSIZE $%02X\n" % [
		int(rom.get("cart_type", 0)), int(rom.get("size_code", 0x0D)), int(rom.get("sram_code", 0))]
	text += "  COUNTRY $01\n  LICENSEECODE $00\n  VERSION $00\n.ENDSNES\n"
	text += ".SNESNATIVEVECTOR\n  COP EmptyHandler\n  BRK EmptyHandler\n  ABORT EmptyHandler\n"
	text += "  NMI VBlank\n  IRQ EmptyHandler\n.ENDNATIVEVECTOR\n"
	text += ".SNESEMUVECTOR\n  COP EmptyHandler\n  ABORT EmptyHandler\n  NMI EmptyHandler\n"
	text += "  RESET tcc__start\n  IRQBRK EmptyHandler\n.ENDEMUVECTOR\n"
	text += ".BASE %s\n" % base
	_write_text(dir.path_join("hdr.asm"), text)

static func _write_msu1_support(dir: String, name: String) -> void:
	var header := """#ifndef RETRO_MSU1_H
#define RETRO_MSU1_H
#include <snes.h>

/* MSU-1 registers (banks $00-$3F / $80-$BF, $2000-$2007). */
#define MSU_STATUS  (*(volatile u8 *)0x2000)
#define MSU_READ    (*(volatile u8 *)0x2001)
#define MSU_ID0     (*(volatile u8 *)0x2002)
#define MSU_ID1     (*(volatile u8 *)0x2003)
#define MSU_ID2     (*(volatile u8 *)0x2004)
#define MSU_ID3     (*(volatile u8 *)0x2005)
#define MSU_ID4     (*(volatile u8 *)0x2006)
#define MSU_ID5     (*(volatile u8 *)0x2007)
#define MSU_SEEK0   (*(volatile u8 *)0x2000)
#define MSU_SEEK1   (*(volatile u8 *)0x2001)
#define MSU_SEEK2   (*(volatile u8 *)0x2002)
#define MSU_SEEK3   (*(volatile u8 *)0x2003)
#define MSU_TRACK_L (*(volatile u8 *)0x2004)
#define MSU_TRACK_H (*(volatile u8 *)0x2005)
#define MSU_VOLUME  (*(volatile u8 *)0x2006)
#define MSU_CONTROL (*(volatile u8 *)0x2007)

static inline u8 msu1_present(void)
{
    return (MSU_ID0 == 'S' && MSU_ID1 == '-' && MSU_ID2 == 'M'
        && MSU_ID3 == 'S' && MSU_ID4 == 'U' && MSU_ID5 == '1');
}

static inline void msu1_set_volume(u8 volume)
{
    MSU_VOLUME = volume;
}

static inline void msu1_play(u16 track, u8 loop)
{
    MSU_TRACK_L = (u8)(track & 0xFF);
    MSU_TRACK_H = (u8)(track >> 8);
    MSU_VOLUME = 0xFF;
    MSU_CONTROL = loop ? 0x03 : 0x01;
}

static inline void msu1_stop(void)
{
    MSU_CONTROL = 0x00;
}

#endif
"""
	_write_text(dir.path_join("src/msu1.h"), header)
	var msu_path := dir.path_join(name + ".msu")
	if not FileAccess.file_exists(msu_path):
		var f := FileAccess.open(msu_path, FileAccess.WRITE)
		if f:
			f.close()

static func finalize_rom(project: RetroProject, rom_path: String) -> Dictionary:
	if project == null or rom_path.is_empty() or not FileAccess.file_exists(rom_path):
		return {"ok": false, "error": "ROM not found"}
	var meta: Dictionary = project.get_metadata()
	var trim_to := int(meta.get("rom_trim_bytes", 0))
	var header_mode := int(meta.get("rom_header_mode", 0))
	var mapping := String(meta.get("rom_mapping", ""))
	var profile := String(meta.get("rom_profile", ""))
	var msu1 := bool(meta.get("msu1", false))
	var needs_trim := trim_to > 0
	var needs_patch := header_mode == 0x32
	if not needs_trim and not needs_patch and not msu1:
		return {"ok": true, "rom": rom_path, "size": FileAccess.get_size(rom_path), "trimmed": false}
	var data := FileAccess.get_file_as_bytes(rom_path)
	if needs_trim and data.size() > trim_to:
		data.resize(trim_to)
	var header := 0x00FFC0
	if mapping == "exhirom" or profile in ["exhirom_fast", "tales_phantasia"]:
		header = 0x40FFC0
	elif mapping == "lorom":
		header = 0x007FC0
	if needs_patch and header + 0x15 < data.size():
		data[header + 0x15] = 0x32
	if needs_trim or needs_patch:
		data = _fix_snes_checksum(data, header)
	var f := FileAccess.open(rom_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "could not write ROM"}
	f.store_buffer(data)
	f.close()
	if msu1:
		var msu_path := rom_path.get_basename() + ".msu"
		if not FileAccess.file_exists(msu_path):
			var mf := FileAccess.open(msu_path, FileAccess.WRITE)
			if mf:
				mf.close()
	meta["rom_actual_size"] = data.size()
	meta["rom_trimmed"] = needs_trim
	project.set_metadata(meta)
	project.set_rom_path(rom_path)
	project.save()
	return {"ok": true, "rom": rom_path, "size": data.size(), "trimmed": needs_trim}

static func validate_rom(rom_path: String) -> Dictionary:
	if rom_path.is_empty() or not FileAccess.file_exists(rom_path):
		return {"ok": false, "error": "ROM not found"}
	var data := FileAccess.get_file_as_bytes(rom_path)
	var out := {"ok": true, "path": rom_path, "size": data.size(), "warnings": []}
	var lower := rom_path.to_lower()
	if lower.ends_with(".md") or lower.ends_with(".gen") or lower.ends_with(".bin"):
		var sega := ""
		for i in range(16):
			if 0x100 + i < data.size():
				sega += String.chr(data[0x100 + i])
		out["platform"] = "megadrive"
		out["mapper"] = "SSF2 / Pier Solar / custom (size-dependent)" if data.size() > 0x400000 else "Sega 4 MiB linear"
		out["header_ok"] = sega.begins_with("SEGA")
		out["summary"] = "Mega Drive %s, %s, mapper: %s" % [RomProfiles.human_bytes(data.size()), "SEGA header OK" if bool(out["header_ok"]) else "header missing", String(out["mapper"])]
		if not bool(out["header_ok"]):
			out["warnings"].append("SEGA header not found at 0x100.")
		if data.size() > 0x400000 and bool(out["header_ok"]):
			out["warnings"].append("ROM above 4 MiB requires an SSF2/Pier Solar/custom mapper; bank switching is application code.")
		return out
	var header := -1
	var mode := 0
	var size_byte := 0
	var checksum := 0
	var complement := 0
	var title := ""
	var candidates := [0x7FC0, 0xFFC0, 0x40FFC0] if data.size() <= 0x400000 else [0x40FFC0, 0xFFC0, 0x7FC0]
	for candidate in candidates:
		if candidate + 0x20 > data.size():
			continue
		var csum := (data[candidate + 0x1F] << 8) | data[candidate + 0x1E]
		var comp := (data[candidate + 0x1D] << 8) | data[candidate + 0x1C]
		if ((csum + comp) & 0xFFFF) == 0xFFFF:
			header = candidate
			checksum = csum
			complement = comp
			mode = data[candidate + 0x15]
			size_byte = data[candidate + 0x17]
			for i in range(21):
				title += String.chr(data[candidate + i]) if data[candidate + i] >= 32 and data[candidate + i] < 127 else " "
			break
	if header < 0:
		out["ok"] = false
		out["error"] = "valid SNES header/checksum not found"
		return out
	var msu_path := rom_path.get_basename() + ".msu"
	var msu_present := FileAccess.file_exists(msu_path)
	var msu_size := FileAccess.get_size(msu_path) if msu_present else 0
	var mapping := "ExHiROM" if mode == 0x35 else ("HiROM (S-DD1)" if mode == 0x32 else ("HiROM" if (mode & 1) else "LoROM"))
	out["platform"] = "snes"
	out["mapping"] = mapping
	out["mode"] = mode
	out["size_byte"] = size_byte
	out["title"] = title.strip_edges()
	out["checksum"] = checksum
	out["complement"] = complement
	out["checksum_ok"] = true
	out["msu_present"] = msu_present
	out["msu_size"] = msu_size
	out["summary"] = "SNES %s, %s, %s, checksum OK%s" % [RomProfiles.human_bytes(data.size()), mapping, title.strip_edges(), (", MSU-1 %s" % RomProfiles.human_bytes(msu_size)) if msu_present else ""]
	if mode == 0x32:
		out["warnings"].append("S-DD1 header/layout: the S-DD1 decompressor and MMC bank switching are not included in this ROM.")
	if data.size() > 0x400000 and mode != 0x35 and mode != 0x32:
		out["warnings"].append("ROM is larger than 4 MiB but the header is not ExHiROM/S-DD1; real hardware may not expose the full image.")
	if data.size() > 0x400000 and not msu_present:
		out["warnings"].append("Large ROM has no .msu companion; MSU-1 streaming will report UNAVAILABLE.")
	out["sd2snes_ready"] = bool(out["checksum_ok"]) and (data.size() <= 0x400000 or mode == 0x35 or msu_present)
	return out

static func _fix_snes_checksum(data: PackedByteArray, header: int) -> PackedByteArray:
	if header + 0x20 > data.size():
		return data
	data[header + 0x1C] = 0xFF
	data[header + 0x1D] = 0xFF
	data[header + 0x1E] = 0x00
	data[header + 0x1F] = 0x00
	var total := 0
	for i in range(data.size()):
		total = (total + data[i]) & 0xFFFF
	var checksum := total & 0xFFFF
	var complement := checksum ^ 0xFFFF
	data[header + 0x1C] = complement & 0xFF
	data[header + 0x1D] = (complement >> 8) & 0xFF
	data[header + 0x1E] = checksum & 0xFF
	data[header + 0x1F] = (checksum >> 8) & 0xFF
	return data

static func _write_snes_makefile(path: String, name: String, audio: Dictionary, rom: Dictionary = {}) -> void:
	var text := "ifeq ($(strip $(PVSNESLIB_HOME)),)\n$(error Set PVSNESLIB_HOME to the PVSnesLib root)\nendif\n"
	# PVSnesLib's snes_rules auto-generates hdr.asm from ROMTITLE. The SNES
	# header NAME field is limited to 21 characters, so truncate it here.
	text += "export ROMNAME := %s\nexport ROMTITLE := %s\n" % [name, name.to_upper().substr(0, 21)]
	if not rom.is_empty():
		var mapping := String(rom.get("mapping", "lorom"))
		if mapping in ["hirom", "exhirom"]:
			text += "HIROM := 1\n"
		if bool(rom.get("fast", false)):
			text += "FASTROM := 1\n"
		text += "ROMSIZE := %02X\n" % int(rom.get("size_code", 0x08))
		text += "ROMBANKS := %d\n" % int(rom.get("banks", 8))
		if int(rom.get("sram_code", 0)) > 0:
			text += "SRAMSIZE := %02X\n" % int(rom.get("sram_code", 0))
			text += "CARTRIDGETYPE := %02X\n" % int(rom.get("cart_type", 0x02))
		if bool(rom.get("custom_header", false)):
			text += "AUTOHDR := 0\n"
	var bgm: Dictionary = audio.get("bgm", {})
	if not bgm.is_empty():
		var it_name := _safe_audio_name(String(bgm.get("name", "bgm"))) + ".it"
		text += "export SOUNDBANK := soundbank\n"
		text += "export SMCONVFLAGS := -s -o $(SOUNDBANK)\n"
		text += "export AUDIOFILES := audio/%s\n" % it_name
	text += "include $(PVSNESLIB_HOME)/devkitsnes/snes_rules\nall: $(ROMNAME).sfc\n"
	_write_text(path, text)

static func _write_md_audio_res(dir: String, audio: Dictionary) -> void:
	var lines: Array = []
	var bgm: Dictionary = audio.get("bgm", {})
	if not bgm.is_empty():
		var name := _safe_audio_name(String(bgm.get("name", "bgm")))
		if not String(bgm.get("files", {}).get("vgm", "")).is_empty():
			lines.append("XGM2 %s \"%s.vgm\"" % [name, name])
		elif not String(bgm.get("files", {}).get("wav", "")).is_empty():
			lines.append("WAV %s \"%s.wav\" XGM2" % [name, name])
	for sfx in audio.get("sfx", []):
		var name := _safe_audio_name(String(sfx.get("name", "sfx")))
		if not String(sfx.get("files", {}).get("wav", "")).is_empty():
			lines.append("WAV %s \"%s.wav\" XGM2" % [name, name])
	if lines.is_empty():
		return
	var path := dir.path_join("res/audio.res")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_write_text(path, "\n".join(lines) + "\n")

static func _safe_audio_name(name: String) -> String:
	var out := ""
	for c in name.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" else "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "audio"

static func _write_md_makefile(path: String, rom: Dictionary = {}) -> void:
	var text := "ifndef GDK\n$(error Set GDK to the SGDK root)\nendif\nLIBGCC := $(GDK)/lib/libgcc.a\ninclude $(GDK)/makefile.gen\n"
	if not rom.is_empty():
		var align := maxi(131072, int(rom.get("sizealign", 131072)))
		text += "\n# Large ROM: pad to the selected mapper capacity and fix the checksum.\n"
		text += "padROM: $(OUT)/rom.bin\n\t$(SIZEBND) $(OUT)/rom.bin -sizealign %d -checksum\n" % align
	_write_text(path, text)

static func _write_md_mapper(dir: String, rom: Dictionary) -> void:
	var mapper := String(rom.get("mapper", ""))
	if mapper.is_empty():
		return
	var src := dir.path_join("src")
	DirAccess.make_dir_recursive_absolute(src)
	var sizealign := int(rom.get("sizealign", 0))
	if mapper in ["ssf2", "ssf2_ext"]:
		var header := "#ifndef RETRO_MAPPER_SSF2_H\n#define RETRO_MAPPER_SSF2_H\n\n#include <genesis.h>\n\n"
		header += "#define SSF2_SEGMENTS %d\n#define SSF2_SEGMENT_BYTES 0x%X\n#define SSF2_WINDOW_BYTES 0x%X\n" % [
			int(rom.get("segments", 8)), int(rom.get("segment_bytes", 0x80000)), int(rom.get("window_bytes", 0x400000))]
		header += "#define SSF2_REG_BASE 0xA130F1\n#define SSF2_FIXED_SEGMENTS %d\n\n" % int(rom.get("fixed_segments", 1))
		header += "/* Segment 0 is fixed. Segment 1 starts at 0x080000. */\n"
		header += "void ssf2_set_segment(u8 segment, u8 bank);\nu8 ssf2_get_segment(u8 segment);\n"
		header += "u8 ssf2_read_bank(u8 bank, u16 offset);\n\n#endif\n"
		var source := "#include \"mapper_ssf2.h\"\n\n"
		source += "void ssf2_set_segment(u8 segment, u8 bank)\n{\n"
		source += "    if (segment > 0 && segment < SSF2_SEGMENTS) {\n"
		source += "        *(volatile u8 *)(SSF2_REG_BASE + (segment - 1)) = bank;\n"
		source += "    }\n}\n\n"
		source += "u8 ssf2_get_segment(u8 segment)\n{\n"
		source += "    if (segment > 0 && segment < SSF2_SEGMENTS) return *(volatile u8 *)(SSF2_REG_BASE + (segment - 1));\n"
		source += "    return 0;\n}\n\n"
		source += "u8 ssf2_read_bank(u8 bank, u16 offset)\n{\n"
		source += "    ssf2_set_segment(1, bank);\n"
		source += "    return *(volatile u8 *)(SSF2_SEGMENT_BYTES + (offset & (SSF2_SEGMENT_BYTES - 1)));\n"
		source += "}\n"
		_write_text(src.path_join("mapper_ssf2.h"), header)
		_write_text(src.path_join("mapper_ssf2.c"), source)
	elif mapper == "msu_md":
		var msu := "#ifndef RETRO_MSU_MD_H\n#define RETRO_MSU_MD_H\n\n"
		msu += "/* MSU-MD / MD+ are flashcart audio/data companions. The exact register\n"
		msu += " * protocol depends on the flashcart firmware; keep the companion file\n"
		msu += " * beside the ROM with the same base name. */\n"
		msu += "#define RETRO_MSU_MD 1\n#define RETRO_MSU_MD_ROM_BYTES 0x%X\n\n#endif\n" % sizealign
		_write_text(src.path_join("msu_md.h"), msu)
	else:
		var profile := "#ifndef RETRO_MAPPER_PROFILE_H\n#define RETRO_MAPPER_PROFILE_H\n\n"
		profile += "#define RETRO_MAPPER_%s 1\n" % mapper.to_upper()
		profile += "#define RETRO_MAPPER_WINDOW 0x%X\n#define RETRO_MAPPER_SEGMENT 0x%X\n" % [
			int(rom.get("window_bytes", 0x400000)), int(rom.get("segment_bytes", 0))]
		profile += "#define RETRO_MAPPER_ROM_BYTES 0x%X\n\n" % sizealign
		profile += "/* %s mapper: implement the bank registers for the target cartridge/flashcart. */\n\n#endif\n" % String(rom.get("registers", "custom"))
		_write_text(src.path_join("mapper_profile.h"), profile)
	var doc := "# Mapper — %s\n\n" % String(rom.get("profile_label", mapper))
	doc += "- Mapper: `%s`\n- ROM image: `%s`\n- Window: `%s` bytes\n- Segment: `%s` bytes\n- Registers: `%s`\n" % [
		mapper, RomProfiles.human_bytes(sizealign), str(rom.get("window_bytes", 0)), str(rom.get("segment_bytes", 0)), String(rom.get("registers", ""))]
	doc += "\nGenerated projects include the mapper header/source scaffold. Code that runs while switching banks must stay in the fixed segment (segment 0); data in higher banks is addressed through a mapped segment.\n"
	if mapper == "mega_cd":
		doc += "\nMega-CD images are not generated by SGDK; this is a profile/export reference only.\n"
	if mapper == "msu_md":
		doc += "\nCopy the matching MSU-MD/MD+ companion next to the ROM; audio/data streaming is provided by the flashcart.\n"
	_write_text(dir.path_join("MAPPER.md"), doc)

static func _remove_extension(dir: String, extension: String) -> void:
	var files := DirAccess.get_files_at(dir)
	for file in files:
		if file.get_extension().to_lower() == extension:
			DirAccess.remove_absolute(dir.path_join(file))

static func _write_text(path: String, text: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_CREATE
	f.store_string(text)
	f.close()
	return OK

static func _write_bytes(path: String, data: PackedByteArray) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_CREATE
	f.store_buffer(data)
	f.close()
	return OK
