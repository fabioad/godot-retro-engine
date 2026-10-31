extends SceneTree
## Raw PNG/JPG assets belong to Images; only editor=="sprite" is a game sprite.

const RetroMain = preload("res://addons/retro_engine/retro_main.gd")

func _initialize() -> void:
	await process_frame
	var ok := true
	var cases := [
		[{"editor": "sprite", "ext": "png", "editable": true}, "Sprites"],
		[{"editor": "sprite", "ext": "chr", "editable": true}, "Sprites"],
		[{"editor": "image", "ext": "png", "editable": true}, "Images"],
		[{"editor": "image", "ext": "jpg", "editable": true}, "Images"],
		[{"editor": "none", "ext": "png", "editable": true}, "Images"],
		[{"editor": "none", "ext": "webp", "editable": true}, "Images"],
		[{"editor": "stage", "ext": "png", "editable": true}, "Stages"],
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
