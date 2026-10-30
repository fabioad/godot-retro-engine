@tool
extends RefCounted
## Generates standalone PVSnesLib / SGDK demo projects from native assets or
## from the current retro project, with an optional Godot-logo fade splash.

const LOGO_PATH := "res://addons/retro_engine/assets/godot_splash.png"
const ExportProfiles = preload("res://addons/retro_engine/export_profiles.gd")
const AudioPipeline = preload("res://addons/retro_engine/audio_pipeline.gd")

static func target_for_mode(mode: String) -> String:
	if mode in ["native_snes", "megadrive_snes"]:
		return "snes"
	if mode in ["native_megadrive", "snes_megadrive"]:
		return "megadrive"
	return ""

static func generate(mode: String, source: RetroProject, out_root: String, game_name: String,
		include_splash: bool, source_stage_path := "") -> Dictionary:
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
	var header_path := dir.path_join("src/assets.h")
	var source_path := dir.path_join("src/assets.c")
	var write := _write_assets(header_path, source_path, stage, splash, target, include_splash)
	if not bool(write.get("ok", false)):
		return write
	var port := _find_native_port(source)
	var port_result := _copy_native_port(port, dir)
	if target == "snes":
		_write_snes_main(dir.path_join("src/main.c"), stage, splash, include_splash, audio)
		_write_snes_makefile(dir.path_join("Makefile"), game_name, audio)
	else:
		_write_md_main(dir.path_join("src/main.c"), stage, splash, include_splash, audio)
		_write_md_makefile(dir.path_join("Makefile"))
		# rescomp scans .res files in the project root. The generated C arrays
		# already contain the tiles/palette/map, so remove the temporary SGDK
		# resource scripts produced while building the native stage.
		_remove_extension(dir, "res")
		_write_md_audio_res(dir, audio)
	var project := RetroProject.new()
	project.set_name(game_name)
	project.set_path(dir)
	project.set_source_path(dir)
	project.set_platform(target)
	project.set_mode(String(profile.get("bg_mode", "mode1")))
	project.set_sdk_path(_sdk_path(source, target))
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
		"native_port": String(port_result.get("directory", ""))
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
		"stage": stage, "splash_stage": splash, "port": port_result}

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
				var assets: Array = data.get("assets", [])
				for i in range(assets.size() - 1, -1, -1):
					var a: Dictionary = assets[i]
					var path := String(a.get("asset", ""))
					if str(a.get("type", "")) == "stage" or path.ends_with(".retro_stage.json"):
						var s := _load_stage(path, target, bridge)
						if s != null:
							return s
		var stage_resources := source.find_resources("stage", true)
		for r in stage_resources:
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
		target: String, include_splash: bool) -> Dictionary:
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
	return {"ok": e1 == OK and e2 == OK, "header": header_path, "source": source_path}

static func _stage_data(stage: RetroStage, target: String) -> Dictionary:
	var tileset: Image = stage.get_tileset()
	var palette: PackedColorArray = stage.get_palette()
	if tileset == null or palette.is_empty():
		return {}
	var md := target == "megadrive"
	var tiles := RetroGraphics.encode_tiles(tileset, stage.get_bpp(), palette, stage.get_tile_size(), md)
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

static func _write_snes_main(path: String, stage: RetroStage, splash: RetroStage, include_splash: bool, audio: Dictionary) -> void:
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
		code += _array_decl("sfx_" + safe + "_brr", _byte_values(data), "unsigned char")
		region = maxi(region, int((data.size() + 255) / 256) + 2)
	if not sfx_brr_arrays.is_empty():
		code += "static brrsamples sfx_table[%d];\n\n" % sfx_brr_arrays.size()
	code += "int main(void)\n{\n    consoleInit();\n    setMode(BG_MODE1, 0);\n"
	code += "    // Show BG1 only; uninitialised OAM/BG2/BG3 would otherwise draw stripes.\n"
	code += "    REG_TM = 0x01; REG_TS = 0x00;\n"
	code += "#if RETRO_SPLASH\n    showSplash();\n#endif\n"
	code += "    loadStage(game_tiles, game_pal, game_map, game_tiles_size, game_pal_size, GAME_MAP_W, GAME_MAP_H, GAME_MAP_STRIDE, GAME_MAP_BYTES, GAME_BG_SIZE, 1);\n"
	if has_bgm or not sfx_brr_arrays.is_empty():
		code += "    spcBoot();\n"
		if has_bgm:
			code += "    spcSetBank((u8 *)&%s);\n" % bank_symbol
			code += "    spcLoad(%s);\n" % module_name
		for i in range(sfx_brr_arrays.size()):
			code += "    spcSetSoundEntry(15, 8, 6, sizeof(sfx_%s_brr), (u8 *)sfx_%s_brr, &sfx_table[%d]);\n" % [sfx_brr_arrays[i], sfx_brr_arrays[i], i]
		if not sfx_brr_arrays.is_empty():
			code += "    spcSetSoundTableEntry(&sfx_table[0]);\n"
			code += "    spcAllocateSoundRegion(%d);\n" % region
		code += "    spcFlush();\n"
		if has_bgm:
			code += "    spcPlay(0);\n"
	if not sfx_brr_arrays.is_empty() or has_bgm:
		code += "    { u16 sfx_timer = 0; while (1) { spcProcess(); if (++sfx_timer >= 120) { sfx_timer = 0;\n"
		if not sfx_brr_arrays.is_empty():
			code += "        spcPlaySound(0);\n"
		code += "    } WaitForVBlank(); } }\n"
	else:
		code += "    while (1) WaitForVBlank();\n"
	code += "    return 0;\n}\n"
	_write_text(path, code)

static func _write_md_main(path: String, stage: RetroStage, splash: RetroStage, include_splash: bool, audio: Dictionary) -> void:
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
	code += "    VDP_setHorizontalScroll(BG_A, (s16)((320 - SPLASH_MAP_W * 8) / 2));\n"
	code += "    // On Mega Drive a positive vertical scroll moves the plane up, so the\n"
	code += "    // centering offset must be negative.\n"
	code += "    VDP_setVerticalScroll(BG_A, (s16)(-((224 - SPLASH_MAP_H * 8) / 2)));\n"
	code += "    for (level = 0; level <= %d; level++) { fadeSplash(level); SYS_doVBlankProcess(); }\n" % fade_steps
	code += "    for (hold = 0; hold < %d; hold++) SYS_doVBlankProcess();\n" % hold_frames
	code += "    for (level = %d; level > 0; level--) { fadeSplash(level); SYS_doVBlankProcess(); }\n" % fade_steps
	code += "    fadeSplash(0); PAL_setColor(0, 0x0000); SYS_doVBlankProcess();\n}\n"
	code += "#endif\n\n"
	code += "int main(bool hard)\n{\n    (void)hard;\n    VDP_setScreenWidth320();\n    VDP_setPlaneSize(64, 32, TRUE);\n    VDP_setBackgroundColor(0);\n"
	code += "#if RETRO_SPLASH\n    showSplash();\n#endif\n"
	code += "    loadStage(game_tiles, GAME_TILE_COUNT, game_pal, game_map, GAME_MAP_W, GAME_MAP_H);\n"
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
			code += "    { u16 sfx_timer = 0; while (TRUE) { SYS_doVBlankProcess(); if (++sfx_timer >= 120) { sfx_timer = 0; XGM2_playPCM(%s, sizeof(%s), SOUND_PCM_CH2); } } }\n" % [sfx_name, sfx_name]
		else:
			code += "    while (TRUE) SYS_doVBlankProcess();\n"
	else:
		code += "    while (TRUE) SYS_doVBlankProcess();\n"
	code += "    return 0;\n}\n"
	_write_text(path, code)

static func _write_snes_makefile(path: String, name: String, audio: Dictionary) -> void:
	var text := "ifeq ($(strip $(PVSNESLIB_HOME)),)\n$(error Set PVSNESLIB_HOME to the PVSnesLib root)\nendif\n"
	text += "export ROMNAME := %s\nexport ROMTITLE := %s\n" % [name, name.to_upper()]
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

static func _write_md_makefile(path: String) -> void:
	_write_text(path, "ifndef GDK\n$(error Set GDK to the SGDK root)\nendif\nLIBGCC := $(GDK)/lib/libgcc.a\ninclude $(GDK)/makefile.gen\n")

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
