extends SceneTree
## Stage 9 regression: complete MUGEN state import, .cmd command sequences,
## expression-based HitDef damage, batch animation import and full graph build.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/opencode/mugen_import"
	for i in range(args.size()):
		if String(args[i]) == "--dir" and i + 1 < args.size():
			out = String(args[i + 1])
	var cns := "/run/media/fabio/Dados/Fabio/kof98_port_snes/assets/characters/Iori-KOF98/Iori_SNES.cns"
	var air := "/run/media/fabio/Dados/Fabio/kof98_port_snes/assets/characters/Iori-KOF98/Iori.air"
	var cmd := "/run/media/fabio/Dados/Fabio/kof98_port_snes/assets/characters/Iori-KOF98/Iori.cmd"
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.make_dir_recursive_absolute(out + "/md")

	var importer := RetroMugenImport.new()
	var parsed := importer.parse_states(cns, air)
	var commands := importer.parse_commands(cmd)
	var states: Array = parsed.get("states", [])
	var s200: Dictionary = {}
	for st in states:
		if int(st.get("number", -1)) == 200:
			s200 = st
			break
	var hd: Dictionary = s200.get("hitdef_data", {})
	print("PARSE ok=%s states=%d actions=%d commands=%d state200_hitdef=%d/%d hitstun=%d damage=%d" % [
		parsed.get("ok"), states.size(), int(parsed.get("air_action_count", 0)),
		int(commands.get("command_count", 0)),
		int(hd.get("hitstop_attacker", 0)), int(hd.get("hitstop_defender", 0)),
		int(hd.get("hitstun", 0)), int(hd.get("damage", 0))])

	var anim := RetroAnimation.new()
	anim.set_name("mugen_import_test")
	var imported := importer.import_state(cns, air, 200, anim, "ATTACK")
	print("IMPORT ok=%s frames=%d hitboxes=%d hurtboxes=%d" % [
		imported.get("ok"), int(Dictionary(imported.get("import", {})).get("frames", 0)),
		int(Dictionary(imported.get("import", {})).get("hit_boxes", 0)),
		int(Dictionary(imported.get("import", {})).get("hurt_boxes", 0))])

	var auto := importer.auto_map_states(parsed)
	var mapping: Dictionary = auto.get("mapping", {})
	print("AUTOMAP ok=%s mapped=%d" % [auto.get("ok"), mapping.size()])

	var batch := RetroAnimation.new()
	batch.set_name("mugen_batch_test")
	var imported_all := importer.import_mapped_states(parsed, mapping, batch, air)
	print("IMPORT_ALL ok=%s states=%d frames=%d hitboxes=%d hurtboxes=%d animation_states=%d" % [
		imported_all.get("ok"), int(imported_all.get("states", 0)),
		int(imported_all.get("frames", 0)), int(imported_all.get("hit_boxes", 0)),
		int(imported_all.get("hurt_boxes", 0)), batch.get_states().size()])

	var input := RetroInputMap.new()
	input.setup_defaults("snes")
	var built := importer.build_fight_graph(parsed, mapping, input, 0, commands.get("commands", {}))
	var graph: RetroStateGraph = built.get("graph")
	var moves: Array = built.get("moves", [])
	var command_transitions := 0
	var sequence_conditions := 0
	var auto_transitions := 0
	for t in graph.get_transitions():
		if bool(t.get("auto", false)):
			auto_transitions += 1
		else:
			command_transitions += 1
		for c in Array(t.get("conditions", [])):
			if Dictionary(c).has("sequence"):
				sequence_conditions += 1
	var move_with_hitstop := 0
	var move_with_pushback := 0
	var move_with_hit_id := 0
	for m in moves:
		if int(m.get("hitstop_attacker", 0)) > 0:
			move_with_hitstop += 1
		if int(m.get("pushback", 0)) > 0:
			move_with_pushback += 1
		if int(m.get("hit_id", 0)) > 0:
			move_with_hit_id += 1
	print("GRAPH ok=%s nodes=%d transitions=%d command=%d auto=%d sequences=%d moves=%d hitstop_moves=%d warnings=%d" % [
		built.get("ok"), int(built.get("node_count", 0)), int(built.get("transition_count", 0)),
		command_transitions, auto_transitions, sequence_conditions, moves.size(), move_with_hitstop,
		Array(built.get("warnings", [])).size()])
	var validation := graph.validate(input)
	print("VALIDATE ok=%s errors=%d warnings=%d" % [
		validation.get("ok"), Array(validation.get("errors", [])).size(),
		Array(validation.get("warnings", [])).size()])

	var graph_snes := graph.export_snes(out, "retro_state_machine", input)
	var graph_md := graph.export_sgdk(out + "/md", "retro_state_machine", input)
	var graph_json := graph.save(out + "/mugen_graph.json")
	var rt := RetroCollisionRuntime.new()
	rt.setup_from_animation(batch)
	rt.set_moves(moves)
	var col_snes := rt.export_snes(out, "retro_collision", batch)
	var col_md := rt.export_sgdk(out + "/md", "retro_collision", batch)

	var ok := bool(parsed.get("ok", false)) \
		and states.size() == 259 \
		and int(commands.get("command_count", 0)) >= 40 \
		and String(Dictionary(Dictionary(commands.get("commands", {})).get("holdfwd", {})).get("steps", [{}])[0].get("mode", "")) == "held" \
		and int(s200.get("hitdef_count", 0)) >= 1 \
		and int(hd.get("damage", 0)) > 0 \
		and int(hd.get("hitstop_attacker", 0)) == 11 \
		and int(hd.get("hitstop_defender", 0)) == 13 \
		and int(hd.get("hitstun", 0)) == 9 \
		and bool(imported.get("ok", false)) \
		and int(Dictionary(imported.get("import", {})).get("frames", 0)) == 5 \
		and bool(auto.get("ok", false)) \
		and mapping.size() >= 250 \
		and bool(imported_all.get("ok", false)) \
		and int(imported_all.get("states", 0)) >= 200 \
		and batch.get_states().size() >= 200 \
		and bool(built.get("ok", false)) \
		and int(built.get("node_count", 0)) >= 250 \
		and int(built.get("transition_count", 0)) >= 50 \
		and command_transitions > 0 \
		and sequence_conditions > 0 \
		and auto_transitions > 0 \
		and move_with_hitstop > 0 \
		and move_with_pushback > 0 \
		and move_with_hit_id > 0 \
		and bool(validation.get("ok", false)) \
		and bool(graph_snes.get("ok", false)) \
		and bool(graph_md.get("ok", false)) \
		and graph_json == OK \
		and bool(col_snes.get("ok", false)) \
		and bool(col_md.get("ok", false))
	print("FILES graph=%s collision=%s" % [graph_snes.get("source"), col_snes.get("source")])
	if ok:
		print("MUGEN_IMPORT PASS")
		quit(0)
	else:
		print("MUGEN_IMPORT FAIL")
		quit(1)
