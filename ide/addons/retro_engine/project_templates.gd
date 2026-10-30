@tool
extends RefCounted
## Creates real, buildable PVSnesLib / SGDK starter projects.
##
## The template uses the same validated asset pipeline as Game Build: a
## 16-colour starter screen is converted to console tiles, a real project is
## generated, and the result is imported back into the IDE with editable
## sources/assets.

const GameBuild = preload("res://addons/retro_engine/game_build.gd")
const I18n = preload("res://addons/retro_engine/i18n.gd")

const TARGET_SNES := "snes"
const TARGET_MD := "megadrive"

const FONT := {
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
}

static func slug(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "retro_game"

static func create(target: String, base_dir: String, project_name: String, animate := true) -> Dictionary:
	if target not in [TARGET_SNES, TARGET_MD]:
		return {"ok": false, "error": I18n.t("templates.unsupported_target", {"target": target})}
	var name := slug(project_name)
	if base_dir.strip_edges().is_empty():
		return {"ok": false, "error": I18n.t("templates.choose_destination")}
	base_dir = base_dir.simplify_path()
	var dir := base_dir.path_join(name)
	if DirAccess.dir_exists_absolute(dir):
		return {"ok": false, "error": I18n.t("templates.folder_exists", {"path": dir})}
	DirAccess.make_dir_recursive_absolute(base_dir)
	var temp := ProjectSettings.globalize_path("user://template_sources/%s_%s" % [target, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(temp.path_join("native"))
	DirAccess.make_dir_recursive_absolute(temp.path_join(".retro"))

	var mode := "mode1" if target == TARGET_SNES else "h40"
	var image := _template_image(target)
	var bridge := RetroNativeBridge.new()
	var stage_result: Dictionary = bridge.import_stage_image(
		image, "template_stage", temp.path_join("native"), target, mode, 8,
		1024 if target == TARGET_SNES else 2048, 16, "template")
	if not bool(stage_result.get("ok", false)):
		_remove_tree(temp)
		return {"ok": false, "error": I18n.t("templates.stage_failed", {"error": String(stage_result.get("error", "unknown"))})}

	var stage_json := String(stage_result.get("stage_json", ""))
	var source := RetroProject.new()
	source.set_name(name)
	source.set_path(temp)
	source.set_source_path(temp)
	source.set_platform(target)
	source.set_mode(mode)
	source.set_resources([{
		"id": "template_stage",
		"rel_path": "native/template_stage.retro_stage.json",
		"path": stage_json,
		"name": stage_json.get_file(),
		"ext": "json",
		"kind": "data",
		"editor": "stage",
		"editable": true,
		"size": FileAccess.get_size(stage_json),
		"group": "stage",
		"native_source": "template",
	}])
	source.save()

	var generation: Dictionary = GameBuild.generate(
		"native_snes" if target == TARGET_SNES else "native_megadrive",
		source, base_dir, name, false, "")
	if not bool(generation.get("ok", false)):
		_remove_tree(temp)
		if DirAccess.dir_exists_absolute(dir):
			_remove_tree(dir)
		return {"ok": false, "error": I18n.t("templates.generation_failed", {"error": String(generation.get("error", "project generation failed"))})}
	var gen_dir := String(generation.get("directory", dir))
	_copy_artifacts(stage_result, gen_dir.path_join("art"))
	var animated := _animate_main(gen_dir.path_join("src/main.c"), target) if animate else false
	_write_readme(gen_dir, target, name)
	_remove_tree(temp)

	var importer := RetroImporter.new()
	var project: RetroProject = importer.import_project(gen_dir, target, base_dir, false, name)
	if project == null:
		return {"ok": false, "error": I18n.t("templates.import_failed"), "directory": gen_dir}
	return {
		"ok": true,
		"project": project,
		"directory": gen_dir,
		"target": target,
		"name": name,
		"animated": animated,
		"stage": stage_result,
		"generation": generation,
	}

static func _template_image(target: String) -> Image:
	var width := 256 if target == TARGET_SNES else 512
	var height := 224
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var colors := [
		Color("#101820"), Color("#1b2a41"), Color("#253d5b"), Color("#2f5478"),
		Color("#3f6f99"), Color("#5b8db8"), Color("#7fb3d5"), Color("#a9d0e8"),
		Color("#f2c14e"), Color("#f78154"), Color("#e94f37"), Color("#6ee7a8"),
		Color("#b8f2e6"), Color("#ffffff"), Color("#8a8a8a"), Color("#000000"),
	]
	for y in range(height):
		for x in range(width):
			image.set_pixel(x, y, colors[1] if ((x / 16) + (y / 16)) % 2 == 0 else colors[2])
	_rect(image, Rect2i(0, 0, width, 4), colors[8])
	_rect(image, Rect2i(0, height - 4, width, 4), colors[8])
	_rect(image, Rect2i(0, 0, 4, height), colors[8])
	_rect(image, Rect2i(width - 4, 0, 4, height), colors[8])
	_rect(image, Rect2i(8, 8, width - 16, 2), colors[6])
	_rect(image, Rect2i(8, height - 10, width - 16, 2), colors[6])

	var visible_width := 256 if target == TARGET_SNES else 320
	var title_w := _text_width("RETRO", 8)
	_draw_text(image, "RETRO", (visible_width - title_w) / 2, 24, 8, colors[13], colors[0])
	var subtitle := "SNES" if target == TARGET_SNES else "MEGA DRIVE"
	var subtitle_w := _text_width(subtitle, 3)
	_draw_text(image, subtitle, (visible_width - subtitle_w) / 2, 82, 3, colors[7], colors[0])

	var cx := visible_width / 2
	var cy := 140
	var radius := 34
	for dy in range(-radius, radius + 1):
		var half: int = radius - absi(dy)
		for dx in range(-half, half + 1):
			var px := cx + dx
			var py := cy + dy
			if px < 0 or py < 0 or px >= width or py >= height:
				continue
			var ring: int = absi(dx) + absi(dy)
			var color: Color = colors[9]
			if ring < radius / 2:
				color = colors[13]
			elif ring < radius * 3 / 4:
				color = colors[9]
			else:
				color = colors[10]
			image.set_pixel(px, py, color)
	_rect(image, Rect2i(cx - 70, cy + radius + 10, 140, 5), colors[11])
	_rect(image, Rect2i(cx - 70, cy + radius + 18, 140, 3), colors[5])
	_draw_text(image, "GODOT RETRO ENGINE", (visible_width - _text_width("GODOT RETRO ENGINE", 2)) / 2,
		height - 26, 2, colors[12], colors[0])
	return image

static func _rect(image: Image, rect: Rect2i, color: Color) -> void:
	var x0 := maxi(0, rect.position.x)
	var y0 := maxi(0, rect.position.y)
	var x1 := mini(image.get_width(), rect.position.x + rect.size.x)
	var y1 := mini(image.get_height(), rect.position.y + rect.size.y)
	for y in range(y0, y1):
		for x in range(x0, x1):
			image.set_pixel(x, y, color)

static func _text_width(text: String, scale: int) -> int:
	return maxi(0, text.length() * 6 - 1) * scale

static func _draw_text(image: Image, text: String, x: int, y: int, scale: int, color: Color, shadow: Color) -> void:
	var cx := x
	for ch in text.to_upper():
		var glyph: Array = FONT.get(ch, FONT[" "])
		for row in range(glyph.size()):
			var line := String(glyph[row])
			for col in range(line.length()):
				if line[col] != "1":
					continue
				for sy in range(scale):
					for sx in range(scale):
						var px := cx + col * scale + sx
						var py := y + row * scale + sy
						if px + 1 < image.get_width() and py + 1 < image.get_height():
							image.set_pixel(px + 1, py + 1, shadow)
						if px < image.get_width() and py < image.get_height():
							image.set_pixel(px, py, color)
		cx += 6 * scale

static func _copy_artifacts(stage: Dictionary, dest: String) -> void:
	var paths: Array = []
	paths.append(String(stage.get("tileset_png", "")))
	paths.append(String(stage.get("stage_json", "")))
	for key in ["snes", "sgdk"]:
		var data: Dictionary = stage.get(key, {})
		for value in data.values():
			if value is String:
				paths.append(String(value))
	DirAccess.make_dir_recursive_absolute(dest)
	var seen := {}
	for src in paths:
		var path := String(src)
		if path.is_empty() or seen.has(path) or not FileAccess.file_exists(path):
			continue
		seen[path] = true
		DirAccess.copy_absolute(path, dest.path_join(path.get_file()))

static func _animate_main(path: String, target: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var code := FileAccess.get_file_as_string(path)
	var old := "    while (1) WaitForVBlank();\n" if target == TARGET_SNES else "    while (TRUE) SYS_doVBlankProcess();\n"
	if not code.contains(old):
		return false
	var replacement := ""
	if target == TARGET_SNES:
		replacement = "    /* Template demo: scroll the background. */\n"
		replacement += "    { u16 demo_scroll = 0;\n"
		replacement += "      while (1) { bgSetScroll(0, demo_scroll++, 0); WaitForVBlank(); }\n"
		replacement += "    }\n"
	else:
		replacement = "    /* Template demo: scroll the background. */\n"
		replacement += "    { s16 demo_scroll = 0;\n"
		replacement += "      while (TRUE) { VDP_setHorizontalScroll(BG_A, demo_scroll++); SYS_doVBlankProcess(); }\n"
		replacement += "    }\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(code.replace(old, replacement))
	f.close()
	return true

static func _write_readme(dir: String, target: String, name: String) -> void:
	var text := "# %s\n\n" % name
	text += "Generated by Godot Retro Engine.\n\n"
	text += "Target: **%s**\n\n" % ("SNES / PVSnesLib" if target == TARGET_SNES else "Mega Drive / SGDK")
	text += "## Build\n\n"
	if target == TARGET_SNES:
		text += "```sh\nPVSNESLIB_HOME=/path/to/pvsneslib make\n```\n"
	else:
		text += "```sh\nGDK=/path/to/sgdk make\n```\n"
	text += "\nOr open this folder with **Retro → Import Project...** / the New Project dialog and use **Build + Run**.\n\n"
	text += "## Files\n\n"
	text += "- `src/main.c` — starter program (scrolls the background);\n"
	text += "- `src/assets.c/.h` — 16-colour starter screen tiles;\n"
	text += "- `art/` — editable source assets for the Stage/Sprite editors;\n"
	text += "- `PORTING.md` — native UI/node/script manifest when available.\n\n"
	text += "The template is a real console project, not a mock. Replace the demo loop with your game loop.\n"
	var f := FileAccess.open(dir.path_join("README.md"), FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()

static func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for file in d.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
