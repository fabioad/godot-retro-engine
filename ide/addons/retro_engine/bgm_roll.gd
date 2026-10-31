@tool
extends Control
## Piano-roll widget for the BGM sequencer.
##
## Draws the horizontal step grid and vertical pitch lanes, with one color per
## track. Left click adds/selects, drag moves, the right edge resizes, right
## click deletes, and Delete removes the selected note.

signal note_selected(track: int, note: int)
signal song_changed()

const KEY_WIDTH := 42.0
const SCROLLBAR_H := 18.0
const MIN_PITCH := 24
const MAX_PITCH := 96
const TRACK_COLORS := [
	Color("#7fd1ff"), Color("#6ee7a8"), Color("#ffd45e"), Color("#ff9f6e"),
	Color("#c792ea"), Color("#f78fb3"), Color("#82e0aa"), Color("#f5b7b1"),
	Color("#85c1e9"), Color("#f8c471"),
]

var song: Dictionary = {}
var selected_track := 0
var zoom := 1.0
var scroll_x := 0.0
var scroll_y := 0.0
var playhead := -1
var _selected_note := -1
var _drag: Dictionary = {}
var _hscroll: HScrollBar

func _ready() -> void:
	custom_minimum_size = Vector2(560, 380)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	_hscroll = HScrollBar.new()
	_hscroll.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hscroll.offset_top = -SCROLLBAR_H
	_hscroll.offset_bottom = 0.0
	_hscroll.value_changed.connect(func(value: float):
		scroll_x = float(value)
		queue_redraw())
	add_child(_hscroll)
	resized.connect(_sync_hscroll)
	_sync_hscroll()

func set_song(p_song: Dictionary, p_track := 0, p_zoom := 1.0) -> void:
	song = p_song
	selected_track = clampi(p_track, 0, maxi(0, _tracks().size() - 1))
	zoom = clampf(p_zoom, 0.5, 2.5)
	_selected_note = -1
	_drag = {}
	_sync_hscroll()
	queue_redraw()

func set_selected_track(index: int) -> void:
	selected_track = clampi(index, 0, maxi(0, _tracks().size() - 1))
	_selected_note = -1
	_drag = {}
	queue_redraw()

func set_zoom(value: float) -> void:
	zoom = clampf(value, 0.5, 2.5)
	_sync_hscroll()
	queue_redraw()

func set_playhead(step: int) -> void:
	playhead = step
	if step >= 0:
		_follow_playhead(step)
	queue_redraw()

func scroll_to_start() -> void:
	scroll_x = 0.0
	_sync_hscroll()
	queue_redraw()

func _follow_playhead(step: int) -> void:
	if size.x <= 0.0:
		return
	var col_w := _col_w()
	var px := KEY_WIDTH + float(step) * col_w - scroll_x
	if px > size.x * 0.70:
		scroll_x = KEY_WIDTH + float(step) * col_w - size.x * 0.70
	elif px < KEY_WIDTH + col_w * 2.0:
		scroll_x = KEY_WIDTH + float(step) * col_w - KEY_WIDTH - col_w * 2.0
	scroll_x = clampf(scroll_x, 0.0, _max_scroll_x())
	_sync_hscroll()

func _sync_hscroll() -> void:
	if _hscroll == null:
		return
	var content := KEY_WIDTH + float(_steps()) * _col_w()
	var view := maxf(1.0, size.x)
	_hscroll.min_value = 0.0
	_hscroll.max_value = maxf(content, view)
	_hscroll.page = view
	_hscroll.step = maxf(1.0, _col_w())
	var limit := maxf(0.0, _hscroll.max_value - view)
	_hscroll.set_value_no_signal(clampf(scroll_x, 0.0, limit))

func select_note(track: int, note: int) -> void:
	selected_track = clampi(track, 0, maxi(0, _tracks().size() - 1))
	_selected_note = note
	queue_redraw()

func _tracks() -> Array:
	return song.get("tracks", [])

func _steps() -> int:
	return maxi(1, int(song.get("steps", 64)))

func _steps_per_beat() -> int:
	return maxi(1, int(song.get("steps_per_beat", 4)))

func _row_h() -> float:
	return maxf(6.0, 10.0 * zoom)

func _col_w() -> float:
	return maxf(8.0, 12.0 * zoom)

func _max_scroll_x() -> float:
	return maxf(0.0, KEY_WIDTH + _steps() * _col_w() - size.x)

func _max_scroll_y() -> float:
	return maxf(0.0, (MAX_PITCH - MIN_PITCH + 1) * _row_h() - (size.y - SCROLLBAR_H))

func _pitch_at(y: float) -> int:
	return clampi(MAX_PITCH - int(floor((y + scroll_y) / _row_h())), MIN_PITCH, MAX_PITCH)

func _step_at(x: float) -> int:
	return clampi(int(floor((x - KEY_WIDTH + scroll_x) / _col_w())), 0, _steps() - 1)

func _note_rect(track_index: int, note: Dictionary) -> Rect2:
	var x := KEY_WIDTH + float(int(note.get("step", 0))) * _col_w() - scroll_x
	var y := float(MAX_PITCH - int(note.get("pitch", 60))) * _row_h() - scroll_y
	var w := maxf(_col_w() * 0.9, float(int(note.get("length", 1))) * _col_w())
	return Rect2(x, y, w, maxf(4.0, _row_h() - 1.0))

func _hit_note(pos: Vector2) -> int:
	if selected_track < 0 or selected_track >= _tracks().size():
		return -1
	var notes: Array = Dictionary(_tracks()[selected_track]).get("notes", [])
	for i in range(notes.size() - 1, -1, -1):
		if _note_rect(selected_track, notes[i]).has_point(pos):
			return i
	return -1

func _hit_any(pos: Vector2) -> Dictionary:
	var tracks := _tracks()
	for ti in range(tracks.size() - 1, -1, -1):
		var notes: Array = Dictionary(tracks[ti]).get("notes", [])
		for ni in range(notes.size() - 1, -1, -1):
			if _note_rect(ti, notes[ni]).has_point(pos):
				return {"track": ti, "note": ni}
	return {}

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var view_bottom := size.y - SCROLLBAR_H
	draw_rect(Rect2(Vector2.ZERO, size), Color("#141a21"))
	draw_rect(Rect2(0.0, view_bottom, size.x, SCROLLBAR_H), Color("#0e1318"))
	if song.is_empty():
		draw_string(font, Vector2(48, 34), "No BGM loaded", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#9fb4d0"))
		return
	var steps := _steps()
	var spb := _steps_per_beat()
	var row_h := _row_h()
	var col_w := _col_w()
	# Left keyboard strip.
	draw_rect(Rect2(0, 0, KEY_WIDTH, size.y), Color("#0e1318"))
	for pitch in range(MIN_PITCH, MAX_PITCH + 1):
		var y := float(MAX_PITCH - pitch) * row_h - scroll_y
		if y + row_h < 0 or y > view_bottom:
			continue
		var pc := pitch % 12
		var black := pc in [1, 3, 6, 8, 10]
		if not black:
			draw_rect(Rect2(0, y, KEY_WIDTH - 1, maxf(3.0, row_h - 1)), Color("#19212a"))
		draw_line(Vector2(0, y + row_h), Vector2(size.x, y + row_h), Color("#202a35"), 1.0)
		if pc == 0:
			draw_string(font, Vector2(3, y + row_h - 2), "C%d" % (pitch / 12 - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#8fa3b8"))
	# Step grid.
	for step in range(steps + 1):
		var x := KEY_WIDTH + step * col_w - scroll_x
		if x < KEY_WIDTH - 1 or x > size.x:
			continue
		var color := Color("#202a35")
		if step % (spb * 4) == 0:
			color = Color("#405268")
		elif step % spb == 0:
			color = Color("#2b3948")
		draw_line(Vector2(x, 0), Vector2(x, view_bottom), color, 1.0)
	# Notes, all tracks (selected track editable/bright).
	var tracks := _tracks()
	var soloed := false
	for t in tracks:
		if bool(Dictionary(t).get("solo", false)):
			soloed = true
	for ti in range(tracks.size()):
		var track: Dictionary = tracks[ti]
		var muted := bool(track.get("muted", false)) or (soloed and not bool(track.get("solo", false)))
		var base: Color = TRACK_COLORS[ti % TRACK_COLORS.size()]
		if muted:
			base = base.darkened(0.55)
		elif ti != selected_track:
			base = base.darkened(0.2)
		var notes: Array = track.get("notes", [])
		for ni in range(notes.size()):
			var note: Dictionary = notes[ni]
			var rect := _note_rect(ti, note)
			if rect.position.x > size.x or rect.position.x + rect.size.x < KEY_WIDTH or rect.end.y < 0 or rect.position.y > view_bottom:
				continue
			var color := base
			if ti == selected_track and ni == _selected_note:
				color = color.lightened(0.25)
			draw_rect(rect, color)
			draw_rect(rect, color.lightened(0.35), false, 1.0)
			if rect.size.x > 24:
				draw_string(font, rect.position + Vector2(2, rect.size.y - 2), _note_name(int(note.get("pitch", 60))),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#0b1016"))
	# Playhead.
	if playhead >= 0 and playhead <= steps:
		var px := KEY_WIDTH + playhead * col_w - scroll_x
		draw_line(Vector2(px, 0), Vector2(px, view_bottom), Color("#ff5c7a"), 2.0)

func _note_name(pitch: int) -> String:
	var names := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
	return "%s%d" % [names[pitch % 12], pitch / 12 - 1]

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if mb.shift_pressed:
				scroll_x = clampf(scroll_x - 40, 0, _max_scroll_x())
			else:
				scroll_y = clampf(scroll_y - 40, 0, _max_scroll_y())
			_sync_hscroll()
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if mb.shift_pressed:
				scroll_x = clampf(scroll_x + 40, 0, _max_scroll_x())
			else:
				scroll_y = clampf(scroll_y + 40, 0, _max_scroll_y())
			_sync_hscroll()
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mb.position.x < KEY_WIDTH or mb.position.y > size.y - SCROLLBAR_H:
				return
			grab_focus()
			var hit := _hit_any(mb.position)
			if not hit.is_empty():
				selected_track = int(hit["track"])
				_selected_note = int(hit["note"])
				var note: Dictionary = Dictionary(_tracks()[selected_track]).get("notes", [])[_selected_note]
				var rect := _note_rect(selected_track, note)
				_drag = {
					"track": selected_track, "note": _selected_note,
					"step": int(note.get("step", 0)), "pitch": int(note.get("pitch", 60)),
					"length": int(note.get("length", 1)), "mouse": mb.position,
					"resize": mb.position.x > rect.position.x + rect.size.x - 7.0,
				}
				note_selected.emit(selected_track, _selected_note)
			else:
				var track: Dictionary = _tracks()[selected_track]
				var notes: Array = track.get("notes", [])
				notes.append({
					"step": _step_at(mb.position.x), "length": 1, "pitch": _pitch_at(mb.position.y),
					"velocity": 100, "slide": 0.0, "vibrato": 0.0, "delay": 0.0, "gate": 1.0,
				})
				track["notes"] = notes
				_selected_note = notes.size() - 1
				_drag = {"track": selected_track, "note": _selected_note,
					"step": int(notes[_selected_note]["step"]),
					"pitch": int(notes[_selected_note]["pitch"]), "length": 1,
					"mouse": mb.position, "resize": false}
				note_selected.emit(selected_track, _selected_note)
				song_changed.emit()
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var hit := _hit_any(mb.position)
			if not hit.is_empty():
				selected_track = int(hit["track"])
				var track: Dictionary = _tracks()[selected_track]
				var notes: Array = track.get("notes", [])
				notes.remove_at(int(hit["note"]))
				track["notes"] = notes
				_selected_note = -1
				_drag = {}
				song_changed.emit()
				queue_redraw()
				accept_event()
			return
	if event is InputEventMouseMotion and not _drag.is_empty():
		var mm := event as InputEventMouseMotion
		var drag_track := int(_drag.get("track", selected_track))
		if drag_track < 0 or drag_track >= _tracks().size():
			return
		var track: Dictionary = _tracks()[drag_track]
		var notes: Array = track.get("notes", [])
		var index := int(_drag.get("note", -1))
		if index < 0 or index >= notes.size():
			return
		var note: Dictionary = notes[index]
		var dx := int(round((mm.position.x - float(_drag.get("mouse", mm.position).x)) / _col_w()))
		var dy := int(round((float(_drag.get("mouse", mm.position).y) - mm.position.y) / _row_h()))
		if bool(_drag.get("resize", false)):
			note["length"] = maxi(1, int(_drag.get("length", 1)) + dx)
		else:
			note["step"] = clampi(int(_drag.get("step", 0)) + dx, 0, _steps() - 1)
			note["pitch"] = clampi(int(_drag.get("pitch", 60)) + dy, MIN_PITCH, MAX_PITCH)
		notes[index] = note
		track["notes"] = notes
		song_changed.emit()
		queue_redraw()
		accept_event()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode in [KEY_DELETE, KEY_BACKSPACE] and _selected_note >= 0:
			var track: Dictionary = _tracks()[selected_track]
			var notes: Array = track.get("notes", [])
			if _selected_note < notes.size():
				notes.remove_at(_selected_note)
				track["notes"] = notes
				_selected_note = -1
				song_changed.emit()
				queue_redraw()
				accept_event()
