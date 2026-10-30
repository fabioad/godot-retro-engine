extends SceneTree
## Drives the actual MUGEN wizard widgets and applies the generated graph and
## move profiles to the real StateGraph / Hitbox editors.

func _initialize() -> void:
	await process_frame
	var mugen = preload("res://addons/retro_engine/mugen_editor.gd").new()
	var state_graph = preload("res://addons/retro_engine/state_graph_editor.gd").new()
	var collision = preload("res://addons/retro_engine/collision_editor.gd").new()
	get_root().add_child(mugen)
	get_root().add_child(state_graph)
	get_root().add_child(collision)
	await process_frame

	var input := RetroInputMap.new()
	input.setup_defaults("snes")
	var anim := RetroAnimation.new()
	anim.set_name("ui_test")
	var project := RetroProject.new()
	mugen.set_context(project, "snes", anim, input)
	mugen._cns_path = "/run/media/fabio/Dados/Fabio/kof98_port_snes/assets/characters/Iori-KOF98/Iori_SNES.cns"
	mugen._air_path = "/run/media/fabio/Dados/Fabio/kof98_port_snes/assets/characters/Iori-KOF98/Iori.air"
	mugen._cmd_path = "/run/media/fabio/Dados/Fabio/kof98_port_snes/assets/characters/Iori-KOF98/Iori.cmd"
	mugen._parse()
	mugen._auto_map()
	var captured := {"graph": null, "moves": [], "batch": 0}
	mugen.graph_built.connect(func(g, m):
		captured["graph"] = g
		captured["moves"] = m)
	mugen.states_imported.connect(func(count): captured["batch"] = count)
	mugen._build_graph()
	await process_frame
	mugen._import_all()
	await process_frame

	var captured_graph: RetroStateGraph = captured["graph"]
	var captured_moves: Array = captured["moves"]
	var ok := int(captured["batch"]) >= 200 and anim.get_states().size() >= 200
	ok = ok and mugen._commands.size() >= 40
	if captured_graph == null:
		ok = false
	elif captured_graph.get_nodes().size() < 5 or captured_graph.get_transitions().size() < 5:
		ok = false
	if captured_moves.is_empty():
		ok = false
	if ok:
		state_graph.set_context(project, "snes", input, anim)
		state_graph.replace_graph(captured_graph)
		collision.set_context(project, "snes", null, anim)
		collision.apply_moves(captured_moves)
		ok = state_graph.graph.get_nodes().size() == captured_graph.get_nodes().size()
		ok = ok and not collision.collision_runtime.get_move(String(captured_moves[0].get("state", ""))).is_empty()
	var built_info: String = mugen._build_info.text
	print("MUGEN_UI nodes=%d transitions=%d moves=%d batch=%d commands=%d animation_states=%d graph_tab=%d info=%s" % [
		captured_graph.get_nodes().size() if captured_graph else 0,
		captured_graph.get_transitions().size() if captured_graph else 0,
		captured_moves.size(), int(captured["batch"]), mugen._commands.size(), anim.get_states().size(),
		state_graph.graph.get_nodes().size() if state_graph.graph else 0,
		not built_info.is_empty()])
	if ok:
		print("MUGEN_UI PASS")
		quit(0)
	else:
		print("MUGEN_UI FAIL")
		quit(1)
