extends SceneTree
func _initialize() -> void:
	print("SDK=", RetroSDK.detect_all())
	var pal := PackedColorArray([Color(0,0,0,0), Color.RED, Color.GREEN, Color.BLUE])
	print("PAL_SNES=", RetroGraphics.encode_palette(pal, false).size())
	print("PAL_MD=", RetroGraphics.encode_palette(pal, true).size())
	print("LIMITS=", RetroHardware.specs("snes","mode1").get("mode"))
	print("EMU=", RetroEmulator.detect("snes"))
	quit(0)
