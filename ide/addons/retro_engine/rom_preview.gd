@tool
extends Control
## Real ROM preview for the Preview tab.
##
## The project's built ROM is executed by a libretro core (snes9x/bsnes or
## genesis_plus_gx) in a helper process. Frames are streamed back over a local
## socket, so the editor shows the actual game code that runs on the SNES/Mega
## Drive, including its real boot sequence. Pause, frame step and rewind all
## operate on emulator frames; inputs are injected as real joypad presses.

signal status(text: String)
signal state_changed(text: String)
signal log_changed()
signal pause_changed(is_paused: bool)
signal build_requested()

const HELPER := "res://addons/retro_engine/tools/libretro_preview.py"
const CORE_BASE := 46100
const MAX_LOG := 300
const RETRO_BITS_SNES := {
	"B": 0, "Y": 1, "SELECT": 2, "START": 3, "UP": 4, "DOWN": 5,
	"LEFT": 6, "RIGHT": 7, "A": 8, "X": 9, "L": 10, "R": 11,
}
const RETRO_BITS_MD := {
	"A": 1, "B": 0, "C": 8, "X": 10, "Y": 9, "Z": 11, "MODE": 2,
	"SELECT": 2, "START": 3, "UP": 4, "DOWN": 5, "LEFT": 6, "RIGHT": 7,
}

var project: RetroProject
var platform := "snes"
var rom_path := ""
var core_path := ""
var running := false
var paused := false
var frame := 0
var speed := 1.0
var pause_on_input := false
var pause_on_change := true
var audio_enabled := true
var audio_packets := 0
var audio_frames := 0
var auto_start := true
var input_enabled := true
var last_command := ""
var events: Array = []

var _server: TCPServer
var _peer: StreamPeerTCP
var _pid := -1
var _buffer := PackedByteArray()
var _screen: TextureRect
var _texture: ImageTexture
var _message: Label
var _hud: Label
var _input_map: RetroInputMap
var _pause_after_frame := -1
var _hello: Dictionary = {}
var _fps := 60.0
var _core_name := ""
var _rom_name := ""
var _frame_format := FORMAT_RGB565
var _audio_rate := 0.0
var _audio_player: AudioStreamPlayer
var _audio_generator: AudioStreamGenerator
var _audio_playback: AudioStreamGeneratorPlayback
var _have_frame := false
var _stopping := false
var _start_ms := 0
var _paused_for_hidden := false
var _paused_for_tab := false
var _watch_frames := 0
var _watch_command := ""
var _watch_sig := PackedByteArray()
var _press_frames: Dictionary = {}

const FORMAT_RGB565 := 0
const FORMAT_RGBA8 := 1

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var background := ColorRect.new()
	background.color = Color("#07090d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_screen = TextureRect.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	_hud = Label.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hud.offset_left = 8
	_hud.offset_top = 6
	_hud.offset_right = -8
	_hud.add_theme_color_override("font_color", Color("#7fd1ff"))
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_message = Label.new()
	_message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", Color("#e8f3ff"))
	_message.add_theme_font_size_override("font_size", 16)
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_message)
	_message.text = "No ROM loaded."
	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = "Master"
	add_child(_audio_player)
	set_process(true)

func _exit_tree() -> void:
	stop()

func set_project(p_project: RetroProject) -> void:
	var previous_project := project
	var previous_rom := rom_path
	var previous_core := core_path
	project = p_project
	if project != null:
		platform = project.get_platform()
		rom_path = _resolve_rom(project)
		core_path = find_core(platform)
	else:
		rom_path = ""
		core_path = ""
	var changed := previous_project != project or previous_rom != rom_path or previous_core != core_path
	if not changed:
		if not running and _pid <= 0 and auto_start and is_visible_in_tree() and project != null:
			start()
		return
	stop()
	_clear_screen()
	if project == null:
		_set_message("No project loaded.")
		return
	if rom_path.is_empty():
		_set_message("No built ROM.\nUse Build ROM to compile the real project, then Run ROM.")
		_emit_state()
		return
	if core_path.is_empty():
		_set_message("No libretro core found.\nInstall a RetroArch core: snes9x/bsnes for SNES or genesis_plus_gx for Mega Drive.")
		_emit_state()
		return
	if auto_start:
		start()

func set_platform(p_platform: String) -> void:
	if platform == p_platform:
		return
	platform = p_platform
	if project != null:
		core_path = find_core(platform)
		if running:
			stop()
			_clear_screen()
			if not core_path.is_empty() and not rom_path.is_empty() and auto_start:
				start()

func set_input_map(p_map: RetroInputMap) -> void:
	_input_map = p_map

func set_active(active: bool) -> void:
	input_enabled = active
	if not active and running and not paused:
		_paused_for_tab = true
		set_pause(true)
	elif active and running and paused and _paused_for_tab:
		_paused_for_tab = false
		set_pause(false)
	elif active and not running and auto_start and project != null and not rom_path.is_empty():
		start()

func start() -> bool:
	stop()
	if project == null:
		return false
	rom_path = _resolve_rom(project)
	core_path = find_core(platform)
	if rom_path.is_empty():
		_set_message("No built ROM.\nUse Build ROM to compile the real project.")
		return false
	if core_path.is_empty():
		_set_message("No libretro core found for %s." % platform)
		return false
	_server = null
	var port := -1
	for i in range(40):
		var candidate := CORE_BASE + i
		var server := TCPServer.new()
		if server.listen(candidate, "127.0.0.1") == OK:
			_server = server
			port = candidate
			break
	if port < 0:
		_set_message("Could not reserve a local port for the emulator.")
		_server = null
		return false
	var python := "python3" if OS.get_name() != "Windows" else "python"
	var args := [
		ProjectSettings.globalize_path(HELPER),
		"--core", core_path,
		"--rom", rom_path,
		"--port", str(port),
		"--platform", platform,
	]
	_pid = OS.create_process(python, args)
	_start_ms = Time.get_ticks_msec()
	if _pid <= 0:
		_start_ms = 0
		_set_message("Could not start the libretro host. Check python3/numpy.")
		_server.stop()
		_server = null
		return false
	_buffer.clear()
	_hello = {}
	_have_frame = false
	_frame_format = FORMAT_RGB565
	paused = false
	_press_frames.clear()
	audio_packets = 0
	audio_frames = 0
	_stop_audio()
	pause_changed.emit(false)
	_pause_after_frame = -1
	_core_name = core_path.get_file()
	_rom_name = rom_path.get_file()
	_message.text = "Starting %s ..." % _core_name
	_message.visible = true
	_hud.text = "%s | %s" % [_core_name, _rom_name]
	status.emit("Starting real ROM preview: %s" % _rom_name)
	_log("ROM start requested: %s (%s)" % [_rom_name, _core_name])
	return true

func stop() -> void:
	if _stopping:
		return
	_stopping = true
	if _peer != null:
		_send("quit\n")
		_peer.disconnect_from_host()
		_peer = null
	if _server != null:
		_server.stop()
		_server = null
	if _pid > 0:
		if OS.get_name() == "Windows":
			OS.execute("taskkill", ["/PID", str(_pid), "/F"])
		else:
			OS.execute("kill", ["-TERM", str(_pid)])
		_pid = -1
	running = false
	paused = false
	_press_frames.clear()
	_stop_audio()
	_start_ms = 0
	_stopping = false

func power_on() -> void:
	if running:
		reset()
	else:
		start()

func reset() -> void:
	if not running:
		start()
		return
	_send("reset\n")
	paused = false
	_press_frames.clear()
	_stop_audio()
	if audio_enabled:
		_start_audio()
	_pause_after_frame = -1
	_log("ROM reset")
	pause_changed.emit(false)
	_set_message("")
	_emit_state()

func set_pause(value: bool) -> void:
	if not running or paused == value:
		return
	paused = value
	_send("pause\n" if paused else "run\n")
	_log("pause ON" if paused else "resume")
	pause_changed.emit(paused)
	_update_overlay()
	_emit_state()

func toggle_pause() -> void:
	set_pause(not paused)

func step_frames(count: int = 1) -> void:
	if not running:
		return
	if not paused:
		set_pause(true)
	_send("step %d\n" % maxi(1, count))
	_log("step %d frame(s)" % maxi(1, count))

func rewind_frames(count: int = 1) -> void:
	if not running:
		return
	if not paused:
		set_pause(true)
	_send("rewind %d\n" % maxi(1, count))
	_log("rewind %d frame(s)" % maxi(1, count))

func set_speed(value: float) -> void:
	speed = clampf(value, 0.05, 4.0)
	if running:
		_send("speed %.3f\n" % speed)

func command(action_id: String) -> void:
	if not running:
		return
	var action := _input_map.get_action(action_id) if _input_map != null else {}
	var mask := _mask_for_action(action_id, action)
	if mask == 0:
		return
	last_command = action_id
	tap_mask(mask, action_id, 4, true)
	_emit_state()

func tap_mask(mask: int, label := "", frames := 4, watch := true) -> void:
	if not running or mask == 0:
		return
	_send("tap %d %d\n" % [mask, maxi(1, frames)])
	_log("input %s (mask 0x%04X)" % [label, mask])
	if watch:
		_begin_watch(label)
		if pause_on_input:
			_pause_after_frame = frame + maxi(1, frames)

func press_mask(mask: int, label := "", watch := false) -> void:
	if not running or mask == 0:
		return
	_send("press %d\n" % mask)
	_press_frames[mask] = frame
	_log("button %s down (0x%04X)" % [label, mask])
	if watch:
		_begin_watch(label)
		if pause_on_input:
			_pause_after_frame = frame + 2

func release_mask(mask: int, label := "") -> void:
	if not running or mask == 0:
		return
	var started := int(_press_frames.get(mask, frame))
	if frame - started < 2:
		# The click was shorter than an emulated frame. Hold it for two
		# frames so the game always sees the press.
		_send("tap %d 2\n" % mask)
	else:
		_send("release %d\n" % mask)
	_press_frames.erase(mask)
	_log("button %s up" % label)

func _begin_watch(label: String) -> void:
	if not pause_on_change:
		return
	_watch_frames = 180
	_watch_command = label
	_watch_sig = PackedByteArray()

func get_log_text() -> String:
	var lines := PackedStringArray()
	for entry in events:
		lines.append("[%05d] %s" % [int(entry.get("frame", 0)), String(entry.get("text", ""))])
	return "\n".join(lines)

func clear_log() -> void:
	events.clear()
	log_changed.emit()

func get_status_text() -> String:
	if project == null:
		return "No project"
	if not running:
		if rom_path.is_empty():
			return "No built ROM"
		if core_path.is_empty():
			return "No libretro core"
		return "Stopped"
	return "F%d%s" % [frame, " | PAUSED" if paused else ""]

func get_full_status_text() -> String:
	if not running:
		return get_status_text()
	var suffix := " | PAUSED" if paused else ""
	if not audio_enabled:
		suffix += " | MUTE"
	return "%s | %s | frame %d | %.2f fps%s" % [
		_core_name, _rom_name, frame, _fps, suffix]

func _process(_delta: float) -> void:
	if running:
		var visible_now := is_visible_in_tree()
		if not visible_now and not paused:
			_paused_for_hidden = true
			set_pause(true)
		elif visible_now and paused and _paused_for_hidden:
			_paused_for_hidden = false
			set_pause(false)
	if _start_ms > 0 and not running and _peer == null:
		if Time.get_ticks_msec() - _start_ms > 12000:
			_fail("The libretro host did not respond. Check python3/numpy and the core.")
			return
	if _server != null and _peer == null and _server.is_connection_available():
		_peer = _server.take_connection()
		if _peer != null:
			_peer.set_no_delay(true)
	if _peer != null:
		_peer.poll()
		if _peer.get_status() == StreamPeerTCP.STATUS_ERROR:
			_fail("The libretro host disconnected.")
			return
		var available := _peer.get_available_bytes()
		if available > 0:
			var got := _peer.get_partial_data(available)
			if int(got[0]) == OK:
				_buffer.append_array(got[1])
				_parse_buffer()
	if _pause_after_frame >= 0 and running and not paused and frame >= _pause_after_frame:
		_pause_after_frame = -1
		_log("auto-pause after input at frame %d" % frame)
		set_pause(true)

func _parse_buffer() -> void:
	while _buffer.size() >= 4:
		if _buffer.slice(0, 4).get_string_from_ascii() == "LRF1":
			if _buffer.size() < 24:
				return
			var width := _buffer.decode_u32(4)
			var height := _buffer.decode_u32(8)
			var fmt := _buffer.decode_u32(12)
			var index := _buffer.decode_u32(16)
			var size := _buffer.decode_u32(20)
			var total := 24 + size
			if _buffer.size() < total:
				return
			var payload := _buffer.slice(24, total)
			_buffer = _buffer.slice(total)
			_apply_frame(width, height, fmt, index, payload)
			continue
		if _buffer.slice(0, 4).get_string_from_ascii() == "AUD0":
			if _buffer.size() < 16:
				return
			var rate := _buffer.decode_u32(4)
			var frames := _buffer.decode_u32(8)
			var size := _buffer.decode_u32(12)
			var total := 16 + size
			if _buffer.size() < total:
				return
			var audio := _buffer.slice(16, total)
			_buffer = _buffer.slice(total)
			_on_audio(rate, frames, audio)
			continue
		var newline := _buffer.find(10)
		if newline < 0:
			if _buffer.size() > 65536:
				_buffer.clear()
			return
		var line := _buffer.slice(0, newline).get_string_from_utf8()
		_buffer = _buffer.slice(newline + 1)
		line = line.strip_edges()
		if not line.begins_with("{"):
			continue
		var parsed = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var hello: Dictionary = parsed
		if not bool(hello.get("ok", false)):
			_fail(String(hello.get("error", "The libretro host failed.")))
			return
		_hello = hello
		_fps = float(hello.get("fps", 60.0))
		_audio_rate = float(hello.get("audio_rate", 0.0))
		_core_name = String(hello.get("core", _core_name))
		_rom_name = String(hello.get("rom", _rom_name))
		running = true
		_start_ms = 0
		_have_frame = false
		_message.visible = false
		_log("ROM running: %s with %s" % [_rom_name, _core_name])
		status.emit("Real ROM preview running: %s" % _rom_name)
		if audio_enabled:
			_start_audio()
		else:
			_send("audio 0\n")
		_update_overlay()
		_emit_state()

func _apply_frame(width: int, height: int, fmt: int, index: int,
		payload: PackedByteArray) -> void:
	if width <= 0 or height <= 0 or payload.is_empty():
		return
	var expected := width * height * (2 if fmt == FORMAT_RGB565 else 4)
	if payload.size() < expected:
		return
	if payload.size() > expected:
		payload = payload.slice(0, expected)
	var image: Image
	if fmt == FORMAT_RGB565:
		image = Image.create_from_data(width, height, false, Image.FORMAT_RGB565, payload)
	else:
		image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, payload)
	if image == null:
		return
	_texture = ImageTexture.create_from_image(image)
	_screen.texture = _texture
	frame = index
	_have_frame = true
	_frame_format = fmt
	_watch_frame(image)
	_update_overlay()
	_emit_state()

func _watch_frame(image: Image) -> void:
	if _watch_frames <= 0:
		return
	var sig := _signature(image)
	_watch_frames -= 1
	if _watch_sig.is_empty():
		_watch_sig = sig
		return
	var diff := _signature_diff(_watch_sig, sig)
	if diff >= 0.18:
		_log("screen change after %s at frame %d (%.2f)" % [_watch_command, frame, diff])
		_watch_frames = 0
		_watch_sig.clear()
		if pause_on_change and not paused:
			set_pause(true)
	elif _watch_frames == 0:
		_log("no screen change after %s within 180 frames" % _watch_command)
		_watch_sig.clear()

func _signature(image: Image) -> PackedByteArray:
	var small: Image = image.duplicate()
	small.resize(32, 28, Image.INTERPOLATE_NEAREST)
	return small.get_data()

func _signature_diff(a: PackedByteArray, b: PackedByteArray) -> float:
	var count := mini(a.size(), b.size())
	if count < 4:
		return 0.0
	var total := 0
	for i in range(0, count - 3, 4):
		total += absi(int(a[i]) - int(b[i]))
		total += absi(int(a[i + 1]) - int(b[i + 1]))
		total += absi(int(a[i + 2]) - int(b[i + 2]))
	var samples := (count / 4) * 3
	return float(total) / (float(samples) * 255.0)

func set_audio_enabled(enabled: bool) -> void:
	if audio_enabled == enabled:
		return
	audio_enabled = enabled
	_send("audio %d\n" % (1 if audio_enabled else 0))
	if audio_enabled:
		_start_audio()
	else:
		_stop_audio()
	_log("audio ON" if audio_enabled else "audio OFF")
	_update_overlay()
	_emit_state()

func _start_audio() -> void:
	if not audio_enabled or _audio_player == null or _audio_rate <= 0.0:
		return
	if _audio_playback != null and _audio_generator != null and is_equal_approx(_audio_generator.mix_rate, _audio_rate):
		return
	_audio_player.stop()
	_audio_generator = AudioStreamGenerator.new()
	_audio_generator.mix_rate = _audio_rate
	_audio_generator.buffer_length = 0.25
	_audio_player.stream = _audio_generator
	_audio_player.play()
	_audio_playback = _audio_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _stop_audio() -> void:
	if _audio_player != null:
		_audio_player.stop()
		_audio_player.stream = null
	_audio_generator = null
	_audio_playback = null

func _on_audio(rate: int, frames: int, payload: PackedByteArray) -> void:
	if not audio_enabled or frames <= 0:
		return
	audio_packets += 1
	if _audio_playback == null or not is_equal_approx(_audio_rate, float(rate)):
		_audio_rate = float(rate)
		_start_audio()
	if _audio_playback == null:
		return
	var available := _audio_playback.get_frames_available()
	var count := mini(frames, available)
	if count <= 0:
		return
	var out := PackedVector2Array()
	out.resize(count)
	for i in range(count):
		var offset := i * 4
		out[i] = Vector2(
			float(payload.decode_s16(offset)) / 32768.0,
			float(payload.decode_s16(offset + 2)) / 32768.0)
	if _audio_playback.push_buffer(out):
		audio_frames += count

func _update_overlay() -> void:
	_hud.text = get_full_status_text()
	if not running:
		return
	if paused:
		_message.text = "PAUSED — frame %d\nStep / Rewind to inspect the real transition." % frame
		_message.visible = true
	else:
		_message.visible = false

func _emit_state() -> void:
	state_changed.emit(get_status_text())

func _set_message(text: String) -> void:
	_message.text = text
	_message.visible = not text.is_empty()
	_hud.text = get_status_text()

func _clear_screen() -> void:
	_screen.texture = null
	_texture = null
	_have_frame = false
	frame = 0
	_buffer.clear()
	_hud.text = ""
	_emit_state()

func _fail(text: String) -> void:
	stop()
	_clear_screen()
	_set_message(text)
	_log(text)
	status.emit(text)

func _log(text: String) -> void:
	events.append({"frame": frame, "text": text})
	while events.size() > MAX_LOG:
		events.pop_front()
	log_changed.emit()

func _send(command: String) -> void:
	if _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_peer.put_data(command.to_utf8_buffer())

func _resolve_rom(p_project: RetroProject) -> String:
	var path := p_project.get_rom_path()
	if not path.is_empty() and FileAccess.file_exists(path):
		return path
	return ""

static func find_core(p_platform: String) -> String:
	var snes := ["snes9x_libretro", "bsnes_libretro", "mesen_libretro"]
	var md := ["genesis_plus_gx_libretro", "genesis_plus_gx_wide_libretro",
		"picodrive_libretro", "blastem_libretro"]
	var names: Array = snes if p_platform == "snes" else md
	var suffixes := [".so", ".dylib", ".dll"]
	var dirs: Array = []
	var home := OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_environment("USERPROFILE")
	if not home.is_empty():
		dirs.append(home.path_join(".config/retroarch/cores"))
		dirs.append(home.path_join(".var/app/org.libretro.RetroArch/config/retroarch/cores"))
		dirs.append(home.path_join("Library/Application Support/RetroArch/cores"))
	var appdata := OS.get_environment("APPDATA")
	if not appdata.is_empty():
		dirs.append(appdata.path_join("RetroArch/cores"))
	dirs.append("/usr/lib/libretro")
	dirs.append("/usr/local/lib/libretro")
	dirs.append("/usr/lib/x86_64-linux-gnu/libretro")
	var cfg_dirs := [
		home.path_join(".config/retroarch/retroarch.cfg") if not home.is_empty() else "",
		home.path_join(".var/app/org.libretro.RetroArch/config/retroarch/retroarch.cfg") if not home.is_empty() else "",
	]
	for cfg in cfg_dirs:
		if cfg.is_empty() or not FileAccess.file_exists(cfg):
			continue
		var text := FileAccess.get_file_as_string(cfg)
		var re := RegEx.new()
		re.compile("libretro_directory\\s*=\\s*\"?([^\"\\n]+)\"?")
		var found := re.search(text)
		if found != null:
			dirs.append(found.get_string(1).strip_edges())
	for name in names:
		for suffix in suffixes:
			for dir in dirs:
				if String(dir).is_empty():
					continue
				var path := String(dir).path_join(String(name) + String(suffix))
				if FileAccess.file_exists(path):
					return path
	return ""

func _mask_for_action(action_id: String, action: Dictionary) -> int:
	var names: Array = []
	if not action.is_empty():
		names = action.get("snes" if platform == "snes" else "md", [])
	var mask := 0
	for name in names:
		mask |= _bit_for_button(String(name))
	if mask == 0:
		mask = _fallback_mask(action_id)
	return mask

func _bit_for_button(name: String) -> int:
	var key := name.strip_edges().to_upper()
	if platform == "megadrive":
		return int(RETRO_BITS_MD.get(key, 0))
	return int(RETRO_BITS_SNES.get(key, 0))

func _fallback_mask(action_id: String) -> int:
	var id := action_id.to_lower()
	if id.contains("start"):
		return 1 << 3
	if id.contains("select") or id.contains("mode"):
		return 1 << 2
	if id.contains("left"):
		return 1 << 6
	if id.contains("right"):
		return 1 << 7
	if id.contains("up") or id.contains("jump"):
		return 1 << 4
	if id.contains("down") or id.contains("crouch"):
		return 1 << 5
	if id.contains("attack_a"):
		return 1 << (1 if platform == "megadrive" else 0)
	if id.contains("attack_b"):
		return 1 << (0 if platform == "megadrive" else 1)
	if id.contains("attack_c"):
		return 1 << (8 if platform == "megadrive" else 9)
	if id.contains("guard"):
		return 1 << (9 if platform == "megadrive" else 10)
	if id.contains("throw"):
		return 1 << 11
	return 0

func _press_action(action_id: String) -> void:
	var action := _input_map.get_action(action_id) if _input_map != null else {}
	var mask := _mask_for_action(action_id, action)
	if mask == 0:
		return
	last_command = action_id
	_log("input %s (mask 0x%04X)" % [action_id, mask])
	_send("press %d\n" % mask)
	if pause_on_input:
		_pause_after_frame = frame + 2

func _release_action(action_id: String) -> void:
	var action := _input_map.get_action(action_id) if _input_map != null else {}
	var mask := _mask_for_action(action_id, action)
	if mask != 0:
		_send("release %d\n" % mask)

func _action_for_key(key: String) -> String:
	if _input_map == null:
		return ""
	var wanted := _norm_key(key)
	for action in _input_map.get_actions():
		for k in action.get("keys", []):
			if _norm_key(String(k)) == wanted:
				return String(action.get("id", ""))
	return ""

func _action_for_pad(pad_name: String) -> String:
	if _input_map == null:
		return ""
	var wanted := _norm_key(pad_name)
	for action in _input_map.get_actions():
		for g in action.get("gamepad", []):
			if _norm_key(String(g)) == wanted:
				return String(action.get("id", ""))
	return ""

func _norm_key(value: String) -> String:
	return value.strip_edges().replace(" ", "").replace("_", "").to_upper()

func _find_start_id() -> String:
	if _input_map == null:
		return ""
	for action in _input_map.get_actions():
		var id := String(action.get("id", ""))
		if id.to_lower().contains("start"):
			return id
	return "start"

func _joy_name(index: int) -> String:
	match index:
		JOY_BUTTON_A: return "JOY_A"
		JOY_BUTTON_B: return "JOY_B"
		JOY_BUTTON_X: return "JOY_X"
		JOY_BUTTON_Y: return "JOY_Y"
		JOY_BUTTON_BACK: return "JOY_BACK"
		JOY_BUTTON_START: return "JOY_START"
		JOY_BUTTON_LEFT_SHOULDER: return "JOY_L"
		JOY_BUTTON_RIGHT_SHOULDER: return "JOY_R"
		JOY_BUTTON_DPAD_UP: return "JOY_UP"
		JOY_BUTTON_DPAD_DOWN: return "JOY_DOWN"
		JOY_BUTTON_DPAD_LEFT: return "JOY_LEFT"
		JOY_BUTTON_DPAD_RIGHT: return "JOY_RIGHT"
	return ""

func _joy_bit(index: int) -> int:
	if platform == "megadrive":
		match index:
			JOY_BUTTON_A: return 1 << 1
			JOY_BUTTON_B: return 1 << 0
			JOY_BUTTON_X: return 1 << 10
			JOY_BUTTON_Y: return 1 << 9
			JOY_BUTTON_START: return 1 << 3
			JOY_BUTTON_BACK: return 1 << 2
			JOY_BUTTON_LEFT_SHOULDER: return 1 << 9
			JOY_BUTTON_RIGHT_SHOULDER: return 1 << 11
			JOY_BUTTON_DPAD_UP: return 1 << 4
			JOY_BUTTON_DPAD_DOWN: return 1 << 5
			JOY_BUTTON_DPAD_LEFT: return 1 << 6
			JOY_BUTTON_DPAD_RIGHT: return 1 << 7
	else:
		match index:
			JOY_BUTTON_A: return 1 << 8
			JOY_BUTTON_B: return 1 << 0
			JOY_BUTTON_X: return 1 << 9
			JOY_BUTTON_Y: return 1 << 1
			JOY_BUTTON_START: return 1 << 3
			JOY_BUTTON_BACK: return 1 << 2
			JOY_BUTTON_LEFT_SHOULDER: return 1 << 10
			JOY_BUTTON_RIGHT_SHOULDER: return 1 << 11
			JOY_BUTTON_DPAD_UP: return 1 << 4
			JOY_BUTTON_DPAD_DOWN: return 1 << 5
			JOY_BUTTON_DPAD_LEFT: return 1 << 6
			JOY_BUTTON_DPAD_RIGHT: return 1 << 7
	return 0

func _is_hold_action(action_id: String, action: Dictionary) -> bool:
	if bool(action.get("hold", false)) or String(action.get("type", "button")) == "hold":
		return true
	var id := action_id.to_lower()
	var state := String(action.get("state", "")).to_lower()
	for token in ["left", "right", "up", "down", "jump", "crouch", "guard", "walk"]:
		if id.contains(token) or state.contains(token):
			return true
	return false

func _input(event: InputEvent) -> void:
	if not input_enabled or not is_visible_in_tree():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.echo:
			return
		var code := ke.keycode if ke.keycode != KEY_NONE else ke.physical_keycode
		var key := OS.get_keycode_string(code)
		var normalized := _norm_key(key)
		if ke.pressed and normalized == "P":
			toggle_pause()
			get_viewport().set_input_as_handled()
			return
		if ke.pressed and normalized == "F8":
			step_frames(1)
			get_viewport().set_input_as_handled()
			return
		if ke.pressed and normalized == "F9":
			step_frames(10)
			get_viewport().set_input_as_handled()
			return
		var action := _action_for_key(key)
		if action.is_empty() and ke.pressed and normalized in ["ENTER", "KPENTER", "SPACE"]:
			action = _find_start_id()
		if action.is_empty():
			return
		var action_data := _input_map.get_action(action) if _input_map != null else {}
		if _is_hold_action(action, action_data):
			if ke.pressed:
				_press_action(action)
			else:
				_release_action(action)
		elif ke.pressed:
			command(action)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		var pad_name := _joy_name(jb.button_index)
		var action := _action_for_pad(pad_name)
		if action.is_empty() and jb.button_index == JOY_BUTTON_START and jb.pressed:
			action = _find_start_id()
		if action.is_empty():
			var mask := _joy_bit(jb.button_index)
			if mask != 0:
				if jb.pressed:
					_send("press %d\n" % mask)
				else:
					_send("release %d\n" % mask)
			return
		var action_data := _input_map.get_action(action) if _input_map != null else {}
		if _is_hold_action(action, action_data):
			if jb.pressed:
				_press_action(action)
			else:
				_release_action(action)
		elif jb.pressed:
			command(action)
		get_viewport().set_input_as_handled()
