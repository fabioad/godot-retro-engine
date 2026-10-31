extends SceneTree
## Real ROM preview: launches a libretro core, streams frames, pauses, steps,
## injects a command, rewinds and stops. Skips cleanly when no core/ROM fixture
## is installed on the host.

const RomPreview = preload("res://addons/retro_engine/rom_preview.gd")
const SNES_ROM := "/run/media/fabio/Dados/Fabio/godot_snes_genesis_engine/validation/projects/kof98/build/char_visibility_pre_20261026/kof98-snes.sfc"
const MD_ROM := "/run/media/fabio/Dados/Fabio/godot_snes_genesis_engine/validation/projects/sgdk_platformer/out/rom.bin"

func _initialize() -> void:
	await process_frame
	var ok := true
	var ran := false
	var map := RetroInputMap.new()
	map.setup_defaults("snes")
	if FileAccess.file_exists(SNES_ROM) and not RomPreview.find_core("snes").is_empty():
		ran = true
		ok = ok and await _exercise(SNES_ROM, "snes", map)
	else:
		print("ROM_PREVIEW SKIP snes (ROM or libretro core missing)")
	var md_map := RetroInputMap.new()
	md_map.setup_defaults("megadrive")
	if FileAccess.file_exists(MD_ROM) and not RomPreview.find_core("megadrive").is_empty():
		ran = true
		ok = ok and await _exercise(MD_ROM, "megadrive", md_map)
	else:
		print("ROM_PREVIEW SKIP megadrive (ROM or libretro core missing)")
	if not ran:
		print("ROM_PREVIEW SKIP no fixture")
		quit(0)
		return
	print("ROM_PREVIEW ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _exercise(rom: String, platform: String, map: RetroInputMap) -> bool:
	var project := RetroProject.new()
	project.set_name(platform + "_preview")
	project.set_platform(platform)
	project.set_rom_path(rom)
	var preview = RomPreview.new()
	get_root().add_child(preview)
	await process_frame
	preview.auto_start = true
	preview.set_input_map(map)
	preview.set_project(project)
	var ok := await _wait_until(func(): return preview.running and preview.frame > 60, 9000)
	if not ok:
		print("ROM_PREVIEW ", platform, " start FAILED msg=", preview.get_status_text())
		preview.stop()
		preview.queue_free()
		await process_frame
		return false
	var first_frame: int = int(preview.frame)
	var texture_ok: bool = preview._screen.texture != null
	var audio_ok: bool = preview.audio_packets > 0
	var audio_before: int = int(preview.audio_packets)
	preview.set_audio_enabled(false)
	await _wait_frames(12)
	var audio_off_ok: bool = int(preview.audio_packets) <= audio_before + 2
	preview.set_audio_enabled(true)
	var audio_on_ok := await _wait_until(func(): return int(preview.audio_packets) > audio_before + 4, 3000)
	ok = ok and audio_ok and audio_off_ok and audio_on_ok
	preview.set_pause(true)
	await _wait_frames(20)
	var frozen_frame: int = int(preview.frame)
	await _wait_frames(30)
	var frozen: bool = absi(int(preview.frame) - frozen_frame) <= 1
	preview.step_frames(5)
	var stepped_ok := await _wait_until(func(): return int(preview.frame) >= frozen_frame + 5, 3000)
	var before_command: int = int(preview.frame)
	preview.command("start")
	var command_ok := await _wait_until(func(): return int(preview.frame) >= before_command + 4, 3000)
	var log_ok: bool = preview.get_log_text().contains("input start")
	var before_rewind: int = int(preview.frame)
	preview.rewind_frames(2)
	var rewind_ok := await _wait_until(func(): return int(preview.frame) < before_rewind, 3000)
	var before_button: int = int(preview.frame)
	preview.press_mask(1 << 3, "START", false)
	await _wait_frames(2)
	preview.release_mask(1 << 3, "START")
	var button_ok := await _wait_until(func(): return int(preview.frame) >= before_button + 1, 3000)
	var button_log: bool = preview.get_log_text().contains("button START down")
	ok = ok and button_ok and button_log
	preview.set_speed(0.25)
	var status: String = preview.get_status_text()
	preview.stop()
	var stopped: bool = not preview.running
	print("ROM_PREVIEW ", platform, " first=", first_frame, " frozen=", frozen,
		" stepped=", stepped_ok, " command=", command_ok, " log=", log_ok,
		" rewind=", rewind_ok, " button=", button_ok, " button_log=", button_log,
		" audio=", audio_ok, " audio_off=", audio_off_ok, " audio_on=", audio_on_ok,
		" texture=", texture_ok, " stopped=", stopped, " status=", status)
	preview.queue_free()
	await process_frame
	return texture_ok and frozen and stepped_ok and command_ok and log_ok and rewind_ok and stopped

func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame

func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())
