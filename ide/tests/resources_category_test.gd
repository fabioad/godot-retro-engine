extends SceneTree
## Image categories: alpha -> sprite, strip dimensions -> sprite, tile/bg/stage
## names or a companion map -> Tiles/Stages; truly generic images -> Images.

const RetroMain = preload("res://addons/retro_engine/retro_main.gd")

func _initialize() -> void:
	await process_frame
	var ok := true
	var cases := [
		[{"editor": "sprite", "ext": "png", "editable": true}, "Sprites"],
		[{"editor": "sprite", "ext": "chr", "editable": true}, "Sprites"],
		[{"editor": "image", "ext": "png", "editable": true, "rel_path": "res/logo.png"}, "Images"],
		[{"editor": "image", "ext": "jpg", "editable": true, "rel_path": "res/frame.jpg"}, "Images"],
		[{"editor": "image", "ext": "png", "editable": true, "has_alpha": true, "rel_path": "res/hero.png"}, "Sprites"],
		[{"editor": "image", "ext": "png", "editable": true, "width": 128, "height": 256, "rel_path": "res/ghost.png"}, "Sprites"],
		[{"editor": "image", "ext": "png", "editable": true, "width": 432, "height": 32, "rel_path": "res/daniel.png"}, "Sprites"],
		[{"editor": "image", "ext": "png", "editable": true, "width": 256, "height": 256, "rel_path": "res/bg.png"}, "Tiles"],
		[{"editor": "image", "ext": "png", "editable": true, "rel_path": "res/level/deco_tileset.png"}, "Tiles"],
		[{"editor": "none", "ext": "png", "editable": true, "rel_path": "res/mystery.png"}, "Images"],
		[{"editor": "stage", "ext": "png", "editable": true, "rel_path": "res/tiles.png"}, "Tiles"],
		[{"editor": "stage", "ext": "png", "editable": true, "map_path": "res/tiles.map"}, "Stages"],
		[{"editor": "stage", "ext": "map", "editable": true}, "Stages"],
		[{"editor": "palette", "ext": "pal", "editable": true}, "Palettes"],
		[{"editor": "audio", "ext": "mid", "editable": true}, "Audio"],
		[{"editor": "code", "ext": "c", "editable": true}, "Code"],
		[{"editor": "none", "ext": "bin", "editable": false}, "Read-only"],
		[{"editor": "none", "ext": "json", "editable": true}, "Other"],
	]
	for c in cases:
		var got := RetroMain.resource_category(c[0])
		if got != String(c[1]):
			ok = false
			print("RESOURCE_CATEGORY FAIL ", c[0], " -> ", got, " expected ", c[1])
	print("RESOURCE_CATEGORY ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
