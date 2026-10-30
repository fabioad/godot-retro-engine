extends SceneTree
func _initialize() -> void:
	await process_frame
	var dir := "/tmp/opencode/audio_editor_project"
	DirAccess.make_dir_recursive_absolute(dir)
	var project := RetroProject.new()
	project.set_name("audio_editor"); project.set_path(dir); project.set_platform("snes"); project.save()
	var editor = preload("res://addons/retro_engine/audio_editor.gd").new()
	get_root().add_child(editor)
	await process_frame
	editor.set_project(project)
	editor._name.text = "beep"; editor._frequency.value = 440; editor._duration.value = 120
	editor._create_sfx()
	var descriptor := dir.path_join(".retro/audio/beep.retro_audio.json")
	var ok := FileAccess.file_exists(descriptor)
	if ok:
		editor._refresh_list(); editor._asset_list.select(0); editor._on_selected(0)
		editor._preview("snes")
		for i in range(240):
			await process_frame
			if not editor._preview_busy:
				break
		ok = editor._player.stream != null and editor._player.playing
		editor._stop_preview()
		await process_frame
		ok = ok and not editor._player.playing and editor._player.stream == null
		# Stop during conversion must cancel the pending preview.
		editor._preview("snes")
		editor._stop_preview()
		for i in range(240):
			await process_frame
			if not editor._preview_busy:
				break
		ok = ok and editor._player.stream == null and not editor._player.playing
	print("AUDIO_EDITOR ", "PASS" if ok else "FAIL", " stream=", editor._player.stream)
	editor.queue_free()
	quit(0 if ok else 1)
