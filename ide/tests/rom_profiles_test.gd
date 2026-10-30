extends SceneTree
## Pure ROM mapping/size/suggestion checks (no toolchain build).

const RomProfiles = preload("res://addons/retro_engine/rom_profiles.gd")

func _initialize() -> void:
	await process_frame
	var ok := true
	var suggestions := [
		[0x40000, "lorom_fast", "2m"],
		[0x100000, "lorom_fast", "8m"],
		[0x200000, "lorom_fast", "16m"],
		[0x300000, "hirom_fast", "32m"],
		[0x400000, "hirom_fast", "32m"],
		[0x500000, "exhirom_fast", "64m"],
		[0x600000, "exhirom_fast", "64m"],
		[0x800000, "exhirom_fast", "64m"],
	]
	for raw in suggestions:
		var case: Array = raw
		var result: Dictionary = RomProfiles.suggest(int(case[0]), false)
		var good := String(result.get("profile", "")) == String(case[1]) \
			and String(Dictionary(result.get("size", {})).get("id", "")) == String(case[2])
		print("ROM_SUGGEST ", case[0], " -> ", result.get("profile"), " ", Dictionary(result.get("size", {})).get("id"), " ", "PASS" if good else "FAIL")
		ok = ok and good

	var msu_small: Dictionary = RomProfiles.suggest(0x200000, true)
	var msu_large: Dictionary = RomProfiles.suggest(0x300000, true)
	var over: Dictionary = RomProfiles.suggest(0xA00000, false)
	var msu_ok := String(msu_small.get("profile", "")) == "lorom_fast" \
		and String(msu_large.get("profile", "")) == "hirom_fast" \
		and bool(msu_small.get("msu1", false)) and bool(over.get("msu1", false))
	print("ROM_SUGGEST_MSU small=", msu_small.get("profile"), " large=", msu_large.get("profile"), " over=", over.get("profile"), " ", "PASS" if msu_ok else "FAIL")
	ok = ok and msu_ok

	var profiles := {
		"lorom_slow": {"mode": 0x20, "size": 0x200000, "banks": 64},
		"lorom_fast": {"mode": 0x30, "size": 0x200000, "banks": 64},
		"hirom_slow": {"mode": 0x21, "size": 0x200000, "banks": 32},
		"hirom_fast": {"mode": 0x31, "size": 0x200000, "banks": 32},
		"exhirom_fast": {"mode": 0x35, "size": 0x800000, "banks": 128},
		"tales_phantasia": {"mode": 0x35, "size": 0x600000, "banks": 96},
		"star_ocean": {"mode": 0x32, "size": 0x600000, "banks": 96},
	}
	for id in profiles.keys():
		var expected: Dictionary = profiles[id]
		var resolved: Dictionary = RomProfiles.resolve({"profile": id}, 0x200000)
		var good := bool(resolved.get("ok", false)) \
			and int(resolved.get("header_mode", 0)) == int(expected["mode"]) \
			and int(resolved.get("size_bytes", 0)) == int(expected["size"]) \
			and int(resolved.get("banks", 0)) == int(expected["banks"])
		print("ROM_PROFILE ", id, " ok=", resolved.get("ok"), " mode=", resolved.get("header_mode"), " size=", resolved.get("size_bytes"), " banks=", resolved.get("banks"), " ", "PASS" if good else "FAIL")
		ok = ok and good

	var tales: Dictionary = RomProfiles.resolve({"profile": "tales_phantasia"}, 0x40000)
	var tales_ok := int(tales.get("trim_to", 0)) == 0x600000 \
		and int(tales.get("sram_code", 0)) == 0x03 \
		and int(tales.get("cart_type", 0)) == 0x02 \
		and bool(tales.get("custom_header", false)) \
		and int(tales.get("fixed_size", 0)) == 0x600000
	print("ROM_TALES fixed=", tales.get("fixed_size"), " trim=", tales.get("trim_to"), " sram=", tales.get("sram_code"), " ", "PASS" if tales_ok else "FAIL")
	ok = ok and tales_ok

	var star: Dictionary = RomProfiles.resolve({"profile": "star_ocean"}, 0x40000)
	var star_codes: Array = star.get("warning_codes", [])
	var star_ok := int(star.get("header_mode", 0)) == 0x32 \
		and bool(star.get("custom_header", false)) \
		and not star_codes.is_empty() \
		and String(Dictionary(star_codes[0]).get("code", "")) == "game_build.rom_warn_sdd1"
	print("ROM_STAR mode=", star.get("header_mode"), " warning=", star_codes, " ", "PASS" if star_ok else "FAIL")
	ok = ok and star_ok

	var too_large: Dictionary = RomProfiles.resolve({"profile": "lorom_fast", "size_id": "64m"}, 0x40000)
	var large_codes: Array = too_large.get("error_codes", [])
	var large_ok := not bool(too_large.get("ok", false)) \
		and not large_codes.is_empty() \
		and String(Dictionary(large_codes[0]).get("code", "")) == "game_build.rom_error_too_large"
	print("ROM_TOO_LARGE ok=", too_large.get("ok"), " code=", large_codes, " ", "PASS" if large_ok else "FAIL")
	ok = ok and large_ok

	var auto_large: Dictionary = RomProfiles.resolve({"profile": "auto", "size_id": "64m"}, 0x40000)
	var auto_large_ok := bool(auto_large.get("ok", false)) \
		and String(auto_large.get("profile_id", "")) == "exhirom_fast" \
		and int(auto_large.get("size_bytes", 0)) == 0x800000
	print("ROM_AUTO_LARGE profile=", auto_large.get("profile_id"), " size=", auto_large.get("size_bytes"), " ", "PASS" if auto_large_ok else "FAIL")
	ok = ok and auto_large_ok

	var small: Dictionary = RomProfiles.resolve({"profile": "hirom_fast", "size_id": "2m"}, 0x300000)
	var small_codes: Array = small.get("warning_codes", [])
	var small_ok := bool(small.get("ok", false)) and not small_codes.is_empty() \
		and String(Dictionary(small_codes[0]).get("code", "")) == "game_build.rom_warn_small"
	print("ROM_TOO_SMALL warning=", small_codes, " ", "PASS" if small_ok else "FAIL")
	ok = ok and small_ok

	var msu_exhirom: Dictionary = RomProfiles.resolve({"profile": "exhirom_fast", "size_id": "64m", "msu1": true}, 0x40000)
	var msu_codes: Array = msu_exhirom.get("warning_codes", [])
	var msu_exhirom_ok := false
	for entry in msu_codes:
		if String(Dictionary(entry).get("code", "")) == "game_build.rom_warn_msu1_exhirom":
			msu_exhirom_ok = true
	print("ROM_MSU1_EXHIROM warning=", msu_codes, " ", "PASS" if msu_exhirom_ok else "FAIL")
	ok = ok and msu_exhirom_ok

	var human_ok := RomProfiles.human_bytes(0x40000) == "256.0 KiB" \
		and RomProfiles.human_bytes(0x600000) == "6.00 MiB"
	print("ROM_HUMAN 256KiB/6MiB ", "PASS" if human_ok else "FAIL")
	ok = ok and human_ok

	print("ROM_PROFILES_TEST ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
