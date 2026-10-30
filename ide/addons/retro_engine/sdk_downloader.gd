@tool
extends Window
## Downloads and installs the official PVSnesLib and SGDK releases from GitHub.
## SDKs are installed under user://sdks, so the IDE remains usable on machines
## where neither SDK nor any project is preinstalled.

signal installed(platform: String, path: String)
signal status(text: String)

const WindowControls = preload("res://addons/retro_engine/window_controls.gd")
const I18n = preload("res://addons/retro_engine/i18n.gd")

const PVS_VERSION := "4.6.0"
const PVS_DEST := "user://sdks/pvsneslib-4.6.0"

const SGDK_VERSION := "2.11"
const SGDK_URL := "https://github.com/Stephane-D/SGDK/archive/refs/tags/v2.11.zip"
const SGDK_ARCHIVE := "sgdk-2.11-source.zip"
const SGDK_DEST := "user://sdks/sgdk-2.11"

var _pvs_status: Label
var _md_status: Label
var _progress: ProgressBar
var _log: RichTextLabel
var _request: HTTPRequest
var _busy := false
var _current_platform := ""

func _ready() -> void:
	title = I18n.t("sdk_downloader.title")
	size = Vector2i(780, 460)
	unresizable = false
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var heading := Label.new()
	heading.text = I18n.t("sdk_downloader.heading")
	heading.add_theme_font_size_override("font_size", 14)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	WindowControls.add_controls(head, self, true)
	var note := Label.new()
	note.text = I18n.t("sdk_downloader.note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("#9fb4d0"))
	root.add_child(note)
	root.add_child(_sdk_row(I18n.t("sdk_downloader.pvs", {"version": PVS_VERSION}), true))
	root.add_child(_sdk_row(I18n.t("sdk_downloader.sgdk", {"version": SGDK_VERSION}), false))
	_progress = ProgressBar.new()
	_progress.min_value = 0
	_progress.max_value = 100
	_progress.value = 0
	root.add_child(_progress)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.selection_enabled = true
	root.add_child(_log)
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	var folder := Button.new()
	folder.text = I18n.t("sdk_downloader.open_folder")
	folder.pressed.connect(func():
		var path := ProjectSettings.globalize_path("user://sdks")
		DirAccess.make_dir_recursive_absolute(path)
		OS.shell_open(path))
	bottom.add_child(folder)
	var close := Button.new()
	close.text = I18n.t("common.close")
	close.pressed.connect(func(): hide())
	bottom.add_child(close)
	close_requested.connect(func(): hide())
	_refresh_status()

func _sdk_row(title: String, pvs: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 160
	row.add_child(label)
	var status_label := Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("#9fb4d0"))
	row.add_child(status_label)
	var button := Button.new()
	button.text = I18n.t("sdk_downloader.download")
	button.pressed.connect(func(): _download("snes" if pvs else "megadrive"))
	row.add_child(button)
	if pvs:
		_pvs_status = status_label
	else:
		_md_status = status_label
	return row

func _refresh_status() -> void:
	var pvs_dest := ProjectSettings.globalize_path(PVS_DEST)
	var md_dest := ProjectSettings.globalize_path(SGDK_DEST)
	var pvs_root := _find_sdk_root("snes", pvs_dest)
	if pvs_root.is_empty():
		pvs_root = pvs_dest
	var md_root := _find_sdk_root("megadrive", md_dest)
	if md_root.is_empty():
		md_root = md_dest
	var pvs: Dictionary = RetroSDK.probe_snes(pvs_root)
	var md: Dictionary = RetroSDK.probe_megadrive(md_root)
	if bool(pvs.get("found", false)) and bool(pvs.get("ready", false)):
		_pvs_status.text = I18n.t("sdk_downloader.installed", {"path": pvs_root})
	else:
		_pvs_status.text = I18n.t("sdk_downloader.not_installed")
	if bool(md.get("found", false)):
		var lin: Dictionary = md.get("linux", {})
		_md_status.text = I18n.t("sdk_downloader.installed", {"path": md_root}) if bool(lin.get("available", false)) else I18n.t("sdk_downloader.resource_only")
	else:
		_md_status.text = I18n.t("sdk_downloader.not_installed")

func _download(platform: String) -> void:
	if _busy:
		_log.append_text("[color=#ffd45e]%s[/color]\n" % I18n.t("sdk_downloader.busy"))
		return
	_busy = true
	_current_platform = platform
	_progress.value = 0
	var url := SGDK_URL
	var archive := SGDK_ARCHIVE
	if platform == "snes":
		var pvs := _pvs_asset()
		url = String(pvs[0])
		archive = String(pvs[1])
	var cache := ProjectSettings.globalize_path("user://sdk_cache")
	DirAccess.make_dir_recursive_absolute(cache)
	var archive_path := cache.path_join(archive)
	if FileAccess.file_exists(archive_path):
		DirAccess.remove_absolute(archive_path)
	_log.append_text("[color=#7fd1ff]%s[/color]\n" % I18n.t("sdk_downloader.downloading", {"url": url}))
	_request = HTTPRequest.new()
	_request.download_file = archive_path
	_request.max_redirects = 16
	add_child(_request)
	_request.request_completed.connect(_on_download_complete.bind(platform, archive_path))
	var err := _request.request(url)
	if err != OK:
		_busy = false
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("sdk_downloader.could_not_start", {"err": err}))
		status.emit(I18n.t("sdk_downloader.start_failed_status"))
		return
	set_process(true)

func _process(_delta: float) -> void:
	if not _busy or _request == null:
		return
	var total := _request.get_body_size()
	var done := _request.get_downloaded_bytes()
	if total > 0:
		_progress.value = clampf(done * 100.0 / total, 0.0, 100.0)

func _on_download_complete(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray,
		platform: String, archive_path: String) -> void:
	set_process(false)
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 400:
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("sdk_downloader.download_failed", {"result": result, "code": response_code}))
		status.emit(I18n.t("sdk_downloader.download_failed_status"))
		return
	if not FileAccess.file_exists(archive_path) or FileAccess.get_size(archive_path) <= 0:
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("sdk_downloader.archive_empty"))
		return
	_log.append_text("[color=#6ee7a8]%s[/color]\n" % I18n.t("sdk_downloader.downloaded", {
		"file": archive_path.get_file(),
		"size": _size_text(FileAccess.get_size(archive_path)),
	}))
	if _request != null:
		_request.queue_free()
		_request = null
	await _install_archive(platform, archive_path)

func _pvs_asset() -> Array:
	match OS.get_name():
		"Windows":
			return ["https://github.com/alekmaul/pvsneslib/releases/download/4.6.0/pvsneslib_460_64b_windows_release.zip", "pvsneslib_4.6.0_windows.zip"]
		"macOS":
			return ["https://github.com/alekmaul/pvsneslib/releases/download/4.6.0/pvsneslib_460_64b_darwin_release.zip", "pvsneslib_4.6.0_darwin.zip"]
		_:
			return ["https://github.com/alekmaul/pvsneslib/releases/download/4.6.0/pvsneslib_460_64b_linux_release.zip", "pvsneslib_4.6.0_linux.zip"]

func _install_archive(platform: String, archive_path: String) -> void:
	var dest := ProjectSettings.globalize_path(PVS_DEST if platform == "snes" else SGDK_DEST)
	_remove_recursive(dest)
	DirAccess.make_dir_recursive_absolute(dest)
	_log.append_text("%s\n" % I18n.t("sdk_downloader.extracting", {"path": dest}))
	var ok := await _extract_zip(archive_path, dest)
	if not ok:
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("sdk_downloader.extract_failed"))
		return
	var root := _find_sdk_root(platform, dest)
	if root.is_empty():
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("sdk_downloader.layout_failed"))
		return
	if platform == "snes":
		_make_pvsneslib_executable(root)
	var probe: Dictionary = RetroSDK.probe_snes(root) if platform == "snes" else RetroSDK.probe_megadrive(root)
	if not bool(probe.get("found", false)):
		_log.append_text("[color=#ff7a7a]%s[/color]\n" % I18n.t("sdk_downloader.probe_failed", {"path": root}))
		return
	RetroSDK.configure(platform, root)
	_progress.value = 100
	_log.append_text("[color=#6ee7a8]%s[/color]\n" % I18n.t("sdk_downloader.installed_at", {"platform": I18n.platform_label(platform), "path": root}))
	if platform == "megadrive":
		var lin: Dictionary = probe.get("linux", {})
		if not bool(lin.get("available", false)):
			_log.append_text("[color=#ffd45e]%s[/color]\n" % I18n.t("sdk_downloader.resource_only_note"))
	_refresh_status()
	installed.emit(platform, root)
	status.emit(I18n.t("sdk_downloader.installed_status", {"path": root}))

func _find_sdk_root(platform: String, dest: String) -> String:
	var candidates: Array = []
	if platform == "snes":
		candidates = [dest.path_join("pvsneslib"), dest]
	else:
		candidates = [dest.path_join("SGDK-" + SGDK_VERSION), dest.path_join("sgdk" + SGDK_VERSION), dest]
	for c in candidates:
		if platform == "snes":
			if FileAccess.file_exists(c.path_join("devkitsnes/snes_rules")) and FileAccess.file_exists(c.path_join("pvsneslib/include/snes.h")):
				return c
		else:
			if FileAccess.file_exists(c.path_join("inc/genesis.h")) and FileAccess.file_exists(c.path_join("lib/libmd.a")):
				return c
	return ""

func _extract_zip(zip_path: String, dest: String) -> bool:
	var zip := ZIPReader.new()
	var err := zip.open(zip_path)
	if err != OK:
		return false
	var files := zip.get_files()
	for i in range(files.size()):
		var file := files[i]
		if file.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(dest.path_join(file))
		else:
			var out_path := dest.path_join(file)
			DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
			var data := zip.read_file(file, true)
			var f := FileAccess.open(out_path, FileAccess.WRITE)
			if f == null:
				zip.close()
				return false
			f.store_buffer(data)
			f.close()
		if i % 80 == 0:
			_progress.value = 100.0 * float(i) / float(max(1, files.size()))
			await get_tree().process_frame
	zip.close()
	return true

func _make_pvsneslib_executable(root: String) -> void:
	if OS.get_name() == "Windows":
		return
	var perm := FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER | \
		FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_EXECUTE_GROUP | FileAccess.UNIX_READ_OTHER | FileAccess.UNIX_EXECUTE_OTHER
	for sub in ["devkitsnes/bin", "devkitsnes/tools"]:
		var dir := root.path_join(sub)
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for file in d.get_files():
			FileAccess.set_unix_permissions(dir.path_join(file), perm)

func _remove_recursive(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for file in d.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub in d.get_directories():
		_remove_recursive(path.path_join(sub))
	DirAccess.remove_absolute(path)

func _size_text(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.1f MiB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%.1f KiB" % (bytes / 1024.0)
	return str(bytes) + " B"
