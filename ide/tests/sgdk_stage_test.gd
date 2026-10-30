extends SceneTree
func _initialize() -> void:
	var out := "/tmp/opencode/retro_stage_md"
	DirAccess.make_dir_recursive_absolute(out)
	var tiles := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	tiles.fill(Color(0,0,0,0))
	var cols := [Color("#101020"), Color("#e04040"), Color("#40c060"), Color("#4060e0")]
	for t in range(4):
		for y in range(8):
			for x in range(8):
				tiles.set_pixel((t % 2) * 8 + x, (t / 2) * 8 + y, cols[t])
	var st := RetroStage.new()
	st.set_platform("megadrive")
	st.set_mode("h40")
	st.set_tileset(tiles)
	st.set_palette(PackedColorArray(cols))
	st.set_tile_size(8)
	st.set_tiles_x(2)
	st.set_bpp(4)
	st.set_map_size(Vector2i(4, 4))
	var m := PackedByteArray()
	m.resize(4 * 4 * 2)
	for i in range(16):
		var v := i % 4
		m[i * 2] = v & 0xFF
		m[i * 2 + 1] = (v >> 8) & 0xFF
	st.set_map(m)
	var r: Dictionary = st.export_sgdk(out, "retro_stage")
	print("stage export=", r)
	var args := PackedStringArray(["-jar", "/run/media/fabio/Dados/Fabio/sgdk211/bin/rescomp.jar", out + "/retro_stage.res", out + "/retro_stage.s", "-dep", out + "/retro_stage.o"])
	var code := OS.execute("java", args, [], true)
	print("rescomp stage exit=", code, " h=", FileAccess.file_exists(out + "/retro_stage.h"), " s=", FileAccess.file_exists(out + "/retro_stage.s"))
	print(FileAccess.get_file_as_string(out + "/retro_stage.res"))
	quit(0)
