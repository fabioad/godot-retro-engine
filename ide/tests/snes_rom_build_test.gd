extends SceneTree
## Real PVSnesLib/WLA builds for every supported SNES ROM mapping.

const Templates = preload("res://addons/retro_engine/project_templates.gd")
const GameBuild = preload("res://addons/retro_engine/game_build.gd")
const RomProfiles = preload("res://addons/retro_engine/rom_profiles.gd")

var _done: Dictionary = {"ok": false, "rom": ""}

func _initialize() -> void:
	await process_frame
	var root_dir := "/tmp/opencode/snes_rom_build_test"
	_remove_tree(root_dir)
	DirAccess.make_dir_recursive_absolute(root_dir)
	var template: Dictionary = Templates.create("snes", root_dir, "rom_source", false)
	var source: RetroProject = template.get("project")
	if source == null or not bool(template.get("ok", false)):
		print("SNES_ROM_BUILD_TEST FAIL source=", template)
		quit(1)
		return
	var specs: Array = [
		{"name": "auto", "profile": "auto", "size_id": "auto", "msu1": false,
			"expect_profile": "lorom_fast", "size": 0x40000, "mode": 0x30, "code": 0x08},
		{"name": "lorom2", "profile": "lorom_fast", "size_id": "16m", "msu1": false,
			"expect_profile": "lorom_fast", "size": 0x200000, "mode": 0x30, "code": 0x0B},
		{"name": "hirom4", "profile": "hirom_fast", "size_id": "32m", "msu1": false,
			"expect_profile": "hirom_fast", "size": 0x400000, "mode": 0x31, "code": 0x0C},
		{"name": "exhirom8", "profile": "exhirom_fast", "size_id": "64m", "msu1": false,
			"expect_profile": "exhirom_fast", "size": 0x800000, "mode": 0x35, "code": 0x0D},
		{"name": "tales6", "profile": "tales_phantasia", "size_id": "auto", "msu1": false,
			"expect_profile": "tales_phantasia", "size": 0x600000, "mode": 0x35, "code": 0x0D},
		{"name": "star6", "profile": "star_ocean", "size_id": "auto", "msu1": false,
			"expect_profile": "star_ocean", "size": 0x600000, "mode": 0x32, "code": 0x0D},
		{"name": "msu1", "profile": "lorom_fast", "size_id": "16m", "msu1": true,
			"expect_profile": "lorom_fast", "size": 0x200000, "mode": 0x30, "code": 0x0B},
	]
	var all_ok := true
	for raw in specs:
		var spec: Dictionary = raw
		var case_ok := await _run_case(source, root_dir, spec)
		all_ok = all_ok and case_ok
	_remove_tree(root_dir)
	print("SNES_ROM_BUILD_TEST ", "PASS" if all_ok else "FAIL")
	quit(0 if all_ok else 1)

func _run_case(source: RetroProject, root_dir: String, spec: Dictionary) -> bool:
	var game_name := String(spec["name"])
	var settings := {
		"profile": String(spec["profile"]),
		"size_id": String(spec["size_id"]),
		"msu1": bool(spec["msu1"]),
	}
	var generated: Dictionary = GameBuild.generate("native_snes", source, root_dir, game_name, false, "", settings)
	if not bool(generated.get("ok", false)):
		print("ROM_BUILD ", game_name, " GENERATE_FAIL ", generated.get("error"))
		return false
	var rom_settings: Dictionary = generated.get("rom_settings", {})
	var project: RetroProject = generated.get("project")
	var dir := String(generated.get("directory", ""))
	var settings_ok := String(rom_settings.get("profile_id", "")) == String(spec["expect_profile"]) \
		and int(rom_settings.get("size_bytes", 0)) == int(spec["size"]) \
		and int(rom_settings.get("header_mode", 0)) == int(spec["mode"])
	if bool(spec["msu1"]):
		settings_ok = settings_ok \
			and FileAccess.file_exists(dir.path_join(game_name + ".msu")) \
			and FileAccess.file_exists(dir.path_join("src/msu1.h")) \
			and FileAccess.get_file_as_string(dir.path_join("src/main.c")).contains("msu1.h")
	if not settings_ok:
		print("ROM_BUILD ", game_name, " SETTINGS_FAIL ", rom_settings)
		return false
	var builder := RetroBuilder.new()
	get_root().add_child(builder)
	_done = {"ok": false, "rom": ""}
	builder.build_finished.connect(func(success, info):
		_done["ok"] = success
		_done["rom"] = String(info.get("rom_path", ""))
	)
	var err := builder.build(project, "", false, false)
	if err != OK:
		print("ROM_BUILD ", game_name, " START_FAIL ", err)
		builder.queue_free()
		return false
	for i in range(720):
		await create_timer(0.5).timeout
		if bool(_done["ok"]) or not builder.is_building():
			break
	var rom := String(_done.get("rom", ""))
	var build_ok := bool(_done.get("ok", false)) and not rom.is_empty() and FileAccess.file_exists(rom)
	builder.queue_free()
	if not build_ok:
		print("ROM_BUILD ", game_name, " BUILD_FAIL rom=", rom)
		return false
	var finalize: Dictionary = GameBuild.finalize_rom(project, rom)
	if not bool(finalize.get("ok", false)):
		print("ROM_BUILD ", game_name, " FINALIZE_FAIL ", finalize)
		return false
	var data := FileAccess.get_file_as_bytes(rom)
	var header := 0x00FFC0
	if String(spec["expect_profile"]) in ["exhirom_fast", "tales_phantasia"]:
		header = 0x40FFC0
	elif String(spec["expect_profile"]) == "lorom_fast":
		header = 0x007FC0
	if data.size() != int(spec["size"]):
		print("ROM_BUILD ", game_name, " SIZE_FAIL actual=", data.size(), " expected=", spec["size"])
		return false
	var mode := data[header + 0x15]
	var size_code := data[header + 0x17]
	var complement := data[header + 0x1C] | (data[header + 0x1D] << 8)
	var checksum := data[header + 0x1E] | (data[header + 0x1F] << 8)
	var total := 0
	for i in range(data.size()):
		total = (total + data[i]) & 0xFFFF
	var header_ok := mode == int(spec["mode"]) and size_code == int(spec["code"]) \
		and checksum == total and complement == (checksum ^ 0xFFFF)
	var msu_ok := true
	if bool(spec["msu1"]):
		msu_ok = FileAccess.file_exists(rom.get_basename() + ".msu")
	print("ROM_BUILD ", game_name, " size=", data.size(), " mode=", mode, " code=", size_code,
		" checksum=", checksum, " header=", header_ok, " msu=", msu_ok)
	return header_ok and msu_ok

func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for file in d.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
