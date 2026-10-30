extends SceneTree
## Missing SDKs must produce guidance, not a crash or a fake build.
func _initialize() -> void:
	await process_frame
	var ok := true
	var project := RetroProject.new()
	project.set_name("missing_sdk")
	project.set_path("/tmp/retro_missing_sdk_project")
	project.set_platform("snes")
	project.set_build_system("pvsneslib")
	project.set_sdk_path("/tmp/retro_sdk_does_not_exist")
	var panel = preload("res://addons/retro_engine/build_panel.gd").new()
	get_root().add_child(panel)
	await process_frame
	panel.set_project(project)
	var snes_problem := panel._sdk_problem()
	print("MISSING_SDK snes=", snes_problem)
	ok = ok and not snes_problem.is_empty()
	project.set_platform("megadrive")
	project.set_build_system("sgdk")
	panel.set_platform("megadrive")
	var md_problem := panel._sdk_problem()
	print("MISSING_SDK md=", md_problem)
	ok = ok and not md_problem.is_empty()
	var pvs := RetroSDK.probe_snes("/tmp/retro_sdk_does_not_exist")
	var md := RetroSDK.probe_megadrive("/tmp/retro_sdk_does_not_exist")
	print("MISSING_SDK probes snes_found=", pvs.get("found", false), " md_found=", md.get("found", false))
	ok = ok and not bool(pvs.get("found", false)) and not bool(md.get("found", false))
	print("MISSING_SDK ", "PASS" if ok else "FAIL")
	panel.queue_free()
	quit(0 if ok else 1)
