extends SceneTree
## All Godot editor locales must have a complete 401-key dictionary and keep
## every translation placeholder intact.

const I18n = preload("res://addons/retro_engine/i18n.gd")

const LOCALES := [
	"ar", "bg", "bn", "ca", "cs", "de", "el", "eo", "es", "es_AR",
	"et", "fa", "fi", "fr", "ga", "gl", "he", "hu", "id", "it",
	"ja", "ka", "ko", "lo", "nl", "pl", "pt", "pt_BR", "ro", "ru",
	"sk", "sv", "ta", "th", "tok", "tr", "uk", "vi", "zh_Hans", "zh_Hant",
]

func _initialize() -> void:
	await process_frame
	I18n.ensure_loaded()
	var previous := TranslationServer.get_locale()
	var ok := true
	var en: Dictionary = I18n.STRINGS["en"]
	var en_keys := en.keys()
	var ph := RegEx.new()
	ph.compile("\\{[A-Za-z_][A-Za-z0-9_]*\\}")
	for locale in LOCALES:
		if not I18n.STRINGS.has(locale):
			print("I18N_COVERAGE missing locale ", locale)
			ok = false
			continue
		var table: Dictionary = I18n.STRINGS[locale]
		if table.size() != en_keys.size():
			print("I18N_COVERAGE key count ", locale, " ", table.size(), "/", en_keys.size())
			ok = false
		for key in en_keys:
			if not table.has(key):
				print("I18N_COVERAGE missing key ", locale, " ", key)
				ok = false
				continue
			var expected := _placeholders(ph, String(en[key]))
			var actual := _placeholders(ph, String(table[key]))
			if expected != actual:
				print("I18N_COVERAGE placeholder mismatch ", locale, " ", key, " ", expected, " != ", actual)
				ok = false
		TranslationServer.set_locale(locale)
		if I18n.current_language() != locale:
			print("I18N_COVERAGE locale resolution ", locale, " -> ", I18n.current_language())
			ok = false
		if I18n.t("common.close").is_empty() or I18n.t("common.close") == "common.close":
			print("I18N_COVERAGE empty translation ", locale)
			ok = false
		var sample := I18n.t("top.new_project")
		if sample.is_empty() or sample == "top.new_project":
			print("I18N_COVERAGE empty sample ", locale)
			ok = false
		print("I18N_LOCALE ", locale, " keys=", table.size(), " sample=", sample)

	# Region/script fallbacks.
	var fallbacks := {
		"pt_PT": "pt_BR",
		"fr_FR": "fr",
		"de_DE": "de",
		"es_MX": "es",
		"zh_CN": "zh_Hans",
		"zh_TW": "zh_Hant",
		"en_GB": "en",
	}
	for locale in fallbacks:
		TranslationServer.set_locale(locale)
		var expected := String(fallbacks[locale])
		var actual := I18n.current_language()
		print("I18N_FALLBACK ", locale, " -> ", actual)
		if actual != expected:
			ok = false
	TranslationServer.set_locale(previous)
	print("I18N_COVERAGE_TEST ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _placeholders(re: RegEx, text: String) -> Array:
	var out: Array = []
	for m in re.search_all(text):
		out.append(m.get_string())
	out.sort()
	return out
