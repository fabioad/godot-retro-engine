extends SceneTree
var project: RetroProject
var rom_before := ""
func _initialize() -> void:
	_go.call_deferred()
func _go() -> void:
	var rootp := "/run/media/fabio/Dados/Fabio/godot_snes_genesis_engine/validation/projects/daniel_snes"
	project = RetroProject.new()
	var err := project.load(rootp + "/.retro/project.json")
	print("load project=", err, " path=", project.get_path())
	var chr := rootp + "/src/gen/bg1.chr"
	var map := rootp + "/src/gen/bg1.map"
	var pal := rootp + "/src/gen/bg1.pal"
	var bak := rootp + "/.retro/validation/edit_backup"
	DirAccess.make_dir_recursive_absolute(bak)
	for f in [chr, map, pal]:
		DirAccess.copy_absolute(f, bak.path_join(f.get_file()))
	var st := RetroStage.new()
	err = st.load_snes(chr, map, pal, 32, 32, 8, 4, 16, false)
	print("load stage=", err, " size=", st.get_map_size())
	var idx := st.get_tile_indices()
	print("indices=", idx.get_width(), "x", idx.get_height())
	var oldc := idx.get_pixel(8, 0)
	idx.set_pixel(8, 0, Color(1.0/255.0, 1.0/255.0, 1.0/255.0))
	st.set_tile_indices(idx)
	var ex := st.export_snes(chr.get_base_dir(), "bg1")
	print("export=", ex)
	rom_before = FileAccess.get_md5(project.get_rom_path())
	print("ROM before edit rebuild: ", rom_before)
	var b := RetroBuilder.new()
	get_root().add_child(b)
	var done := [false, {}]
	b.build_finished.connect(func(ok, res): done[0]=true; done[1]=res, CONNECT_DEFERRED)
	print("build start err=", b.build(project, "", true, false))
	while not done[0]:
		await process_frame
	var res: Dictionary = done[1]
	print("build success=", res.get("success"), " exit=", res.get("exit_code"), " errors=", res.get("error_count"), " rom=", res.get("rom_path"))
	var rom_after := FileAccess.get_md5(String(res.get("rom_path", "")))
	print("ROM after  edit rebuild: ", rom_after)
	print("ROM_CHANGED=", rom_before != rom_after)
	# restore the originals and rebuild to the baseline.
	for f in [chr, map, pal]:
		DirAccess.copy_absolute(bak.path_join(f.get_file()), f)
	var b2 := RetroBuilder.new()
	get_root().add_child(b2)
	var done2 := [false, {}]
	b2.build_finished.connect(func(ok, res2): done2[0]=true; done2[1]=res2, CONNECT_DEFERRED)
	b2.build(project, "", true, false)
	while not done2[0]:
		await process_frame
	var rom_restored := FileAccess.get_md5(project.get_rom_path())
	print("ROM restored rebuild: ", rom_restored, " matches_original=", rom_restored == rom_before)
	quit(0)
