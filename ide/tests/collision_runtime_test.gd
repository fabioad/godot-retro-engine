extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/opencode/col_test"
	for i in range(args.size()):
		if String(args[i]) == "--dir" and i + 1 < args.size(): out = String(args[i + 1])
	var a := RetroAnimation.new()
	a.set_name("runtime_test")
	a.add_frame("ATTACK", 0, 4)
	a.add_hitbox("ATTACK", 0, Rect2i(4, 4, 16, 16), "hit")
	a.add_hitbox("ATTACK", 0, Rect2i(0, 0, 24, 32), "hurt")
	a.add_frame("BLOCK", 0, 4)
	a.add_hitbox("BLOCK", 0, Rect2i(0, 0, 24, 32), "hurt")
	var rt := RetroCollisionRuntime.new()
	rt.setup_from_animation(a)
	rt.set_move("ATTACK", {"damage": 12, "hitstop_attacker": 5, "hitstop_defender": 9, "hitstun": 18, "blockstun": 7, "invuln": 10, "guard": true, "hit_id": 7, "pushback": 4})
	print("moves=", rt.get_moves().size(), " attack=", rt.get_move("ATTACK"))
	DirAccess.make_dir_recursive_absolute(out)
	print("snes=", rt.export_snes(out, "retro_collision", a))
	print("md=", rt.export_sgdk(out, "retro_collision", a))
	quit()
