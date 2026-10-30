extends SceneTree
func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/opencode/game_build"
	for i in range(args.size()):
		if String(args[i]) == "--dir" and i + 1 < args.size():
			out = String(args[i + 1])
	var root := out.path_join("source")
	DirAccess.make_dir_recursive_absolute(root)
	# Full-screen showcase source (40x28 tiles) so the generated ROMs fill the
	# SNES 256x224 and Mega Drive 320x224 screens instead of leaving a large
	# empty backdrop with a small test block in the top-left corner.
	var img := Image.create_empty(320, 224, false, Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			img.set_pixel(x, y, Color(0.1, 0.2, 0.4, 1) if ((x / 8) + (y / 8)) % 2 == 0 else Color(0.25, 0.45, 0.8, 1))
	var bridge := RetroNativeBridge.new()
	var snes_stage_result: Dictionary = bridge.import_stage_image(img, "source_snes", root, "snes", "mode1", 8, 1024, 16, "native")
	var md_stage_result: Dictionary = bridge.import_stage_image(img, "source_md", root, "megadrive", "h40", 8, 2048, 16, "native")
	var snes_stage: RetroStage = snes_stage_result.get("stage")
	var md_stage: RetroStage = md_stage_result.get("stage")
	snes_stage.save(root.path_join("source_snes.retro_stage.json"))
	md_stage.save(root.path_join("source_md.retro_stage.json"))
	var source := RetroProject.new()
	source.set_name("source")
	source.set_path(root)
	source.set_platform("snes")
	var gen = preload("res://addons/retro_engine/game_build.gd")
	var cases := [
		["native_snes", "native_snes", root.path_join("source_snes.retro_stage.json")],
		["native_megadrive", "native_md", root.path_join("source_snes.retro_stage.json")],
		["snes_megadrive", "snes_to_md", root.path_join("source_snes.retro_stage.json")],
		["megadrive_snes", "md_to_snes", root.path_join("source_md.retro_stage.json")],
	]
	var ok := true
	var profile_ok := true
	for c in cases:
		var r: Dictionary = gen.generate(String(c[0]), source, out, String(c[1]), true, String(c[2]))
		print("GEN ", c[1], " ok=", r.get("ok"), " target=", r.get("target"), " dir=", r.get("directory"), " err=", r.get("error"))
		ok = ok and bool(r.get("ok", false))
		if bool(r.get("ok", false)):
			var profile: Dictionary = r.get("profile", {})
			var profile_file := String(r.get("export_profile", ""))
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(profile_file)) if FileAccess.file_exists(profile_file) else null
			var target := String(r.get("target", ""))
			var profile_ok_case := bool(profile.get("ok", false)) and FileAccess.file_exists(profile_file) \
				and typeof(parsed) == TYPE_DICTIONARY \
				and int(profile.get("profile_version", 0)) == 1 \
				and String(profile.get("profile_id", "")).begins_with(target)
			if target == "snes":
				profile_ok_case = profile_ok_case \
					and String(profile.get("tile_encoding", "")) == "snes-planar" \
					and String(profile.get("map_layout", "")) == "screens-32x32" \
					and String(profile.get("splash_fade", "")) == "hardware-brightness" \
					and bool(profile.get("screen_disabled_while_loading", false))
			else:
				profile_ok_case = profile_ok_case \
					and String(profile.get("tile_encoding", "")) == "packed-nibbles" \
					and String(profile.get("splash_scroll", {}).get("x", "")) == "positive" \
					and String(profile.get("splash_scroll", {}).get("y", "")) == "negative" \
					and bool(profile.get("clear_sprites", false))
			var project_meta: Dictionary = r.get("project").get_metadata()
			profile_ok_case = profile_ok_case and project_meta.has("export_profile") \
				and int(project_meta.get("export_profile_version", 0)) == 1
			profile_ok = profile_ok and profile_ok_case
		else:
			profile_ok = false
	var plain_snes: Dictionary = gen.generate("native_snes", source, out, "native_snes_nosplash", false, root.path_join("source_snes.retro_stage.json"))
	var plain_md: Dictionary = gen.generate("native_megadrive", source, out, "native_md_nosplash", false, root.path_join("source_snes.retro_stage.json"))
	var plain_ok := bool(plain_snes.get("ok", false)) and bool(plain_md.get("ok", false))
	if plain_ok:
		var snes_main := FileAccess.get_file_as_string(String(plain_snes.get("directory", "")).path_join("src/main.c"))
		var md_main := FileAccess.get_file_as_string(String(plain_md.get("directory", "")).path_join("src/main.c"))
		plain_ok = plain_ok and snes_main.contains("bgSetScroll(0, (u16)(-(") and md_main.contains("VDP_clearPlane") and md_main.contains("VDP_setTileMapDataRect")
	# Splash regressions: black backdrop, centered logo and a palette that
	# keeps the logo's blue/white (and the "Game engine" subtitle) instead of
	# collapsing to grayscale.
	var splash_ok := ok
	if splash_ok:
		var splash_snes_dir := String(gen.generate("native_snes", source, out, "native_snes", true, root.path_join("source_snes.retro_stage.json")).get("directory", ""))
		var splash_md_dir := String(gen.generate("native_megadrive", source, out, "native_md", true, root.path_join("source_snes.retro_stage.json")).get("directory", ""))
		var snes_splash := FileAccess.get_file_as_string(splash_snes_dir.path_join("src/main.c"))
		var md_splash := FileAccess.get_file_as_string(splash_md_dir.path_join("src/main.c"))
		splash_ok = splash_ok and snes_splash.contains("REG_TM = 0x01")
		splash_ok = splash_ok and snes_splash.contains("bgSetScroll(0, (u16)(-(")
		# The splash loads with the display disabled (enable=0) and uses the
		# hardware brightness fade, which cannot tear CGRAM during active
		# display or show a full-brightness/white frame.
		splash_ok = splash_ok and snes_splash.contains("SPLASH_BG_SIZE, 0);")
		splash_ok = splash_ok and snes_splash.contains("if (enable) setScreenOn();")
		splash_ok = splash_ok and snes_splash.contains("setFadeEffectEx(FADE_IN, 2)") and snes_splash.contains("setFadeEffectEx(FADE_OUT, 2)")
		splash_ok = splash_ok and not snes_splash.contains("fadeSplash(")
		splash_ok = splash_ok and md_splash.contains("VDP_setVerticalScroll(BG_A, (s16)(-(") and md_splash.contains("PAL_setColor(0, 0x0000)")
		var splash_stage := RetroStage.new()
		var loaded := splash_stage.load(splash_snes_dir.path_join("godot_splash.retro_stage.json")) == OK
		var colored := false
		if loaded:
			for c in splash_stage.get_palette():
				if max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b)) > 0.1:
					colored = true
					break
		splash_ok = splash_ok and loaded and colored
	print("GEN profile ok=", profile_ok)
	print("GEN splash ok=", splash_ok)
	ok = ok and profile_ok and splash_ok
	if plain_ok:
		var hs := FileAccess.get_file_as_string(String(plain_snes.get("directory", "")).path_join("src/assets.h"))
		var hm := FileAccess.get_file_as_string(String(plain_md.get("directory", "")).path_join("src/assets.h"))
		plain_ok = hs.contains("#define RETRO_SPLASH 0") and hm.contains("#define RETRO_SPLASH 0") and not hs.contains("splash_tiles") and not hm.contains("splash_tiles")
	print("GEN nosplash ok=", plain_ok, " snes=", plain_snes.get("directory"), " md=", plain_md.get("directory"))
	ok = ok and plain_ok
	print("GAME_BUILD PASS" if ok else "GAME_BUILD FAIL")
	quit(0 if ok else 1)
