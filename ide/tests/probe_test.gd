extends SceneTree
func _initialize():
	for p in [
		"/run/media/fabio/Dados/Fabio/godot_snes_genesis_engine/validation/projects/sgdk_image/out/rom.bin",
		"/run/media/fabio/Dados/Fabio/godot_snes_genesis_engine/validation/projects/daniel_snes/build/daniel-blue.sfc",
		"/run/media/fabio/Dados/Fabio/godot_snes_genesis_engine/validation/projects/kof98/kof98-snes.sfc"]:
		var r: Dictionary = RetroEmulator.probe_rom(p)
		print(p.get_file(), " -> ", r.get("platform"), " ", r.get("mapper"), " title=", r.get("title"), " valid=", r.get("checksum_valid"))
		for e in RetroEmulator.detect(String(r.get("platform",""))):
			print("   emu ", e.get("id"), " ", e.get("name"))
	quit()
