extends SceneTree
func _initialize() -> void:
	var base := "/run/media/fabio/Dados/Fabio/godot_snes_genesis_engine/validation/projects/sidearms/port/data/stage1"
	var st := RetroStage.new()
	var err := st.load_snes(base + ".pic", base + ".map", base + ".pal", 240, 32, 8, 4, 16, true)
	print("load=", err, " map=", st.get_map_size(), " col=", st.get_column_major(), " pal=", st.get_palette().size())
	var img := st.render()
	print("render=", img.get_width() if img else -1, "x", img.get_height() if img else -1)
	img.save_png("/tmp/sidearms_stage1_preview.png")
	print("tile0=", st.get_tile_info(0,0))
	print("analyze=", st.analyze())
	quit(0)
