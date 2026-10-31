extends SceneTree
## Native MUGEN tools: SFF v1/v2, AIR, SND, DEF, hub loading and project import.

const SffBank = preload("res://addons/retro_engine/mugen_sff.gd")
const AirAnim = preload("res://addons/retro_engine/mugen_air.gd")
const SndBank = preload("res://addons/retro_engine/mugen_snd.gd")
const MugenDef = preload("res://addons/retro_engine/mugen_def.gd")
const MugenTools = preload("res://addons/retro_engine/mugen_tools.gd")
const MugenImport = preload("res://addons/retro_engine/mugen_import.gd")

const KOF := "/home/fabio/.local/share/godot-retro-engine/ide/workspaces/kof98_port_snes"
var ok := true

func _initialize() -> void:
	await process_frame
	if not DirAccess.dir_exists_absolute(KOF):
		print("MUGEN_TOOLS_TEST SKIP (KOF workspace not found)")
		quit(0)
		return
	var kyo_def := KOF + "/assets/characters/Kyo-KOF98/Kyo-KOF98.def"
	var kyo_sff := KOF + "/assets/characters/Kyo-KOF98/Kyo.sff"
	var kyo_air := KOF + "/assets/characters/Kyo-KOF98/Kyo.air"
	var kyo_snd := KOF + "/assets/characters/Kyo-KOF98/Kyo.snd"
	var stage_def := KOF + "/assets/stages/KOF98-JpnStreetStage.def"

	var sff = SffBank.new()
	_check("sff_v1_load", sff.load_file(kyo_sff), sff.error_message())
	_check("sff_v1_count", sff.sprite_count() > 2000, str(sff.sprite_count()))
	var img: Image = sff.render(0)
	_check("sff_v1_render", img != null and img.get_width() > 0)
	var pal_a: PackedColorArray = sff.find(0, 0).get("palette", PackedColorArray())
	var pal_b: PackedColorArray = sff.find(0, 2).get("palette", PackedColorArray())
	_check("sff_v1_shared_palette", pal_a.size() == 256 and pal_b.size() == 256 and pal_a.slice(0, 6) == pal_b.slice(0, 6), str(pal_a.slice(0, 3)) + " / " + str(pal_b.slice(0, 3)))

	var sff2 = SffBank.new()
	_check("sff_v2_load", sff2.load_file(KOF + "/assets/stages/stage0.sff"), sff2.error_message())
	var img2: Image = sff2.render(0)
	_check("sff_v2_render", img2 != null and img2.get_width() > 0)

	var air = AirAnim.new()
	_check("air_load", air.load_file(kyo_air), str(air.actions.size()))
	_check("air_action_0", air.frame_count(0) > 0 and not air.frame_at(0, 0).get("clsn2", []).is_empty(), str(air.frame_count(0)))

	var snd = SndBank.new()
	_check("snd_load", snd.load_file(kyo_snd), str(snd.entry_count()))
	var stream: AudioStreamWAV = snd.stream_for(0, 0)
	_check("snd_stream", stream != null and stream.mix_rate > 0)

	var cdef = MugenDef.new()
	_check("def_char", cdef.load_file(kyo_def) and cdef.is_character())
	var files := cdef.character_files()
	_check("def_char_files", FileAccess.file_exists(String(files.get("sprite", ""))) and FileAccess.file_exists(String(files.get("anim", ""))))
	var sdef = MugenDef.new()
	_check("def_stage", sdef.load_file(stage_def) and sdef.is_stage())
	_check("def_stage_layers", sdef.bg_layers.size() == 10, str(sdef.bg_layers.size()))

	var tools = MugenTools.new()
	get_root().add_child(tools)
	await process_frame
	_check("tools_char", tools.open_char(kyo_def, 20) and tools.current_page() == "char")
	_check("tools_stage", tools.open_stage(stage_def) and tools.current_page() == "stage")
	_check("tools_stage_layers", tools._stage_layers.get_root() != null and tools._stage_layers.get_root().get_child_count() == 10, str(tools._stage_layers.get_root().get_child_count() if tools._stage_layers.get_root() else 0))
	_check("tools_sff", tools.open_sff(kyo_sff) and tools.current_page() == "sff")
	_check("tools_snd", tools.open_snd(kyo_snd) and tools.current_page() == "sounds")
	_check("tools_snd_list", tools._snd_list.item_count > 0, str(tools._snd_list.item_count))
	tools.queue_free()

	var root := "/tmp/opencode/mugen_tools_test"
	_remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	var project := RetroProject.new()
	project.set_name("mugen_tools_test")
	project.set_path(root)
	project.set_source_path(root)
	project.set_platform("snes")
	project.set_mode("mode1")
	var cres: Dictionary = MugenImport.import_character(project, kyo_def, "snes", 24)
	_check("import_char", bool(cres.get("ok", false)), String(cres.get("error", "")))
	_check("import_char_files", FileAccess.file_exists(String(cres.get("sprite_png", ""))) and FileAccess.file_exists(String(cres.get("anim_json", ""))))
	var sres: Dictionary = MugenImport.import_stage(project, stage_def, "snes")
	_check("import_stage", bool(sres.get("ok", false)), String(sres.get("error", "")))
	_check("import_stage_json", FileAccess.file_exists(String(sres.get("stage_json", ""))))
	_check("import_resources", project.get_resources().size() >= 4, str(project.get_resources().size()))

	print("MUGEN_TOOLS_TEST ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _check(name: String, condition: bool, detail := "") -> void:
	if not condition:
		ok = false
	print("MUGEN ", name, " ", "PASS" if condition else "FAIL", (" " + detail) if detail != "" else "")

func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	while true:
		var name := da.get_next()
		if name.is_empty():
			break
		if name == "." or name == "..":
			continue
		var p := path.path_join(name)
		if da.current_is_dir():
			_remove_tree(p)
		else:
			DirAccess.remove_absolute(p)
	da.list_dir_end()
	DirAccess.remove_absolute(path)
