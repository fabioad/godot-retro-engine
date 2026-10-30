@tool
extends Control
## Embedded OS terminal with VSCode-style tabs. Terminal emulation and PTY
## handling come from the bundled GDTerm extension (MIT).

const TERM_SCENE := "res://addons/gdterm/terminal/term.tscn"
const I18n = preload("res://addons/retro_engine/i18n.gd")
const CONFIG_PATH := "user://terminal.cfg"
const DEFAULT_FONT_SIZE := 18
const MIN_FONT_SIZE := 12
const MAX_FONT_SIZE := 48
const FONT_STEP := 2

var _tabs: TabBar
var _menu: MenuButton
var _font_menu: MenuButton
var _content: PanelContainer
var _empty: Label
var _terms: Array = []
var _current := -1
var _switching := false
var _colors: Dictionary = {}
var _real_shell := ""
var _shell_wrapper := ""
var _font_size := DEFAULT_FONT_SIZE
var _config_path := CONFIG_PATH

func _ready() -> void:
	_colors = _palette()
	if OS.has_environment("RETRO_TERMINAL_CONFIG"):
		_config_path = OS.get_environment("RETRO_TERMINAL_CONFIG")
	_load_font_size()
	var env_size := OS.get_environment("RETRO_TERMINAL_FONT_SIZE")
	if env_size.is_valid_int():
		_font_size = clampi(int(env_size), MIN_FONT_SIZE, MAX_FONT_SIZE)
	set_process_input(true)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	var header_panel := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = _colors["surface"]
	header_style.border_width_bottom = 1
	header_style.border_color = _colors["border"]
	header_style.content_margin_left = 8
	header_style.content_margin_right = 8
	header_style.content_margin_top = 2
	header_style.content_margin_bottom = 0
	header_panel.add_theme_stylebox_override("panel", header_style)
	root.add_child(header_panel)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header_panel.add_child(header)
	_tabs = TabBar.new()
	_tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tabs.clip_tabs = false
	_tabs.tab_changed.connect(_on_tab_changed)
	_apply_tab_theme()
	header.add_child(_tabs)
	# VSCode-style: the new-tab button sits right after the last tab.
	var plus := Button.new()
	plus.text = "+"
	plus.tooltip_text = I18n.t("terminal.new_tip")
	plus.custom_minimum_size.x = 32
	plus.pressed.connect(_add_terminal)
	_style_button(plus, true)
	header.add_child(plus)
	var minus := Button.new()
	minus.text = "−"
	minus.tooltip_text = I18n.t("terminal.close_tip")
	minus.custom_minimum_size.x = 32
	minus.pressed.connect(_close_current)
	_style_button(minus)
	header.add_child(minus)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_menu = MenuButton.new()
	_menu.text = I18n.t("terminal.menu")
	_menu.tooltip_text = I18n.t("terminal.menu_tip")
	_menu.get_popup().id_pressed.connect(_on_menu_id)
	_style_button(_menu)
	_style_popup(_menu.get_popup())
	header.add_child(_menu)
	_font_menu = MenuButton.new()
	_font_menu.text = "Aa"
	_font_menu.tooltip_text = I18n.t("terminal.font_tip")
	_font_menu.get_popup().id_pressed.connect(_on_font_menu_id)
	_style_button(_font_menu)
	_style_popup(_font_menu.get_popup())
	header.add_child(_font_menu)
	_rebuild_font_menu()
	_content = PanelContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = _colors["bg"]
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	_content.add_theme_stylebox_override("panel", style)
	root.add_child(_content)
	_empty = Label.new()
	_empty.text = I18n.t("terminal.empty")
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.add_theme_color_override("font_color", _colors["muted"])
	_empty.add_theme_font_size_override("font_size", 18)
	_content.add_child(_empty)
	visibility_changed.connect(_on_visibility_changed)

func _load_font_size() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_config_path) == OK:
		_font_size = clampi(int(cfg.get_value("terminal", "font_size", DEFAULT_FONT_SIZE)), MIN_FONT_SIZE, MAX_FONT_SIZE)

func _save_font_size() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_config_path)
	cfg.set_value("terminal", "font_size", _font_size)
	cfg.save(_config_path)

func _rebuild_font_menu() -> void:
	var popup := _font_menu.get_popup()
	popup.clear()
	popup.add_item(I18n.t("terminal.increase"), 2000)
	popup.add_item(I18n.t("terminal.decrease"), 2001)
	popup.add_item(I18n.t("terminal.reset"), 2002)
	popup.add_separator()
	popup.add_item(I18n.t("terminal.current", {"size": _font_size}), -1)
	popup.set_item_disabled(popup.item_count - 1, true)
	popup.set_item_disabled(0, _font_size >= MAX_FONT_SIZE)
	popup.set_item_disabled(1, _font_size <= MIN_FONT_SIZE)

func _on_font_menu_id(id: int) -> void:
	match id:
		2000:
			_change_font_size(FONT_STEP)
		2001:
			_change_font_size(-FONT_STEP)
		2002:
			_set_font_size(DEFAULT_FONT_SIZE)

func _change_font_size(delta: int) -> void:
	_set_font_size(_font_size + delta)

func _set_font_size(value: int) -> void:
	var clamped := clampi(value, MIN_FONT_SIZE, MAX_FONT_SIZE)
	if clamped == _font_size:
		_rebuild_font_menu()
		return
	_font_size = clamped
	_apply_font_size()
	_refresh_tab_names()
	_rebuild_menu()
	_rebuild_font_menu()
	_save_font_size()

func _apply_font_size() -> void:
	for term in _terms:
		if not is_instance_valid(term):
			continue
		var gd = term.get_node_or_null("GDTerm")
		if gd != null:
			gd.set("font_size", _font_size)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if not (key.ctrl_pressed or key.meta_pressed):
		return
	var handled := true
	match key.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_change_font_size(FONT_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_change_font_size(-FONT_STEP)
		KEY_0, KEY_KP_0:
			_set_font_size(DEFAULT_FONT_SIZE)
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()

func _palette() -> Dictionary:
	# OpenCode dark theme palette (default "opencode" theme).
	return {
		"bg": Color("#0a0a0a"),
		"bg_dark": Color("#000000"),
		"surface": Color("#161616"),
		"selection": Color("#1e1e1e"),
		"fg": Color("#e0e0e0"),
		"muted": Color("#8a8a8a"),
		"border": Color("#2a2a2a"),
		"primary": Color("#5c9cf5"),
		"secondary": Color("#5c9cf5"),
		"accent": Color("#9d7cd8"),
		"red": Color("#e06c75"),
		"orange": Color("#f5a742"),
		"green": Color("#7fd88f"),
		"cyan": Color("#56b6c2"),
		"yellow": Color("#e5c07b"),
	}

func _flat_style(bg: Color, border: Color, margins: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = margins
	style.content_margin_right = margins
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _style_button(button: Button, accent: bool = false) -> void:
	var normal := _flat_style(Color(0, 0, 0, 0), _colors["border"], 8)
	var hover := _flat_style(_colors["selection"], _colors["border"], 8)
	var pressed := _flat_style(_colors["surface"], _colors["primary"], 8)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", _colors["primary"] if accent else _colors["fg"])
	button.add_theme_color_override("font_hover_color", _colors["primary"] if accent else Color("#ffffff"))
	button.add_theme_color_override("font_pressed_color", _colors["primary"])
	button.add_theme_font_size_override("font_size", 16)

func _style_popup(popup: PopupMenu) -> void:
	var panel := _flat_style(_colors["surface"], _colors["border"], 8)
	panel.corner_radius_top_left = 8
	panel.corner_radius_top_right = 8
	panel.corner_radius_bottom_left = 8
	panel.corner_radius_bottom_right = 8
	var hover := _flat_style(_colors["selection"], _colors["primary"], 8)
	popup.add_theme_stylebox_override("panel", panel)
	popup.add_theme_stylebox_override("hover", hover)
	popup.add_theme_color_override("font_color", _colors["fg"])
	popup.add_theme_color_override("font_hover_color", Color("#ffffff"))
	popup.add_theme_color_override("font_separator_color", _colors["muted"])

func _apply_tab_theme() -> void:
	var selected := StyleBoxFlat.new()
	selected.bg_color = _colors["surface"]
	selected.border_width_bottom = 2
	selected.border_color = _colors["primary"]
	selected.content_margin_left = 14
	selected.content_margin_right = 14
	selected.content_margin_top = 4
	selected.content_margin_bottom = 4
	var unselected := StyleBoxFlat.new()
	unselected.bg_color = _colors["bg"]
	unselected.content_margin_left = 14
	unselected.content_margin_right = 14
	unselected.content_margin_top = 4
	unselected.content_margin_bottom = 4
	var hovered := unselected.duplicate()
	hovered.bg_color = _colors["selection"]
	_tabs.add_theme_stylebox_override("tab_selected", selected)
	_tabs.add_theme_stylebox_override("tab_unselected", unselected)
	_tabs.add_theme_stylebox_override("tab_hovered", hovered)
	_tabs.add_theme_color_override("font_selected_color", Color("#ffffff"))
	_tabs.add_theme_color_override("font_unselected_color", _colors["muted"])
	_tabs.add_theme_color_override("font_hovered_color", _colors["fg"])
	_tabs.add_theme_font_size_override("font_size", 16)

func ensure_terminal() -> void:
	if _terms.is_empty():
		_add_terminal()
	elif _current >= 0 and _current < _terms.size():
		_start_terminal(_terms[_current])
		_focus_terminal(_terms[_current])

func _on_visibility_changed() -> void:
	if visible:
		ensure_terminal()

func _add_terminal() -> void:
	if not ClassDB.class_exists("GDTerm"):
		_show_error(I18n.t("terminal.no_extension"))
		return
	if not FileAccess.file_exists(TERM_SCENE):
		_show_error(I18n.t("terminal.no_scene", {"path": TERM_SCENE}))
		return
	_empty.visible = false
	var term = load(TERM_SCENE).instantiate()
	_content.add_child(term)
	term.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	term.size_flags_vertical = Control.SIZE_EXPAND_FILL
	term.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	term.visible = false
	term.close.connect(_close_terminal.bind(term))
	term.new_above.connect(_add_terminal)
	term.new_below.connect(_add_terminal)
	term.new_left.connect(_add_terminal)
	term.new_right.connect(_add_terminal)
	_apply_terminal_theme(term)
	_terms.append(term)
	var index := _terms.size() - 1
	_tabs.add_tab(I18n.t("terminal.name", {"n": index + 1}))
	_refresh_tab_names()
	_select_terminal(index)
	_rebuild_menu()

func _apply_terminal_theme(term: Control) -> void:
	var gd := term.get_node_or_null("GDTerm")
	if gd == null:
		return
	var colors := {
		"background": _colors["bg"],
		"foreground": _colors["fg"],
		"black": _colors["bg_dark"],
		"red": _colors["red"],
		"green": _colors["green"],
		"yellow": _colors["yellow"],
		"blue": _colors["secondary"],
		"magenta": _colors["accent"],
		"cyan": _colors["cyan"],
		"white": _colors["fg"],
		"bright_black": _colors["muted"],
		"bright_red": Color("#fd7e87"),
		"bright_green": Color("#96f7a7"),
		"bright_yellow": _colors["primary"],
		"bright_blue": Color("#82b4fb"),
		"bright_magenta": Color("#b38ff4"),
		"bright_cyan": Color("#68d0dd"),
		"bright_white": Color("#ffffff"),
	}
	for key in colors:
		gd.set(key, colors[key])
	term.apply_theme()
	if Engine.is_editor_hint():
		term.apply_font_setting(null, _font_size)
		gd.set("font_size", _font_size)
	var bar := term.get_node_or_null("scrollbar")
	if bar != null:
		bar.custom_minimum_size.x = 14
		var scroll_bg := StyleBoxFlat.new()
		scroll_bg.bg_color = _colors["bg"]
		var grabber := StyleBoxFlat.new()
		grabber.bg_color = _colors["border"]
		grabber.corner_radius_top_left = 4
		grabber.corner_radius_top_right = 4
		grabber.corner_radius_bottom_left = 4
		grabber.corner_radius_bottom_right = 4
		var grabber_hover := grabber.duplicate()
		grabber_hover.bg_color = _colors["muted"]
		bar.add_theme_stylebox_override("scroll", scroll_bg)
		bar.add_theme_stylebox_override("grabber", grabber)
		bar.add_theme_stylebox_override("grabber_highlight", grabber_hover)
		bar.add_theme_stylebox_override("grabber_pressed", grabber_hover)

func _prepare_shell_environment() -> void:
	# GDTerm's Linux/macOS PTY hardcodes TERM=ansi. OpenCode and other TUI
	# programs then fall back to a reduced color/feature set, so route the shell
	# through a tiny wrapper that advertises a modern terminal before exec.
	if OS.get_name() == "Windows":
		return
	if _shell_wrapper.is_empty():
		_real_shell = OS.get_environment("SHELL")
		if _real_shell.is_empty() or _real_shell.ends_with("terminal_shell.sh") or not FileAccess.file_exists(_real_shell):
			_real_shell = "/bin/bash"
		_shell_wrapper = ProjectSettings.globalize_path("user://terminal_shell.sh")
		var f := FileAccess.open(_shell_wrapper, FileAccess.WRITE)
		if f == null:
			_shell_wrapper = ""
			return
		f.store_line("#!/bin/sh")
		f.store_line("export TERM=xterm-256color")
		f.store_line("export COLORTERM=truecolor")
		f.store_line("exec " + _shell_quote(_real_shell) + " \"$@\"")
		f.close()
		var perm := FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER | \
			FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_EXECUTE_GROUP | FileAccess.UNIX_READ_OTHER | FileAccess.UNIX_EXECUTE_OTHER
		FileAccess.set_unix_permissions(_shell_wrapper, perm)
	if not _shell_wrapper.is_empty():
		OS.set_environment("SHELL", _shell_wrapper)

func _shell_quote(value: String) -> String:
	return "'" + value.replace("'", "'\\''") + "'"

func _start_terminal(term: Control) -> void:
	if term == null or not is_instance_valid(term) or term.has_meta("started"):
		return
	if not is_visible_in_tree() or not term.is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(term) or term.has_meta("started"):
		return
	_prepare_shell_environment()
	term.set_active(true)
	# Prevent the terminal from restarting every time tabs are shown/hidden.
	term.active = false
	term.set_meta("started", true)

func _select_terminal(index: int) -> void:
	if index < 0 or index >= _terms.size() or _switching:
		return
	_switching = true
	_current = index
	for i in range(_terms.size()):
		_terms[i].visible = (i == index)
	_tabs.current_tab = index
	_switching = false
	_start_terminal(_terms[index])
	_focus_terminal(_terms[index])
	_rebuild_menu()

func _focus_terminal(term: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(term) or not term.visible or not is_visible_in_tree():
		return
	var gd = term.get_node_or_null("GDTerm")
	if gd != null and gd.has_method("grab_focus"):
		gd.grab_focus()

func _on_tab_changed(index: int) -> void:
	if not _switching:
		_select_terminal(index)

func _close_current() -> void:
	if _current >= 0 and _current < _terms.size():
		_close_terminal(_terms[_current])

func _close_terminal(term: Control) -> void:
	var index := _terms.find(term)
	if index < 0:
		return
	var was_current := index == _current
	var gd := term.get_node_or_null("GDTerm")
	if gd != null and gd.has_method("stop"):
		gd.stop()
	_terms.remove_at(index)
	_tabs.remove_tab(index)
	term.queue_free()
	_refresh_tab_names()
	if _terms.is_empty():
		_current = -1
		_empty.visible = true
	else:
		var next_index := mini(index, _terms.size() - 1)
		if not was_current:
			next_index = index if index < _current else _current - 1
		_current = -1
		_select_terminal(clampi(next_index, 0, _terms.size() - 1))
	_rebuild_menu()

func close_all() -> void:
	_switching = true
	for term in _terms.duplicate():
		var gd = term.get_node_or_null("GDTerm")
		if gd != null and gd.has_method("stop"):
			gd.stop()
		term.queue_free()
	_terms.clear()
	_tabs.clear_tabs()
	_current = -1
	_empty.visible = true
	_switching = false

func _refresh_tab_names() -> void:
	for i in range(_tabs.tab_count):
		_tabs.set_tab_title(i, I18n.t("terminal.name", {"n": i + 1}))
		_tabs.set_tab_tooltip(i, I18n.t("terminal.theme_info", {"size": _font_size}))

func _rebuild_menu() -> void:
	var popup := _menu.get_popup()
	popup.clear()
	popup.add_item(I18n.t("terminal.new"), 1000)
	popup.add_item(I18n.t("terminal.close_current"), 1001)
	popup.add_separator(I18n.t("terminal.separator"))
	for i in range(_terms.size()):
		popup.add_item(I18n.t("terminal.name", {"n": i + 1}), i)
		popup.set_item_checked(popup.item_count - 1, i == _current)
	popup.add_separator()
	popup.add_item(I18n.t("terminal.theme_info", {"size": _font_size}), -1)
	popup.set_item_disabled(popup.item_count - 1, true)

func _on_menu_id(id: int) -> void:
	if id == 1000:
		_add_terminal()
	elif id == 1001:
		_close_current()
	elif id >= 0 and id < _terms.size():
		_select_terminal(id)

func _show_error(text: String) -> void:
	_empty.text = text
	_empty.visible = true
