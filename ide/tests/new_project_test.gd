extends SceneTree
## New SNES/Mega Drive template: generate, import, build and run-check.

const Templates = preload("res://addons/retro_engine/project_templates.gd")

func _initialize() -> void:
	await process_frame
	var root := "/tmp/opencode/new_project_test"
	_remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	var ok := true
	for target in ["snes", "megadrive"]:
		var label := "snes" if target == "snes" else "md"
		var result: Dictionary = Templates.create(target, root, "template_" + label, true)
		var project: RetroProject = result.get("project")
		var dir := String(result.get("directory", ""))
		var main_path := dir.path_join("src/main.c")
		var make_path := dir.path_join("Makefile")
		var readme_path := dir.path_join("README.md")
		var art_dir := dir.path_join("art")
		var main_code := FileAccess.get_file_as_string(main_path) if FileAccess.file_exists(main_path) else ""
		var assets_path := dir.path_join("src/assets.h")
		var assets_code := FileAccess.get_file_as_string(assets_path) if FileAccess.file_exists(assets_path) else ""
		var checks := {
			"ok": bool(result.get("ok", false)),
			"project": project != null,
			"main": FileAccess.file_exists(main_path),
			"make": FileAccess.file_exists(make_path) or FileAccess.file_exists(dir.path_join("makefile")),
			"readme": FileAccess.file_exists(readme_path),
			"animated": bool(result.get("animated", false)),
			"splash": bool(result.get("splash", false)),
			"workflow_comments": main_code.contains("Godot Retro Engine - Hello World") and main_code.contains("Workflow:"),
			"main_splash": main_code.contains("showSplash()"),
			"assets_splash": assets_code.contains("RETRO_SPLASH 1"),
			"build_system": project != null and project.get_build_system() in ["pvsneslib", "sgdk"],
			"resources": project != null and project.get_resources().size() > 0,
			"art": DirAccess.dir_exists_absolute(art_dir),
		}
		print("NEW_PROJECT ", label, " checks=", checks)
		ok = ok and checks.values().all(func(v): return bool(v))
		if project == null or not bool(result.get("ok", false)):
			continue
		var builder := RetroBuilder.new()
		get_root().add_child(builder)
		var done := {"ok": false, "rom": ""}
		builder.build_finished.connect(func(success, info):
			done["ok"] = success
			done["rom"] = String(info.get("rom_path", ""))
		)
		builder.log_line.connect(func(line, level):
			if level >= 1 or String(line).contains("warning:") or String(line).contains("error:"):
				print("NEW_PROJECT_BUILD_LOG ", label, " ", line)
		)
		var err := builder.build(project, "", false, false)
		print("NEW_PROJECT ", label, " build_start=", err, " sdk=", project.get_sdk_path(), " system=", project.get_build_system())
		for i in range(240):
			await create_timer(0.5).timeout
			if bool(done["ok"]) or not builder.is_building():
				break
		var rom := String(done.get("rom", ""))
		var build_ok := bool(done.get("ok", false)) and not rom.is_empty() and FileAccess.file_exists(rom)
		print("NEW_PROJECT ", label, " build_ok=", build_ok, " rom=", rom, " size=", FileAccess.get_size(rom) if FileAccess.file_exists(rom) else 0)
		ok = ok and build_ok
		builder.queue_free()
		await process_frame
	_remove_tree(root)
	print("NEW_PROJECT_TEST ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

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
