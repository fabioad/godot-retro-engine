@tool
extends VBoxContainer
## Sprite / shape editor: pixel editing, palette index preservation, frames,
## hitboxes, origin, VRAM estimate and native exports.

signal modified()
signal status(text: String)

const PixelCanvas = preload("res://addons/retro_engine/pixel_canvas.gd")
const SpriteSheet = preload("res://addons/retro_engine/sprite_sheet.gd")

var sprite: RetroSprite
var project: RetroProject
var animation: RetroAnimation
var platform: String = "snes"

var _canvas
var _frame_list: ItemList
var _info: Label
var _stats: Label
var _palette_bar: HBoxContainer
var _color_picker: ColorPickerButton
var _zoom_spin: SpinBox
var _grid_check: CheckBox
var _play_button: Button
var _play_timer: Timer
var _play_frame: int = 0
var _state_option: OptionButton
var _hit_type: OptionButton
var _hit_boxes: Array = []
var _frame_index: int = 0
var _origin_x: SpinBox
var _origin_y: SpinBox
var _frame_x: SpinBox
var _frame_y: SpinBox
var _frame_w: SpinBox
var _frame_h: SpinBox
var _duration: SpinBox
var _split_w: SpinBox
var _split_h: SpinBox
var _edit_mode: OptionButton
var _tiles_x: SpinBox
var _bpp_option: OptionButton
var _show_hitboxes: CheckBox

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	var canvas_scroll := ScrollContainer.new()
	canvas_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(canvas_scroll)
	_canvas = PixelCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.modified.connect(_on_canvas_modified)
	_canvas.hitbox_added.connect(_on_hitbox_drawn)
	_canvas.color_picked.connect(func(c): _color_picker.color = c; _set_active_color(c))
	_canvas.pixel_hovered.connect(_on_pixel_hovered)
	canvas_scroll.add_child(_canvas)

	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = 300
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 290
	side.add_theme_constant_override("separation", 5)
	side_scroll.add_child(side)

	_info = Label.new()
	_info.text = "No sprite loaded"
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_info)
	_stats = Label.new()
	_stats.add_theme_color_override("font_color", Color("#9fb4d0"))
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_stats)

	var tools := HBoxContainer.new()
	_edit_mode = OptionButton.new()
	_edit_mode.add_item("Paint", 0)
	_edit_mode.add_item("Hitbox", 1)
	_edit_mode.item_selected.connect(func(i): _canvas.set_edit_mode("paint" if i == 0 else "hitbox"))
	tools.add_child(_edit_mode)
	_zoom_spin = SpinBox.new()
	_zoom_spin.min_value = 1
	_zoom_spin.max_value = 32
	_zoom_spin.value = 4
	_zoom_spin.prefix = "Zoom "
	_zoom_spin.value_changed.connect(func(v): _canvas.zoom = int(v); _canvas.custom_minimum_size = Vector2(_canvas.image.get_width() * int(v), _canvas.image.get_height() * int(v)) if _canvas.image else Vector2(320, 240); _canvas.queue_redraw())
	tools.add_child(_zoom_spin)
	_grid_check = CheckBox.new()
	_grid_check.text = "Grid"
	_grid_check.button_pressed = true
	_grid_check.toggled.connect(func(v): _canvas.show_grid = v; _canvas.queue_redraw())
	tools.add_child(_grid_check)
	_show_hitboxes = CheckBox.new()
	_show_hitboxes.text = "Boxes"
	_show_hitboxes.button_pressed = true
	_show_hitboxes.toggled.connect(func(v): _canvas.set_hitboxes(_hit_boxes if v else []))
	tools.add_child(_show_hitboxes)
	side.add_child(tools)

	# Palette strip.
	var pal_label := Label.new()
	pal_label.text = "Palette (index order preserved)"
	side.add_child(pal_label)
	var pal_row := HBoxContainer.new()
	side.add_child(pal_row)
	_palette_bar = HBoxContainer.new()
	_palette_bar.add_theme_constant_override("separation", 1)
	pal_row.add_child(_palette_bar)
	_color_picker = ColorPickerButton.new()
	_color_picker.custom_minimum_size = Vector2(34, 28)
	_color_picker.color = Color.WHITE
	_color_picker.color_changed.connect(_set_active_color)
	pal_row.add_child(_color_picker)
	var remap_btn := Button.new()
	remap_btn.text = "Remap"
	remap_btn.tooltip_text = "Snap every pixel to the nearest palette color"
	remap_btn.pressed.connect(_remap_palette)
	pal_row.add_child(remap_btn)

	var sep1 := HSeparator.new()
	side.add_child(sep1)

	# Frames.
	var fhead := HBoxContainer.new()
	var flabel := Label.new()
	flabel.text = "Frames"
	flabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fhead.add_child(flabel)
	var split_btn := Button.new()
	split_btn.text = "Split grid"
	split_btn.pressed.connect(_split_grid)
	fhead.add_child(split_btn)
	side.add_child(fhead)

	var split_row := HBoxContainer.new()
	_split_w = _spin(1, 512, 16, "W")
	_split_h = _spin(1, 512, 16, "H")
	split_row.add_child(_split_w)
	split_row.add_child(_split_h)
	side.add_child(split_row)

	_frame_list = ItemList.new()
	_frame_list.custom_minimum_size.y = 110
	_frame_list.item_selected.connect(_on_frame_selected)
	side.add_child(_frame_list)

	var frow := HBoxContainer.new()
	_frame_x = _spin(0, 4096, 0, "X")
	_frame_y = _spin(0, 4096, 0, "Y")
	_frame_w = _spin(1, 512, 16, "W")
	_frame_h = _spin(1, 512, 16, "H")
	_duration = _spin(1, 999, 6, "Dur")
	frow.add_child(_frame_x)
	frow.add_child(_frame_y)
	frow.add_child(_frame_w)
	frow.add_child(_frame_h)
	frow.add_child(_duration)
	side.add_child(frow)
	var fbtns := HBoxContainer.new()
	var add_frame := Button.new()
	add_frame.text = "Add frame"
	add_frame.pressed.connect(_add_frame)
	fbtns.add_child(add_frame)
	var del_frame := Button.new()
	del_frame.text = "Delete frame"
	del_frame.pressed.connect(_delete_frame)
	fbtns.add_child(del_frame)
	var sync_btn := Button.new()
	sync_btn.text = "Apply rect"
	sync_btn.pressed.connect(_apply_frame_rect)
	fbtns.add_child(sync_btn)
	side.add_child(fbtns)

	# Origin.
	var orow := HBoxContainer.new()
	var olbl := Label.new()
	olbl.text = "Origin"
	orow.add_child(olbl)
	_origin_x = _spin(-999, 999, 0, "X")
	_origin_y = _spin(-999, 999, 0, "Y")
	_origin_x.value_changed.connect(_update_origin)
	_origin_y.value_changed.connect(_update_origin)
	orow.add_child(_origin_x)
	orow.add_child(_origin_y)
	side.add_child(orow)

	# Hitboxes.
	var hlabel := Label.new()
	hlabel.text = "Hitboxes / hurtboxes (selected frame)"
	side.add_child(hlabel)
	var hrow := HBoxContainer.new()
	_hit_type = OptionButton.new()
	_hit_type.add_item("Hitbox", 0)
	_hit_type.add_item("Hurtbox", 1)
	hrow.add_child(_hit_type)
	var add_hit := Button.new()
	add_hit.text = "Add full-frame box"
	add_hit.pressed.connect(_add_full_hitbox)
	hrow.add_child(add_hit)
	var clear_hit := Button.new()
	clear_hit.text = "Clear"
	clear_hit.pressed.connect(_clear_hitboxes)
	hrow.add_child(clear_hit)
	side.add_child(hrow)

	# Animation playback.
	var sep2 := HSeparator.new()
	side.add_child(sep2)
	var ahead := HBoxContainer.new()
	var alabel := Label.new()
	alabel.text = "Animation preview"
	alabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ahead.add_child(alabel)
	_state_option = OptionButton.new()
	_state_option.tooltip_text = "Animation state from the Animation tab"
	ahead.add_child(_state_option)
	side.add_child(ahead)
	var abtns := HBoxContainer.new()
	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.pressed.connect(_toggle_play)
	abtns.add_child(_play_button)
	var stop_btn := Button.new()
	stop_btn.text = "Stop"
	stop_btn.pressed.connect(_stop_play)
	abtns.add_child(stop_btn)
	side.add_child(abtns)
	_play_timer = Timer.new()
	_play_timer.wait_time = 1.0 / 60.0
	_play_timer.timeout.connect(_tick_play)
	add_child(_play_timer)

	# Import/export.
	var ehead := Label.new()
	ehead.text = "Export"
	side.add_child(ehead)
	var erow := HBoxContainer.new()
	var exp_png := Button.new()
	exp_png.text = "PNG"
	exp_png.pressed.connect(_export_png)
	erow.add_child(exp_png)
	var exp_snes := Button.new()
	exp_snes.text = "SNES .chr/.pal/.inc"
	exp_snes.pressed.connect(_export_snes)
	erow.add_child(exp_snes)
	var exp_md := Button.new()
	exp_md.text = "MD .png/.res"
	exp_md.pressed.connect(_export_sgdk)
	erow.add_child(exp_md)
	side.add_child(erow)

	var cvt := HBoxContainer.new()
	var tiles_lbl := Label.new()
	tiles_lbl.text = "Tiles/row"
	cvt.add_child(tiles_lbl)
	_tiles_x = _spin(1, 128, 16, "")
	_tiles_x.value_changed.connect(func(_v): _reload_chr_if_needed())
	cvt.add_child(_tiles_x)
	_bpp_option = OptionButton.new()
	_bpp_option.add_item("2bpp", 0)
	_bpp_option.add_item("4bpp", 1)
	_bpp_option.add_item("8bpp (Mode 7)", 2)
	_bpp_option.select(1)
	_bpp_option.item_selected.connect(func(_i): _reload_chr_if_needed())
	cvt.add_child(_bpp_option)
	side.add_child(cvt)

func _spin(minv: float, maxv: float, value: float, prefix: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.value = value
	if prefix != "":
		s.prefix = prefix
	s.custom_minimum_size.x = 62
	return s

func _set_active_color(c: Color) -> void:
	_color_picker.color = c
	_canvas.active_color = c

func set_platform(p: String) -> void:
	platform = p
	var maxc := 256 if p == "snes" else 64
	if sprite:
		if p == "snes":
			_bpp_option.set_item_disabled(2, false)
		else:
			_bpp_option.select(1)
			_bpp_option.set_item_disabled(2, true)

func set_sprite(doc: RetroSprite, p_project: RetroProject = null) -> void:
	sprite = doc
	project = p_project
	if sprite == null:
		_canvas.set_image(null)
		_frame_list.clear()
		_info.text = "No sprite loaded"
		return
	# Indexed sheets often encode transparency as palette index 0 (usually
	# magenta). Convert that to alpha for editing/preview; encoding still
	# writes those pixels back as index 0.
	SpriteSheet.apply_sprite_key(sprite)
	_canvas.set_image(sprite.get_image())
	_canvas.set_palette(sprite.get_palette())
	_canvas.origin = sprite.get_origin()
	_canvas.show_origin = true
	_origin_x.set_value_no_signal(sprite.get_origin().x)
	_origin_y.set_value_no_signal(sprite.get_origin().y)
	_bpp_option.select(0 if sprite.get_bpp() == 2 else (2 if sprite.get_bpp() == 8 else 1))
	_rebuild_frames()
	_rebuild_palette()
	if sprite.get_image():
		_canvas.fit_zoom(Vector2(560, 420))
		if sprite.get_image().get_height() <= 64 and _canvas.zoom < 2:
			_canvas.zoom = 2
			_canvas.custom_minimum_size = Vector2(sprite.get_image().get_width() * 2, sprite.get_image().get_height() * 2)
		_zoom_spin.set_value_no_signal(_canvas.zoom)
	_info.text = "%s  |  %s" % [sprite.get_name(), sprite.get_source_path()]
	_update_stats()
	status.emit("Sprite loaded: %s" % sprite.get_name())

func set_animation(anim: RetroAnimation) -> void:
	animation = anim
	_state_option.clear()
	if anim == null:
		return
	var keys := anim.get_states().keys()
	for k in keys:
		_state_option.add_item(String(k))
	if _state_option.item_count > 0:
		_state_option.select(0)

func _rebuild_frames() -> void:
	_frame_list.clear()
	if sprite == null:
		return
	var frames := sprite.get_frames()
	if frames.size() <= 1 and sprite.get_image():
		# Imported sheets arrive as one full-image frame. Split by alpha gaps
		# so the frame list and stats count the real scenes immediately.
		var detected := SpriteSheet.ensure_sprite_frames(sprite)
		if detected.size() > 1:
			frames = detected
	if frames.is_empty() and sprite.get_image():
		sprite.add_frame("full", Rect2i(0, 0, sprite.get_image().get_width(), sprite.get_image().get_height()), 6)
		frames = sprite.get_frames()
	for i in range(frames.size()):
		var f: Dictionary = frames[i]
		var r: Rect2i = f.get("rect", Rect2i())
		var text := "%02d  %s  %dx%d @%d,%d  %df" % [i, String(f.get("name", "frame")), r.size.x, r.size.y, r.position.x, r.position.y, int(f.get("duration", 1))]
		_frame_list.add_item(text)
	if _frame_list.item_count > 0:
		_frame_index = clampi(_frame_index, 0, _frame_list.item_count - 1)
		_frame_list.select(_frame_index)
		_on_frame_selected(_frame_index)

func _rebuild_palette() -> void:
	for c in _palette_bar.get_children():
		c.queue_free()
	if sprite == null:
		return
	var pal := sprite.get_palette()
	for i in range(pal.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(20, 20)
		b.tooltip_text = "Index %d %s" % [i, pal[i].to_html(true)]
		var sb := StyleBoxFlat.new()
		sb.bg_color = pal[i]
		sb.border_color = Color("#3b4658")
		sb.set_border_width_all(1)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.pressed.connect(func(): _set_active_color(pal[i]))
		_palette_bar.add_child(b)
	if pal.size() > 0:
		_set_active_color(pal[0])

func _on_canvas_modified() -> void:
	if sprite:
		sprite.set_image(_canvas.image)
		_update_stats()
		modified.emit()

func _on_pixel_hovered(x: int, y: int) -> void:
	if sprite and _canvas.image:
		var c: Color = _canvas.image.get_pixel(x, y)
		_stats.text = _base_stats() + "\nPixel %d,%d  %s" % [x, y, c.to_html(true)]

func _base_stats() -> String:
	if sprite == null:
		return ""
	var a: Dictionary = sprite.analyze()
	return "Sheet %dx%d  |  %d frames  |  palette %d  |  %dbpp\nVRAM ~%d bytes" % [
		int(a.get("width", 0)), int(a.get("height", 0)), int(a.get("frames", 0)),
		int(a.get("palette_size", 0)), int(a.get("bpp", 4)), int(a.get("vram_bytes", 0))]

func _update_stats() -> void:
	if _stats:
		_stats.text = _base_stats()

func _on_frame_selected(index: int) -> void:
	_frame_index = index
	_hit_boxes = []
	if sprite == null:
		return
	var frames := sprite.get_frames()
	if index < 0 or index >= frames.size():
		return
	var f: Dictionary = frames[index]
	var r: Rect2i = f.get("rect", Rect2i())
	_frame_x.set_value_no_signal(r.position.x)
	_frame_y.set_value_no_signal(r.position.y)
	_frame_w.set_value_no_signal(r.size.x)
	_frame_h.set_value_no_signal(r.size.y)
	_duration.set_value_no_signal(int(f.get("duration", 1)))
	_hit_boxes = f.get("hitboxes", [])
	_canvas.set_hitboxes(_hit_boxes if _show_hitboxes.button_pressed else [])
	_canvas.frame_rect = r
	_canvas.show_frame = true
	_canvas.queue_redraw()

func _split_grid() -> void:
	if sprite == null:
		return
	sprite.split_grid(int(_split_w.value), int(_split_h.value))
	_frame_index = 0
	_rebuild_frames()
	_update_stats()
	modified.emit()

func _add_frame() -> void:
	if sprite == null:
		return
	var r := Rect2i(int(_frame_x.value), int(_frame_y.value), int(_frame_w.value), int(_frame_h.value))
	sprite.add_frame("frame_%d" % sprite.get_frames().size(), r, int(_duration.value))
	_frame_index = sprite.get_frames().size() - 1
	_rebuild_frames()
	modified.emit()

func _delete_frame() -> void:
	if sprite == null:
		return
	sprite.remove_frame(_frame_index)
	_frame_index = clampi(_frame_index, 0, max(0, sprite.get_frames().size() - 1))
	_rebuild_frames()
	modified.emit()

func _apply_frame_rect() -> void:
	if sprite == null or _frame_index >= sprite.get_frames().size():
		return
	var frames := sprite.get_frames()
	var f: Dictionary = frames[_frame_index]
	f["rect"] = Rect2i(int(_frame_x.value), int(_frame_y.value), int(_frame_w.value), int(_frame_h.value))
	f["duration"] = int(_duration.value)
	frames[_frame_index] = f
	sprite.set_frames(frames)
	_rebuild_frames()
	modified.emit()

func _update_origin() -> void:
	if sprite == null:
		return
	sprite.set_origin(Vector2i(int(_origin_x.value), int(_origin_y.value)))
	_canvas.origin = sprite.get_origin()
	_canvas.queue_redraw()
	modified.emit()

func _add_full_hitbox() -> void:
	if sprite == null or _frame_index >= sprite.get_frames().size():
		return
	var type := "hit" if _hit_type.selected == 0 else "hurt"
	var r := Rect2i(0, 0, int(_frame_w.value), int(_frame_h.value))
	sprite.add_hitbox(_frame_index, r, type)
	_on_frame_selected(_frame_index)
	modified.emit()

func _on_hitbox_drawn(r: Rect2i) -> void:
	if sprite == null or _frame_index >= sprite.get_frames().size():
		return
	var type := "hit" if _hit_type.selected == 0 else "hurt"
	sprite.add_hitbox(_frame_index, r, type)
	_on_frame_selected(_frame_index)
	modified.emit()

func _clear_hitboxes() -> void:
	if sprite == null or _frame_index >= sprite.get_frames().size():
		return
	var frames := sprite.get_frames()
	var f: Dictionary = frames[_frame_index]
	f["hitboxes"] = []
	frames[_frame_index] = f
	sprite.set_frames(frames)
	_on_frame_selected(_frame_index)
	modified.emit()

func _remap_palette() -> void:
	if sprite == null or sprite.get_image() == null:
		return
	var mapped: Image = RetroGraphics.map_to_palette(sprite.get_image(), sprite.get_palette(), true)
	sprite.set_image(mapped)
	_canvas.set_image(mapped)
	_update_stats()
	modified.emit()

func _reload_chr_if_needed() -> void:
	if sprite == null or sprite.get_source_path().is_empty():
		return
	var ext := sprite.get_source_path().get_extension().to_lower()
	if ext != "chr" and ext != "pic":
		return
	var pal_path := ""
	if project:
		for r in project.get_resources():
			if String(r.get("path", "")) == sprite.get_source_path():
				pal_path = String(r.get("palette_path", ""))
				break
	if pal_path.is_empty():
		pal_path = sprite.get_source_path().get_basename() + ".pal"
	var bpp := 2 if _bpp_option.selected == 0 else (8 if _bpp_option.selected == 2 else 4)
	sprite.set_platform(platform)
	var err := sprite.load_snes(sprite.get_source_path(), pal_path, int(_tiles_x.value), bpp)
	if err == OK:
		set_sprite(sprite, project)
		modified.emit()

func _toggle_play() -> void:
	if _play_timer.is_stopped():
		_play_timer.start()
		_play_button.text = "Pause"
	else:
		_play_timer.stop()
		_play_button.text = "Play"

func _stop_play() -> void:
	_play_timer.stop()
	_play_button.text = "Play"
	_play_frame = 0

func _tick_play() -> void:
	if sprite == null or sprite.get_frames().is_empty():
		return
	var frames := sprite.get_frames()
	var f: Dictionary = frames[_play_frame % frames.size()]
	_frame_index = _play_frame % frames.size()
	_frame_list.select(_frame_index)
	_on_frame_selected(_frame_index)
	_play_frame += 1
	var duration := int(f.get("duration", 6))
	_play_timer.wait_time = duration / 60.0

func open_resource(res: Dictionary, p_project: RetroProject) -> void:
	project = p_project
	platform = p_project.get_platform() if p_project else platform
	var path := String(res.get("path", ""))
	var ext := String(res.get("ext", ""))
	var doc := RetroSprite.new()
	doc.set_platform(platform)
	var err := FAILED
	if ext in ["png", "bmp", "webp", "jpg", "jpeg", "tga", "gif"]:
		err = doc.load_image(path)
	elif ext == "chr" or ext == "pic":
		var pal_path := String(res.get("palette_path", ""))
		if pal_path.is_empty():
			pal_path = path.get_basename() + ".pal"
		var tiles_x := 16
		var bpp := 4
		if String(res.get("kind", "")) == "pvsneslib_tiles":
			tiles_x = 16
		err = doc.load_snes(path, pal_path, tiles_x, bpp)
	else:
		status.emit("Unsupported sprite source: " + ext)
		return
	if err != OK:
		status.emit("Could not open sprite: %s" % path)
		return
	var frame_data: Variant = res.get("frames", [])
	if frame_data is Array and not frame_data.is_empty():
		var frames: Array = []
		for fd in frame_data:
			if typeof(fd) != TYPE_DICTIONARY:
				continue
			var frame_dict: Dictionary = fd
			var rect := Rect2i()
			var rect_data: Variant = frame_dict.get("rect", null)
			if rect_data is Rect2i:
				rect = rect_data
			elif rect_data is Array and rect_data.size() >= 4:
				rect = Rect2i(int(rect_data[0]), int(rect_data[1]), int(rect_data[2]), int(rect_data[3]))
			elif rect_data is Dictionary:
				rect = Rect2i(int(rect_data.get("x", 0)), int(rect_data.get("y", 0)), int(rect_data.get("w", 0)), int(rect_data.get("h", 0)))
			if rect.size.x <= 0 or rect.size.y <= 0:
				continue
			frames.append({
				"name": String(frame_dict.get("name", "frame_%d" % frames.size())),
				"rect": rect,
				"duration": int(frame_dict.get("duration", 6)),
				"hitboxes": [],
				"events": [],
			})
		if not frames.is_empty():
			doc.set_frames(frames)
	if doc.get_image() != null:
		SpriteSheet.apply_chroma_key(doc.get_image(), doc.get_palette())
	_tiles_x.set_value_no_signal(16)
	var frame_w := int(res.get("frame_w", 0))
	var frame_h := int(res.get("frame_h", 0))
	if frame_w > 0 and frame_h > 0:
		_split_w.set_value_no_signal(frame_w)
		_split_h.set_value_no_signal(frame_h)
	elif ext in ["png", "bmp", "webp"]:
		var img := doc.get_image()
		if img and img.get_width() % 16 == 0 and img.get_height() % 16 == 0:
			_split_w.set_value_no_signal(16)
			_split_h.set_value_no_signal(16)
	set_sprite(doc, p_project)
	modified.emit()

func _export_png() -> void:
	if sprite == null:
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.png", "PNG (indexed, palette preserved)")
	dlg.current_file = sprite.get_name() + ".png"
	dlg.file_selected.connect(func(path):
		var r: Dictionary = sprite.export_png_asset(path)
		status.emit("Exported PNG: %s" % path)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func _default_export_dir() -> String:
	if project:
		return project.resolve("assets")
	return ""

func _export_snes() -> void:
	if sprite == null:
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.current_dir = _default_export_dir()
	dlg.dir_selected.connect(func(dir):
		var base := sprite.get_name().to_lower().replace(" ", "_")
		var r: Dictionary = sprite.export_snes(dir, base)
		status.emit("Exported SNES: %s" % String(r.get("chr", "")))
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _export_sgdk() -> void:
	if sprite == null:
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.current_dir = _default_export_dir()
	dlg.dir_selected.connect(func(dir):
		var base := sprite.get_name().to_lower().replace(" ", "_")
		var r: Dictionary = sprite.export_sgdk(dir, base)
		status.emit("Exported SGDK sprite: %s" % String(r.get("png", "")))
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _paint_at(local_pos: Vector2) -> void:
	pass
