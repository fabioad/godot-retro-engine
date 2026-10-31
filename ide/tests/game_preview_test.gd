extends SceneTree
## Boot/transition simulator: power-on sequence, Start/Select commands, pause,
## frame stepping, pause-on-transition and transition log.

const GamePreview = preload("res://addons/retro_engine/game_preview.gd")

func _initialize() -> void:
	await process_frame
	var gp = GamePreview.new()
	get_root().add_child(gp)
	gp.set_pause(true)
	await process_frame
	gp.input_enabled = false
	var map := RetroInputMap.new()
	map.setup_defaults("snes")
	gp.set_input_map(map)
	gp.set_platform("snes")
	gp.power_on(true)
	gp.set_pause(true)
	var ok := true

	ok = ok and _run_until(gp, "BOOT", 60)
	ok = ok and _run_until(gp, "TITLE", 240)
	ok = ok and _run_until_idle(gp, 120)
	print("GAME_PREVIEW boot screen=", gp.screen, " frame=", gp.frame)

	gp.command("start")
	ok = ok and _run_until(gp, "GAMEPLAY", 120)
	ok = ok and _run_until_idle(gp, 120)
	print("GAME_PREVIEW game screen=", gp.screen)

	gp.command("left")
	gp.step_frames(10)
	var moved: bool = gp.player_pos.x < 128.0
	var walking: bool = gp.animation_state == "WALK"
	gp.release_action("left")
	ok = ok and moved and walking

	gp.command("start")
	ok = ok and _run_until(gp, "PAUSE", 120)
	ok = ok and _run_until_idle(gp, 120)
	gp.command("start")
	ok = ok and _run_until(gp, "GAMEPLAY", 120)
	ok = ok and _run_until_idle(gp, 120)

	gp.set_pause(true)
	var frozen_frame: int = int(gp.frame)
	gp._on_timer()
	var frozen: bool = gp.frame == frozen_frame and gp.paused
	gp.step_frames(3)
	var stepped: bool = gp.frame == frozen_frame + 3
	gp.set_pause(false)
	ok = ok and frozen and stepped

	gp.pause_on_transition = true
	gp.command("start")
	var auto_paused: bool = gp.paused and not gp._transition_phase.is_empty()
	ok = ok and auto_paused
	ok = ok and _run_until(gp, "PAUSE", 120)
	ok = ok and _run_until_idle(gp, 120)
	gp.pause_on_transition = false
	gp.set_pause(false)

	gp.input_enabled = true
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	gp._input(event)
	var detected: bool = gp.last_command == "start"
	ok = ok and detected
	ok = ok and _run_until(gp, "PAUSE", 120)
	ok = ok and _run_until_idle(gp, 120)

	var log: String = gp.get_log_text()
	ok = ok and log.contains("TITLE -> GAMEPLAY")
	ok = ok and log.contains("GAMEPLAY -> PAUSE")
	ok = ok and log.contains("command start")
	gp.clear_log()
	ok = ok and gp.get_log_text().is_empty()

	gp.reset()
	ok = ok and gp.screen == "OFF" and gp.frame == 0 and gp.get_log_text().contains("POWER ON")

	print("GAME_PREVIEW pause=", frozen, " step=", stepped, " auto=", auto_paused,
		" detected=", detected, " log=", log.split("\n").size(), " lines")
	print("GAME_PREVIEW ", "PASS" if ok else "FAIL")
	gp.queue_free()
	await process_frame
	quit(0 if ok else 1)

func _run_until(gp, target: String, max_steps: int) -> bool:
	for _i in range(max_steps):
		if gp.screen == target:
			return true
		gp.step_frames(1)
	return gp.screen == target

func _run_until_idle(gp, max_steps: int) -> bool:
	for _i in range(max_steps):
		if gp._transition_phase.is_empty():
			return true
		gp.step_frames(1)
	return gp._transition_phase.is_empty()
