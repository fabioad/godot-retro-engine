@tool
extends RefCounted
## Real SNES/Mega Drive audio conversion used by the editor and Game Build.
##
## Heavy lifting lives in tools/retro_audio_tool.py (MIDI/IT/WAV/MP3 -> IT,
## VGM/PSG or PCM, WAV -> BRR, SFX synthesis). This wrapper only locates the
## SDK tools, runs the converter and exposes previews to the audio editor.

const TOOL_PATH := "res://addons/retro_engine/tools/retro_audio_tool.py"

static func tool_path() -> String:
	return ProjectSettings.globalize_path(TOOL_PATH)

static func default_sfx_params() -> Dictionary:
	return {
		"waveform": "square",
		"frequency": 660.0,
		"duration_ms": 220.0,
		"volume": 0.8,
		"duty": 0.5,
		"attack_ms": 2.0,
		"decay_ms": 50.0,
		"sustain": 0.65,
		"release_ms": 70.0,
		"pitch_slide": 0.0,
		"vibrato_hz": 0.0,
		"vibrato_depth": 0.0,
		"noise": 0.0,
		"bitcrush": 16,
	}

static func _run(args: Array) -> Dictionary:
	var output: Array = []
	var python := "python3" if OS.get_name() != "Windows" else "python"
	var code := OS.execute(python, [tool_path()] + args, output, true)
	var text := ""
	for line in output:
		text += String(line)
	var parsed = null
	var first := text.find("{")
	var last := text.rfind("}")
	if first >= 0 and last > first:
		parsed = JSON.parse_string(text.substr(first, last - first + 1))
	var ok := code == 0 and parsed != null and bool(parsed.get("ok", true))
	return {"ok": ok, "exit": code, "output": text, "json": parsed}

static func _safe_name(name: String) -> String:
	var out := ""
	for c in name.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" else "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "audio"

static func _ensure_snes_env() -> void:
	var snes_root := String(RetroSDK.get_sdk("snes").get("path", ""))
	if snes_root.is_empty():
		snes_root = OS.get_environment("PVSNESLIB_HOME")
	if snes_root.is_empty():
		return
	OS.set_environment("PVSNESLIB_HOME", snes_root)
	var snesbrr := snes_root.path_join("devkitsnes/tools/snesbrr")
	if FileAccess.file_exists(snesbrr):
		OS.set_environment("SNESBRR", snesbrr)

static func convert_asset(input_path: String, out_dir: String, name: String, kind: String,
		target: String, params: Dictionary = {}) -> Dictionary:
	if target == "snes":
		_ensure_snes_env()
	var safe := _safe_name(name)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var args := ["convert", "--input", input_path, "--out-dir", out_dir,
		"--name", safe, "--kind", kind, "--target", target]
	if not params.is_empty():
		var params_path := out_dir.path_join(safe + ".params.json")
		var pf := FileAccess.open(params_path, FileAccess.WRITE)
		if pf != null:
			pf.store_string(JSON.stringify(params, "\t"))
			pf.close()
			args += ["--params", params_path]
	var run := _run(args)
	var result: Dictionary = {}
	if typeof(run.get("json")) == TYPE_DICTIONARY:
		result = Dictionary(run.get("json")).duplicate(true)
	result["ok"] = bool(run.get("ok", false)) and bool(result.get("ok", true))
	result["exit"] = int(run.get("exit", -1))
	result["output"] = String(run.get("output", ""))
	result["name"] = safe
	result["kind"] = kind
	result["target"] = target
	result["directory"] = out_dir
	return result

static func synthesize_sfx(params: Dictionary, out_dir: String, name: String, target: String) -> Dictionary:
	if target == "snes":
		_ensure_snes_env()
	var safe := _safe_name(name)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var params_path := out_dir.path_join(safe + ".params.json")
	var pf := FileAccess.open(params_path, FileAccess.WRITE)
	if pf == null:
		return {"ok": false, "error": "could not write SFX parameters"}
	pf.store_string(JSON.stringify(params, "\t"))
	pf.close()
	return convert_asset(params_path, out_dir, safe, "sfx", target, params)

static func prepare_for_build(assets: Array, target: String, out_dir: String) -> Dictionary:
	var bgm: Dictionary = {}
	var sfx: Array = []
	var previews: Array = []
	var converted: Array = []
	var used_names := {}
	DirAccess.make_dir_recursive_absolute(out_dir)
	if target == "snes":
		var snes_root := String(RetroSDK.get_sdk("snes").get("path", ""))
		if not snes_root.is_empty():
			OS.set_environment("PVSNESLIB_HOME", snes_root)
			var snesbrr := snes_root.path_join("devkitsnes/tools/snesbrr")
			if FileAccess.file_exists(snesbrr):
				OS.set_environment("SNESBRR", snesbrr)
	for a in assets:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var kind := String(a.get("kind", "sfx"))
		var name := String(a.get("name", a.get("id", "audio")))
		var source := String(a.get("source", a.get("path", "")))
		var params: Dictionary = a.get("params", {})
		if source.is_empty() and params.is_empty():
			continue
		# The generated game uses one BGM. Converting every BGM resource wastes
		# time and can collide with SFX names in the SGDK resource script.
		if kind == "bgm" and not bgm.is_empty():
			continue
		var safe := _safe_name(name)
		var unique := safe
		if used_names.has(unique):
			var prefix := "sfx_" if kind == "sfx" else "bgm_"
			unique = prefix + safe
			var suffix := 2
			while used_names.has(unique):
				unique = "%s%s_%d" % [prefix, safe, suffix]
				suffix += 1
		used_names[unique] = true
		var result := convert_asset(source, out_dir, unique, kind, target, params)
		if not bool(result.get("ok", false)):
			return {"ok": false, "error": "audio conversion failed for %s: %s" % [name, String(result.get("output", ""))]}
		converted.append(result)
		if not String(result.get("preview", "")).is_empty():
			previews.append(String(result.get("preview", "")))
		if kind == "bgm" and bgm.is_empty():
			bgm = result
		elif kind == "sfx":
			sfx.append(result)
	var snes_soundbank := {}
	if target == "snes" and not bgm.is_empty():
		var it_path := String(bgm.get("files", {}).get("it", ""))
		if not it_path.is_empty():
			var smconv := _snes_tool("smconv")
			var bank := out_dir.get_base_dir().path_join("soundbank")
			var sm := _run_external(smconv, ["-s", "-o", bank, it_path])
			if not bool(sm.get("ok", false)):
				return {"ok": false, "error": "smconv failed: " + String(sm.get("output", ""))}
			var bank_symbol := "SOUNDBANK__"
			var bank_asm := FileAccess.get_file_as_string(bank + ".asm")
			if bank_asm.contains("SOUNDBANK__0:"):
				bank_symbol = "SOUNDBANK__0"
			snes_soundbank = {"path": bank, "module": "MOD_" + _safe_name(bgm.get("name", "bgm")).to_upper(),
				"bank_symbol": bank_symbol}
			bgm["soundbank"] = snes_soundbank
	return {"ok": true, "bgm": bgm, "sfx": sfx, "previews": previews,
		"converted": converted, "directory": out_dir, "target": target}

static func _snes_tool(name: String) -> String:
	var sdk := RetroSDK.get_sdk("snes")
	var root := String(sdk.get("path", ""))
	if root.is_empty():
		root = OS.get_environment("PVSNESLIB_HOME")
	var path := root.path_join("devkitsnes/tools").path_join(name)
	return path if FileAccess.file_exists(path) else name

static func _run_external(path: String, args: Array) -> Dictionary:
	var output: Array = []
	var code := OS.execute(path, args, output, true)
	var text := ""
	for line in output:
		text += String(line)
	return {"ok": code == 0, "exit": code, "output": text}
