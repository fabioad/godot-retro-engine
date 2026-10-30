extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var platform := "snes"
	var dir := "/tmp/opencode/graph_snes"
	for i in range(args.size()):
		if String(args[i]) == "--platform" and i + 1 < args.size(): platform = String(args[i + 1])
		if String(args[i]) == "--dir" and i + 1 < args.size(): dir = String(args[i + 1])
	var im := RetroInputMap.new()
	im.setup_defaults(platform)
	var durs: Array = []
	for i in range(im.get_states().size()):
		durs.append(0)
	durs[im.get_states().find("WALK")] = 2
	durs[im.get_states().find("ATTACK")] = 2
	durs[im.get_states().find("SUPER")] = 2
	im.set_state_durations(durs)
	var g := RetroStateGraph.new()
	g.setup_from_input_map(im)
	var idle := ""; var walk := ""; var attack := ""; var special := ""
	for n in g.get_nodes():
		match String(n.get("state", "")):
			"IDLE": idle = String(n.get("id", ""))
			"WALK": walk = String(n.get("id", ""))
			"ATTACK": attack = String(n.get("id", ""))
			"SPECIAL": special = String(n.get("id", ""))
	for t in g.get_transitions():
		if String(t.get("from", "")) == idle and String(t.get("to", "")) == walk:
			g.update_transition(String(t.get("id", "")), {"cooldown": 3})
	g.add_transition({"from": walk, "to": attack,
		"conditions": [{"action":"attack_a","mode":"pressed"},{"action":"left","mode":"held"}],
		"op": "all", "cooldown": 0, "priority": 10, "auto": false})
	# MUGEN-style command sequence: down, right, attack within 20 frames.
	g.add_transition({"from": walk, "to": special,
		"conditions": [{"sequence": [
			{"actions":["down"],"mode":"pressed"},
			{"actions":["right"],"mode":"pressed"},
			{"actions":["attack_a"],"mode":"pressed"}], "window": 20}],
		"op": "all", "cooldown": 0, "priority": 5, "auto": false})
	var v := g.validate(im)
	print("GRAPH_VALIDATE ", v)
	var result: Dictionary
	if platform == "snes":
		result = g.export_snes(dir, "retro_state_machine", im)
	else:
		result = g.export_sgdk(dir, "retro_state_machine", im)
	print("GRAPH_EXPORT ", result)
	quit(0 if bool(v.get("ok", false)) else 1)
