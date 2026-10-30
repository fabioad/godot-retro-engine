@tool
extends Window
## BGM piano-roll sequencer. Opens as a separate window so it can be resized
## or maximized when the Audio tab is narrow. It edits notes, track/chip
## parameters, exports MIDI and saves a .retro_bgm.json + BGM descriptor.

signal saved(descriptor_path: String, source_path: String, name: String)
signal status(text: String)

const BgmRoll = preload("res://addons/retro_engine/bgm_roll.gd")
const AudioPipeline = preload("res://addons/retro_engine/audio_pipeline.gd")
const I18n = preload("res://addons/retro_engine/i18n.gd")
const TOOL_PATH := "res://addons/retro_engine/tools/bgm_tool.py"
const TRACK_COLORS := [
	Color("#7fd1ff"), Color("#6ee7a8"), Color("#ffd45e"), Color("#ff9f6e"),
	Color("#c792ea"), Color("#f78fb3"), Color("#82e0aa"), Color("#f5b7b1"),
	Color("#85c1e9"), Color("#f8c471"),
]

var _project: RetroProject
var _song: Dictionary = {}
var _descriptor_path := ""
var _source_path := ""
var _track_index := 0
var _note_index := -1
var _note_track := -1
var _updating := false
var _preview_busy := false
var _preview_generation := 0
var _preview_thread: Thread
var _preview_result: Dictionary = {}
var _player: AudioStreamPlayer
var _playing := false
var _play_started := 0
var _roll: Control
var _tracks: ItemList
var _mute: CheckBox
var _solo: CheckBox
var _chip_box: VBoxContainer
var _name: LineEdit
var _platform: OptionButton
var _bpm: SpinBox
var _steps: SpinBox
var _zoom: SpinBox
var _status: Label
var _note_controls := {}
var _play_button: Button
var _stop_button: Button

func _ready() -> void:
	title = I18n.t("bgm.title")
	size = Vector2i(1220, 820)
	min_size = Vector2i(900, 600)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 5)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	top.add_child(_label(I18n.t("bgm.name")))
	_name = LineEdit.new()
	_name.custom_minimum_size.x = 150
	_name.text_changed.connect(func(_t): _song["name"] = _slug(_name.text))
	top.add_child(_name)
	top.add_child(_label(I18n.t("bgm.track")))
	_platform = OptionButton.new()
	_platform.add_item("SNES", 0)
	_platform.add_item("Mega Drive", 1)
	_platform.item_selected.connect(_on_platform_changed)
	top.add_child(_platform)
	top.add_child(_label(I18n.t("bgm.bpm")))
	_bpm = _spin(40, 300, 1, 120, " BPM")
	_bpm.value_changed.connect(func(v):
		_song["bpm"] = float(v)
		_mark_changed())
	top.add_child(_bpm)
	top.add_child(_label(I18n.t("bgm.steps")))
	_steps = _spin(16, 16384, 16, 64, "")
	_steps.value_changed.connect(func(v):
		_song["steps"] = int(v)
		_roll.queue_redraw()
		_mark_changed())
	top.add_child(_steps)
	top.add_child(_label(I18n.t("bgm.zoom")))
	_zoom = _spin(0.5, 2.5, 0.1, 1.0, "x")
	_zoom.value_changed.connect(func(v): _roll.set_zoom(float(v)))
	top.add_child(_zoom)
	_play_button = Button.new()
	_play_button.text = I18n.t("bgm.play")
	_play_button.pressed.connect(_play)
	top.add_child(_play_button)
	_stop_button = Button.new()
	_stop_button.text = I18n.t("bgm.stop")
	_stop_button.pressed.connect(_stop)
	top.add_child(_stop_button)
	var save := Button.new()
	save.text = I18n.t("bgm.save")
	save.pressed.connect(_save_bgm)
	top.add_child(save)
	var export := Button.new()
	export.text = I18n.t("bgm.export_midi")
	export.pressed.connect(_export_midi)
	top.add_child(export)
	var close := Button.new()
	close.text = I18n.t("bgm.close")
	close.pressed.connect(hide)
	top.add_child(close)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 210
	split.add_child(left)
	left.add_child(_label(I18n.t("bgm.tracks")))
	_tracks = ItemList.new()
	_tracks.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tracks.item_selected.connect(_on_track_selected)
	left.add_child(_tracks)
	var track_actions := HBoxContainer.new()
	left.add_child(track_actions)
	var add := Button.new()
	add.text = I18n.t("bgm.add_track")
	add.pressed.connect(_add_track)
	track_actions.add_child(add)
	var remove := Button.new()
	remove.text = I18n.t("bgm.remove_track")
	remove.pressed.connect(_remove_track)
	track_actions.add_child(remove)
	_mute = CheckBox.new()
	_mute.text = I18n.t("bgm.mute")
	_mute.toggled.connect(func(on):
		_track()["muted"] = on
		_roll.queue_redraw())
	left.add_child(_mute)
	_solo = CheckBox.new()
	_solo.text = I18n.t("bgm.solo")
	_solo.toggled.connect(func(on):
		_track()["solo"] = on
		_roll.queue_redraw())
	left.add_child(_solo)

	_roll = BgmRoll.new()
	_roll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roll.note_selected.connect(_on_note_selected)
	_roll.song_changed.connect(_mark_changed)
	split.add_child(_roll)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 300
	split.add_child(right)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(tabs)
	var note_tab := VBoxContainer.new()
	note_tab.name = I18n.t("bgm.note")
	tabs.add_child(note_tab)
	var note_grid := GridContainer.new()
	note_grid.columns = 2
	note_tab.add_child(note_grid)
	for spec in [
		["pitch", "Pitch", 0, 127, 1, 60],
		["step", "Start", 0, 16383, 1, 0],
		["length", "Length", 1, 4096, 1, 1],
		["velocity", "Velocity", 1, 127, 1, 100],
		["slide", "Slide", -24, 24, 0.5, 0],
		["vibrato", "Vibrato", 0, 12, 0.1, 0],
		["delay", "Delay", 0, 1, 0.05, 0],
		["gate", "Gate", 0.1, 2, 0.05, 1],
	]:
		var label := _label(String(spec[1]))
		note_grid.add_child(label)
		var spin := _spin(float(spec[2]), float(spec[3]), float(spec[4]), float(spec[5]), "")
		var key := String(spec[0])
		spin.value_changed.connect(func(v):
			if not _updating:
				_apply_note_value(key, float(v)))
		note_grid.add_child(spin)
		_note_controls[key] = spin
	var chip_tab_scroll := ScrollContainer.new()
	chip_tab_scroll.name = I18n.t("bgm.chip")
	tabs.add_child(chip_tab_scroll)
	_chip_box = VBoxContainer.new()
	_chip_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip_tab_scroll.add_child(_chip_box)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("#9fb4d0"))
	right.add_child(_status)
	_player = AudioStreamPlayer.new()
	add_child(_player)
	close_requested.connect(func(): hide())

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _spin(min_v: float, max_v: float, step: float, value: float, suffix: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.suffix = suffix
	s.custom_minimum_size.x = 90
	return s

func open_new(project: RetroProject, platform: String) -> void:
	_project = project
	_descriptor_path = ""
	_source_path = ""
	_song = _default_song(platform, _unique_name("bgm"))
	_apply_song()
	popup_centered_ratio(0.9)

func open_source(project: RetroProject, descriptor_path: String, source_path: String,
		name: String, platform: String) -> bool:
	_project = project
	_descriptor_path = descriptor_path
	_source_path = source_path
	var imported := _import_source(source_path, name, platform)
	if not bool(imported.get("ok", false)):
		_status.text = I18n.t("bgm.import_failed", {"path": source_path,
			"error": String(imported.get("error", "unknown"))})
		status.emit(_status.text)
		return false
	_song = imported.get("song", _default_song(platform, name))
	_apply_song()
	popup_centered_ratio(0.9)
	return true

func open_song(project: RetroProject, descriptor_path: String, source_path: String,
		song: Dictionary, name: String) -> void:
	_project = project
	_descriptor_path = descriptor_path
	_source_path = source_path
	_song = song.duplicate(true)
	if _song.is_empty():
		_song = _default_song("snes", name)
	_song["name"] = String(_song.get("name", name))
	_apply_song()
	popup_centered_ratio(0.9)

func _apply_song() -> void:
	_updating = true
	_song["platform"] = String(_song.get("platform", "snes"))
	_platform.select(1 if String(_song["platform"]) == "megadrive" else 0)
	_name.text = String(_song.get("name", "song"))
	_bpm.value = float(_song.get("bpm", 120.0))
	_steps.value = int(_song.get("steps", 64))
	_zoom.value = 1.0
	_track_index = 0
	_note_index = -1
	_note_track = -1
	_tracks.clear()
	for i in range(_tracks_count()):
		_tracks.add_item(_track_label(i))
		_tracks.set_item_metadata(i, i)
	if _tracks.item_count > 0:
		_tracks.select(0)
	_roll.set_song(_song, 0, 1.0)
	_update_track_checks()
	_rebuild_chip_panel()
	_show_note(-1)
	_updating = false

func _tracks_count() -> int:
	return Array(_song.get("tracks", [])).size()

func _track(index := -1) -> Dictionary:
	var tracks: Array = _song.get("tracks", [])
	var i := _track_index if index < 0 else index
	return tracks[i] if i >= 0 and i < tracks.size() else {}

func _track_label(index: int) -> String:
	var track := _track(index)
	var kind := String(track.get("kind", "snes")).to_upper()
	var flags := ""
	if bool(track.get("muted", false)):
		flags += " M"
	if bool(track.get("solo", false)):
		flags += " S"
	return "%s [%s]%s" % [String(track.get("name", "Track")), kind, flags]

func _refresh_tracks() -> void:
	var selected := _track_index
	_tracks.clear()
	for i in range(_tracks_count()):
		_tracks.add_item(_track_label(i))
		_tracks.set_item_metadata(i, i)
	if selected >= 0 and selected < _tracks.item_count:
		_tracks.select(selected)
	_update_track_checks()

func _update_track_checks() -> void:
	var track := _track()
	_mute.button_pressed = bool(track.get("muted", false))
	_solo.button_pressed = bool(track.get("solo", false))

func _on_track_selected(index: int) -> void:
	_track_index = index
	_roll.set_selected_track(index)
	_update_track_checks()
	_rebuild_chip_panel()
	_show_note(-1)

func _on_platform_changed(index: int) -> void:
	if _updating:
		return
	var platform := "megadrive" if index == 1 else "snes"
	_song["platform"] = platform
	var counts := _default_song(platform, String(_song.get("name", "bgm")))
	_song["tracks"] = counts["tracks"]
	_track_index = 0
	_refresh_tracks()
	_roll.set_song(_song, 0, float(_zoom.value))
	_rebuild_chip_panel()
	_show_note(-1)
	_mark_changed()

func _add_track() -> void:
	var platform := String(_song.get("platform", "snes"))
	var limit := 10 if platform == "megadrive" else 8
	if _tracks_count() >= limit:
		return
	var track := _default_track(platform, _tracks_count())
	track["name"] = "Track %d" % (_tracks_count() + 1)
	_song["tracks"].append(track)
	_track_index = _tracks_count() - 1
	_refresh_tracks()
	_roll.set_song(_song, _track_index, float(_zoom.value))
	_rebuild_chip_panel()
	_mark_changed()

func _remove_track() -> void:
	if _tracks_count() <= 1:
		return
	_song["tracks"].remove_at(_track_index)
	_track_index = clampi(_track_index, 0, _tracks_count() - 1)
	_refresh_tracks()
	_roll.set_song(_song, _track_index, float(_zoom.value))
	_rebuild_chip_panel()
	_mark_changed()

func _mark_changed() -> void:
	if _updating:
		return
	_roll.queue_redraw()

func _on_note_selected(track: int, note: int) -> void:
	_track_index = track
	_note_track = track
	_note_index = note
	_tracks.select(track)
	_update_track_checks()
	_rebuild_chip_panel()
	_show_note(note)

func _show_note(index: int) -> void:
	_updating = true
	if index < 0:
		for spin in _note_controls.values():
			var box: SpinBox = spin
			box.editable = false
		_updating = false
		return
	var notes: Array = _track().get("notes", [])
	if index >= notes.size():
		_updating = false
		return
	var note: Dictionary = notes[index]
	var values := {
		"pitch": int(note.get("pitch", 60)), "step": int(note.get("step", 0)),
		"length": int(note.get("length", 1)), "velocity": int(note.get("velocity", 100)),
		"slide": float(note.get("slide", 0.0)), "vibrato": float(note.get("vibrato", 0.0)),
		"delay": float(note.get("delay", 0.0)), "gate": float(note.get("gate", 1.0)),
	}
	for key in _note_controls.keys():
		var spin: SpinBox = _note_controls[key]
		spin.editable = true
		spin.value = float(values.get(key, 0))
	_updating = false

func _apply_note_value(key: String, value: float) -> void:
	if _note_index < 0:
		return
	var notes: Array = _track().get("notes", [])
	if _note_index >= notes.size():
		return
	var note: Dictionary = notes[_note_index]
	if key in ["pitch", "step", "length", "velocity"]:
		note[key] = int(value)
	elif key in ["slide", "vibrato", "delay", "gate"]:
		note[key] = value
	notes[_note_index] = note
	_track()["notes"] = notes
	_roll.queue_redraw()

func _rebuild_chip_panel() -> void:
	if _chip_box == null:
		return
	for child in _chip_box.get_children():
		child.queue_free()
	var track := _track()
	if track.is_empty():
		return
	var kind := String(track.get("kind", "snes"))
	_chip_box.add_child(_label("Volume / Pan"))
	var vp := GridContainer.new()
	vp.columns = 2
	_chip_box.add_child(vp)
	_chip_number(vp, "Volume", 0, 100, 1, float(track.get("volume", 100)), track, "volume")
	_chip_number(vp, "Pan", 0, 127, 1, float(track.get("pan", 64)), track, "pan")
	if kind == "snes":
		_chip_box.add_child(_label("SNES SPC channel"))
		var wave := _chip_option("Waveform", ["sine", "square", "saw", "triangle", "noise"],
			String(track.get("waveform", "square")))
		wave.item_selected.connect(func(i):
			var value: String = wave.get_item_text(i)
			_track()["waveform"] = value
			_track()["snes"]["waveform"] = value
			_mark_changed())
		var grid := GridContainer.new()
		grid.columns = 2
		_chip_box.add_child(grid)
		var snes: Dictionary = track.get("snes", {})
		_chip_number(grid, "Attack ms", 0, 4000, 1, float(snes.get("attack_ms", 2)), snes, "attack_ms")
		_chip_number(grid, "Decay ms", 0, 4000, 1, float(snes.get("decay_ms", 50)), snes, "decay_ms")
		_chip_number(grid, "Sustain", 0, 1, 0.01, float(snes.get("sustain", 0.65)), snes, "sustain")
		_chip_number(grid, "Release ms", 0, 4000, 1, float(snes.get("release_ms", 70)), snes, "release_ms")
		_chip_number(grid, "Echo", 0, 127, 1, float(snes.get("echo", 0)), snes, "echo")
		_chip_number(grid, "Noise", 0, 1, 0.01, float(snes.get("noise", 0)), snes, "noise")
		_chip_number(grid, "Pitch mod", 0, 1, 0.01, float(snes.get("pitch_mod", 0)), snes, "pitch_mod")
		_chip_number(grid, "Detune", -1, 1, 0.01, float(snes.get("detune", 0)), snes, "detune")
	elif kind == "fm":
		_chip_box.add_child(_label("YM2612 FM channel"))
		var patch := _chip_option("Patch", ["piano", "guitar", "bass", "strings", "brass", "lead"],
			String(track.get("fm_patch", "lead")))
		patch.item_selected.connect(func(i):
			_track()["fm_patch"] = patch.get_item_text(i)
			_mark_changed())
		var grid := GridContainer.new()
		grid.columns = 2
		_chip_box.add_child(grid)
		var fm: Dictionary = track.get("fm", {})
		_chip_number(grid, "Algorithm", 0, 7, 1, float(fm.get("algorithm", 7)), fm, "algorithm")
		_chip_number(grid, "Feedback", 0, 7, 1, float(fm.get("feedback", 0)), fm, "feedback")
		var ops: Array = fm.get("operators", [])
		for i in range(min(4, ops.size())):
			var op: Dictionary = ops[i]
			_chip_box.add_child(_label("Operator %d" % (i + 1)))
			var og := GridContainer.new()
			og.columns = 2
			_chip_box.add_child(og)
			_chip_number(og, "Mult", 0, 15, 1, float(op.get("mul", 1)), op, "mul")
			_chip_number(og, "Level", 0, 127, 1, float(op.get("tl", 16)), op, "tl")
			_chip_number(og, "Attack", 0, 31, 1, float(op.get("ar", 31)), op, "ar")
			_chip_number(og, "Decay", 0, 31, 1, float(op.get("dr", 8)), op, "dr")
			_chip_number(og, "Sustain", 0, 15, 1, float(op.get("sl", 1)), op, "sl")
			_chip_number(og, "Release", 0, 15, 1, float(op.get("rr", 12)), op, "rr")
			_chip_number(og, "Detune", 0, 7, 1, float(op.get("detune", 0)), op, "detune")
	elif kind == "psg":
		_chip_box.add_child(_label("SN76489 PSG channel"))
		var wave := _chip_option("Waveform", ["square", "noise"],
			String(track.get("psg", {}).get("waveform", "square")))
		wave.item_selected.connect(func(i):
			_track()["psg"]["waveform"] = wave.get_item_text(i)
			_mark_changed())
		var grid := GridContainer.new()
		grid.columns = 2
		_chip_box.add_child(grid)
		var psg: Dictionary = track.get("psg", {})
		_chip_number(grid, "PSG volume", 0, 15, 1, float(psg.get("volume", 15)), psg, "volume")
		_chip_number(grid, "Noise", 0, 1, 0.01, float(psg.get("noise", 0)), psg, "noise")
		_chip_number(grid, "Attack ms", 0, 4000, 1, float(psg.get("attack_ms", 2)), psg, "attack_ms")
		_chip_number(grid, "Decay ms", 0, 4000, 1, float(psg.get("decay_ms", 80)), psg, "decay_ms")
		_chip_number(grid, "Sustain", 0, 1, 0.01, float(psg.get("sustain", 0.7)), psg, "sustain")
		_chip_number(grid, "Release ms", 0, 4000, 1, float(psg.get("release_ms", 100)), psg, "release_ms")
	else:
		_chip_box.add_child(_label("DAC / PCM sample track"))
		var sample := LineEdit.new()
		sample.text = String(track.get("dac", {}).get("sample", ""))
		sample.placeholder_text = "sample path"
		sample.text_changed.connect(func(text):
			if not _updating:
				_track()["dac"]["sample"] = text
				_mark_changed())
		_chip_box.add_child(sample)

func _chip_option(label: String, values: Array, value: String) -> OptionButton:
	_chip_box.add_child(_label(label))
	var option := OptionButton.new()
	for item in values:
		option.add_item(String(item))
	for i in range(option.item_count):
		if option.get_item_text(i) == value:
			option.select(i)
			break
	_chip_box.add_child(option)
	return option

func _chip_number(parent: Container, label: String, min_v: float, max_v: float,
		step: float, value: float, target: Dictionary, key: String) -> void:
	parent.add_child(_label(label))
	var spin := _spin(min_v, max_v, step, value, "")
	spin.value_changed.connect(func(v):
		if not _updating:
			target[key] = v
			_mark_changed())
	parent.add_child(spin)

func _default_operators() -> Array:
	var out: Array = []
	for i in range(4):
		out.append({"mul": 1, "tl": 16, "ar": 31, "dr": 8, "sl": 1, "rr": 12, "detune": 0})
	return out

func _default_song(platform: String, name: String) -> Dictionary:
	var tracks: Array = []
	var count := 10 if platform == "megadrive" else 8
	for i in range(count):
		tracks.append(_default_track(platform, i))
	return {"name": name, "platform": platform, "bpm": 120.0, "steps": 64,
		"steps_per_beat": 4, "tracks": tracks}

func _default_track(platform: String, index: int) -> Dictionary:
	if platform == "megadrive":
		var kind := "fm" if index < 6 else ("psg" if index < 9 else "dac")
		return {"name": "FM %d" % (index + 1) if kind == "fm" else ("PSG %d" % (index - 5) if kind == "psg" else "DAC"),
			"kind": kind, "channel": index, "midi_channel": mini(8, index),
			"muted": false, "solo": false, "volume": 100, "pan": 64,
			"instrument": 0, "fm_patch": "lead", "waveform": "square",
			"fm": {"algorithm": 7, "feedback": 0, "operators": _default_operators()},
			"psg": {"waveform": "square", "volume": 15, "noise": 0.0,
				"attack_ms": 2, "decay_ms": 80, "sustain": 0.7, "release_ms": 100},
			"dac": {"sample": ""}, "notes": []}
	return {"name": "SPC %d" % (index + 1), "kind": "snes", "channel": index,
		"midi_channel": index, "muted": false, "solo": false, "volume": 100, "pan": 64,
		"instrument": 0, "waveform": "square",
		"snes": {"waveform": "square", "attack_ms": 2, "decay_ms": 50, "sustain": 0.65,
			"release_ms": 70, "echo": 0, "noise": 0.0, "pitch_mod": 0.0, "detune": 0.0},
		"notes": []}

func _unique_name(base: String) -> String:
	if _project == null:
		return base
	var candidate := base
	var n := 1
	while FileAccess.file_exists(_project.path.path_join(".retro/audio").path_join(candidate + ".retro_bgm.json")):
		n += 1
		candidate = "%s_%d" % [base, n]
	return candidate

func _slug(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "bgm"

func _export_midi_internal(path: String) -> Dictionary:
	if _project == null:
		return {"ok": false, "error": "no project"}
	var cache := ProjectSettings.globalize_path("user://bgm_preview")
	DirAccess.make_dir_recursive_absolute(cache)
	var song_path := cache.path_join(_slug(String(_song.get("name", "song"))) + ".retro_bgm.json")
	var song_file := FileAccess.open(song_path, FileAccess.WRITE)
	if song_file == null:
		return {"ok": false, "error": "could not write song JSON"}
	song_file.store_string(JSON.stringify(_song, "\t"))
	song_file.close()
	var result := _run_tool(["export-midi", "--song", song_path, "--out", path])
	return result

func _run_tool(args: Array) -> Dictionary:
	var output: Array = []
	var python := "python3" if OS.get_name() != "Windows" else "python"
	var code := OS.execute(python, [ProjectSettings.globalize_path(TOOL_PATH)] + args, output, true)
	var text := ""
	for line in output:
		text += String(line)
	var parsed = null
	var first := text.find("{")
	var last := text.rfind("}")
	if first >= 0 and last > first:
		parsed = JSON.parse_string(text.substr(first, last - first + 1))
	return {"ok": code == 0 and parsed != null and bool(Dictionary(parsed).get("ok", true)),
		"output": text, "json": parsed}

func _import_source(source_path: String, name: String, platform: String) -> Dictionary:
	var cache := ProjectSettings.globalize_path("user://bgm_preview")
	DirAccess.make_dir_recursive_absolute(cache)
	var out := cache.path_join(_slug(name) + ".import.retro_bgm.json")
	var ext := source_path.get_extension().to_lower()
	var result: Dictionary
	if ext == "mid" or ext == "midi":
		result = _run_tool(["import-midi", "--midi", source_path, "--out", out,
			"--name", name, "--platform", platform])
	elif ext == "it":
		result = _run_tool(["import-it", "--it", source_path, "--out", out,
			"--name", name, "--platform", platform])
	else:
		return {"ok": false, "error": "unsupported music format: " + ext}
	if not bool(result.get("ok", false)):
		return {"ok": false, "error": String(result.get("output", "import failed"))}
	var parsed = result.get("json")
	var song_path := String(Dictionary(parsed).get("out", out))
	if not FileAccess.file_exists(song_path):
		return {"ok": false, "error": "import did not produce a song JSON"}
	var song = JSON.parse_string(FileAccess.get_file_as_string(song_path))
	if typeof(song) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid song JSON"}
	return {"ok": true, "song": song}

func _save_bgm() -> void:
	if _project == null:
		status.emit(I18n.t("bgm.no_project"))
		return
	var name := _slug(_name.text.strip_edges())
	if name.is_empty():
		name = "bgm"
	_song["name"] = name
	_song["bpm"] = float(_bpm.value)
	_song["steps"] = int(_steps.value)
	var audio_root := _project.path.path_join(".retro/audio")
	var sources := audio_root.path_join("sources")
	DirAccess.make_dir_recursive_absolute(sources)
	var midi_path := sources.path_join(name + ".mid")
	var export := _export_midi_internal(midi_path)
	if not bool(export.get("ok", false)):
		_status.text = I18n.t("bgm.preview_failed", {"error": String(export.get("output", "MIDI export failed"))})
		status.emit(_status.text)
		return
	var song_path := audio_root.path_join(name + ".retro_bgm.json")
	var sf := FileAccess.open(song_path, FileAccess.WRITE)
	if sf == null:
		_status.text = "Could not write song JSON."
		return
	sf.store_string(JSON.stringify(_song, "\t"))
	sf.close()
	var descriptor_path := _descriptor_path
	if descriptor_path.is_empty() or descriptor_path.get_extension().to_lower() != "json":
		descriptor_path = audio_root.path_join(name + ".retro_audio.json")
	var data: Dictionary = {}
	if FileAccess.file_exists(descriptor_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(descriptor_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
	data["name"] = name
	data["kind"] = "bgm"
	data["platform"] = String(_song.get("platform", "snes"))
	data["source"] = midi_path
	data["song"] = song_path
	if not data.has("params"):
		data["params"] = {}
	if not data.has("previews"):
		data["previews"] = {}
	var df := FileAccess.open(descriptor_path, FileAccess.WRITE)
	if df == null:
		_status.text = "Could not write BGM descriptor."
		return
	df.store_string(JSON.stringify(data, "\t"))
	df.close()
	_descriptor_path = descriptor_path
	_source_path = midi_path
	_status.text = I18n.t("bgm.saved", {"name": name})
	status.emit(_status.text)
	saved.emit(descriptor_path, midi_path, name)

func _export_midi() -> void:
	if _project == null:
		status.emit(I18n.t("bgm.no_project"))
		return
	var name := _slug(_name.text.strip_edges())
	if name.is_empty():
		name = "bgm"
	var path := _project.path.path_join(".retro/audio/sources").path_join(name + ".mid")
	var result := _export_midi_internal(path)
	if bool(result.get("ok", false)):
		_status.text = I18n.t("bgm.exported", {"path": path})
	else:
		_status.text = I18n.t("bgm.preview_failed", {"error": String(result.get("output", "MIDI export failed"))})
	status.emit(_status.text)

func _play() -> void:
	if _preview_busy or _project == null:
		return
	_preview_busy = true
	var token := _preview_generation
	_play_button.disabled = true
	_status.text = "Rendering preview..."
	var cache := ProjectSettings.globalize_path("user://bgm_preview")
	DirAccess.make_dir_recursive_absolute(cache)
	var name := _slug(String(_song.get("name", "bgm")))
	var midi_path := cache.path_join(name + "_seq.mid")
	var song_path := cache.path_join(name + "_seq.retro_bgm.json")
	var sf := FileAccess.open(song_path, FileAccess.WRITE)
	if sf != null:
		sf.store_string(JSON.stringify(_song, "\t"))
		sf.close()
	var target := String(_song.get("platform", "snes"))
	var preview_dir := cache.path_join("preview").path_join(target)
	_preview_result = {}
	_preview_thread = Thread.new()
	_preview_thread.start(func():
		var exp := _run_tool(["export-midi", "--song", song_path, "--out", midi_path])
		if not bool(exp.get("ok", false)):
			call_deferred("_finish_preview", {"ok": false, "error": String(exp.get("output", "MIDI export failed"))})
			return
		var result := AudioPipeline.convert_asset(midi_path, preview_dir, name, "bgm", target, {})
		call_deferred("_finish_preview", result)
	)
	while _preview_result.is_empty():
		await get_tree().process_frame
	_preview_thread.wait_to_finish()
	_preview_thread = null
	_preview_busy = false
	_play_button.disabled = false
	if token != _preview_generation:
		return
	var result: Dictionary = _preview_result
	if not bool(result.get("ok", false)):
		_status.text = I18n.t("bgm.preview_failed", {"error": String(result.get("output", result.get("error", "")))})
		status.emit(_status.text)
		return
	var wav := String(result.get("preview", ""))
	var stream := AudioStreamWAV.load_from_file(wav) if FileAccess.file_exists(wav) else null
	if stream == null:
		_status.text = "Could not load preview WAV."
		return
	_player.stream = stream
	_player.play()
	_playing = true
	_play_started = Time.get_ticks_msec()
	_status.text = I18n.t("bgm.playing", {"name": name})
	status.emit(_status.text)

func _finish_preview(result: Dictionary) -> void:
	_preview_result = result

func _stop() -> void:
	_preview_generation += 1
	_playing = false
	if _player != null:
		_player.stop()
		_player.stream = null
	_roll.set_playhead(-1)
	_status.text = I18n.t("bgm.stopped")

func _process(_delta: float) -> void:
	if not _playing or _player == null or _player.stream == null:
		return
	var elapsed := (Time.get_ticks_msec() - _play_started) / 1000.0
	var beat := elapsed * float(_song.get("bpm", 120.0)) / 60.0
	var step := int(beat * float(_song.get("steps_per_beat", 4)))
	_roll.set_playhead(step)
	if elapsed >= _player.stream.get_length():
		_stop()

func _exit_tree() -> void:
	_playing = false
	if _player != null:
		_player.stop()
	if _preview_thread != null:
		_preview_thread.wait_to_finish()
		_preview_thread = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		hide()
