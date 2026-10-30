extends SceneTree
## BGM sequencer end-to-end: create, edit, save, preview, reopen by double
## click, import a real MIDI, and delete the descriptor/source/song.

func _initialize() -> void:
	await process_frame
	var dir := "/tmp/opencode/bgm_editor_project"
	_remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var project := RetroProject.new()
	project.set_name("bgm_editor")
	project.set_path(dir)
	project.set_platform("snes")
	project.save()
	var editor = preload("res://addons/retro_engine/audio_editor.gd").new()
	get_root().add_child(editor)
	await process_frame
	editor.set_project(project)
	editor._synthesize_bgm()
	await process_frame
	var seq = editor._bgm_sequencer
	var ok: bool = seq != null and seq.visible
	if not ok:
		print("BGM_EDITOR cannot open sequencer")
		quit(1)
		return

	# Compose a short melody through the same data path the piano roll uses.
	seq._name.text = "theme"
	seq._bpm.value = 150.0
	seq._steps.value = 32
	var notes: Array = seq._song["tracks"][0]["notes"]
	notes.append({"step": 0, "length": 4, "pitch": 60, "velocity": 100,
		"slide": 0.0, "vibrato": 0.0, "delay": 0.0, "gate": 1.0})
	notes.append({"step": 4, "length": 4, "pitch": 64, "velocity": 96,
		"slide": 0.0, "vibrato": 0.0, "delay": 0.0, "gate": 1.0})
	notes.append({"step": 8, "length": 8, "pitch": 67, "velocity": 110,
		"slide": 0.0, "vibrato": 0.0, "delay": 0.0, "gate": 0.9})
	seq._roll.queue_redraw()
	seq._save_bgm()
	await process_frame

	var audio_root := dir.path_join(".retro/audio")
	var descriptor := audio_root.path_join("theme.retro_audio.json")
	var song_path := audio_root.path_join("theme.retro_bgm.json")
	var midi_path := audio_root.path_join("sources/theme.mid")
	ok = FileAccess.file_exists(descriptor) and FileAccess.file_exists(song_path)
	ok = ok and FileAccess.file_exists(midi_path) and FileAccess.get_file_as_bytes(midi_path).size() > 32
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(descriptor))
	ok = ok and String(data.get("kind", "")) == "bgm"
	ok = ok and String(data.get("platform", "")) == "snes"
	ok = ok and String(data.get("source", "")) == midi_path
	ok = ok and String(data.get("song", "")) == song_path
	var song: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(song_path))
	ok = ok and Array(Dictionary(song.get("tracks", [])[0]).get("notes", [])).size() == 3

	# Preview is real: render and play the saved song.
	seq._play()
	for i in range(600):
		await process_frame
		if not seq._preview_busy:
			break
	ok = ok and seq._player.stream != null and seq._player.playing
	seq._stop()
	await process_frame

	# Double click on the descriptor reopens the stored song.
	seq.visible = false
	editor._refresh_list()
	var index := -1
	for i in range(editor._asset_list.item_count):
		if String(editor._asset_list.get_item_metadata(i)) == descriptor:
			index = i
			break
	editor._on_asset_activated(index)
	await process_frame
	ok = ok and index >= 0 and seq.visible
	ok = ok and Array(Dictionary(seq._song.get("tracks", [])[0]).get("notes", [])).size() == 3

	# Import the saved MIDI as a raw music asset (double click path).
	var imported: Dictionary = seq._import_source(midi_path, "theme_raw", "snes")
	ok = ok and bool(imported.get("ok", false))
	var imported_song: Dictionary = imported.get("song", {})
	ok = ok and Array(Dictionary(imported_song.get("tracks", [])[0]).get("notes", [])).size() == 3
	ok = ok and is_equal_approx(float(imported_song.get("bpm", 0.0)), 150.0)

	# Import a real Impulse Tracker song through libopenmpt.
	var repo := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var it_path := repo.path_join("validation/projects/kof98/assets/audio/esaka/esaka.it")
	if FileAccess.file_exists(it_path):
		var it_import: Dictionary = seq._import_source(it_path, "esaka", "megadrive")
		ok = ok and bool(it_import.get("ok", false))
		var it_song: Dictionary = it_import.get("song", {})
		var it_tracks: Array = it_song.get("tracks", [])
		var it_notes := 0
		for track in it_tracks:
			it_notes += Array(Dictionary(track).get("notes", [])).size()
		ok = ok and it_notes > 1000
		ok = ok and String(it_song.get("platform", "")) == "megadrive"
		ok = ok and absf(float(it_song.get("bpm", 0.0)) - 136.62) < 0.5
		print("BGM_EDITOR IT notes=", it_notes, " bpm=", it_song.get("bpm"),
			" steps=", it_song.get("steps"))

	# Delete the BGM: descriptor, MIDI source, song JSON and previews.
	editor._delete_sfx_confirmed(descriptor, data, "theme", true)
	await process_frame
	ok = ok and not FileAccess.file_exists(descriptor)
	ok = ok and not FileAccess.file_exists(midi_path)
	ok = ok and not FileAccess.file_exists(song_path)
	ok = ok and not FileAccess.file_exists(audio_root.path_join("preview/snes/theme_preview.wav"))

	print("BGM_EDITOR ", "PASS" if ok else "FAIL")
	editor.queue_free()
	await process_frame
	quit(0 if ok else 1)

func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
