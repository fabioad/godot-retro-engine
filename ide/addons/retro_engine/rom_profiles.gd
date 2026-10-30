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

static func profile_ids() -> Array:
	return ["lorom_slow", "lorom_fast", "hirom_slow", "hirom_fast", "exhirom_fast", "tales_phantasia", "star_ocean"]

static func profiles() -> Array:
	var out: Array = []
	for id in profile_ids():
		out.append(PROFILES[id].duplicate(true))
	return out

static func profile(id: String) -> Dictionary:
	return PROFILES.get(id, {}).duplicate(true)

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

