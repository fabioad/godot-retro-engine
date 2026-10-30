extends SceneTree
## Retro addon i18n regression: Portuguese follows the editor locale, other
## locales fall back to English.

const I18n = preload("res://addons/retro_engine/i18n.gd")

func _initialize() -> void:
	await process_frame
	var previous := TranslationServer.get_locale()
	var ok := true

	TranslationServer.set_locale("pt_BR")
	ok = ok and I18n.current_language() == "pt_BR"
	ok = ok and I18n.t("top.new_project") == "Novo Projeto..."
	ok = ok and I18n.t("game_build.mode_snes_md") == "Projeto SNES → Mega Drive"
	ok = ok and I18n.t("native.other_nodes") == "Outros nós"
	ok = ok and I18n.t("terminal.menu") == "Terminais"
	ok = ok and I18n.t("checks.platform_mismatch", {
		"selected": "Mega Drive", "project": "meu_jogo", "project_platform": "SNES",
	}).contains("seletor de plataforma")
	print("I18N pt_BR new_project=", I18n.t("top.new_project"), " mode=", I18n.t("game_build.mode_snes_md"))

	# New dialogs must be created with the Portuguese labels.
	var NewProjectDialog = preload("res://addons/retro_engine/new_project_dialog.gd")
	var np = NewProjectDialog.new()
	get_root().add_child(np)
	await process_frame
	ok = ok and np._create_button.text == "Criar projeto"
	ok = ok and np._build_button.text == "Criar + Compilar"
	ok = ok and np._platform.get_item_text(0) == "SNES / PVSnesLib"
	print("I18N_DIALOG_NEW create=", np._create_button.text, " build=", np._build_button.text)
	np.queue_free()

	var GameBuildDialog = preload("res://addons/retro_engine/game_build_dialog.gd")
	var gb = GameBuildDialog.new()
	get_root().add_child(gb)
	await process_frame
	ok = ok and gb._mode.get_item_text(0) == "Jogo nativo → SNES"
	ok = ok and gb._generate_button.text == "Gerar projeto"
	ok = ok and gb._build_button.text == "Gerar + Compilar ROM"
	ok = ok and gb._splash.text == "Fade in/out do logo Godot"
	print("I18N_DIALOG_GAME mode=", gb._mode.get_item_text(0), " generate=", gb._generate_button.text)
	gb.queue_free()

	var SDKDownloader = preload("res://addons/retro_engine/sdk_downloader.gd")
	var sd = SDKDownloader.new()
	get_root().add_child(sd)
	await process_frame
	ok = ok and sd.title == "Download de SDKs — GitHub"
	print("I18N_DIALOG_SDK title=", sd.title)
	sd.queue_free()
	await process_frame

	TranslationServer.set_locale("en")
	ok = ok and I18n.current_language() == "en"
	ok = ok and I18n.t("top.new_project") == "New Project..."
	ok = ok and I18n.t("native.other_nodes") == "Other nodes"
	ok = ok and I18n.t("checks.platform_mismatch", {
		"selected": "Mega Drive", "project": "my_game", "project_platform": "SNES",
	}).contains("Platform selector")
	print("I18N en new_project=", I18n.t("top.new_project"), " mode=", I18n.t("game_build.mode_snes_md"))

	TranslationServer.set_locale("fr_FR")
	var fr_lang := I18n.current_language()
	var fr_cancel := I18n.t("common.cancel")
	ok = ok and fr_lang == "fr" and fr_cancel != "Cancel"
	TranslationServer.set_locale("xx_YY")
	ok = ok and I18n.current_language() == "en" and I18n.t("common.cancel") == "Cancel"
	print("I18N fallback fr_FR=", fr_lang, " cancel=", fr_cancel, " xx=", I18n.current_language())

	TranslationServer.set_locale(previous)
	print("I18N_TEST ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
