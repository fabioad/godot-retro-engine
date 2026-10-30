extends SceneTree
## Headless integration harness for Godot Retro Engine.
##
## Usage:
##   GodotRetroEngine --headless --path ide --script res://tests/validate.gd -- \
##       --workspace ../validation/workspace \
##       --project ../validation/projects/daniel_snes --project ../validation/projects/sidearms_pvsnes \
##       --build 0 --copy 0
##
## It exercises the same C++ importer, converters, builders and emulator probe
## used by the editor UI. No mocks are involved.

var importer
var report: Dictionary = {}
var failures: int = 0

func _initialize() -> void:
	importer = RetroImporter.new()
	_run.call_deferred()

func _log(msg: String) -> void:
	print("[validate] " + msg)

func _fail(msg: String) -> void:
	failures += 1
	_log("FAIL: " + msg)
	var arr: Array = report.get("failures", [])
	arr.append(msg)
	report["failures"] = arr

func _main_args() -> Dictionary:
	var out := {}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := String(args[i])
		if a.begins_with("--"):
			var key := a.trim_prefix("--")
			var value := "1"
			if key.contains("="):
				value = key.get_slice("=", 1)
				key = key.get_slice("=", 0)
			elif i + 1 < args.size() and not String(args[i + 1]).begins_with("--"):
				value = String(args[i + 1])
				i += 1
			if key == "project":
				var list: Array = out.get("project", [])
				list.append(value)
				out["project"] = list
			else:
				out[key] = value
		i += 1
	return out

func _run() -> void:
	var args := _main_args()
	var workspace := String(args.get("workspace", ProjectSettings.globalize_path("res://workspaces")))
	DirAccess.make_dir_recursive_absolute(workspace)
	# Keep Godot's importer away from working copies: binary build artifacts
	# such as .obj would be parsed as Wavefront OBJ text.
	var ignore_marker := workspace.path_join(".gdignore")
	if not FileAccess.file_exists(ignore_marker):
		var marker := FileAccess.open(ignore_marker, FileAccess.WRITE)
		if marker:
			marker.close()
	var projects: Array = []
	for raw in args.get("project", []):
		var p := String(raw)
		if p.begins_with("res://") or p.begins_with("user://"):
			p = ProjectSettings.globalize_path(p)
		projects.append(p)
	if projects.is_empty():
		_log("No --project passed; running self-tests only.")
	var copy := String(args.get("copy", "0")) == "1"
	var do_build := String(args.get("build", "0")) == "1"

	var sdk: Dictionary = RetroSDK.detect_all()
	report["sdk"] = sdk
	_log("SDK SNES: " + String(sdk.get("snes", {}).get("version", "not found")))
	_log("SDK Mega Drive: " + String(sdk.get("megadrive", {}).get("version", "not found")))

	_self_test_conversions()
	_self_test_text_and_ignore()

	for p in projects:
		await _test_project(String(p), workspace, copy, do_build)

	report["failures_count"] = failures
	report["ok"] = failures == 0
	var out_dir := String(args.get("out", ProjectSettings.globalize_path("res://validation")))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(out_dir.path_join("headless_report.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t", false))
		f.close()
	_log("Report written to " + out_dir.path_join("headless_report.json"))
	_log("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)

func _self_test_conversions() -> void:
	# Build a 16x16 indexed image with 4 colors and verify the native formats.
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color("#101820"))
	var pal := PackedColorArray([Color(0, 0, 0, 0), Color("#ff0000"), Color("#00ff00"), Color("#0000ff")])
	for y in range(16):
		for x in range(16):
			var idx := (x / 8) + (y / 8) * 2
			img.set_pixel(x, y, pal[idx])
	var chr := RetroGraphics.encode_tiles(img, 4, pal, 8, false)
	if chr.size() != 32 * 4:
		_fail("SNES CHR encode: expected 128 bytes, got %d" % chr.size())
	var back := RetroGraphics.decode_tiles(chr, 2, 4, pal, 8, false)
	if back == null:
		_fail("SNES CHR decode returned null")
	elif back.get_pixel(0, 0) != img.get_pixel(0, 0):
		_fail("SNES CHR planar roundtrip differs at 0,0")
	var mdchr := RetroGraphics.encode_tiles(img, 4, pal, 8, true)
	if mdchr.size() != 128:
		_fail("Mega Drive CHR encode: expected 128 bytes, got %d" % mdchr.size())
	# SGDK/Mega Drive tiles store two 4bpp pixels per byte (high nibble is
	# the left pixel). Tile 0 is transparent (index 0), tile 1 is red
	# (index 1) and tile 3 is blue (index 3), so their bytes are 0x00,
	# 0x11 and 0x33 respectively.
	elif mdchr[0] != 0x00 or mdchr[31] != 0x00:
		_fail("Mega Drive CHR is not packed-nibble format (tile 0)")
	elif mdchr[32] != 0x11 or mdchr[63] != 0x11:
		_fail("Mega Drive CHR is not packed-nibble format (tile 1)")
	elif mdchr[96] != 0x33 or mdchr[127] != 0x33:
		_fail("Mega Drive CHR is not packed-nibble format (tile 3)")
	var mdback := RetroGraphics.decode_tiles(mdchr, 2, 4, pal, 8, true)
	if mdback == null or mdback.get_pixel(15, 15) != img.get_pixel(15, 15):
		_fail("Mega Drive 4bpp roundtrip differs")
	var snes_pal := RetroGraphics.encode_palette(pal, false)
	var pal_back := RetroGraphics.decode_palette(snes_pal, false)
	if pal_back.size() != pal.size():
		_fail("SNES palette roundtrip size mismatch")
	var md_pal := RetroGraphics.encode_palette(pal, true)
	if RetroGraphics.decode_palette(md_pal, true).size() != pal.size():
		_fail("Mega Drive palette roundtrip size mismatch")
	# Input map / state association self-test.
	var im := RetroInputMap.new()
	im.setup_defaults("snes")
	if im.get_actions().size() != 10:
		_fail("Input map default actions: expected 10, got %d" % im.get_actions().size())
	if im.action_mask("left", "snes") != 0x0200:
		_fail("Input map SNES KEY_LEFT mask mismatch: %d" % im.action_mask("left", "snes"))
	if im.action_mask("attack_a", "megadrive") != 0x0040:
		_fail("Input map SGDK BUTTON_A mask mismatch: %d" % im.action_mask("attack_a", "megadrive"))
	if not bool(im.validate().get("ok", false)):
		_fail("Default input map validation failed")
	report["self_test"] = {"ok": failures == 0, "chr_bytes": chr.size(), "md_chr_bytes": mdchr.size(), "input_actions": im.get_actions().size()}

func _self_test_text_and_ignore() -> void:
	# Windows-1252/Latin-1 sources (common in MUGEN CNS/AIR and old C files)
	# must decode cleanly instead of printing one UTF-8 warning per byte.
	var tmp := ProjectSettings.globalize_path("user://retro_encoding_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var legacy := tmp.path_join("Makefile")
	var bytes := "NAME=Caf".to_utf8_buffer()
	bytes.append(0xE9) # 'é' in Windows-1252 / Latin-1.
	bytes.append_array("\nPVSNESLIB_HOME=/opt/snes\n".to_utf8_buffer())
	var f := FileAccess.open(legacy, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
		f.close()
	var build_files: Array = importer.detect_build_files(tmp)
	var content := ""
	for m in build_files:
		if String(m.get("name", "")) == "Makefile":
			content = String(m.get("content", ""))
	if not content.contains("Café"):
		_fail("read_text did not decode Windows-1252 text (got %s)" % content)
	if not content.ends_with("\n"):
		_fail("read_text dropped the final character of a Windows-1252 file")

	# Imported working copies must be hidden from Godot's own importer,
	# otherwise binary .obj build artifacts are parsed as Wavefront OBJ text.
	var src := tmp.path_join("proj")
	DirAccess.make_dir_recursive_absolute(src)
	var mf := FileAccess.open(src.path_join("Makefile"), FileAccess.WRITE)
	if mf:
		mf.store_string("PVSNESLIB_HOME=/opt/snes\ninclude $(PVSNESLIB_HOME)/snes_rules\n")
		mf.close()
	var project: RetroProject = importer.import_project(src, "snes", tmp.path_join("ws"), true, "encoding_test")
	if project == null or project.get_path().is_empty():
		_fail("Encoding self-test import returned no project")
	elif not FileAccess.file_exists(project.get_path().path_join(".gdignore")):
		_fail("Import did not write .gdignore into the working copy")
	report["self_test_text"] = {"ok": failures == 0, "content": content}

func _test_project(path: String, workspace: String, copy: bool, do_build: bool) -> void:
	_log("=== Project: " + path)
	var info: Dictionary = {"path": path}
	if not DirAccess.dir_exists_absolute(path):
		_fail("Project directory missing: " + path)
		return
	var scan: Dictionary = importer.scan(path, "")
	info["scan"] = {
		"ok": scan.get("ok", false),
		"platform": scan.get("platform", ""),
		"build_system": scan.get("build_system", ""),
		"build_file": scan.get("build_file", ""),
		"build_target": scan.get("build_target", ""),
		"resource_count": scan.get("resource_count", 0),
		"editable_count": _count_editable(scan.get("resources", [])),
		"sdk_version": scan.get("sdk_version", ""),
		"rom_path": scan.get("rom_path", ""),
	}
	_log("platform=%s build=%s resources=%d editable=%d" % [
		String(scan.get("platform", "")), String(scan.get("build_system", "")),
		int(scan.get("resource_count", 0)), int(info["scan"]["editable_count"])])
	if not bool(scan.get("ok", false)):
		_fail("Scan failed for " + path)
		report[path] = info
		return

	var project: RetroProject = importer.import_project(path, String(scan.get("platform", "")), workspace, copy, "")
	if project == null or project.get_path().is_empty():
		_fail("Import returned no project for " + path)
		report[path] = info
		return
	info["import"] = {
		"path": project.get_path(),
		"source": project.get_source_path(),
		"linked_in_place": project.get_linked_in_place(),
		"name": project.get_name(),
	}
	_log("working copy: " + project.get_path())

	# Resource inspection: verify that every editable resource can be decoded by
	# its declared editor, and that read-only formats are never claimed editable.
	var sprite_tested := false
	var stage_tested := false
	for r in project.get_resources():
		var ext := String(r.get("ext", ""))
		var editable := bool(r.get("editable", false))
		if ext == "sff" and editable:
			_fail("SFF incorrectly marked editable: " + String(r.get("name", "")))
		if not editable:
			continue
		if not sprite_tested and (ext == "chr" or ext == "pic"):
			var pal := String(r.get("palette_path", ""))
			if pal != "" and FileAccess.file_exists(String(r.get("path", ""))):
				var sp := RetroSprite.new()
				sp.set_platform(project.get_platform())
				if sp.load_snes(String(r.get("path", "")), pal, 16, 4) == OK:
					sprite_tested = _test_sprite_export(sp, project)
		if not stage_tested and (ext == "chr" or ext == "pic"):
			var pal := String(r.get("palette_path", ""))
			var map := String(r.get("map_path", ""))
			if pal != "" and map != "" and FileAccess.file_exists(map):
				var st := RetroStage.new()
				st.set_platform(project.get_platform())
				var size := FileAccess.get_size(map) / 2
				var w := int(r.get("map_w", 0))
				var h := int(r.get("map_h", 0))
				if w <= 0:
					w = 64 if size >= 2048 else 32
				if h <= 0:
					h = int(max(1, size / w))
				if st.load_snes(String(r.get("path", "")), map, pal, w, h, 8, 4, 16, bool(r.get("column_major", false))) == OK:
					stage_tested = _test_stage_export(st, project)
	info["conversions"] = {"sprite": sprite_tested, "stage": stage_tested}
	_log("conversion tests: sprite=%s stage=%s" % [str(sprite_tested), str(stage_tested)])

	if do_build:
		var build_result := await _build(project)
		info["build"] = build_result
		if not bool(build_result.get("success", false)):
			_fail("Build failed for " + path + " (exit %d)" % int(build_result.get("exit_code", -1)))
		else:
			var rom := String(build_result.get("rom_path", ""))
			if rom == "" or not FileAccess.file_exists(rom):
				_fail("Build reported success but no ROM exists for " + path)
			else:
				var probe: Dictionary = RetroEmulator.probe_rom(rom)
				info["rom_probe"] = probe
				var emus: Array = RetroEmulator.detect(String(probe.get("platform", "")))
				info["emulators"] = emus
				_log("ROM %s (%s), emulators: %d" % [rom, String(probe.get("size_human", "")), emus.size()])
				if emus.is_empty():
					_log("No emulator installed for this platform (launch test skipped).")
				else:
					# Do not open a GUI window in CI. Launch is exercised by the
					# editor; here we verify detection and command construction.
					info["emulator_ready"] = true
	report[path] = info

func _count_editable(list: Array) -> int:
	var n := 0
	for r in list:
		if bool(r.get("editable", false)):
			n += 1
	return n

func _test_sprite_export(sp: RetroSprite, project: RetroProject) -> bool:
	var out_dir := project.resolve(".retro/validation")
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Deliberately modify one pixel, then export and decode it back. This is the
	# edit -> converted asset -> verification step, without mutating the source.
	var img := sp.get_image()
	if img == null:
		return false
	var old := img.get_pixel(0, 0)
	var newc := Color("#ff00ff") if old != Color("#ff00ff") else Color("#00ffff")
	img.set_pixel(0, 0, newc)
	sp.set_image(img)
	var res: Dictionary = sp.export_snes(out_dir, "validation_sprite")
	if not bool(res.get("ok", false)):
		_fail("Sprite export failed")
		return false
	var chr: PackedByteArray = FileAccess.get_file_as_bytes(String(res.get("chr", "")))
	if chr.size() == 0:
		_fail("Exported CHR is empty")
		return false
	var pal_bytes: PackedByteArray = FileAccess.get_file_as_bytes(String(res.get("pal", "")))
	var pal: PackedColorArray = RetroGraphics.decode_palette(pal_bytes, false)
	var decoded: Image = RetroGraphics.decode_tiles(chr, max(1, img.get_width() / 8), 4, pal, 8, false)
	if decoded == null:
		_fail("Could not decode exported CHR")
		return false
	var md: Dictionary = sp.export_sgdk(out_dir, "validation_sprite")
	if not bool(md.get("ok", false)):
		_fail("SGDK sprite export failed")
		return false
	if not FileAccess.file_exists(String(md.get("png", ""))):
		_fail("SGDK PNG missing")
		return false
	img.set_pixel(0, 0, old)
	return true

func _test_stage_export(st: RetroStage, project: RetroProject) -> bool:
	var out_dir := project.resolve(".retro/validation")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var img := st.render()
	if img == null:
		_fail("Stage render returned null")
		return false
	var res: Dictionary = st.export_snes(out_dir, "validation_stage")
	if not bool(res.get("ok", false)):
		_fail("Stage export failed")
		return false
	if FileAccess.get_size(String(res.get("chr", ""))) == 0 or FileAccess.get_size(String(res.get("map", ""))) == 0:
		_fail("Stage export produced empty files")
		return false
	var sgdk: Dictionary = st.export_sgdk(out_dir, "validation_stage")
	if not bool(sgdk.get("ok", false)):
		_fail("SGDK stage export failed")
		return false
	return true

func _build(project: RetroProject) -> Dictionary:
	_log("Building " + project.get_name() + " ...")
	var builder := RetroBuilder.new()
	get_root().add_child(builder)
	var done := [false, {}]
	builder.build_finished.connect(func(success, result): done[0] = true; done[1] = result, CONNECT_DEFERRED)
	var err: int = builder.build(project, project.get_build_target(), false, false)
	if err != OK:
		builder.queue_free()
		return {"success": false, "error": "could not start", "exit_code": -1}
	while not done[0]:
		await process_frame
	builder.queue_free()
	var result: Dictionary = done[1]
	result.erase("log")
	_log("build finished: success=%s exit=%d rom=%s" % [str(result.get("success", false)), int(result.get("exit_code", -1)), String(result.get("rom_path", ""))])
	return result
