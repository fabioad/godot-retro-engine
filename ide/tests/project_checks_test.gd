extends SceneTree
## Project/platform/mode/SDK/export-profile coherence checks.

const ProjectChecks = preload("res://addons/retro_engine/project_checks.gd")

func _initialize() -> void:
	await process_frame
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var snes := RetroProject.new()
	snes.set_name("coherence_snes")
	snes.set_platform("snes")
	snes.set_mode("mode1")
	snes.set_build_system("pvsneslib")
	var md := RetroProject.new()
	md.set_name("coherence_md")
	md.set_platform("megadrive")
	md.set_mode("h40")
	md.set_build_system("sgdk")

	var ok := true
	var valid: Dictionary = ProjectChecks.inspect(snes, "snes", "mode1")
	print("CHECK_VALID ", valid)
	ok = ok and bool(valid.get("ok", false)) and Array(valid.get("errors", [])).is_empty()

	var wrong_platform: Dictionary = ProjectChecks.inspect(snes, "megadrive", "mode1")
	print("CHECK_PLATFORM ", wrong_platform)
	ok = ok and not bool(wrong_platform.get("ok", false)) and _has_code(wrong_platform, "platform_mismatch")

	snes.set_mode("h40")
	var wrong_mode: Dictionary = ProjectChecks.inspect(snes, "snes", "h40")
	print("CHECK_MODE ", wrong_mode)
	ok = ok and not bool(wrong_mode.get("ok", false)) and _has_code(wrong_mode, "invalid_mode")
	snes.set_mode("mode1")

	snes.set_build_system("sgdk")
	var wrong_system: Dictionary = ProjectChecks.inspect(snes, "snes", "mode1")
	print("CHECK_SYSTEM ", wrong_system)
	ok = ok and not bool(wrong_system.get("ok", false)) and _has_code(wrong_system, "snes_with_sgdk")
	snes.set_build_system("pvsneslib")

	var snes_sdk := String(RetroSDK.get_sdk("snes").get("path", ""))
	var md_sdk := String(RetroSDK.get_sdk("megadrive").get("path", ""))
	if not snes_sdk.is_empty() and not md_sdk.is_empty():
		snes.set_sdk_path(md_sdk)
		var wrong_sdk: Dictionary = ProjectChecks.inspect(snes, "snes", "mode1")
		print("CHECK_SDK ", wrong_sdk)
		ok = ok and not bool(wrong_sdk.get("ok", false)) and _has_code(wrong_sdk, "sdk_points_sgdk")
		snes.set_sdk_path(snes_sdk)

	snes.set_metadata({"export_profile": {"platform": "megadrive", "profile_id": "megadrive-v1"}})
	var profile_warning: Dictionary = ProjectChecks.inspect(snes, "snes", "mode1")
	print("CHECK_PROFILE ", profile_warning)
	ok = ok and bool(profile_warning.get("ok", false)) and _has_code(profile_warning, "export_profile_target")

	snes.set_metadata({"3d_profile": "svp"})
	var profile_3d: Dictionary = ProjectChecks.inspect(snes, "snes", "mode1")
	print("CHECK_3D ", profile_3d)
	ok = ok and bool(profile_3d.get("ok", false)) and _has_code(profile_3d, "svp_on_snes")

	snes.set_metadata({"build_mode": "native_megadrive"})
	var build_mode: Dictionary = ProjectChecks.inspect(snes, "snes", "mode1")
	print("CHECK_BUILD_MODE ", build_mode)
	ok = ok and not bool(build_mode.get("ok", false)) and _has_code(build_mode, "build_mode_mismatch")
	snes.set_metadata({})

	var md_valid: Dictionary = ProjectChecks.inspect(md, "megadrive", "h40")
	print("CHECK_MD_VALID ", md_valid)
	ok = ok and bool(md_valid.get("ok", false))
	var md_platform: Dictionary = ProjectChecks.inspect(md, "snes", "h40")
	ok = ok and not bool(md_platform.get("ok", false)) and _has_code(md_platform, "platform_mismatch")
	md.set_mode("mode1")
	var md_mode: Dictionary = ProjectChecks.inspect(md, "megadrive", "mode1")
	ok = ok and not bool(md_mode.get("ok", false)) and _has_code(md_mode, "invalid_mode")
	md.set_mode("h40")
	md.set_build_system("pvsneslib")
	var md_system: Dictionary = ProjectChecks.inspect(md, "megadrive", "h40")
	ok = ok and not bool(md_system.get("ok", false)) and _has_code(md_system, "md_with_snes_build")

	# The Build panel must block an incoherent platform selection and offer the fix.
	var BuildPanel = preload("res://addons/retro_engine/build_panel.gd")
	var panel = BuildPanel.new()
	get_root().add_child(panel)
	await process_frame
	panel.set_project(snes)
	panel.set_platform("megadrive")
	var fix_target := {"value": ""}
	panel.platform_fix_requested.connect(func(target): fix_target["value"] = target)
	panel.start_build(false, false)
	await process_frame
	var panel_blocked: bool = not panel.builder.is_building() and panel._coherence.visible and panel._coherence.text.contains("Platform selector") and panel._fix_platform.visible
	if panel._fix_platform.visible:
		panel._fix_platform.pressed.emit()
	print("CHECK_BUILD_PANEL blocked=", panel_blocked, " fix=", fix_target["value"])
	ok = ok and panel_blocked and String(fix_target["value"]) == "snes"
	panel.queue_free()
	await process_frame

	# Game Build must reject "Mega Drive project -> SNES" when the active
	# project is SNES, instead of silently using the wrong source.
	var GameBuildDialog = preload("res://addons/retro_engine/game_build_dialog.gd")
	var dialog = GameBuildDialog.new()
	get_root().add_child(dialog)
	await process_frame
	dialog.project = snes
	dialog.platform = "snes"
	dialog._mode.select(3) # megadrive_snes
	dialog._refresh_warnings()
	var mode_error: bool = dialog._mode_error.contains("requires an active Mega Drive project") and dialog._warning.visible
	print("CHECK_GAME_BUILD_MODE error=", dialog._mode_error, " visible=", dialog._warning.visible)
	ok = ok and mode_error
	dialog.queue_free()
	await process_frame

	TranslationServer.set_locale(previous_locale)
	print("PROJECT_CHECKS ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _has_code(check: Dictionary, code: String) -> bool:
	for item in check.get("errors", []):
		if item is Dictionary and String(item.get("code", "")) == code:
			return true
	for item in check.get("warnings", []):
		if item is Dictionary and String(item.get("code", "")) == code:
			return true
	return false
