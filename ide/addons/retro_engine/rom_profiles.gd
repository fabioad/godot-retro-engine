@tool
extends RefCounted
## SNES ROM mappings, header sizes and size-based suggestions.
##
## Mapping facts:
## - LoROM mode $20 (Slow) / $30 (Fast): 32 KiB banks, max 4 MiB.
## - HiROM mode $21 (Slow) / $31 (Fast): 64 KiB banks, max 4 MiB.
## - ExHiROM mode $25 (Slow) / $35 (Fast): 64 KiB banks, max 8 MiB;
##   used by Tales of Phantasia (6 MiB, FastROM).
## - Star Ocean uses S-DD1 (mode $32, FastROM) and a 6 MiB raw ROM. This
##   engine generates the header/layout only; S-DD1 compression/MMC is external.
## - MSU-1 is an expansion that adds a .msu data file and PCM tracks; the base
##   ROM remains LoROM/HiROM (usually <=4 MiB).

const PROFILES := {
	"lorom_slow": {
		"id": "lorom_slow", "label": "LoROM (SlowROM)", "mapping": "lorom",
		"fast": false, "max_bytes": 0x400000, "header_mode": 0x20,
		"sram_code": 0x00, "cart_type": 0x00, "custom_header": false,
	},
	"lorom_fast": {
		"id": "lorom_fast", "label": "LoROM FastROM", "mapping": "lorom",
		"fast": true, "max_bytes": 0x400000, "header_mode": 0x30,
		"sram_code": 0x00, "cart_type": 0x00, "custom_header": false,
	},
	"hirom_slow": {
		"id": "hirom_slow", "label": "HiROM (SlowROM)", "mapping": "hirom",
		"fast": false, "max_bytes": 0x400000, "header_mode": 0x21,
		"sram_code": 0x00, "cart_type": 0x00, "custom_header": false,
	},
	"hirom_fast": {
		"id": "hirom_fast", "label": "HiROM FastROM", "mapping": "hirom",
		"fast": true, "max_bytes": 0x400000, "header_mode": 0x31,
		"sram_code": 0x00, "cart_type": 0x00, "custom_header": false,
	},
	"exhirom_fast": {
		"id": "exhirom_fast", "label": "ExHiROM FastROM (8 MiB)", "mapping": "exhirom",
		"fast": true, "max_bytes": 0x800000, "header_mode": 0x35,
		"sram_code": 0x00, "cart_type": 0x00, "custom_header": true,
		"default_size": 0x800000,
	},
	"tales_phantasia": {
		"id": "tales_phantasia", "label": "Tales of Phantasia (ExHiROM FastROM 48 Mbit)",
		"mapping": "exhirom", "fast": true, "max_bytes": 0x600000,
		"header_mode": 0x35, "sram_code": 0x03, "cart_type": 0x02,
		"custom_header": true, "fixed_size": 0x600000,
	},
	"kof98_sd2snes": {
		"id": "kof98_sd2snes", "label": "KOF98 / SD2SNES MKII (ExHiROM 8 MiB + MSU-1)",
		"mapping": "exhirom", "fast": true, "max_bytes": 0x800000,
		"header_mode": 0x35, "sram_code": 0x00, "cart_type": 0x00,
		"custom_header": true, "fixed_size": 0x800000, "msu1_recommended": true,
	},
	"star_ocean": {
		"id": "star_ocean", "label": "Star Ocean (S-DD1 48 Mbit)",
		"mapping": "hirom", "fast": true, "max_bytes": 0x600000,
		"header_mode": 0x32, "sram_code": 0x03, "cart_type": 0x02,
		"custom_header": true, "fixed_size": 0x600000, "requires_sdd1": true,
	},
}

const SIZES := [
	{"id": "2m", "code": 0x08, "bytes": 0x040000, "label": "2 Mbit (256 KiB)"},
	{"id": "4m", "code": 0x09, "bytes": 0x080000, "label": "4 Mbit (512 KiB)"},
	{"id": "8m", "code": 0x0A, "bytes": 0x100000, "label": "8 Mbit (1 MiB)"},
	{"id": "16m", "code": 0x0B, "bytes": 0x200000, "label": "16 Mbit (2 MiB)"},
	{"id": "32m", "code": 0x0C, "bytes": 0x400000, "label": "32 Mbit (4 MiB)"},
	{"id": "48m", "code": 0x0D, "bytes": 0x600000, "label": "48 Mbit (6 MiB)"},
	{"id": "64m", "code": 0x0D, "bytes": 0x800000, "label": "64 Mbit (8 MiB)"},
]


# Mega Drive large-ROM mappings. Capacities above 8 MiB are not universal
# Mega Drive formats: they depend on the mapper and the flashcart/hardware.
const MD_PROFILES := {
	"md_linear": {
		"id": "md_linear", "label": "Mega Drive linear (up to 4 MiB)",
		"mapper": "linear", "max_bytes": 0x400000, "window_bytes": 0x400000,
		"segment_bytes": 0, "registers": "", "build_supported": true,
	},
	"md_ssf2": {
		"id": "md_ssf2", "label": "SSF2 mapper (8 MiB)",
		"mapper": "ssf2", "max_bytes": 0x800000, "window_bytes": 0x400000,
		"segment_bytes": 0x80000, "segments": 8, "fixed_segments": 1,
		"registers": "$A130F1-$A130FF", "build_supported": true,
	},
	"md_ssf2_ext": {
		"id": "md_ssf2_ext", "label": "Extended SSF2 mapper (above 8 MiB)",
		"mapper": "ssf2_ext", "max_bytes": 0x2000000, "window_bytes": 0x400000,
		"segment_bytes": 0x80000, "segments": 8, "fixed_segments": 1,
		"registers": "$A130F1-$A130FF", "build_supported": true,
	},
	"md_pier_solar": {
		"id": "md_pier_solar", "label": "Pier Solar mapper (8 MiB)",
		"mapper": "pier_solar", "max_bytes": 0x800000, "window_bytes": 0x400000,
		"segment_bytes": 0x80000, "segments": 8, "fixed_segments": 1,
		"registers": "Pier Solar mapper registers", "build_supported": true,
	},
	"md_custom_16": {
		"id": "md_custom_16", "label": "Custom mapper (16 MiB)",
		"mapper": "custom", "max_bytes": 0x1000000, "window_bytes": 0x400000,
		"segment_bytes": 0x80000, "segments": 8, "fixed_segments": 1,
		"registers": "custom mapper", "build_supported": true,
	},
	"md_custom_32": {
		"id": "md_custom_32", "label": "Custom mapper (32 MiB)",
		"mapper": "custom", "max_bytes": 0x2000000, "window_bytes": 0x400000,
		"segment_bytes": 0x80000, "segments": 8, "fixed_segments": 1,
		"registers": "custom mapper", "build_supported": true,
	},
	"md_mega_cd": {
		"id": "md_mega_cd", "label": "Mega-CD image (hundreds of MiB)",
		"mapper": "mega_cd", "max_bytes": 0x40000000, "window_bytes": 0x400000,
		"segment_bytes": 0, "registers": "", "build_supported": false,
		"requires_companion": true,
	},
	"md_msu_md": {
		"id": "md_msu_md", "label": "MSU-MD / MD+ (external audio/data)",
		"mapper": "msu_md", "max_bytes": 0x800000, "window_bytes": 0x400000,
		"segment_bytes": 0x80000, "segments": 8, "fixed_segments": 1,
		"registers": "flashcart MSU-MD / MD+", "build_supported": true,
		"requires_companion": true,
	},
}

const MD_SIZES := [
	{"id": "md_128k", "bytes": 0x020000, "label": "128 KiB"},
	{"id": "md_256k", "bytes": 0x040000, "label": "256 KiB"},
	{"id": "md_512k", "bytes": 0x080000, "label": "512 KiB"},
	{"id": "md_1m", "bytes": 0x100000, "label": "1 MiB"},
	{"id": "md_2m", "bytes": 0x200000, "label": "2 MiB"},
	{"id": "md_4m", "bytes": 0x400000, "label": "4 MiB (linear limit)"},
	{"id": "md_8m", "bytes": 0x800000, "label": "8 MiB (SSF2 limit)"},
	{"id": "md_16m", "bytes": 0x1000000, "label": "16 MiB (custom mapper)"},
	{"id": "md_32m", "bytes": 0x2000000, "label": "32 MiB (custom mapper)"},
]

static func md_profiles() -> Array:
	var out: Array = []
	for id in ["md_linear", "md_ssf2", "md_ssf2_ext", "md_pier_solar", "md_custom_16", "md_custom_32", "md_mega_cd", "md_msu_md"]:
		out.append(MD_PROFILES[id].duplicate(true))
	return out

static func md_sizes() -> Array:
	return MD_SIZES.duplicate(true)

static func profiles_for_platform(platform: String) -> Array:
	return md_profiles() if platform == "megadrive" else profiles()

static func sizes_for_platform(platform: String) -> Array:
	return md_sizes() if platform == "megadrive" else sizes()

static func resolve_md(settings: Dictionary, estimated_bytes: int) -> Dictionary:
	var profile_id := String(settings.get("profile", ""))
	if profile_id.is_empty() or profile_id == "auto":
		profile_id = "md_ssf2" if estimated_bytes > 0x400000 else "md_linear"
	if bool(settings.get("msu_md", false)) and (profile_id == "auto" or profile_id == "md_linear" or profile_id == "md_ssf2"):
		profile_id = "md_msu_md"
	var p: Dictionary = MD_PROFILES.get(profile_id, {}).duplicate(true)
	if p.is_empty():
		return {"ok": false, "errors": ["Unknown Mega Drive ROM profile: " + profile_id], "warnings": []}
	var size_id := String(settings.get("size_id", "auto"))
	var requested: Dictionary = {}
	if not size_id.is_empty() and size_id != "auto":
		for item in MD_SIZES:
			if String(item["id"]) == size_id:
				requested = item.duplicate(true)
				break
	var mapper := String(p.get("mapper", "linear"))
	var bytes := maxi(estimated_bytes, int(requested.get("bytes", 0)))
	var default_size := 0
	if mapper in ["ssf2", "ssf2_ext", "pier_solar", "msu_md"]:
		default_size = 0x800000
	elif mapper == "custom" and int(p.get("max_bytes", 0)) >= 0x2000000:
		default_size = 0x2000000
	elif mapper == "custom":
		default_size = 0x1000000
	elif mapper == "mega_cd":
		default_size = 0x40000000
	if bytes == 0:
		bytes = default_size if default_size > 0 else 0x400000
	var chosen := requested
	if chosen.is_empty():
		var want := maxi(bytes, default_size)
		for item in MD_SIZES:
			if int(item["bytes"]) >= want:
				chosen = item.duplicate(true)
				break
	if chosen.is_empty():
		chosen = MD_SIZES[MD_SIZES.size() - 1].duplicate(true)
	var size_bytes := int(chosen["bytes"])
	var warnings: Array = []
	var errors: Array = []
	if size_bytes > int(p["max_bytes"]):
		errors.append("%s supports at most %s." % [String(p["label"]), human_bytes(int(p["max_bytes"]))])
	if size_bytes < estimated_bytes:
		warnings.append("ROM size %s is smaller than the estimated payload %s." % [String(chosen["label"]), human_bytes(estimated_bytes)])
	if bool(p.get("build_supported", true)) == false:
		errors.append("%s needs a Mega-CD image builder; this editor only exports the profile metadata." % String(p["label"]))
	if String(p.get("mapper", "")) == "ssf2" or String(p.get("mapper", "")) == "ssf2_ext" or String(p.get("mapper", "")) == "pier_solar" or String(p.get("mapper", "")) == "custom":
		warnings.append("This profile needs mapper bank switching; generated projects include the mapper header/source scaffold, but the game must select banks explicitly.")
	if bool(p.get("requires_companion", false)):
		warnings.append("This profile needs an external companion (Mega-CD disc or MSU-MD/MD+ data file) supplied by the flashcart/runtime.")
	if size_bytes > 0x400000 and String(p.get("mapper", "")) == "linear":
		errors.append("Linear Mega Drive ROMs are limited to 4 MiB; use an SSF2, Pier Solar or custom mapper profile.")
	return {
		"ok": errors.is_empty(), "errors": errors, "warnings": warnings,
		"profile": p, "profile_id": profile_id, "profile_label": String(p["label"]),
		"size": chosen, "size_id": String(chosen["id"]), "size_label": String(chosen["label"]),
		"size_bytes": size_bytes, "sizealign": size_bytes, "mapper": String(p["mapper"]),
		"window_bytes": int(p.get("window_bytes", 0x400000)), "segment_bytes": int(p.get("segment_bytes", 0)),
		"segments": int(p.get("segments", 1)), "fixed_segments": int(p.get("fixed_segments", 1)),
		"registers": String(p.get("registers", "")), "build_supported": bool(p.get("build_supported", true)),
		"requires_companion": bool(p.get("requires_companion", false)),
		"companion": "Mega-CD" if String(p.get("mapper", "")) == "mega_cd" else ("MSU-MD/MD+" if String(p.get("mapper", "")) == "msu_md" else ""),
	}

static func suggest_md(bytes: int, msu_md := false) -> Dictionary:
	if msu_md:
		return {"profile": "md_msu_md", "size": _md_size_for_bytes(maxi(bytes, 0x400000)),
			"reason": "MSU-MD/MD+ streams audio/data from the flashcart companion"}
	if bytes <= 0x400000:
		return {"profile": "md_linear", "size": _md_size_for_bytes(bytes),
			"reason": "linear Mega Drive window, no mapper needed"}
	if bytes <= 0x800000:
		return {"profile": "md_ssf2", "size": _md_size_for_bytes(bytes),
			"reason": "SSF2 mapper exposes 8 segments of 512 KiB in the 4 MiB window"}
	if bytes <= 0x1000000:
		return {"profile": "md_custom_16", "size": _md_size_for_bytes(bytes),
			"reason": "above the 8 MiB SSF2 limit; custom mapper/hardware required"}
	return {"profile": "md_custom_32", "size": _md_size_for_bytes(bytes),
		"reason": "above 8 MiB is not a universal Mega Drive format; mapper/hardware specific"}

static func _md_size_for_bytes(bytes: int) -> Dictionary:
	for item in MD_SIZES:
		if int(item["bytes"]) >= maxi(bytes, 0x80000):
			return item.duplicate(true)
	return MD_SIZES[MD_SIZES.size() - 1].duplicate(true)

static func resolve_for(target: String, settings: Dictionary, estimated_bytes: int) -> Dictionary:
	if target == "megadrive":
		return resolve_md(settings, estimated_bytes)
	return resolve(settings, estimated_bytes)

static func suggest_for(target: String, bytes: int, companion := false) -> Dictionary:
	if target == "megadrive":
		return suggest_md(bytes, companion)
	return suggest(bytes, companion)

static func profile_ids() -> Array:
	return ["lorom_slow", "lorom_fast", "hirom_slow", "hirom_fast", "exhirom_fast", "tales_phantasia", "star_ocean", "kof98_sd2snes"]

static func profiles() -> Array:
	var out: Array = []
	for id in profile_ids():
		out.append(PROFILES[id].duplicate(true))
	return out

static func profile(id: String) -> Dictionary:
	return PROFILES.get(id, {}).duplicate(true)

static func profile_any(id: String) -> Dictionary:
	if MD_PROFILES.has(id):
		return MD_PROFILES[id].duplicate(true)
	return profile(id)

static func size_any(id: String) -> Dictionary:
	for item in MD_SIZES:
		if String(item["id"]) == id:
			return item.duplicate(true)
	return size_by_id(id)

static func sizes() -> Array:
	return SIZES.duplicate(true)

static func size_by_id(id: String) -> Dictionary:
	for size in SIZES:
		if String(size["id"]) == id:
			return size.duplicate(true)
	return {}

static func size_for_bytes(bytes: int) -> Dictionary:
	for size in SIZES:
		if int(size["bytes"]) >= bytes:
			return size.duplicate(true)
	return SIZES[SIZES.size() - 1].duplicate(true)

static func size_for_code(code: int) -> Dictionary:
	for size in SIZES:
		if int(size["code"]) == code:
			return size.duplicate(true)
	return {}

static func suggest(bytes: int, msu1 := false) -> Dictionary:
	bytes = maxi(bytes, 0x40000)
	if msu1:
		var base := "hirom_fast" if bytes > 0x200000 else "lorom_fast"
		return {
			"profile": base,
			"size": size_for_bytes(mini(bytes, 0x400000)),
			"reason": "MSU-1 uses a LoROM/HiROM base plus the .msu data file",
			"msu1": true,
		}
	if bytes <= 0x200000:
		return {"profile": "lorom_fast", "size": size_for_bytes(bytes),
			"reason": "fits a small LoROM image; FastROM improves ROM access"}
	if bytes <= 0x400000:
		return {"profile": "hirom_fast", "size": size_for_bytes(bytes),
			"reason": "larger data benefits from HiROM's 64 KiB banks"}
	if bytes <= 0x800000:
		return {"profile": "exhirom_fast", "size": SIZES[6].duplicate(true),
			"reason": "exceeds the 4 MiB LoROM/HiROM limit; ExHiROM FastROM reaches 8 MiB"}
	return {
		"profile": "hirom_fast",
		"size": SIZES[4].duplicate(true),
		"reason": "exceeds 8 MiB; use the MSU-1 data file for the extra assets",
		"msu1": true,
	}

static func resolve(settings: Dictionary, estimated_bytes: int) -> Dictionary:
	var msu1 := bool(settings.get("msu1", false))
	var size_id := String(settings.get("size_id", ""))
	var requested_size: Dictionary = {}
	if not size_id.is_empty() and size_id != "auto":
		requested_size = size_by_id(size_id)
	var basis_bytes := maxi(estimated_bytes, int(requested_size.get("bytes", 0)))
	var suggestion := suggest(basis_bytes, msu1)
	var profile_id := String(settings.get("profile", ""))
	if profile_id.is_empty() or profile_id == "auto":
		profile_id = String(suggestion["profile"])
	var p := profile(profile_id)
	if p.is_empty():
		return {
			"ok": false,
			"error": "Unknown SNES ROM profile: " + profile_id,
			"errors": ["Unknown SNES ROM profile: " + profile_id],
			"error_codes": [{"code": "game_build.rom_error_unknown_profile", "params": {"profile": profile_id}}],
			"warnings": [],
			"warning_codes": [],
		}
	var fixed_size := int(p.get("fixed_size", 0))
	var default_size := int(p.get("default_size", 0))
	var size := {}
	if fixed_size > 0:
		size = size_for_bytes(fixed_size)
	elif size_id.is_empty() or size_id == "auto":
		size = size_for_bytes(default_size) if default_size > 0 else suggestion["size"]
	else:
		size = size_by_id(size_id)
	if size.is_empty():
		return {
			"ok": false,
			"error": "Unknown SNES ROM size: " + size_id,
			"errors": ["Unknown SNES ROM size: " + size_id],
			"error_codes": [{"code": "game_build.rom_error_unknown_size", "params": {"size": size_id}}],
			"warnings": [],
			"warning_codes": [],
		}
	var size_bytes := int(size["bytes"])
	var mapping := String(p["mapping"])
	var banks := size_bytes / (0x8000 if mapping == "lorom" else 0x10000)
	var warnings: Array = []
	var warning_codes: Array = []
	var errors: Array = []
	var error_codes: Array = []
	if size_bytes > int(p["max_bytes"]):
		errors.append("%s supports at most %s." % [p["label"], _mib(int(p["max_bytes"]))])
		error_codes.append({
			"code": "game_build.rom_error_too_large",
			"params": {"profile": String(p["label"]), "max": _mib(int(p["max_bytes"]))},
		})
	if size_bytes < estimated_bytes:
		warnings.append("ROM size %s is smaller than the estimated asset payload %s." % [size["label"], _mib(estimated_bytes)])
		warning_codes.append({
			"code": "game_build.rom_warn_small",
			"params": {"size": String(size["label"]), "estimate": _mib(estimated_bytes)},
		})
	if bool(p.get("requires_sdd1", false)):
		warnings.append("Star Ocean preset sets the S-DD1 header/layout; S-DD1 compression and MMC code are not included.")
	if bool(p.get("msu1_recommended", false)) and not msu1:
		warnings.append("KOF98/SD2SNES preset: enable MSU-1 and keep the matching .msu companion beside the 8 MiB ROM.")
		warning_codes.append({"code": "game_build.rom_warn_sdd1", "params": {}})
	if msu1 and mapping == "exhirom":
		warnings.append("MSU-1 normally uses a LoROM/HiROM base; ExHiROM is unusual.")
		warning_codes.append({"code": "game_build.rom_warn_msu1_exhirom", "params": {}})
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"error_codes": error_codes,
		"warnings": warnings,
		"warning_codes": warning_codes,
		"profile": p,
		"profile_id": profile_id,
		"profile_label": String(p["label"]),
		"size": size,
		"size_id": String(size["id"]),
		"size_label": String(size["label"]),
		"size_code": int(size["code"]),
		"size_bytes": size_bytes,
		"banks": banks,
		"mapping": mapping,
		"fast": bool(p["fast"]),
		"header_mode": int(p["header_mode"]),
		"sram_code": int(p["sram_code"]),
		"cart_type": int(p["cart_type"]),
		"custom_header": bool(p["custom_header"]),
		"fixed_size": fixed_size,
		"trim_to": size_bytes if size_bytes == 0x600000 else 0,
		"msu1": msu1,
		"suggestion": suggestion,
	}

static func _mib(bytes: int) -> String:
	if bytes >= 0x100000:
		return "%.1f MiB" % (bytes / 1048576.0)
	return "%d KiB" % (bytes / 1024)

static func human_bytes(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.2f MiB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%.1f KiB" % (bytes / 1024.0)
	return "%d bytes" % bytes

