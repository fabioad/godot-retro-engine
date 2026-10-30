extends SceneTree
func _initialize() -> void:
	_go.call_deferred()
func _go() -> void:
	var Sim = load("res://addons/retro_engine/state_simulator.gd")
	var sim = Sim.new()
	get_root().add_child(sim)
	await process_frame
	var anim := RetroAnimation.new()
	anim.add_frame("ATTACK", 0, 4)
	anim.add_frame("SUPER", 0, 2)
	sim.set_context(null, "snes", anim, null)
	sim.input_map.add_action({"id":"super_combo","label":"Super","snes":["R","X"],"md":["Y","C"],"state":"SUPER","next":"IDLE","priority":9,"hold":true})
	sim._sync_durations()
	sim._rebuild_actions()
	var actions: Array = sim.input_map.get_actions()
	var idx := -1
	for i in range(actions.size()):
		if String(actions[i].get("id", "")) == "super_combo":
			idx = i
	if idx < 0:
		print("SIM_LOGIC FAIL combo not found")
		quit(1)
		return
	sim._actions.select(idx)
	sim._on_action_selected(idx)
	sim._held["super_combo"] = true
	sim._step()
	print("after step 1 state=", sim._state, " frame=", sim._elapsed, " pending=", sim._pending)
	if sim._state != "SUPER" or sim._elapsed != 1:
		print("SIM_LOGIC FAIL first step")
		quit(1)
		return
	sim._step()
	print("after step 2 state=", sim._state, " frame=", sim._elapsed)
	if sim._state != "IDLE" or sim._elapsed != 0:
		print("SIM_LOGIC FAIL auto transition")
		quit(1)
		return
	sim._reset()
	print("SIM_LOGIC PASS")
	quit(0)
