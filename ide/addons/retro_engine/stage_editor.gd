@tool
extends VBoxContainer
## Stage / background editor: tile map painting, layers, scrolling,
## parallax, collisions and native exports.

signal modified()
signal status(text: String)

const StageCanvas = preload("res://addons/retro_engine/stage_canvas.gd")
const TilePicker = preload("res://addons/retro_engine/tile_picker.gd")

var stage: RetroStage
var sprite: RetroSprite
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
var _collisions: ItemList
var _map_w: SpinBox
var _map_h: SpinBox
var _tile_size: SpinBox
var _tiles_x: SpinBox
var _bpp: OptionButton
var _use_camera: CheckBox
var _column_check: CheckBox

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
	_paint_check.toggled.connect(func(v): _canvas.paint_mode = v)
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

	var scroll_label_title := Label.new()
	scroll_label_title.text = "Scrolling / parallax preview"
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
	var srow := HBoxContainer.new()
	_use_camera = CheckBox.new()
	_use_camera.text = "Animate scroll"
	srow.add_child(_use_camera)
	var reset_scroll := Button.new()
	reset_scroll.text = "Reset"
	reset_scroll.pressed.connect(func(): _scroll_x.value = 0; _scroll_y.value = 0)
	srow.add_child(reset_scroll)
	side.add_child(srow)

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
	stage = doc
	project = p_project
	_canvas.set_stage(stage)
	if stage == null:
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
	if stage.get_scroll().has("speed_x"):
		_scroll_x.set_value_no_signal(int(stage.get_scroll().get("offset_x", 0)))
		_scroll_y.set_value_no_signal(int(stage.get_scroll().get("offset_y", 0)))
		_on_scroll_changed(0)
	status.emit("Stage loaded: %s" % stage.get_name())

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
	_canvas.scroll_offset = Vector2(_scroll_x.value, _scroll_y.value)
	_canvas.queue_redraw()
	if _scroll_label:
		_scroll_label.text = "X %d  Y %d" % [int(_scroll_x.value), int(_scroll_y.value)]
	if stage:
		stage.set_scroll({"h": true, "v": true, "offset_x": int(_scroll_x.value), "offset_y": int(_scroll_y.value), "speed_x": 1.0, "speed_y": 0.0})

func _add_layer() -> void:
	if stage == null:
		return
	stage.add_layer("layer_%d" % stage.get_layers().size(), stage.get_map())
	_refresh_layers()
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
			status.emit("PNG tileset has no companion .map; import a .chr/.map pair instead.")
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
		return
	status.emit("Unsupported stage source: " + ext)

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
