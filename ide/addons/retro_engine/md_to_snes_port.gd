@tool
extends RefCounted
## Mega Drive -> SNES source-level port registry.
##
## The engine can translate a Mega Drive project without a binary 68000
## emulator only when the game logic exists in a portable form:
##  - native engine projects already use the same actor/state runtime on both
##    targets, so the existing native runtime path is used;
##  - Sonic 2 disassemblies have a dedicated source-level adapter that rebuilds
##    the EHZ engine data and physics for the SNES;
##  - anything else is a raw 68000 game. A faithful port then needs a per-game
##    source adapter; interpreting 68000 on a 3.58 MHz 65816 is not viable.

const SonicStageImport = preload("res://addons/retro_engine/sonic_stage_import.gd")

## Returns "sonic2", "native" or "unsupported".
static func detect(source: RetroProject) -> String:
	if source == null or source.get_platform() != "megadrive":
		return "unsupported"
	if SonicStageImport.detects(source):
		return "sonic2"
	var links := source.resolve(".retro/editor/native_links.json")
	if FileAccess.file_exists(links):
		var data = JSON.parse_string(FileAccess.get_file_as_string(links))
		if typeof(data) == TYPE_DICTIONARY:
			var port = data.get("port", {})
			if typeof(port) == TYPE_DICTIONARY and not port.is_empty():
				return "native"
			if not Array(data.get("assets", [])).is_empty():
				return "native"
	var meta_port = source.get_metadata().get("native_port", {})
	if typeof(meta_port) == TYPE_DICTIONARY and not meta_port.is_empty():
		return "native"
	return "unsupported"

## Handles formats that need a dedicated generator. Native projects return
## handled=false so GameBuild keeps using the shared native runtime.
static func generate(source: RetroProject, out_root: String, game_name: String) -> Dictionary:
	var format := detect(source)
	if format == "native":
		return {"handled": false, "format": format}
	if format != "sonic2":
		return {
			"handled": true, "ok": false, "format": format,
			"error": "This Mega Drive project has no portable engine representation. "
				+ "A faithful SNES port needs a per-game source adapter (the 68000 "
				+ "binary cannot be interpreted on the SNES in real time).",
		}
	if out_root.is_empty():
		return {"handled": true, "ok": false, "format": format, "error": "output directory is empty"}
	var dir := out_root.path_join(game_name)
	DirAccess.make_dir_recursive_absolute(dir)
	var tool := ProjectSettings.globalize_path("res://addons/retro_engine/tools/sonic2_snes_port.py")
	if not FileAccess.file_exists(tool):
		return {"handled": true, "ok": false, "format": format, "error": "Sonic 2 port generator not found: " + tool}
	var python := "python" if OS.get_name() == "Windows" else "python3"
	var output: Array = []
	var code := OS.execute(python, [tool, source.get_path(), dir], output, true)
	if code != 0:
		var lines := PackedStringArray()
		for line in output:
			lines.append(String(line))
		return {"handled": true, "ok": false, "format": format,
			"error": "Sonic 2 port generator failed: " + "\n".join(lines)}
	if not FileAccess.file_exists(dir.path_join("Makefile")):
		return {"handled": true, "ok": false, "format": format,
			"error": "Sonic 2 port generator did not write a Makefile"}
	var sdk := RetroSDK.get_sdk("snes")
	var sdk_path := String(sdk.get("path", ""))
	if sdk_path.contains(" "):
		# WLA/make include lines break on spaces; prefer the no-space mirror
		# installed by the engine when it exists.
		var home := OS.get_environment("HOME")
		if not home.is_empty():
			var candidate := home.path_join(".local/share/godot-retro-engine/sdks/snes")
			if FileAccess.file_exists(candidate.path_join("devkitsnes/snes_rules")):
				sdk_path = candidate
	var project := RetroProject.new()
	project.set_name(game_name)
	project.set_path(dir)
	project.set_source_path(dir)
	project.set_platform("snes")
	project.set_mode("mode1")
	project.set_sdk_path(sdk_path)
	project.set_sdk_version(String(sdk.get("version", "unknown")))
	project.set_build_system("make")
	project.set_build_file("Makefile")
	project.set_build_target("")
	project.set_clean_target("clean")
	project.set_rom_path(dir.path_join("sonic_port.sfc"))
	var meta := project.get_metadata()
	meta["generated_game"] = true
	meta["build_mode"] = "megadrive_snes"
	meta["source_project"] = source.get_path()
	meta["source_format"] = "sonic2_disassembly"
	meta["snes_port"] = "sonic2_ehz_slice"
	meta["snes_port_tool"] = tool
	project.set_metadata(meta)
	project.save()
	return {
		"handled": true, "ok": true, "format": format, "directory": dir,
		"project": project, "project_path": project.metadata_path(),
		"target": "snes", "rom": project.get_rom_path(),
		"source_format": "sonic2_disassembly",
	}
