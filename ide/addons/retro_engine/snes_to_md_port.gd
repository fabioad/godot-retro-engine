@tool
extends RefCounted
## SNES -> Mega Drive source-level port registry.
##
## The engine can rebuild a SNES homebrew game for SGDK only when its game
## logic and assets are portable.  Gothicvania is a compact PVSnesLib C game
## with ordinary PNG/level data, so it has a dedicated adapter; arbitrary SNES
## binaries still need a per-game translator.

const TOOL := "res://addons/retro_engine/tools/gothicvania_md_port.py"

static func detect(source: RetroProject) -> String:
	if source == null or source.get_platform() != "snes":
		return "unsupported"
	var root := source.get_path()
	if FileAccess.file_exists(root.path_join("src/play.c")) and \
			FileAccess.file_exists(root.path_join("res/level/ground_pagesA.bin")) and \
			FileAccess.file_exists(root.path_join("res/hero.png")):
		return "gothicvania"
	return "unsupported"

static func generate(source: RetroProject, out_root: String, game_name: String) -> Dictionary:
	var format := detect(source)
	if format == "unsupported":
		return {"handled": false, "format": format}
	if out_root.is_empty():
		return {"handled": true, "ok": false, "format": format, "error": "output directory is empty"}
	var dir := out_root.path_join(game_name)
	DirAccess.make_dir_recursive_absolute(dir)
	var tool := ProjectSettings.globalize_path(TOOL)
	if not FileAccess.file_exists(tool):
		return {"handled": true, "ok": false, "format": format,
			"error": "Gothicvania port generator not found: " + tool}
	var python := "python" if OS.get_name() == "Windows" else "python3"
	var output: Array = []
	var code := OS.execute(python, [tool, source.get_path(), dir, "--name", game_name], output, true)
	if code != 0:
		var lines := PackedStringArray()
		for line in output:
			lines.append(String(line))
		return {"handled": true, "ok": false, "format": format,
			"error": "Gothicvania port generator failed: " + "\n".join(lines)}
	if not FileAccess.file_exists(dir.path_join("Makefile")):
		return {"handled": true, "ok": false, "format": format,
			"error": "Gothicvania port generator did not write a Makefile"}
	var sdk := RetroSDK.get_sdk("megadrive")
	var sdk_path := String(sdk.get("path", ""))
	if sdk_path.contains(" "):
		var home := OS.get_environment("HOME")
		if not home.is_empty():
			var candidate := home.path_join(".local/share/godot-retro-engine/sdks/megadrive")
			if FileAccess.file_exists(candidate.path_join("makefile.gen")):
				sdk_path = candidate
	var project := RetroProject.new()
	project.set_name(game_name)
	project.set_path(dir)
	project.set_source_path(dir)
	project.set_platform("megadrive")
	project.set_mode("h40")
	project.set_sdk_path(sdk_path)
	project.set_sdk_version(String(sdk.get("version", "unknown")))
	project.set_build_system("sgdk")
	project.set_build_file("Makefile")
	project.set_build_target("")
	project.set_clean_target("clean")
	project.set_rom_path(dir.path_join("out/rom.bin"))
	var meta := project.get_metadata()
	meta["generated_game"] = true
	meta["build_mode"] = "snes_megadrive"
	meta["source_project"] = source.get_path()
	meta["source_format"] = "gothicvania_pvsneslib"
	meta["md_port"] = "gothicvania_source_port"
	meta["md_port_tool"] = tool
	project.set_metadata(meta)
	project.save()
	return {
		"handled": true, "ok": true, "format": format, "directory": dir,
		"project": project, "project_path": project.metadata_path(),
		"target": "megadrive", "rom": project.get_rom_path(),
		"source_format": "gothicvania_pvsneslib",
	}
