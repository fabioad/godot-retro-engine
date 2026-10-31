extends SceneTree
## Animation/Stage preview regression: real frame sampling, sprite-sheet
## fallback, parallax layer offsets and stage playback.

const AnimPreview = preload("res://addons/retro_engine/anim_preview.gd")
const StageCanvas = preload("res://addons/retro_engine/stage_canvas.gd")
const StageEditor = preload("res://addons/retro_engine/stage_editor.gd")
const SpriteSheet = preload("res://addons/retro_engine/sprite_sheet.gd")
const AnimationEditor = preload("res://addons/retro_engine/animation_editor.gd")

var ok := true

func _initialize() -> void:
	await process_frame
	var sprite := _make_sprite()
	var animation := _make_animation()
	_test_animation(sprite, animation)
	_test_sheet_auto_split()
	await _test_animation_editor()
	await _test_stage(sprite, animation)
	await _test_flat_stage()
	print("PREVIEW_TEST ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _check(name: String, condition: bool, detail := "") -> void:
	if not condition:
		ok = false
	print("PREVIEW ", name, " ", "PASS" if condition else "FAIL", (" " + detail) if detail != "" else "")

func _make_sprite() -> RetroSprite:
	var sprite := RetroSprite.new()
	sprite.set_platform("snes")
	var image := Image.create_empty(64, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for i in range(4):
		image.fill_rect(Rect2i(i * 16, 0, 16, 16), Color(0.1 + i * 0.2, 0.7, 0.3, 1.0))
	sprite.set_image(image)
	for i in range(4):
		sprite.add_frame("frame_%d" % i, Rect2i(i * 16, 0, 16, 16), 4)
	sprite.set_origin(Vector2i(8, 16))
	return sprite

func _make_animation() -> RetroAnimation:
	var animation := RetroAnimation.new()
	animation.set_fps(60)
	var states := animation.get_states()
	for key in states.keys():
		var st: Dictionary = states[key]
		st["frames"] = []
		states[key] = st
	var walk: Dictionary = states["WALK"]
	walk["loop"] = true
	walk["frames"] = []
	for i in range(4):
		walk["frames"].append({
			"sprite_frame": i,
			"duration": 4,
			"rect": Rect2i(i * 16, 0, 16, 16),
			"hitboxes": [],
			"events": [],
		})
	states["WALK"] = walk
	animation.set_states(states)
	return animation

func _test_animation(sprite: RetroSprite, animation: RetroAnimation) -> void:
	var preview = AnimPreview.new()
	get_root().add_child(preview)
	preview.size = Vector2(320, 240)
	preview.set_data(sprite, animation, "WALK")
	preview.time = 0.0
	var frame0: Dictionary = preview.resolve_frame()
	preview.time = 5.0 / 60.0
	var frame1: Dictionary = preview.resolve_frame()
	_check("anim_source", String(frame0.get("source", "")) == "animation")
	_check("anim_frame_0", int(frame0.get("image_index", -1)) == 0, str(frame0))
	_check("anim_frame_advance", int(frame1.get("image_index", -1)) == 1, str(frame1))
	var image := preview.frame_image(frame1)
	_check("anim_frame_image", image != null and image.get_width() == 16 and image.get_height() == 16)

	preview.set_data(sprite, animation, "IDLE")
	preview.time = 0.0
	var sheet0: Dictionary = preview.resolve_frame()
	preview.time = 5.0 / 60.0
	var sheet1: Dictionary = preview.resolve_frame()
	_check("sheet_fallback_source", String(sheet0.get("source", "")) == "sprite_sheet")
	_check("sheet_fallback_advance", int(sheet1.get("image_index", -1)) == 1, str(sheet0) + " -> " + str(sheet1))
	preview.queue_free()

func _make_stage() -> RetroStage:
	var stage := RetroStage.new()
	stage.set_name("preview_stage")
	stage.set_platform("snes")
	stage.set_mode("mode1")
	var tileset := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	tileset.fill(Color.WHITE)
	stage.set_tileset(tileset)
	var palette := PackedColorArray()
	for i in range(16):
		palette.append(Color(i / 15.0, 0.5, 1.0 - i / 15.0))
	stage.set_palette(palette)
	stage.set_tile_size(8)
	stage.set_tiles_x(2)
	stage.set_bpp(4)
	stage.set_map_size(Vector2i(64, 28))
	var map := PackedByteArray()
	map.resize(64 * 28 * 2)
	map.fill(0)
	stage.set_map(map)
	var clouds := map.duplicate()
	for y in range(3, 8):
		for x in range(4, 24):
			if (x + y) % 5 != 0:
				clouds[(y * 64 + x) * 2] = 1
	stage.add_layer("clouds", clouds)
	var layers := stage.get_layers()
	var layer: Dictionary = layers[0]
	layer["parallax"] = 0.5
	layers[0] = layer
	stage.set_layers(layers)
	stage.set_scroll({"h": true, "v": true, "offset_x": 100, "offset_y": 0, "speed_x": 0.5, "speed_y": 0.0})
	return stage

func _test_stage(sprite: RetroSprite, animation: RetroAnimation) -> void:
	var stage := _make_stage()
	var canvas = StageCanvas.new()
	get_root().add_child(canvas)
	canvas.size = Vector2(360, 260)
	canvas.set_stage(stage)
	canvas.set_sprite(sprite, animation)
	canvas.animation_state = "WALK"
	canvas.scroll_offset = Vector2(100, 0)
	canvas.animation_time = 0.0
	canvas._ensure_render()
	var base_map := stage.get_map()
	_check("stage_render", canvas._render != null)
	_check("stage_layer_texture", canvas._layer_textures.size() == 1 and canvas._layer_textures[0] != null)
	_check("stage_layer_distinct", canvas._layer_images[0] != canvas._render)
	_check("stage_map_restored", stage.get_map() == base_map)
	_check("stage_base_scroll", canvas.layer_scroll(-1).is_equal_approx(Vector2(100, 0)), str(canvas.layer_scroll(-1)))
	_check("stage_parallax_scroll", canvas.layer_scroll(0).is_equal_approx(Vector2(50, 0)), str(canvas.layer_scroll(0)))
	_check("stage_sprite_frame_0", canvas.sprite_frame_index() == 0, str(canvas.sprite_frame_index()))
	canvas.animation_time = 5.0 / 60.0
	_check("stage_sprite_advance", canvas.sprite_frame_index() == 1, str(canvas.sprite_frame_index()))

	var editor = StageEditor.new()
	get_root().add_child(editor)
	await process_frame
	editor.set_stage(stage)
	editor.set_sprite(sprite, animation)
	editor._animate_check.set_pressed_no_signal(false)
	editor._stop_preview()
	editor._reset_preview()
	editor._scroll_origin = Vector2.ZERO
	editor._preview_time = 0.0
	editor._speed_spin.value = 60.0
	editor._advance_preview(1.0)
	_check("editor_playback", is_equal_approx(editor._canvas.scroll_offset.x, 30.0), str(editor._canvas.scroll_offset))
	editor._advance_preview(100.0)
	var clamped: Vector2 = editor._canvas.layer_scroll(-1)
	_check("editor_scroll_clamped", clamped.x >= 0.0 and clamped.x <= 256.0, str(clamped))
	editor._layers.select(0)
	editor._parallax_spin.set_value_no_signal(0.25)
	editor._apply_parallax()
	var layers := stage.get_layers()
	_check("editor_parallax_apply", is_equal_approx(float(layers[0].get("parallax", 1.0)), 0.25))
	editor._canvas.queue_free()
	editor.queue_free()
	canvas.queue_free()


func _test_flat_stage() -> void:
	var root := "/tmp/opencode/editor_preview_test"
	DirAccess.make_dir_recursive_absolute(root)
	var png_path := root.path_join("flat_test.png")
	var json_path := root.path_join("stage_animations.json")
	var image := Image.create_empty(32, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.2, 0.4, 1.0))
	image.fill_rect(Rect2i(8, 0, 8, 8), Color(0.9, 0.4, 0.2, 1.0))
	image.fill_rect(Rect2i(24, 8, 8, 8), Color(0.2, 0.9, 0.3, 1.0))
	image.save_png(png_path)
	var data := {"clips": [{
		"id": "bob",
		"stage": "flat_test",
		"target": {
			"target_region_xywh": [8, 0, 8, 8],
			"sequence": [{"pose": 0, "ticks60": 2}, {"pose": 1, "ticks60": 2}],
			"cycle_ticks60": 4,
			"start_phase_ticks60": 0,
		},
	}]}
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var editor = StageEditor.new()
	get_root().add_child(editor)
	await process_frame
	editor._load_flat_image_stage(png_path, null)
	var canvas = editor._canvas
	canvas._ensure_render()
	_check("flat_stage_map", editor.stage != null and editor.stage.get_map_size() == Vector2i(4, 2), str(editor.stage.get_map_size()) if editor.stage else "null")
	_check("flat_stage_render", canvas._render != null and canvas._render.get_size() == Vector2i(32, 16))
	_check("flat_stage_clip", canvas.stage_animations.size() == 1)
	_check("flat_stage_overlay_texture", canvas._stage_animation_textures.size() == 1 and canvas._stage_animation_textures[0] != null)
	var entry: Dictionary = canvas.stage_animations[0] if not canvas.stage_animations.is_empty() else {}
	canvas.animation_time = 0.0
	_check("stage_clip_pose_0", canvas._stage_animation_pose(entry) == 0)
	canvas.animation_time = 0.04
	_check("stage_clip_pose_1", canvas._stage_animation_pose(entry) == 1)
	canvas.animation_time = 0.07
	_check("stage_clip_pose_loop", canvas._stage_animation_pose(entry) == 0)
	editor.queue_free()


func _test_sheet_auto_split() -> void:
	var sheet := Image.create_empty(64, 16, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for i in range(4):
		sheet.fill_rect(Rect2i(i * 16, 0, 12, 16), Color(0.2 + i * 0.2, 0.8, 0.4, 1.0))
	var sprite := RetroSprite.new()
	sprite.set_platform("snes")
	sprite.set_image(sheet)
	sprite.add_frame("full", Rect2i(0, 0, 64, 16), 6)
	var animation := RetroAnimation.new()
	animation.set_fps(60)
	var states := animation.get_states()
	for key in states.keys():
		var st: Dictionary = states[key]
		st["frames"] = []
		states[key] = st
	var idle: Dictionary = states["IDLE"]
	idle["frames"] = [{"sprite_frame": 0, "duration": 6, "rect": Rect2i(0, 0, 64, 16), "hitboxes": []}]
	states["IDLE"] = idle
	animation.set_states(states)
	var rects := SpriteSheet.frames_for_sprite(sprite)
	_check("sheet_detected_count", rects.size() == 4, str(rects))
	if rects.size() == 4:
		_check("sheet_detected_rect", rects[1] == Rect2i(16, 0, 16, 16), str(rects[1]))
	var preview = AnimPreview.new()
	get_root().add_child(preview)
	preview.size = Vector2(320, 240)
	preview.set_data(sprite, animation, "IDLE")
	preview.time = 0.0
	var f0: Dictionary = preview.resolve_frame()
	preview.time = 6.0 / 60.0
	var f1: Dictionary = preview.resolve_frame()
	_check("sheet_preview_source", String(f0.get("source", "")) == "sprite_sheet" and bool(f0.get("auto_sheet", false)))
	_check("sheet_preview_advance", int(f0.get("image_index", -1)) == 0 and int(f1.get("image_index", -1)) == 1, str(f0) + " -> " + str(f1))
	var image := preview.frame_image(f1)
	_check("sheet_preview_crop", image != null and image.get_size() == Vector2i(16, 16))
	var materialized := SpriteSheet.ensure_sprite_frames(sprite)
	_check("sheet_materialized", materialized.size() == 4 and sprite.get_frames().size() == 4)
	preview.queue_free()


func _test_animation_editor() -> void:
	var sheet := Image.create_empty(64, 16, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for i in range(4):
		sheet.fill_rect(Rect2i(i * 16, 0, 12, 16), Color(0.2 + i * 0.2, 0.7, 0.4, 1.0))
	var sprite := RetroSprite.new()
	sprite.set_platform("snes")
	sprite.set_image(sheet)
	sprite.add_frame("full", Rect2i(0, 0, 64, 16), 6)
	var animation := RetroAnimation.new()
	animation.set_fps(60)
	var states := animation.get_states()
	for key in states.keys():
		var st: Dictionary = states[key]
		st["frames"] = []
		states[key] = st
	var idle: Dictionary = states["IDLE"]
	idle["frames"] = [{"sprite_frame": 0, "duration": 6, "rect": Rect2i(0, 0, 64, 16), "hitboxes": []}]
	states["IDLE"] = idle
	animation.set_states(states)
	var editor = AnimationEditor.new()
	get_root().add_child(editor)
	await process_frame
	editor.set_sprite(sprite)
	editor.set_animation(animation)
	_check("editor_autoplay", editor._playing and editor._play_button.text == "Pause")
	_check("editor_sheet_preview", String(editor._preview.resolve_frame().get("source", "")) == "sprite_sheet")
	var before: float = editor._time
	editor._tick()
	_check("editor_tick_advances", editor._time > before and is_equal_approx(editor._preview.time, editor._time))
	editor._toggle_play()
	_check("editor_pause", not editor._playing and editor._user_paused)
	editor._toggle_play()
	_check("editor_resume", editor._playing and not editor._user_paused)
	editor._add_frames_from_sprite()
	_check("editor_materialized_sprite", sprite.get_frames().size() == 4)
	_check("editor_materialized_anim", Array(animation.get_state("IDLE").get("frames", [])).size() == 4)
	_check("editor_anim_preview", String(editor._preview.resolve_frame().get("source", "")) == "animation")
	editor.queue_free()
