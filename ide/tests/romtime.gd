extends SceneTree
func _initialize():
	var a="/run/media/fabio/Dados/Fabio/godot_snes_genesis_engine/validation/projects/kof98/kof98-snes.sfc"
	var b="/run/media/fabio/Dados/Fabio/godot_snes_genesis_engine/validation/projects/kof98/build/msu_chr_late_staging/kof98-snes.sfc"
	print(a, " m=", FileAccess.get_modified_time(a), " size=", FileAccess.get_size(a))
	print(b, " m=", FileAccess.get_modified_time(b), " size=", FileAccess.get_size(b))
	quit()
