@tool
extends VBoxContainer
## Stage / background editor: tile map painting, layers, scrolling,
## parallax, collisions and native exports.

signal modified()
signal status(text: String)

const StageCanvas = preload("res://addons/retro_engine/stage_canvas.gd")
const TilePicker = preload("res://addons/retro_engine/tile_picker.gd")
const SpriteSheet = preload("res://addons/retro_engine/sprite_sheet.gd")

var stage: RetroStage
var sprite: RetroSprite
var animation: RetroAnimation
var project: RetroProject
var platform: String = "snes"
var mode: String = "mode1"

var _canvas
var _picker
var _info: Label
var _stats: Label
var _tile_index: SpinBox
var _palette_index: SpinBox
var _paint_check: CheckBox
var _grid_check: CheckBox
var _collision_check: CheckBox
var _zoom_spin: SpinBox
var _scroll_x: HSlider
var _scroll_y: HSlider
var _scroll_label: Label
var _layers: ItemList
var _parallax_spin: SpinBox
var _collisions: ItemList
var _map_w: SpinBox
var _map_h: SpinBox
var _tile_size: SpinBox
var _tiles_x: SpinBox
var _bpp: OptionButton
var _column_check: CheckBox
var _animate_check: CheckBox
var _speed_spin: SpinBox
var _sprite_check: CheckBox
var _state_option: OptionButton
var _overlay_check: CheckBox
var _animations_label: Label
var _animations_file: String = ""
var _timer: Timer
var _playing: bool = false
var _preview_time: float = 0.0
var _scroll_origin: Vector2 = Vector2.ZERO
var _preview_state: String = "IDLE"

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	var import_btn := Button.new()
	import_btn.text = "Import .chr/.map/.pal"
	import_btn.pressed.connect(_open_import_dialog)
	toolbar.add_child(import_btn)
	_paint_check = CheckBox.new()
	_paint_check.text = "Paint"
	_paint_check.toggled.connect(func(v):
		_canvas.paint_mode = v
		if v and _playing:
			_animate_check.set_pressed_no_signal(false)
			_stop_preview())
	toolbar.add_child(_paint_check)
	var tlbl := Label.new()
	tlbl.text = "Tile"
	toolbar.add_child(tlbl)
	_tile_index = _spin(0, 1023, 0, "")
	_tile_index.value_changed.connect(func(v): _canvas.selected_tile = int(v))
	toolbar.add_child(_tile_index)
	var plbl := Label.new()
	plbl.text = "Pal"
	toolbar.add_child(plbl)
	_palette_index = _spin(0, 15, 0, "")
	_palette_index.value_changed.connect(func(v): _canvas.selected_palette = int(v))
	toolbar.add_child(_palette_index)
	_grid_check = CheckBox.new()
	_grid_check.text = "Grid"
	_grid_check.toggled.connect(func(v): _canvas.show_grid = v; _canvas.queue_redraw())
	toolbar.add_child(_grid_check)
	_collision_check = CheckBox.new()
	_collision_check.text = "Collisions"
	_collision_check.button_pressed = true
	_collision_check.toggled.connect(func(v): _canvas.show_collisions = v; _canvas.queue_redraw())
	toolbar.add_child(_collision_check)
	_zoom_spin = _spin(1, 8, 2, "Zoom ")
	_zoom_spin.value_changed.connect(func(v): _canvas.zoom = int(v); _canvas.queue_redraw())
	toolbar.add_child(_zoom_spin)
	_column_check = CheckBox.new()
	_column_check.text = "Column-major"
	_column_check.tooltip_text = "Sidearms-style maps store 32 rows per column. Disable for normal row-major maps."
	_column_check.toggled.connect(_on_column_toggled)
	toolbar.add_child(_column_check)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_canvas = StageCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.tile_painted.connect(_on_tile_painted)
	_canvas.hovered_tile.connect(_on_tile_hovered)
	split.add_child(_canvas)

	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = 235
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 225
	side.add_theme_constant_override("separation", 5)
	side_scroll.add_child(side)

	_info = Label.new()
	_info.text = "No stage loaded"
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_info)
	_stats = Label.new()
	_stats.add_theme_color_override("font_color", Color("#9fb4d0"))
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_stats)

	var scroll_label_title := Label.new()
	scroll_label_title.text = "Animated stage / parallax preview"
	side.add_child(scroll_label_title)
	_scroll_label = Label.new()
	_scroll_label.text = "X 0  Y 0"
	_scroll_label.add_theme_color_override("font_color", Color("#9fb4d0"))
	side.add_child(_scroll_label)
	_scroll_x = HSlider.new()
	_scroll_x.min_value = 0
	_scroll_x.max_value = 2048
	_scroll_x.value_changed.connect(_on_scroll_changed)
	side.add_child(_scroll_x)
	_scroll_y = HSlider.new()
	_scroll_y.min_value = 0
	_scroll_y.max_value = 2048
	_scroll_y.value_changed.connect(_on_scroll_changed)
	side.add_child(_scroll_y)
	var srow := HFlowContainer.new()
	_animate_check = CheckBox.new()
	_animate_check.text = "Animate scroll"
	_animate_check.button_pressed = true
	_animate_check.toggled.connect(_on_animate_toggled)
	srow.add_child(_animate_check)
	_speed_spin = _spin(0, 240, 24, "Speed ")
	_speed_spin.suffix = "px/s"
	_speed_spin.tooltip_text = "Preview speed. Authored stage scroll speeds take priority (converted from pixels/frame)."
	srow.add_child(_speed_spin)
	var reset_scroll := Button.new()
	reset_scroll.text = "Reset"
	reset_scroll.pressed.connect(_reset_preview)
	srow.add_child(reset_scroll)
	side.add_child(srow)
	var srow2 := HFlowContainer.new()
	_sprite_check = CheckBox.new()
	_sprite_check.text = "Sprite"
	_sprite_check.button_pressed = true
	_sprite_check.toggled.connect(func(v): _canvas.show_sprites = v; _canvas.queue_redraw())
	srow2.add_child(_sprite_check)
	_state_option = OptionButton.new()
	_state_option.custom_minimum_size.x = 130
	_state_option.item_selected.connect(_on_preview_state_selected)
	srow2.add_child(_state_option)
	side.add_child(srow2)
	var srow3 := HFlowContainer.new()
	_overlay_check = CheckBox.new()
	_overlay_check.text = "Stage clips"
	_overlay_check.button_pressed = true
	_overlay_check.tooltip_text = "Animate authored stage clips (crowd, water, machines) read from stage_animations.json"
	_overlay_check.toggled.connect(func(v): _canvas.show_stage_animations = v; _canvas.queue_redraw())
	srow3.add_child(_overlay_check)
	var load_anim := Button.new()
	load_anim.text = "Clips JSON..."
	load_anim.tooltip_text = "Load a stage_animations.json and enable the clips for the current stage"
	load_anim.pressed.connect(_open_animations_json)
	srow3.add_child(load_anim)
	_animations_label = Label.new()
	_animations_label.text = "clips: 0"
	_animations_label.add_theme_color_override("font_color", Color("#9fb4d0"))
	srow3.add_child(_animations_label)
	side.add_child(srow3)

	var mrow := HBoxContainer.new()
	_map_w = _spin(1, 128, 32, "W")
	_map_h = _spin(1, 128, 32, "H")
	_map_w.value_changed.connect(_on_geometry_changed)
	_map_h.value_changed.connect(_on_geometry_changed)
	mrow.add_child(_map_w)
	mrow.add_child(_map_h)
	_tile_size = _spin(8, 16, 8, "Tile ")
	_tile_size.value_changed.connect(_on_geometry_changed)
	mrow.add_child(_tile_size)
	_tiles_x = _spin(1, 128, 16, "TilesX ")
	_tiles_x.value_changed.connect(_on_geometry_changed)
	mrow.add_child(_tiles_x)
	_bpp = OptionButton.new()
	_bpp.add_item("2bpp", 0)
	_bpp.add_item("4bpp", 1)
	_bpp.add_item("8bpp", 2)
	_bpp.select(1)
	_bpp.item_selected.connect(func(_i): _on_geometry_changed(0))
	mrow.add_child(_bpp)
	side.add_child(mrow)

	var picker_label := Label.new()
	picker_label.text = "Tileset"
	side.add_child(picker_label)
	_picker = TilePicker.new()
	_picker.tile_selected.connect(func(i): _tile_index.set_value_no_signal(i); _canvas.selected_tile = i)
	side.add_child(_picker)

	var layer_label := Label.new()
	layer_label.text = "Layers"
	side.add_child(layer_label)
	_layers = ItemList.new()
	_layers.custom_minimum_size.y = 70
	side.add_child(_layers)
	var lbtn := HBoxContainer.new()
	var add_layer := Button.new()
	add_layer.text = "Duplicate as layer"
	add_layer.pressed.connect(_add_layer)
	lbtn.add_child(add_layer)
	var del_layer := Button.new()
	del_layer.text = "Remove"
	del_layer.pressed.connect(_remove_layer)
	lbtn.add_child(del_layer)
	side.add_child(lbtn)
	var lrow2 := HBoxContainer.new()
	_parallax_spin = _spin(0, 8, 1, "Parallax ")
	_parallax_spin.step = 0.05
	_layers.item_selected.connect(func(i):
		var layers := stage.get_layers() if stage else []
		if i >= 0 and i < layers.size():
			_parallax_spin.set_value_no_signal(float(layers[i].get("parallax", 1.0))))
	lrow2.add_child(_parallax_spin)
	var apply_parallax := Button.new()
	apply_parallax.text = "Apply"
	apply_parallax.tooltip_text = "Set the selected layer parallax factor (0 = fixed, 0.5 = half speed, 1 = camera speed)"
	apply_parallax.pressed.connect(_apply_parallax)
	lrow2.add_child(apply_parallax)
	side.add_child(lrow2)


	var col_label := Label.new()
	col_label.text = "Collision areas (world pixels)"
	side.add_child(col_label)
	_collisions = ItemList.new()
	_collisions.custom_minimum_size.y = 70
	side.add_child(_collisions)
	var cbtn := HBoxContainer.new()
	var add_col := Button.new()
	add_col.text = "Add viewport area"
	add_col.pressed.connect(_add_collision)
	cbtn.add_child(add_col)
	var clear_col := Button.new()
	clear_col.text = "Clear"
	clear_col.pressed.connect(_clear_collisions)
	cbtn.add_child(clear_col)
	side.add_child(cbtn)

	var erow := HBoxContainer.new()
	var exp_snes := Button.new()
	exp_snes.text = "Export SNES"
	exp_snes.pressed.connect(_export_snes)
	erow.add_child(exp_snes)
	var exp_md := Button.new()
	exp_md.text = "Export SGDK"
	exp_md.pressed.connect(_export_sgdk)
	erow.add_child(exp_md)
	side.add_child(erow)

	_timer = Timer.new()
	_timer.wait_time = 1.0 / 60.0
	_timer.timeout.connect(_tick_preview)
	add_child(_timer)

func _spin(minv: float, maxv: float, value: float, prefix: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.value = value
	if prefix != "":
		s.prefix = prefix
	s.custom_minimum_size.x = 66
	return s

func set_platform(p: String, m: String) -> void:
	platform = p
	mode = m
	if _canvas:
		_canvas.show_limits = true

func set_stage(doc: RetroStage, p_project: RetroProject = null) -> void:
	var changed := stage != doc
	stage = doc
	project = p_project
	_canvas.set_stage(stage)
	if stage == null:
		_stop_preview()
		return
	_map_w.set_value_no_signal(stage.get_map_size().x)
	_map_h.set_value_no_signal(stage.get_map_size().y)
	_tile_size.set_value_no_signal(stage.get_tile_size())
	_tiles_x.set_value_no_signal(stage.get_tiles_x())
	_bpp.select(0 if stage.get_bpp() == 2 else (2 if stage.get_bpp() == 8 else 1))
	_column_check.set_pressed_no_signal(stage.get_column_major())
	_tile_index.max_value = max(1, stage.get_tiles_x() * max(1, stage.get_tileset().get_height() / stage.get_tile_size()) - 1) if stage.get_tileset() else 1023
	_picker.set_tileset(stage.get_tileset(), stage.get_tile_size(), stage.get_tiles_x())
	_info.text = "%s  |  %s" % [stage.get_name(), String(stage.get_metadata().get("tiles_path", ""))]
	_refresh_layers()
	_refresh_collisions()
	_update_stats()
	_canvas.refresh()
	if stage.get_scroll().has("speed_x") or stage.get_scroll().has("offset_x"):
		_scroll_x.set_value_no_signal(int(stage.get_scroll().get("offset_x", 0)))
		_scroll_y.set_value_no_signal(int(stage.get_scroll().get("offset_y", 0)))
	else:
		_scroll_x.set_value_no_signal(0)
		_scroll_y.set_value_no_signal(0)
	var authored_speed := maxf(absf(float(stage.get_scroll().get("speed_x", 0.0))), absf(float(stage.get_scroll().get("speed_y", 0.0))))
	if authored_speed > 0.0001:
		_speed_spin.set_value_no_signal(authored_speed * 60.0)
	_on_scroll_changed(0)
	if changed:
		_preview_time = 0.0
		_scroll_origin = Vector2(_scroll_x.value, _scroll_y.value)
		_canvas.set_stage_animations([])
		_animations_file = ""
		if _animations_label:
			_animations_label.text = "clips: 0"
		if _animate_check.button_pressed:
			_start_preview()
		else:
			_stop_preview()
		var metadata := stage.get_metadata()
		var anim_path := String(metadata.get("stage_animations", ""))
		if anim_path.is_empty():
			var source_png := String(metadata.get("source_png", ""))
			if not source_png.is_empty():
				anim_path = _find_animations_json(source_png, stage.get_name())
		if not anim_path.is_empty() and FileAccess.file_exists(anim_path):
			load_stage_animations(anim_path, stage.get_name())
	status.emit("Stage loaded: %s" % stage.get_name())

func set_sprite(doc: RetroSprite, anim: RetroAnimation = null) -> void:
	sprite = doc
	if anim != null:
		animation = anim
	_canvas.set_sprite(sprite, animation)
	_rebuild_preview_states()

func set_animation(doc: RetroAnimation) -> void:
	animation = doc
	_canvas.set_animation(animation)
	_rebuild_preview_states()

func _rebuild_preview_states() -> void:
	if _state_option == null:
		return
	_state_option.clear()
	if animation == null:
		_state_option.add_item("Sprite sheet")
		_state_option.select(0)
		_canvas.animation_state = ""
		return
	var preferred := _preview_state
	var states: Dictionary = animation.get_states()
	if not states.has(preferred):
		preferred = ""
		for k in states.keys():
			if not Array(animation.get_state(String(k)).get("frames", [])).is_empty():
				preferred = String(k)
				break
		if preferred.is_empty() and not states.is_empty():
			preferred = String(states.keys()[0])
	for k in states.keys():
		_state_option.add_item(String(k))
	if not preferred.is_empty():
		_preview_state = preferred
		for i in range(_state_option.item_count):
			if _state_option.get_item_text(i) == _preview_state:
				_state_option.select(i)
				break
		_canvas.animation_state = _preview_state
	_canvas.queue_redraw()

func _on_preview_state_selected(index: int) -> void:
	if index < 0:
		return
	var text := _state_option.get_item_text(index)
	_preview_state = "" if text == "Sprite sheet" else text
	_canvas.animation_state = _preview_state
	_preview_time = 0.0
	_canvas.set_animation_time(0.0)

## Load the project's `stage_animations.json` and keep only the clips for
## `stage_name`. Each clip becomes a target region + pose timing; StageCanvas
## re-samples that region from the rendered stage, exactly like the SNES BG1
## sparse-patch runtime.
func load_stage_animations(path: String, stage_name: String = "") -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		status.emit("Stage animations JSON not found: " + path)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		status.emit("Invalid stage animations JSON: " + path)
		return false
	var clips: Array = parsed.get("clips", [])
	var wanted := stage_name.strip_edges()
	var out: Array = []
	for c in clips:
		var clip: Dictionary = c
		if not wanted.is_empty() and String(clip.get("stage", "")) != wanted:
			continue
		var target: Dictionary = clip.get("target", {})
		var region: Array = target.get("target_region_xywh", [])
		if region.size() != 4:
			continue
		var ticks: Array = []
		for step in target.get("sequence", []):
			ticks.append(maxi(1, int(Dictionary(step).get("ticks60", 1))))
		if ticks.is_empty():
			continue
		var cycle := int(target.get("cycle_ticks60", 0))
		if cycle <= 0:
			for t in ticks:
				cycle += int(t)
		out.append({
			"id": String(clip.get("id", "clip")),
			"rect": Rect2i(int(region[0]), int(region[1]), int(region[2]), int(region[3])),
			"ticks": ticks,
			"phase": int(target.get("start_phase_ticks60", 0)),
			"cycle": cycle,
		})
	_animations_file = path
	_canvas.set_stage_animations(out)
	if _overlay_check:
		_overlay_check.set_pressed_no_signal(true)
		_canvas.show_stage_animations = true
	if _animations_label:
		_animations_label.text = "clips: %d" % out.size()
	status.emit("Stage animations: %d clip(s) for %s" % [out.size(), wanted if not wanted.is_empty() else "stage"])
	return not out.is_empty()

func _open_animations_json() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.json", "Stage animations")
	if project != null and not _animations_file.is_empty():
		dlg.current_dir = _animations_file.get_base_dir()
	else:
		dlg.current_dir = _default_export_dir()
	dlg.file_selected.connect(func(path):
		load_stage_animations(path, stage.get_name() if stage else "")
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func _find_animations_json(path: String, stage_name: String) -> String:
	var candidates: Array = [
		path.get_base_dir().path_join("animations/stage_animations.json"),
		path.get_base_dir().path_join("stage_animations.json"),
	]
	if project != null:
		for r in project.get_resources():
			var p := String(r.get("path", ""))
			if p.get_file() == "stage_animations.json":
				candidates.append(p)
	for c in candidates:
		if FileAccess.file_exists(String(c)):
			return String(c)
	return ""

func _on_animate_toggled(v: bool) -> void:
	if v:
		_start_preview()
	else:
		_stop_preview()

func _start_preview() -> void:
	if stage == null:
		return
	_playing = true
	_scroll_origin = _canvas.scroll_offset if _canvas != null else Vector2(_scroll_x.value, _scroll_y.value)
	_preview_time = 0.0
	_timer.start()

func _stop_preview() -> void:
	_playing = false
	if _timer:
		_timer.stop()

func _tick_preview() -> void:
	_advance_preview(1.0 / 60.0)

## Advance the preview by `dt` seconds. Kept public so headless tests can drive
## the same playback path as the 60 Hz timer.
func _advance_preview(dt: float) -> void:
	if stage == null or _canvas == null:
		return
	_preview_time += dt
	var offset := _scroll_origin + _preview_speed() * _preview_time
	var world: Vector2 = _canvas.world_size()
	if world.x > 0.0:
		offset.x = fposmod(offset.x, world.x)
	if world.y > 0.0:
		offset.y = fposmod(offset.y, world.y)
	_apply_preview_scroll(offset)

func _preview_speed() -> Vector2:
	var sx := 0.0
	var sy := 0.0
	if stage != null:
		var scroll: Dictionary = stage.get_scroll()
		sx = float(scroll.get("speed_x", 0.0))
		sy = float(scroll.get("speed_y", 0.0))
	if absf(sx) < 0.0001 and absf(sy) < 0.0001:
		sx = _speed_spin.value / 60.0
	return Vector2(sx * 60.0, sy * 60.0)

func _apply_preview_scroll(offset: Vector2) -> void:
	_canvas.scroll_offset = offset
	_canvas.set_animation_time(_preview_time)
	_scroll_x.set_value_no_signal(int(offset.x))
	_scroll_y.set_value_no_signal(int(offset.y))
	if _scroll_label:
		_scroll_label.text = "X %d  Y %d  |  %.1fs" % [int(offset.x), int(offset.y), _preview_time]

func _reset_preview() -> void:
	var base := Vector2.ZERO
	if stage != null:
		base = Vector2(float(stage.get_scroll().get("offset_x", 0)), float(stage.get_scroll().get("offset_y", 0)))
	_scroll_x.set_value_no_signal(int(base.x))
	_scroll_y.set_value_no_signal(int(base.y))
	_scroll_origin = base
	_preview_time = 0.0
	_apply_preview_scroll(base)

func _refresh_layers() -> void:
	_layers.clear()
	if stage == null:
		return
	var layers := stage.get_layers()
	if layers.is_empty():
		_layers.add_item("Base map (editable)")
	for i in range(layers.size()):
		_layers.add_item("%s  parallax %.2f" % [String(layers[i].get("name", "layer")), float(layers[i].get("parallax", 1.0))])

func _refresh_collisions() -> void:
	_collisions.clear()
	if stage == null:
		return
	var cols := stage.get_collisions()
	for i in range(cols.size()):
		var r: Rect2i = cols[i] if cols[i] is Rect2i else cols[i].get("rect", Rect2i())
		_collisions.add_item("%d: %d,%d %dx%d" % [i, r.position.x, r.position.y, r.size.x, r.size.y])
	_canvas.queue_redraw()

func _update_stats() -> void:
	if stage == null or _stats == null:
		return
	var a: Dictionary = stage.analyze()
	var est: Dictionary = RetroHardware.estimate(platform, {
		"mode": mode, "tile_size": stage.get_tile_size(), "bpp": stage.get_bpp(),
		"tile_count": int(a.get("map_entries", 0)), "map_w": int(a.get("map_w", 0)),
		"map_h": int(a.get("map_h", 0)), "layers": 1, "palette_colors": int(a.get("palette_colors", 16)),
	})
	var issue_text := ""
	for issue in est.get("issues", []):
		issue_text += "\n[!] " + String(issue)
	_stats.text = "%dx%d tiles (%s), %dpx world, %dpx tiles, %dbpp\nPalette %d colors | estimated VRAM %d B (%.1f%%)%s" % [
		int(a.get("map_w", 0)), int(a.get("map_h", 0)), "column-major" if stage.get_column_major() else "row-major",
		int(a.get("pixel_width", 0)), int(a.get("tile_size", 8)), int(a.get("bpp", 4)),
		int(a.get("palette_colors", 0)), int(est.get("vram_total", 0)), float(est.get("vram_percent", 0.0)), issue_text]

func _on_column_toggled(v: bool) -> void:
	if stage == null:
		return
	stage.set_column_major(v)
	_canvas.refresh()
	_update_stats()
	modified.emit()

func _on_geometry_changed(_v: float) -> void:
	if stage == null:
		return
	# Geometry changes require reloading the map bytes; resize the map in place.
	var old_map := stage.get_map()
	var old_w := stage.get_map_size().x
	var old_h := stage.get_map_size().y
	var new_w := int(_map_w.value)
	var new_h := int(_map_h.value)
	var new_map := PackedByteArray()
	new_map.resize(new_w * new_h * 2)
	new_map.fill(0)
	var entry_bytes := 2
	for y in range(min(old_h, new_h)):
		for x in range(min(old_w, new_w)):
			var src := (y * old_w + x) * 2
			var dst := (y * new_w + x) * 2
			if src + 1 < old_map.size():
				new_map[dst] = old_map[src]
				new_map[dst + 1] = old_map[src + 1]
	stage.set_map(new_map)
	stage.set_map_size(Vector2i(new_w, new_h))
	stage.set_tile_size(int(_tile_size.value))
	stage.set_tiles_x(int(_tiles_x.value))
	stage.set_bpp(2 if _bpp.selected == 0 else (8 if _bpp.selected == 2 else 4))
	_canvas.refresh()
	_update_stats()
	modified.emit()

func _on_tile_painted(mx: int, my: int, button: int) -> void:
	if stage == null:
		return
	if button == MOUSE_BUTTON_RIGHT:
		stage.set_tile(mx, my, 0, 0)
	else:
		stage.set_tile(mx, my, int(_tile_index.value), int(_palette_index.value))
	_canvas.refresh()
	_update_stats()
	modified.emit()

func _on_tile_hovered(mx: int, my: int) -> void:
	if stage == null:
		return
	var info: Dictionary = stage.get_tile_info(mx, my)
	_info.text = "%s  |  tile %d,%d -> #%d pal %d prio %d hflip %d vflip %d" % [
		stage.get_name(), mx, my, int(info.get("tile", 0)), int(info.get("palette", 0)),
		int(info.get("priority", 0)), int(info.get("hflip", 0)), int(info.get("vflip", 0))]

func _on_scroll_changed(_v: float) -> void:
	if _canvas == null:
		return
	_scroll_origin = Vector2(_scroll_x.value, _scroll_y.value)
	_preview_time = 0.0
	_apply_preview_scroll(_scroll_origin)
	if stage:
		var scroll: Dictionary = stage.get_scroll()
		scroll["h"] = true
		scroll["v"] = true
		scroll["offset_x"] = int(_scroll_x.value)
		scroll["offset_y"] = int(_scroll_y.value)
		stage.set_scroll(scroll)

func _add_layer() -> void:
	if stage == null:
		return
	stage.add_layer("layer_%d" % stage.get_layers().size(), stage.get_map())
	_refresh_layers()
	_canvas.refresh()
	modified.emit()

func _apply_parallax() -> void:
	if stage == null or _layers.get_selected_items().is_empty():
		return
	var layers := stage.get_layers()
	var idx := _layers.get_selected_items()[0]
	if idx < 0 or idx >= layers.size():
		return
	var layer: Dictionary = layers[idx]
	layer["parallax"] = float(_parallax_spin.value)
	layers[idx] = layer
	stage.set_layers(layers)
	_refresh_layers()
	_layers.select(idx)
	_canvas.refresh()
	modified.emit()

func _remove_layer() -> void:
	if stage == null or _layers.get_selected_items().is_empty():
		return
	var layers := stage.get_layers()
	var idx := _layers.get_selected_items()[0]
	if idx >= 0 and idx < layers.size():
		layers.remove_at(idx)
		stage.set_layers(layers)
		_refresh_layers()
		_canvas.refresh()
		modified.emit()

func _add_collision() -> void:
	if stage == null:
		return
	var cols := stage.get_collisions()
	cols.append(Rect2i(int(_scroll_x.value), int(_scroll_y.value), 256 if platform == "snes" else 320, 224))
	stage.set_collisions(cols)
	_refresh_collisions()
	modified.emit()

func _clear_collisions() -> void:
	if stage == null:
		return
	stage.set_collisions([])
	_refresh_collisions()
	modified.emit()

func _open_import_dialog() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.chr,*.pic", "SNES tile data")
	dlg.file_selected.connect(func(path):
		var pal: String = path.get_basename() + ".pal"
		var map: String = path.get_basename() + ".map"
		if FileAccess.file_exists(map) and FileAccess.file_exists(pal):
			_open_snes(path, map, pal)
		else:
			status.emit("Companion .pal/.map not found next to " + path)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func _open_snes(tiles: String, map: String, pal: String, w: int = 0, h: int = 0, column_major: bool = false) -> void:
	var doc := RetroStage.new()
	doc.set_platform(platform)
	var size := FileAccess.get_size(map) / 2
	if w <= 0:
		w = 64 if size >= 2048 else 32
	if h <= 0:
		h = int(max(1, size / w))
	var err := doc.load_snes(tiles, map, pal, w, h, 8, 4, 16, column_major)
	if err != OK:
		status.emit("Failed to load stage: " + tiles)
		return
	doc.set_name(tiles.get_file().get_basename())
	set_stage(doc, project)
	modified.emit()

func open_resource(res: Dictionary, p_project: RetroProject) -> void:
	project = p_project
	platform = p_project.get_platform() if p_project else platform
	var path := String(res.get("path", ""))
	var ext := String(res.get("ext", ""))
	if ext == "png" or ext == "bmp":
		var map := String(res.get("map_path", ""))
		if map.is_empty():
			map = path.get_basename() + ".map"
		if not FileAccess.file_exists(map):
			_load_flat_image_stage(path, p_project)
			return
		var doc := RetroStage.new()
		doc.set_platform(platform)
		var size := FileAccess.get_size(map) / 2
		var w := int(res.get("map_w", 0))
		var h := int(res.get("map_h", 0))
		if w <= 0:
			w = 64 if size >= 2048 else 32
		if h <= 0:
			h = int(max(1, size / w))
		doc.load_image_tileset(path, map, w, h, 8)
		doc.set_column_major(bool(res.get("column_major", false)))
		doc.set_name(path.get_file().get_basename())
		set_stage(doc, p_project)
		_auto_load_animations(path, doc.get_name())
		modified.emit()
		return
	if ext == "chr" or ext == "pic":
		var pal := String(res.get("palette_path", ""))
		var map := String(res.get("map_path", ""))
		if pal.is_empty():
			pal = path.get_basename() + ".pal"
		if map.is_empty():
			map = path.get_basename() + ".map"
		if not FileAccess.file_exists(map):
			status.emit("No companion .map for " + path)
			return
		_open_snes(path, map, pal, int(res.get("map_w", 0)), int(res.get("map_h", 0)), bool(res.get("column_major", false)))
		_auto_load_animations(path, path.get_file().get_basename())
		return
	status.emit("Unsupported stage source: " + ext)

## Load a plain stage PNG (e.g. a 512x224 KOF98/Esaka background) without a
## companion .map. The image is deduplicated into 8x8 tiles and a normal
## RetroStage map is built, so scrolling, exports and the real stage renderer
## all keep working.
func _load_flat_image_stage(path: String, p_project: RetroProject) -> void:
	var image := Image.load_from_file(path)
	if image == null:
		status.emit("Could not load stage image: " + path)
		return
	if image.get_width() % 8 != 0 or image.get_height() % 8 != 0:
		status.emit("Stage image must be a multiple of 8 pixels: " + path)
		return
	image.convert(Image.FORMAT_RGBA8)
	var png_palette := RetroGraphics.read_png_palette(path)
	if not png_palette.is_empty():
		SpriteSheet.apply_chroma_key(image, png_palette)
	var tiles_x := image.get_width() / 8
	var tiles_y := image.get_height() / 8
	var unique: Dictionary = {}
	var order: Array = []
	var indices := PackedInt32Array()
	indices.resize(tiles_x * tiles_y)
	for y in range(tiles_y):
		for x in range(tiles_x):
			var tile := image.get_region(Rect2i(x * 8, y * 8, 8, 8))
			var key := tile.get_data().hex_encode()
			var idx := int(unique.get(key, -1))
			if idx < 0:
				idx = order.size()
				unique[key] = idx
				order.append(tile)
			indices[y * tiles_x + x] = idx
	if order.is_empty():
		status.emit("Stage image has no tiles: " + path)
		return
	var out_x := mini(16, order.size())
	var out_y := int(ceil(float(order.size()) / float(out_x)))
	var tileset := Image.create_empty(out_x * 8, out_y * 8, false, Image.FORMAT_RGBA8)
	tileset.fill(Color(0, 0, 0, 0))
	for i in range(order.size()):
		tileset.blit_rect(order[i], Rect2i(0, 0, 8, 8), Vector2i((i % out_x) * 8, (i / out_x) * 8))
	var doc := RetroStage.new()
	doc.set_platform(platform)
	doc.set_name(path.get_file().get_basename())
	doc.set_tile_size(8)
	doc.set_tiles_x(out_x)
	doc.set_bpp(4)
	doc.set_map_size(Vector2i(tiles_x, tiles_y))
	doc.set_tileset(tileset)
	doc.set_palette(RetroGraphics.extract_palette(image, 16, true))
	var map_bytes := PackedByteArray()
	map_bytes.resize(tiles_x * tiles_y * 2)
	map_bytes.fill(0)
	doc.set_map(map_bytes)
	for y in range(tiles_y):
		for x in range(tiles_x):
			doc.set_tile(x, y, indices[y * tiles_x + x], 0)
	var anim_json := _find_animations_json(path, doc.get_name())
	var metadata := doc.get_metadata()
	metadata["source_png"] = path
	metadata["flat_image"] = true
	if not anim_json.is_empty():
		metadata["stage_animations"] = anim_json
	doc.set_metadata(metadata)
	set_stage(doc, p_project)
	modified.emit()
	status.emit("Flat stage loaded: %s (%dx%d tiles, %d unique)" % [doc.get_name(), tiles_x, tiles_y, order.size()])

func _auto_load_animations(path: String, stage_name: String) -> void:
	var json := _find_animations_json(path, stage_name)
	if not json.is_empty():
		load_stage_animations(json, stage_name)

func _export_snes() -> void:
	if stage == null:
		return
	var dir := _default_export_dir()
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.current_dir = dir
	dlg.dir_selected.connect(func(d):
		var base := stage.get_name().to_lower().replace(" ", "_")
		var r: Dictionary = stage.export_snes(d, base)
		status.emit("Exported stage: %s" % String(r.get("chr", "")))
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _export_sgdk() -> void:
	if stage == null:
		return
	var dir := _default_export_dir()
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.current_dir = dir
	dlg.dir_selected.connect(func(d):
		var base := stage.get_name().to_lower().replace(" ", "_")
		var r: Dictionary = stage.export_sgdk(d, base)
		status.emit("Exported SGDK stage: %s" % String(r.get("png", "")))
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _default_export_dir() -> String:
	if project:
		return project.resolve("assets")
	return ""
