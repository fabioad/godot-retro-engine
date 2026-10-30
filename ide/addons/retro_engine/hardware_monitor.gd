@tool
extends VBoxContainer
## Hardware monitor. All numbers are estimates derived from the console docs
## and the actual imported resources; they are not measurements from a ROM.

const I18n = preload("res://addons/retro_engine/i18n.gd")

var platform: String = "snes"
var mode: String = "mode1"
var _title: Label
var _mode_label: Label
var _bars: Dictionary = {}
var _values: Dictionary = {}
var _issues: RichTextLabel
var _details: Label

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_title = Label.new()
	_title.text = I18n.t("hardware.title")
	_title.add_theme_font_size_override("font_size", 15)
	add_child(_title)
	_mode_label = Label.new()
	_mode_label.add_theme_color_override("font_color", Color("#9fb4d0"))
	_mode_label.add_theme_font_size_override("font_size", 12)
	_mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_label.custom_minimum_size.x = 0
	_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_label.clip_text = false
	_mode_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_mode_label)
	var bars := [
		["VRAM", I18n.t("hardware.vram")],
		["Palette / CRAM", I18n.t("hardware.palette")],
		["ROM", I18n.t("hardware.rom")],
		["Sprites", I18n.t("hardware.sprites")],
	]
	for item in bars:
		var key: String = String(item[0])
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		var top := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = String(item[1])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(lbl)
		var val := Label.new()
		val.text = "-"
		val.add_theme_color_override("font_color", Color("#9fb4d0"))
		val.add_theme_font_size_override("font_size", 11)
		val.clip_text = true
		val.custom_minimum_size.x = 0
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		top.add_child(val)
		row.add_child(top)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 10
		bar.max_value = 100
		row.add_child(bar)
		add_child(row)
		_bars[key] = bar
		_values[key] = val
	var sep := HSeparator.new()
	add_child(sep)
	var dtitle := Label.new()
	dtitle.text = I18n.t("hardware.details")
	dtitle.add_theme_font_size_override("font_size", 13)
	add_child(dtitle)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_color_override("font_color", Color("#8b98ad"))
	_details.add_theme_font_size_override("font_size", 11)
	_details.custom_minimum_size.x = 0
	add_child(_details)
	_issues = RichTextLabel.new()
	_issues.bbcode_enabled = true
	_issues.fit_content = true
	_issues.custom_minimum_size.y = 80
	_issues.scroll_active = true
	add_child(_issues)

func set_platform(p: String, m: String) -> void:
	platform = p
	mode = m
	refresh(null, null, null, 0)

func refresh(stage: RetroStage, sprite: RetroSprite, animation: RetroAnimation, rom_size: int) -> void:
	var spec: Dictionary = RetroHardware.specs(platform, mode)
	if spec.is_empty():
		return
	_title.text = I18n.t("hardware.snes_name") if platform == "snes" else I18n.t("hardware.md_name")
	_mode_label.text = _mode_description()
	var usage := {
		"mode": mode,
		"tile_size": 8,
		"bpp": 4,
		"tile_count": 0,
		"map_w": 0,
		"map_h": 0,
		"layers": 1,
		"sprites": 0,
		"palette_colors": 16,
		"rom_bytes": rom_size,
	}
	var extra := ""
	if stage != null:
		var a := stage.analyze()
		usage["tile_size"] = stage.get_tile_size()
		usage["bpp"] = stage.get_bpp()
		usage["tile_count"] = int(a.get("map_entries", 0))
		usage["map_w"] = int(a.get("map_w", 0))
		usage["map_h"] = int(a.get("map_h", 0))
		usage["layers"] = 1
		usage["palette_colors"] = int(a.get("palette_colors", 16))
		extra += I18n.t("hardware.stage", {
			"w": int(a.get("map_w", 0)), "h": int(a.get("map_h", 0)),
			"px": int(a.get("pixel_width", 0)), "tile": int(a.get("tile_size", 8)),
			"bpp": int(a.get("bpp", 4)),
		}) + "\n"
	var sprite_count := 0
	if sprite != null:
		var sa := sprite.analyze()
		var frames := int(sa.get("frames", 0))
		sprite_count = frames
		usage["sprites"] = frames
		usage["sprite_w"] = int(sprite.get_image().get_width()) if sprite.get_image() else 16
		usage["sprite_h"] = int(sprite.get_image().get_height()) if sprite.get_image() else 16
		if animation != null:
			var aa := animation.analyze()
			extra += I18n.t("hardware.animation", {
				"states": int(aa.get("states", 0)), "frames": int(aa.get("frames", 0)),
				"hitboxes": int(aa.get("hitboxes", 0)),
			}) + "\n"
		extra += I18n.t("hardware.sprite_sheet", {
			"frames": frames, "colors": int(sa.get("palette_size", 0)), "bpp": int(sa.get("bpp", 4)),
		}) + "\n"
	if rom_size > 0:
		extra += I18n.t("hardware.last_rom", {"size": "%.2f" % (rom_size / 1048576.0)}) + "\n"
	var est: Dictionary = RetroHardware.estimate(platform, usage)
	var vram := int(est.get("vram_total", 0))
	var vcap := int(est.get("vram_capacity", 65536))
	var pct := float(est.get("vram_percent", 0.0))
	_set_bar("VRAM", pct, "%s / %s" % [_fmt(vram), _fmt(vcap)])
	var colors := int(est.get("palette_capacity", 256))
	var used_colors := int(est.get("palette_bytes", 0)) / 2
	_set_bar("Palette / CRAM", float(est.get("palette_percent", 0.0)), "%d / %d" % [used_colors, colors])
	var rcap := int(est.get("rom_capacity", 4194304))
	_set_bar("ROM", (float(rom_size) * 100.0 / max(1, rcap)), "%s / %s" % [_fmt(rom_size), _fmt(rcap)])
	var slimit := int(spec.get("sprites_total", 128))
	_set_bar("Sprites", (float(sprite_count) * 100.0 / max(1, slimit)), "%d / %d (OAM/VDP)" % [sprite_count, slimit])
	_details.text = extra + I18n.t("hardware.refresh", {
		"hz": "%.2f" % float(spec.get("refresh_hz", 60)),
		"cpu": String(spec.get("cpu", "")),
	})
	var text := ""
	for issue in est.get("issues", []):
		text += "[color=#ff7a7a]- %s[/color]\n" % String(issue)
	for note in est.get("notes", []):
		text += "[color=#ffd45e]- %s[/color]\n" % String(note)
	if text.is_empty():
		text = "[color=#6ee7a8]%s[/color]" % I18n.t("hardware.no_limits")
	_issues.text = text

func _mode_description() -> String:
	if platform == "snes":
		if mode == "mode0":
			return I18n.t("hardware.snes_mode0")
		if mode == "mode7":
			return I18n.t("hardware.snes_mode7")
		return I18n.t("hardware.snes_mode1")
	return I18n.t("hardware.md_h32") if mode == "h32" else I18n.t("hardware.md_h40")

func _set_bar(key: String, value: float, label: String) -> void:
	if not _bars.has(key):
		return
	var bar: ProgressBar = _bars[key]
	bar.value = clampf(value, 0.0, 100.0)
	var v: Label = _values[key]
	v.text = label
	if value > 100.0:
		bar.modulate = Color("#ff7a7a")
	elif value > 85.0:
		bar.modulate = Color("#ffd45e")
	else:
		bar.modulate = Color("#6ee7a8")

func _fmt(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.2f MiB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%.1f KiB" % (bytes / 1024.0)
	return str(bytes) + " B"
