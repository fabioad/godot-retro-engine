extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/opencode/hit_test"
	for i in range(args.size()):
		if String(args[i]) == "--dir" and i + 1 < args.size(): out = String(args[i + 1])
	var a := RetroAnimation.new()
	a.set_name("hit_test")
	a.add_frame("ATTACK", 0, 4)
	a.add_frame("ATTACK", 1, 4)
	a.add_hitbox("ATTACK", 0, Rect2i(4, 4, 16, 16), "hit")
	a.add_hitbox("ATTACK", 0, Rect2i(0, 0, 24, 32), "hurt")
	a.add_hitbox("ATTACK", 1, Rect2i(8, 0, 20, 12), "hit")
	var boxes := a.get_frame_hitboxes("ATTACK", 0)
	var hit := a.collision_test("ATTACK", 0, Vector2i(0,0), "ATTACK", 0, Vector2i(10,4))
	var miss := a.collision_test("ATTACK", 0, Vector2i(0,0), "ATTACK", 0, Vector2i(100,100))
	DirAccess.make_dir_recursive_absolute(out)
	var snes := a.export_hitboxes_snes(out + "/hit.inc", "hit_test")
	var md := a.export_hitboxes_sgdk(out + "/hit.h", "hit_test")
	print("HITBOX boxes=", boxes.size(), " hit=", hit.get("hit"), " miss=", miss.get("hit"), " snes=", snes.get("count"), " md=", md.get("count"))
	var ok := boxes.size() == 2 and bool(hit.get("hit", false)) and not bool(miss.get("hit", true)) and int(snes.get("count", 0)) == 3 and int(md.get("count", 0)) == 3
	if not ok:
		print("HITBOX LOGIC FAIL")
		quit(1)
	else:
		print("HITBOX LOGIC PASS")
		quit(0)
