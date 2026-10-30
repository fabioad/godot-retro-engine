extends SceneTree
## Native Godot -> retro asset bridge regression.

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/opencode/native_project"
	for i in range(args.size()):
		if String(args[i]) == "--dir" and i + 1 < args.size():
			out = String(args[i + 1])
	var editor = preload("res://addons/retro_engine/native_bridge.gd").new()
	get_root().add_child(editor)
	await process_frame
	var project := RetroProject.new()
	project.set_name("native_test")
	project.set_path(out.path_join("project"))
	project.set_platform("snes")
	editor.set_context(project, "snes", "mode1")

	var root := Node2D.new()
	root.name = "hero_scene"
	var sprite := Sprite2D.new()
	sprite.name = "Hero"
	var img := Image.create_empty(32, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(16):
		for x in range(32):
			img.set_pixel(x, y, Color(1, 0, 0, 1) if x < 16 else Color(0, 0, 1, 1))
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.hframes = 2
	sprite.vframes = 1
	root.add_child(sprite)

	var animated := AnimatedSprite2D.new()
	animated.name = "HeroAnim"
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for name in ["idle", "walk"]:
		sf.add_animation(name)
		for i in range(2):
			var fi := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
			fi.fill(Color(1, 1, 0, 1) if i == 0 else Color(0, 1, 1, 1))
			sf.add_frame(name, ImageTexture.create_from_image(fi), 0.1)
	animated.sprite_frames = sf
	root.add_child(animated)

	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position = Vector2(100, 80)
	root.add_child(camera)
	var shape_node := CollisionShape2D.new()
	shape_node.name = "Floor"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(64, 8)
	shape_node.shape = shape
	shape_node.position = Vector2(32, 100)
	root.add_child(shape_node)
	var mesh := MeshInstance3D.new()
	mesh.name = "Cube3D"
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)

	var tile_image := Image.create_empty(16, 8, false, Image.FORMAT_RGBA8)
	tile_image.fill(Color(0.2, 0.5, 0.2, 1))
	tile_image.fill_rect(Rect2i(8, 0, 8, 8), Color(0.5, 0.3, 0.1, 1))
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(8, 8)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(tile_image)
	atlas.texture_region_size = Vector2i(8, 8)
	atlas.create_tile(Vector2i(0, 0))
	atlas.create_tile(Vector2i(1, 0))
	tile_set.add_source(atlas, 0)
	var layer := TileMapLayer.new()
	layer.name = "Ground"
	layer.tile_set = tile_set
	layer.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))
	layer.set_cell(Vector2i(1, 0), 0, Vector2i(1, 0))
	root.add_child(layer)

	var label := Label.new()
	label.name = "Title"
	label.text = "Hello SNES"
	label.position = Vector2(8, 8)
	label.size = Vector2(140, 24)
	root.add_child(label)
	var button := Button.new()
	button.name = "StartButton"
	button.text = "Start"
	button.position = Vector2(8, 40)
	button.size = Vector2(90, 28)
	root.add_child(button)
	var marker := Marker2D.new()
	marker.name = "Spawn"
	marker.position = Vector2(64, 72)
	root.add_child(marker)
	var area := Area2D.new()
	area.name = "Trigger"
	area.position = Vector2(120, 72)
	root.add_child(area)

	# Export a real GDScript so the port bundle can list methods/signals and
	# copy the source for the C port.
	var script_path := "user://native_bridge_test_script.gd"
	var script_file := FileAccess.open(script_path, FileAccess.WRITE)
	if script_file:
		script_file.store_string("extends Node2D\n@export var speed: int = 100\nsignal hit\nfunc jump() -> void:\n\tpass\n")
		script_file.close()
		var script = load(script_path)
		if script:
			root.set_script(script)
	get_root().add_child(root)

	editor.set_3d_profile("superfx")
	var result: Dictionary = await editor.import_scene(root)
	print("NATIVE ok=", result.get("ok"), " actors=", result.get("actors"),
		" assets=", Array(result.get("assets", [])).size(), " dir=", result.get("directory"))
	for a in result.get("assets", []):
		print("ASSET ", a.get("name"), " type=", a.get("type"), " asset=", String(a.get("asset", "")).get_file(), " anim=", String(a.get("animation", "")).get_file())
	var dir := String(result.get("directory", ""))
	var checks := {
		"hero_png": FileAccess.file_exists(dir.path_join("hero.png")),
		"hero_chr": FileAccess.file_exists(dir.path_join("hero.chr")),
		"hero_anim": FileAccess.file_exists(dir.path_join("heroanim.retro_animation.json")),
		"scene_header": FileAccess.file_exists(dir.path_join("hero_scene_scene.h")),
		"scene_json": FileAccess.file_exists(dir.path_join("hero_scene_scene.json")),
		"superfx_header": FileAccess.file_exists(dir.path_join("hero_scene_3d_profile.h")),
		"superfx_json": FileAccess.file_exists(dir.path_join("hero_scene_3d_profile.json")),
		"handoff_md": FileAccess.file_exists(dir.path_join("3D_HANDOFF.md")),
		"handoff_json": FileAccess.file_exists(dir.path_join("3d_handoff.json")),
	}
	print("FILES ", checks)
	var port: Dictionary = result.get("port", {})
	var port_json := String(port.get("json", ""))
	var port_header := String(port.get("header", ""))
	var port_md := String(port.get("markdown", ""))
	var port_data: Dictionary = {}
	if FileAccess.file_exists(port_json):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(port_json))
		if typeof(parsed) == TYPE_DICTIONARY:
			port_data = parsed
	var port_widgets: Array = port_data.get("widgets", [])
	var port_nodes: Array = port_data.get("nodes", [])
	var port_scripts: Array = port_data.get("scripts", [])
	var port_script_copy := ""
	if not port_scripts.is_empty():
		port_script_copy = String(Dictionary(port_scripts[0]).get("exported_script", ""))
	var port_script_copy_abs := port_script_copy
	if not port_script_copy.is_empty() and not port_script_copy.is_absolute_path() and not port_script_copy.begins_with("res://") and not port_script_copy.begins_with("user://"):
		port_script_copy_abs = project.get_path().path_join(port_script_copy)
	var port_header_text := FileAccess.get_file_as_string(port_header) if FileAccess.file_exists(port_header) else ""
	var port_md_text := FileAccess.get_file_as_string(port_md) if FileAccess.file_exists(port_md) else ""
	var port_checks := {
		"json": FileAccess.file_exists(port_json),
		"header": FileAccess.file_exists(port_header),
		"markdown": FileAccess.file_exists(port_md),
		"script_copy": FileAccess.file_exists(port_script_copy_abs),
		"widgets": port_widgets.size() >= 2,
		"nodes": port_nodes.size() >= 8,
		"scripts": port_scripts.size() >= 1,
		"header_text": port_header_text.contains("Hello SNES") and port_header_text.contains("retro_port_widgets"),
		"methods": port_md_text.contains("jump") and port_md_text.contains("UI widgets") and port_md_text.contains("Other nodes"),
	}
	print("PORT ok=", port.get("ok"), " widgets=", port_widgets.size(), " nodes=", port_nodes.size(),
		" scripts=", port_scripts.size(), " checks=", port_checks)
	# Game Build copies the port bundle into the generated project so the
	# UI/node/script manifest travels with the ROM project.
	var GameBuild = preload("res://addons/retro_engine/game_build.gd")
	var game_port_dir := out.path_join("game_port")
	var game_port: Dictionary = GameBuild._copy_native_port(port, game_port_dir)
	var game_port_checks := {
		"ok": bool(game_port.get("ok", false)),
		"header": FileAccess.file_exists(String(game_port.get("header", ""))),
		"json": FileAccess.file_exists(String(game_port.get("json", ""))),
		"porting_md": FileAccess.file_exists(game_port_dir.path_join("PORTING.md")),
		"scripts": FileAccess.file_exists(game_port_dir.path_join("port").path_join("scripts").path_join("native_bridge_test_script.gd")),
	}
	print("GAME_PORT ", game_port_checks)
	var game_build_dir := out.path_join("builds")
	var game_result: Dictionary = GameBuild.generate("native_snes", project, game_build_dir, "native_port_demo", false, "")
	var game_port_result: Dictionary = game_result.get("port", {})
	var game_build_checks := {
		"ok": bool(game_result.get("ok", false)),
		"port_header": FileAccess.file_exists(String(game_port_result.get("header", ""))),
		"porting_md": FileAccess.file_exists(String(game_result.get("directory", "")).path_join("PORTING.md")),
		"port_scripts": FileAccess.file_exists(String(game_result.get("directory", "")).path_join("port").path_join("scripts").path_join("native_bridge_test_script.gd")),
	}
	print("GAME_BUILD_PORT ", game_build_checks)
	# A rendered scene/background goes through the same bridge into a native
	# console tilemap (SNES .chr/.pal/.map + SGDK .res).
	var bg := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			bg.set_pixel(x, y, Color(0.1, 0.2, 0.4, 1) if ((x / 8) + (y / 8)) % 2 == 0 else Color(0.2, 0.4, 0.8, 1))
	var stage: Dictionary = editor.bridge.import_stage_image(bg, "native_bg", dir, "snes", "mode1", 8, 1024, 16, "res://demo.tscn")
	var stage_checks := {
		"stage_chr": FileAccess.file_exists(dir.path_join("native_bg.chr")),
		"stage_map": FileAccess.file_exists(dir.path_join("native_bg.map")),
		"stage_pal": FileAccess.file_exists(dir.path_join("native_bg.pal")),
		"stage_inc": FileAccess.file_exists(dir.path_join("native_bg_stage.inc")),
		"tilemap_map": FileAccess.file_exists(dir.path_join("ground_stage.map")),
		"tilemap_chr": FileAccess.file_exists(dir.path_join("ground_stage.chr")),
		"tilemap_json": FileAccess.file_exists(dir.path_join("ground_stage.retro_stage.json")),
	}
	editor._bake_frames.value = 8
	var baked: Dictionary = await editor.import_scene(root, false, true)
	var bake_checks := {
		"bake_png": FileAccess.file_exists(dir.path_join("hero_scene_bake.png")),
		"bake_anim": FileAccess.file_exists(dir.path_join("hero_scene_bake.retro_animation.json")),
	}
	var root2d := Node2D.new()
	root2d.name = "flat_scene"
	var flat := Sprite2D.new()
	flat.texture = ImageTexture.create_from_image(img)
	root2d.add_child(flat)
	get_root().add_child(root2d)
	var captured: Dictionary = await editor.import_scene(root2d, true, false)
	var flat_dir := String(captured.get("directory", ""))
	var capture_checks := {
		"capture_map": FileAccess.file_exists(flat_dir.path_join("flat_scene_bg.map")),
		"capture_chr": FileAccess.file_exists(flat_dir.path_join("flat_scene_bg.chr")),
	}
	print("STAGE ", stage.get("ok"), " tiles=", stage.get("tiles"), " map=", stage.get("map_w"), "x", stage.get("map_h"), " checks=", stage_checks)
	print("BAKE ", baked.get("bake", {}).get("frames"), " checks=", bake_checks)
	print("CAPTURE2D ", captured.get("stage", {}).get("tiles"), " checks=", capture_checks)
	var svp: Dictionary = editor.bridge.export_3d_manifest("svp",
		{"name": "native3d", "source": "res://demo/native3d.tscn", "width": 320, "height": 224},
		result.get("assets", []), {"frames": 8}, dir.path_join("svp_profile.h"))
	print("PROFILES superfx=", editor.get_3d_profile().get("id"), " svp=", Dictionary(svp.get("profile", {})).get("id"),
		" svp_header=", FileAccess.file_exists(dir.path_join("svp_profile.h")))
	var resources := project.get_resources()
	print("RESOURCES ", resources.size(), " native=", project.get_path())
	print("NATIVE_DIR ", dir)
	root.free()
	root2d.free()
	editor.queue_free()
	await process_frame
	var ok := bool(result.get("ok", false)) and Array(result.get("assets", [])).size() >= 5 and checks.values().all(func(v): return bool(v)) and bool(port.get("ok", false)) and port_checks.values().all(func(v): return bool(v)) and game_port_checks.values().all(func(v): return bool(v)) and game_build_checks.values().all(func(v): return bool(v)) and bool(stage.get("ok", false)) and stage_checks.values().all(func(v): return bool(v)) and bool(baked.get("ok", false)) and int(Dictionary(baked.get("bake", {})).get("frames", 0)) == 8 and bake_checks.values().all(func(v): return bool(v)) and bool(captured.get("ok", false)) and capture_checks.values().all(func(v): return bool(v)) and bool(svp.get("ok", false)) and String(project.get_metadata().get("3d_profile", "")) == "superfx"
	if ok:
		print("NATIVE_BRIDGE PASS")
		quit(0)
	else:
		print("NATIVE_BRIDGE FAIL")
		quit(1)
