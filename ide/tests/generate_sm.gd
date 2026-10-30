extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var platform := "snes"
	var dir := "/tmp/retro_sm"
	for i in range(args.size()):
		if String(args[i]) == "--platform" and i + 1 < args.size():
			platform = String(args[i + 1])
		if String(args[i]) == "--dir" and i + 1 < args.size():
			dir = String(args[i + 1])
	var m := RetroInputMap.new()
	m.setup_defaults(platform)
	m.add_action({"id":"super_combo","label":"Super Combo","snes":["R","X"],"md":["Y","C"],"state":"SUPER","next":"IDLE","priority":9,"hold":true})
	# Animation durations (console frames) used by retro_sm_tick().
	var durations: Array = []
	for i in range(m.get_states().size()):
		durations.append(0)
	durations[m.get_states().find("ATTACK")] = 4
	durations[m.get_states().find("SUPER")] = 2
	m.set_state_durations(durations)
	var result: Dictionary
	if platform == "snes":
		result = m.export_state_machine_snes(dir)
	else:
		result = m.export_state_machine_sgdk(dir)
	print("GENERATED ", result)
	quit(0 if bool(result.get("ok", false)) else 1)
