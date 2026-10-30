extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/opencode/air_test"
	for i in range(args.size()):
		if String(args[i]) == "--dir" and i + 1 < args.size(): out = String(args[i + 1])
	var io := RetroHitboxIO.new()
	var air := io.parse_air("/run/media/fabio/Dados/Fabio/kof98_port_snes/assets/characters/Iori-KOF98/Iori.air")
	var target: Dictionary = {}
	for a in air.get("actions", []):
		for f in a.get("frames", []):
			if Array(f.get("clsn1", [])).size() > 0:
				target = a
				break
		if not target.is_empty(): break
	var anim := RetroAnimation.new()
	anim.set_name("iori_attack")
	var imp := io.import_air_action(int(target.get("action", 0)), anim, "ATTACK")
	DirAccess.make_dir_recursive_absolute(out)
	var air_out := io.export_air(anim, "ATTACK", int(target.get("action", 0)), out + "/iori_attack.air")
	var roundtrip := io.parse_air(out + "/iori_attack.air")
	var hb_snes := anim.export_hitboxes_snes(out + "/iori_hitboxes.inc", "iori")
	var hb_md := anim.export_hitboxes_sgdk(out + "/iori_hitboxes.h", "iori")
	var cns := io.parse_cns("/run/media/fabio/Dados/Fabio/kof98_port_snes/assets/characters/Iori-KOF98/Iori_SNES.cns")
	var rt := RetroCollisionRuntime.new()
	rt.setup_from_animation(anim)
	var defs: Array = cns.get("hitdefs", [])
	if not defs.is_empty():
		rt.apply_hitdef("ATTACK", defs[0])
	var col_snes := rt.export_snes(out, "retro_collision", anim)
	var col_md := rt.export_sgdk(out + "/md", "retro_collision", anim)
	var ok := bool(imp.get("ok", false)) and int(imp.get("frames", 0)) == 5 and int(imp.get("hit_boxes", 0)) >= 1 and int(air.get("action_count", 0)) > 0 and int(cns.get("hitdef_count", 0)) > 0 and bool(air_out.get("ok", false)) and bool(roundtrip.get("ok", false)) and bool(col_snes.get("ok", false)) and bool(col_md.get("ok", false))
	print("AIR_CNS actions=", air.get("action_count"), " action=", target.get("action"), " import=", imp, " cns=", cns.get("hitdef_count"), " boxes=", hb_snes.get("count"))
	if ok:
		print("AIR_CNS PASS")
		quit(0)
	else:
		print("AIR_CNS FAIL")
		quit(1)
