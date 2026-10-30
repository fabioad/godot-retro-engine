extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var roms: Array = []
	for i in range(args.size()):
		if String(args[i]) == "--rom" and i + 1 < args.size():
			roms.append(String(args[i + 1]))
	if roms.is_empty():
		print("EMULATOR_SMOKE SKIP: no --rom")
		quit(0)
		return
	var failures := 0
	for rom in roms:
		if not FileAccess.file_exists(rom):
			print("EMULATOR_SMOKE FAIL missing ", rom)
			failures += 1
			continue
		var probe: Dictionary = RetroEmulator.probe_rom(rom)
		var platform := String(probe.get("platform", ""))
		var emus: Array = RetroEmulator.detect(platform)
		if emus.is_empty():
			print("EMULATOR_SMOKE SKIP no emulator for ", platform)
			continue
		var chosen: Dictionary = emus[0]
		var r: Dictionary = RetroEmulator.launch(rom, String(chosen.get("id", "")))
		if not bool(r.get("ok", false)):
			print("EMULATOR_SMOKE FAIL launch ", rom, " : ", r.get("error", ""))
			failures += 1
			continue
		var pid := int(r.get("pid", 0))
		await create_timer(4.0).timeout
		var alive := RetroEmulator.is_running(pid)
		print("EMULATOR_SMOKE ", "PASS" if alive else "FAIL", " ", rom.get_file(), " pid=", pid, " emulator=", chosen.get("id", ""))
		if not alive:
			failures += 1
		RetroEmulator.terminate(pid)
		await create_timer(0.5).timeout
	print("EMULATOR_SMOKE RESULT failures=", failures)
	quit(0 if failures == 0 else 1)
