@tool
extends Control
## Audio asset editor: import/create SNES and Mega Drive BGM/SFX, tune
## synthesized SFX and audition the target conversion before building a ROM.

signal status(text: String)
signal modified()

const AudioPipeline = preload("res://addons/retro_engine/audio_pipeline.gd")
const I18n = preload("res://addons/retro_engine/i18n.gd")

var _project: RetroProject
var _asset_list: ItemList
var _info: RichTextLabel
var _name: LineEdit
var _kind: OptionButton
var _waveform: OptionButton
var _frequency: SpinBox
var _duration: SpinBox
var _volume: SpinBox
var _duty: SpinBox
var _attack: SpinBox
var _decay: SpinBox
var _sustain: SpinBox
var _release: SpinBox
var _slide: SpinBox
var _vib_hz: SpinBox
var _vib_depth: SpinBox
var _noise: SpinBox
var _bitcrush: SpinBox
var _player: AudioStreamPlayer
var _status: Label
var _selected := ""
var _current: Dictionary = {}
var _search: LineEdit
var _kind_filter: OptionButton
var _filter_label: Label
var _all_assets: Array = []
var _preview_generation := 0
var _preview_thread: Thread
var _preview_busy := false
var _pending_preview: Dictionary = {}

func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 5)
	add_child(root)
	var head := Label.new()
	head.text = "BGM / SFX — real SNES (SNESMOD/BRR) and Mega Drive (XGM2/PSG/PCM) conversion"
	head.add_theme_font_size_override("font_size", 13)
	root.add_child(head)
	var imports := HBoxContainer.new()
	root.add_child(imports)
	var bgm := Button.new(); bgm.text = "Import BGM (.mid/.it/.mp3/.wav)"
	bgm.pressed.connect(func(): _open_import("bgm"))
	imports.add_child(bgm)
	var sfx := Button.new(); sfx.text = "Import SFX (.wav/.mp3)"
	sfx.pressed.connect(func(): _open_import("sfx"))
	imports.add_child(sfx)
	var convert := Button.new(); convert.text = "Convert & Preview Both"
	convert.pressed.connect(_convert_both)
	imports.add_child(convert)
	var browse := HBoxContainer.new()
	root.add_child(browse)
	_search = LineEdit.new()
	_search.placeholder_text = I18n.t("audio.filter")
	_search.custom_minimum_size.x = 120
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _apply_filter())
	browse.add_child(_search)
	_kind_filter = OptionButton.new()
	_kind_filter.add_item(I18n.t("audio.all"), 0)
	_kind_filter.add_item(I18n.t("audio.bgm"), 1)
	_kind_filter.add_item(I18n.t("audio.sfx"), 2)
	_kind_filter.item_selected.connect(func(_i): _apply_filter())
	browse.add_child(_kind_filter)
	_filter_label = Label.new()
	_filter_label.custom_minimum_size.x = 150
	_filter_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_filter_label.add_theme_color_override("font_color", Color("#9fb4d0"))
	browse.add_child(_filter_label)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	_asset_list = ItemList.new()
	_asset_list.custom_minimum_size.x = 240
	_asset_list.item_selected.connect(_on_selected)
	split.add_child(_asset_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.custom_minimum_size.y = 70
	right.add_child(_info)
	var form := GridContainer.new()
	form.columns = 4
	right.add_child(form)
	_name = LineEdit.new(); _name.placeholder_text = "name"
	form.add_child(_label("Name")); form.add_child(_name)
	_kind = OptionButton.new(); _kind.add_item("SFX", 0); _kind.add_item("BGM", 1)
	form.add_child(_label("Kind")); form.add_child(_kind)
	_waveform = OptionButton.new()
	for w in ["square", "triangle", "sine", "saw", "noise"]:
		_waveform.add_item(w)
	form.add_child(_label("Wave")); form.add_child(_waveform)
	_frequency = _spin(20, 20000, 1, 660, " Hz"); form.add_child(_label("Frequency")); form.add_child(_frequency)
	_duration = _spin(10, 10000, 1, 220, " ms"); form.add_child(_label("Duration")); form.add_child(_duration)
	_volume = _spin(0, 1, 0.01, 0.8, ""); form.add_child(_label("Volume")); form.add_child(_volume)
	_duty = _spin(0.05, 0.95, 0.01, 0.5, ""); form.add_child(_label("Duty")); form.add_child(_duty)
	_attack = _spin(0, 2000, 1, 2, " ms"); form.add_child(_label("Attack")); form.add_child(_attack)
	_decay = _spin(0, 4000, 1, 50, " ms"); form.add_child(_label("Decay")); form.add_child(_decay)
	_sustain = _spin(0, 1, 0.01, 0.65, ""); form.add_child(_label("Sustain")); form.add_child(_sustain)
	_release = _spin(0, 4000, 1, 70, " ms"); form.add_child(_label("Release")); form.add_child(_release)
	_slide = _spin(-48, 48, 0.5, 0, " st"); form.add_child(_label("Pitch slide")); form.add_child(_slide)
	_vib_hz = _spin(0, 40, 0.5, 0, " Hz"); form.add_child(_label("Vibrato")); form.add_child(_vib_hz)
	_vib_depth = _spin(0, 4, 0.05, 0, " st"); form.add_child(_label("Vib depth")); form.add_child(_vib_depth)
	_noise = _spin(0, 1, 0.01, 0, ""); form.add_child(_label("Noise mix")); form.add_child(_noise)
	_bitcrush = _spin(2, 16, 1, 16, " bit"); form.add_child(_label("Bitcrush")); form.add_child(_bitcrush)
	var actions := HBoxContainer.new()
	right.add_child(actions)
	var create := Button.new(); create.text = "Create / Update SFX"
	create.pressed.connect(_create_sfx)
	actions.add_child(create)
	var play := Button.new(); play.text = I18n.t("audio.play")
	play.tooltip_text = I18n.t("audio.play_tip")
	play.pressed.connect(play_selected)
	actions.add_child(play)
	var stop := Button.new(); stop.text = "Stop"
	stop.pressed.connect(_stop_preview)
	actions.add_child(stop)
	var targets := HBoxContainer.new()
	right.add_child(targets)
	var ps := Button.new(); ps.text = "Preview SNES"
	ps.pressed.connect(func(): _preview("snes"))
	targets.add_child(ps)
	var pm := Button.new(); pm.text = "Preview Mega Drive"
	pm.pressed.connect(func(): _preview("megadrive"))
	targets.add_child(pm)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("#9fb4d0"))
	right.add_child(_status)
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)

func _exit_tree() -> void:
	if _preview_thread != null:
		_preview_thread.wait_to_finish()
		_preview_thread = null

func _label(text: String) -> Label:
	var l := Label.new(); l.text = text; return l

func _spin(min_v: float, max_v: float, step: float, value: float, suffix: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.suffix = suffix
	s.custom_minimum_size.x = 100
	return s

func set_project(project: RetroProject) -> void:
	_project = project
	_refresh_list()

func _refresh_list() -> void:
	if _asset_list == null:
		return
	_all_assets.clear()
	if _project == null:
		_apply_filter()
		return
	for r in _project.find_resources("audio", true):
		var path := String(r.get("path", ""))
		var data := _read_descriptor(path)
		var name := String(data.get("name", r.get("name", path.get_file().get_basename())))
		var kind := String(data.get("kind", r.get("kind", "sfx")))
		if kind not in ["bgm", "sfx"]:
			kind = "bgm" if path.get_extension().to_lower() in ["mid", "it"] else "sfx"
		_all_assets.append({"path": path, "name": name, "kind": kind})
	_apply_filter()

func _apply_filter() -> void:
	if _asset_list == null:
		return
	var selected_path := _selected
	_asset_list.clear()
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	var want := ""
	if _kind_filter != null:
		want = ["", "bgm", "sfx"][clampi(_kind_filter.selected, 0, 2)]
	var bgm_count := 0
	var sfx_count := 0
	for asset in _all_assets:
		var kind := String(asset.get("kind", "sfx"))
		if kind == "bgm":
			bgm_count += 1
		elif kind == "sfx":
			sfx_count += 1
		if not want.is_empty() and kind != want:
			continue
		var haystack := (String(asset.get("name", "")) + " " + String(asset.get("path", ""))).to_lower()
		if not query.is_empty() and not haystack.contains(query):
			continue
		var idx := _asset_list.item_count
		_asset_list.add_item("%s  [%s]" % [String(asset.get("name", "")), kind.to_upper()])
		_asset_list.set_item_metadata(idx, String(asset.get("path", "")))
		_asset_list.set_item_tooltip(idx, String(asset.get("path", "")))
		if String(asset.get("path", "")) == selected_path:
			_asset_list.select(idx)
	if _filter_label != null:
		_filter_label.text = I18n.t("audio.count", {"bgm": bgm_count, "sfx": sfx_count})
	if _asset_list.get_selected_items().is_empty():
		_selected = ""

func select_asset(path: String, autoplay := false) -> void:
	if path.is_empty():
		return
	_selected = path
	if _search != null:
		_search.text = ""
	if _kind_filter != null:
		_kind_filter.select(0)
	_apply_filter()
	for i in range(_asset_list.item_count):
		if String(_asset_list.get_item_metadata(i)) == path:
			_asset_list.select(i)
			_asset_list.ensure_current_is_visible()
			_on_selected(i)
			if autoplay:
				play_selected()
			return

func focus_search() -> void:
	if _search != null:
		_search.grab_focus()
		_search.select_all()

func set_kind_filter(kind: String) -> void:
	if _kind_filter != null:
		_kind_filter.select(1 if kind == "bgm" else (2 if kind == "sfx" else 0))
		_apply_filter()

func play_selected() -> void:
	if _project == null:
		status.emit(I18n.t("audio.project_missing"))
		return
	if _selected.is_empty():
		status.emit(I18n.t("audio.select_first"))
		return
	var target := _project.get_platform()
	if target not in ["snes", "megadrive"]:
		target = "snes"
	_preview(target)

func stop_preview() -> void:
	_stop_preview()

func _read_descriptor(path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return {}

func _selected_descriptor() -> Dictionary:
	if _selected.is_empty():
		return {}
	return _read_descriptor(_selected)

func _on_selected(index: int) -> void:
	if index < 0:
		return
	_selected = String(_asset_list.get_item_metadata(index))
	var d := _selected_descriptor()
	if d.is_empty():
		var ext := _selected.get_extension().to_lower()
		d = {"name": _selected.get_file().get_basename(),
			"kind": "bgm" if ext in ["mid", "it"] else "sfx",
			"source": _selected, "params": {}}
	_current = d
	_name.text = String(d.get("name", ""))
	_info.clear()
	_info.append_text("[b]%s[/b]  (%s)\n" % [String(d.get("name", "")), String(d.get("kind", "")).to_upper()])
	_info.append_text("source: %s\n" % String(d.get("source", "")))
	var pv: Dictionary = d.get("previews", {})
	for k in pv:
		_info.append_text("%s preview: %s\n" % [k, String(pv[k])])
	if String(d.get("kind", "")) == "sfx":
		_kind.select(0)
		var params: Dictionary = d.get("params", {})
		_apply_params(params)
	else:
		_kind.select(1)

func _apply_params(p: Dictionary) -> void:
	var wave := String(p.get("waveform", "square"))
	for i in range(_waveform.item_count):
		if _waveform.get_item_text(i) == wave:
			_waveform.select(i)
			break
	_frequency.value = float(p.get("frequency", 660))
	_duration.value = float(p.get("duration_ms", 220))
	_volume.value = float(p.get("volume", 0.8))
	_duty.value = float(p.get("duty", 0.5))
	_attack.value = float(p.get("attack_ms", 2))
	_decay.value = float(p.get("decay_ms", 50))
	_sustain.value = float(p.get("sustain", 0.65))
	_release.value = float(p.get("release_ms", 70))
	_slide.value = float(p.get("pitch_slide", 0))
	_vib_hz.value = float(p.get("vibrato_hz", 0))
	_vib_depth.value = float(p.get("vibrato_depth", 0))
	_noise.value = float(p.get("noise", 0))
	_bitcrush.value = float(p.get("bitcrush", 16))

func _params() -> Dictionary:
	return {
		"waveform": _waveform.get_item_text(_waveform.selected),
		"frequency": _frequency.value,
		"duration_ms": _duration.value,
		"volume": _volume.value,
		"duty": _duty.value,
		"attack_ms": _attack.value,
		"decay_ms": _decay.value,
		"sustain": _sustain.value,
		"release_ms": _release.value,
		"pitch_slide": _slide.value,
		"vibrato_hz": _vib_hz.value,
		"vibrato_depth": _vib_depth.value,
		"noise": _noise.value,
		"bitcrush": int(_bitcrush.value),
	}

func _open_import(kind: String) -> void:
	if _project == null:
		status.emit("Open a retro project before importing audio.")
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.mid,*.it,*.wav,*.mp3", "Audio")
	dlg.file_selected.connect(func(path): _add_asset(path, kind))
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func _add_asset(source_path: String, kind: String) -> void:
	if _project == null or source_path.is_empty():
		return
	var name := _slug(source_path.get_file().get_basename())
	var ext := source_path.get_extension().to_lower()
	var audio_root := _project.path.path_join(".retro/audio")
	var sources := audio_root.path_join("sources")
	DirAccess.make_dir_recursive_absolute(sources)
	var copied := sources.path_join(name + "." + ext)
	DirAccess.copy_absolute(source_path, copied)
	var descriptor_path := audio_root.path_join(name + ".retro_audio.json")
	var data := {"name": name, "kind": kind, "source": copied, "params": {},
		"original": source_path, "previews": {}}
	_write_json(descriptor_path, data)
	_register_asset(name, kind, descriptor_path)
	_refresh_list()
	status.emit("Imported audio: " + name)

func _create_sfx() -> void:
	if _project == null:
		status.emit("Open a retro project before creating a SFX.")
		return
	var name := _slug(_name.text.strip_edges())
	if name.is_empty():
		name = "sfx_" + str(Time.get_ticks_msec())
	var audio_root := _project.path.path_join(".retro/audio")
	var descriptor_path := audio_root.path_join(name + ".retro_audio.json")
	var data := {"name": name, "kind": "sfx", "source": "", "params": _params(), "previews": {}}
	_write_json(descriptor_path, data)
	_register_asset(name, "sfx", descriptor_path)
	_refresh_list()
	status.emit("SFX created: " + name)

func _register_asset(name: String, kind: String, descriptor_path: String) -> void:
	var res := _project.get_resources()
	var rel := ".retro/audio/" + descriptor_path.get_file()
	for i in range(res.size()):
		if String(res[i].get("path", "")) == descriptor_path:
			res[i]["kind"] = kind
			res[i]["name"] = name
			_project.set_resources(res)
			_project.save()
			return
	res.append({"id": "audio/" + name, "type": "audio", "editor": "audio",
		"path": descriptor_path, "rel_path": rel, "kind": kind, "name": name, "editable": true})
	_project.set_resources(res)
	_project.save()
	modified.emit()

func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func _stop_preview() -> void:
	# Invalidate a preview that is still being converted, then tear down the
	# player. Recreating the player guarantees the AudioServer does not keep an
	# old stream alive (which is what made Stop appear to do nothing).
	_preview_generation += 1
	_pending_preview = {}
	if _player != null:
		_player.stop()
		_player.stream = null
		_player.queue_free()
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_status.text = "Stopped."

func _effective_descriptor() -> Dictionary:
	if not _selected.is_empty():
		var d := _selected_descriptor()
		if not d.is_empty():
			return d
		var ext := _selected.get_extension().to_lower()
		return {"name": _selected.get_file().get_basename(),
			"kind": "bgm" if ext in ["mid", "it"] else "sfx",
			"source": _selected, "params": _params(), "previews": {}}
	return {"name": _slug(_name.text),
		"kind": "bgm" if _kind.selected == 1 else "sfx",
		"source": "", "params": _params(), "previews": {}}

func _preview(target: String) -> void:
	if _project == null:
		return
	_stop_preview()
	var d := _effective_descriptor()
	d["kind"] = "bgm" if _kind.selected == 1 else "sfx"
	if not _name.text.strip_edges().is_empty():
		d["name"] = _slug(_name.text)
	d["params"] = _params()
	var request := {
		"descriptor": d,
		"target": target,
		"name": String(d.get("name", "audio")),
		"kind": String(d.get("kind", "sfx")),
		"preview_dir": _project.path.path_join(".retro/audio/preview"),
		"token": _preview_generation,
	}
	if _preview_busy:
		_pending_preview = request
		_status.text = "Preview queued; press Stop to cancel."
		return
	_start_preview_worker(request)

func _start_preview_worker(request: Dictionary) -> void:
	_preview_busy = true
	_status.text = "Rendering %s preview for %s..." % [request.get("kind", "audio"), request.get("target", "")]
	_preview_thread = Thread.new()
	_preview_thread.start(_preview_worker.bind(request))

func _preview_worker(request: Dictionary) -> void:
	var d: Dictionary = request.get("descriptor", {})
	var result: Dictionary
	if String(request.get("kind", "sfx")) == "sfx":
		result = AudioPipeline.synthesize_sfx(d.get("params", {}), String(request.get("preview_dir", "")),
			String(request.get("name", "audio")), String(request.get("target", "snes")))
	else:
		result = AudioPipeline.convert_asset(String(d.get("source", "")), String(request.get("preview_dir", "")),
			String(request.get("name", "audio")), "bgm", String(request.get("target", "snes")),
			d.get("params", {}))
	call_deferred("_on_preview_ready", result, int(request.get("token", 0)))

func _on_preview_ready(result: Dictionary, token: int) -> void:
	if _preview_thread != null:
		_preview_thread.wait_to_finish()
		_preview_thread = null
	_preview_busy = false
	if token == _preview_generation:
		if not bool(result.get("ok", false)):
			_status.text = "Preview failed: " + String(result.get("output", result.get("error", "")))
			status.emit("Audio preview failed.")
		else:
			var wav := String(result.get("preview", ""))
			if wav.is_empty() or not FileAccess.file_exists(wav):
				_status.text = "Preview WAV was not produced."
			else:
				var stream := AudioStreamWAV.load_from_file(wav)
				if stream == null:
					_status.text = "Could not load preview WAV."
				else:
					_player.stream = stream
					_player.play()
					_status.text = "%s preview (%s): %s" % [String(result.get("kind", "audio")).to_upper(),
						String(result.get("target", "")), wav]
					status.emit("Auditioning audio preview.")
	if not _pending_preview.is_empty():
		var pending := _pending_preview
		_pending_preview = {}
		if int(pending.get("token", 0)) == _preview_generation:
			_start_preview_worker(pending)

func _convert_both() -> void:
	if _project == null:
		return
	var d := _effective_descriptor()
	d["kind"] = "bgm" if _kind.selected == 1 else "sfx"
	if not _name.text.strip_edges().is_empty():
		d["name"] = _slug(_name.text)
	d["params"] = _params()
	var previews := {}
	for target in ["snes", "megadrive"]:
		var result: Dictionary
		if String(d.get("kind", "sfx")) == "sfx":
			result = AudioPipeline.synthesize_sfx(d.get("params", _params()), _project.path.path_join(".retro/audio/preview"), String(d.get("name", "audio")), target)
		else:
			result = AudioPipeline.convert_asset(String(d.get("source", "")), _project.path.path_join(".retro/audio/preview"), String(d.get("name", "audio")), "bgm", target, d.get("params", {}))
		if bool(result.get("ok", false)):
			previews[target] = String(result.get("preview", ""))
	d["previews"] = previews
	if not _selected.is_empty():
		_write_json(_selected, d)
	_on_selected(_asset_list.get_selected_items()[0] if not _asset_list.get_selected_items().is_empty() else -1)
	_status.text = "Converted previews: " + str(previews)
	status.emit("Audio converted for SNES and Mega Drive previews.")

func _slug(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" else "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "audio"
