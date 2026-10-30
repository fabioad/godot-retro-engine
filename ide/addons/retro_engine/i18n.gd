@tool
extends RefCounted
## Retro addon translations.
##
## The UI follows TranslationServer (the editor locale). All 40 Godot editor
## locales are shipped in locales.json; English is the fallback. The JSON is
## loaded lazily because a single 16k-entry GDScript dictionary is too large
## for the GDScript parser.
##
## Use named placeholders such as {project} and pass a Dictionary:
##   I18n.t("checks.platform_mismatch", {"project": "meu_jogo", ...})

const LOCALES_PATH := "res://addons/retro_engine/locales.json"

static var STRINGS: Dictionary = {}
static var _loaded := false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(LOCALES_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(LOCALES_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		STRINGS = parsed

static func current_language() -> String:
	ensure_loaded()
	var raw := TranslationServer.get_locale().replace("-", "_")
	if STRINGS.has(raw):
		return raw
	var locale := raw.to_lower()
	if locale.begins_with("pt"):
		return "pt_BR" if STRINGS.has("pt_BR") else "en"
	if locale.begins_with("es"):
		return "es"
	if locale.begins_with("zh"):
		if locale.contains("hans") or locale in ["zh_cn", "zh_sg"]:
			return "zh_Hans"
		return "zh_Hant"
	var base := locale.get_slice("_", 0)
	if STRINGS.has(base):
		return base
	if locale.begins_with("en"):
		return "en"
	return "en"

static func t(key: String, params = {}) -> String:
	ensure_loaded()
	var lang := current_language()
	var table: Dictionary = STRINGS.get(lang, {})
	var english: Dictionary = STRINGS.get("en", {})
	var text := String(table.get(key, english.get(key, key)))
	if params is Dictionary:
		for name in params.keys():
			text = text.replace("{%s}" % String(name), str(params[name]))
	elif params is Array:
		for i in range(params.size()):
			text = text.replace("{%d}" % i, str(params[i]))
	return text

static func platform_label(platform: String) -> String:
	return t("common.snes") if platform == "snes" else (t("common.megadrive") if platform == "megadrive" else platform)
