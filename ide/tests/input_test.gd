extends SceneTree
func _initialize() -> void:
	var m := RetroInputMap.new()
	m.setup_defaults("snes")
	print("actions=", m.get_actions().size(), " states=", m.get_states().size())
	print("left snes mask=", m.action_mask("left","snes"), " text=", m.mask_text("left","snes"))
	print("attack_a md mask=", m.action_mask("attack_a","megadrive"), " text=", m.mask_text("attack_a","megadrive"))
	print("validate=", m.validate())
	var d := "/tmp/opencode/input_export"
	DirAccess.make_dir_recursive_absolute(d)
	print("snes h=", m.export_snes_header(d + "/retro_input.h"))
	print("snes inc=", m.export_snes_inc(d + "/retro_input.inc"))
	print("md h=", m.export_sgdk_header(d + "/retro_input_md.h"))
	print("save=", m.save(d + "/input_map.json"))
	var m2 := RetroInputMap.new()
	print("load=", m2.load(d + "/input_map.json"), " actions=", m2.get_actions().size())
	m.add_action({"id":"dash_double","label":"Dash","snes":["Right","Right"],"md":["Right","Right"],"state":"WALK"})
	print("custom validate=", m.validate())
	quit()
