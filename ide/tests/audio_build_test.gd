extends SceneTree
## Generates real SNES/Mega Drive ROM projects with the supplied MIDI as BGM
## plus a synthesized jump SFX. The shell test builds both ROMs and records
## emulator audio to prove the conversion is audible.

func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if String(args[i]) == name and i + 1 < args.size():
			return String(args[i + 1])
	return fallback

func _initialize() -> void:
	await process_frame
	var out := _arg("--dir", "/tmp/opencode/audio_build")
	var midi := _arg("--midi", "/tmp/world-map.mid")
	var source_dir := out.path_join("project")
	var audio_dir := source_dir.path_join("audio")
	var sources := audio_dir.path_join("sources")
	DirAccess.make_dir_recursive_absolute(sources)
	DirAccess.make_dir_recursive_absolute(out)
	if not FileAccess.file_exists(midi):
		print("AUDIO_BUILD FAIL missing MIDI: ", midi)
		quit(1)
		return
	var midi_copy := sources.path_join("worldmap.mid")
	if midi != midi_copy:
		DirAccess.copy_absolute(midi, midi_copy)
	var bgm_desc := audio_dir.path_join("worldmap.retro_audio.json")
	_write_json(bgm_desc, {
		"name": "worldmap", "kind": "bgm", "source": midi_copy, "params": {}, "previews": {}
	})
	var sfx_desc := audio_dir.path_join("jump.retro_audio.json")
	_write_json(sfx_desc, {
		"name": "jump", "kind": "sfx", "source": "",
		"params": {
			"waveform": "square", "frequency": 880.0, "duration_ms": 220.0,
			"volume": 0.8, "duty": 0.25, "attack_ms": 2.0, "decay_ms": 60.0,
			"sustain": 0.5, "release_ms": 80.0, "pitch_slide": -12.0,
			"vibrato_hz": 12.0, "vibrato_depth": 0.4, "noise": 0.1, "bitcrush": 12
		}, "previews": {}
	})
	var img := Image.create_empty(320, 224, false, Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			img.set_pixel(x, y, Color(0.1, 0.2, 0.4, 1) if ((x / 8) + (y / 8)) % 2 == 0 else Color(0.25, 0.45, 0.8, 1))
	var bridge := RetroNativeBridge.new()
	var stage_result: Dictionary = bridge.import_stage_image(img, "stage", source_dir, "snes", "mode1", 8, 1024, 16, "native")
	if not bool(stage_result.get("ok", false)):
		print("AUDIO_BUILD FAIL stage import")
		quit(1)
		return
	var stage: RetroStage = stage_result.get("stage")
	stage.save(source_dir.path_join("stage.retro_stage.json"))
	var source := RetroProject.new()
	source.set_name("audio_source")
	source.set_path(source_dir)
	source.set_platform("snes")
	source.set_metadata({"audio_assets": [
		{"path": bgm_desc, "kind": "bgm"},
		{"path": sfx_desc, "kind": "sfx"}
	]})
	var gen = preload("res://addons/retro_engine/game_build.gd")
	var ok := true
	for c in [["native_snes", "audio_snes"], ["native_megadrive", "audio_md"]]:
		var r: Dictionary = gen.generate(String(c[0]), source, out, String(c[1]), false,
			source_dir.path_join("stage.retro_stage.json"))
		print("AUDIO_BUILD GEN ", c[1], " ok=", r.get("ok"), " err=", r.get("error"),
			" bgm=", r.get("profile", {}).get("audio_bgm"),
			" sfx=", r.get("profile", {}).get("audio_sfx"))
		ok = ok and bool(r.get("ok", false))
	print("AUDIO_BUILD PASS" if ok else "AUDIO_BUILD FAIL")
	quit(0 if ok else 1)

func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
