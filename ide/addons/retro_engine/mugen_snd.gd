@tool
extends RefCounted
## Native MUGEN SND v1 reader. Each entry is a WAV payload; playback uses an
## AudioStreamWAV so character sounds can be auditioned inside the IDE.

var path: String = ""
var entries: Array = []
var _by_key: Dictionary = {}

func load_file(p_path: String) -> bool:
	path = p_path
	entries.clear()
	_by_key.clear()
	var f := FileAccess.open(p_path, FileAccess.READ)
	if f == null:
		return false
	var data := f.get_buffer(f.get_length())
	f.close()
	if data.size() < 24 or data.slice(0, 11).get_string_from_ascii() != "ElecbyteSnd":
		return false
	var count := _u32(data, 16)
	var offset := _u32(data, 20)
	var seen: Dictionary = {}
	for i in range(count):
		if offset == 0 or offset >= data.size() or seen.has(offset):
			break
		seen[offset] = true
		var next := _u32(data, offset)
		var size := _u32(data, offset + 4)
		var group := _u32(data, offset + 8)
		var number := _u32(data, offset + 12)
		var entry: Dictionary = {
			"group": group, "number": number, "size": size,
			"offset": offset + 16, "stream": null,
		}
		if size > 0 and offset + 16 + size <= data.size():
			var wav := data.slice(offset + 16, offset + 16 + size)
			entry["stream"] = _decode_wav(wav)
		entries.append(entry)
		_by_key["%d,%d" % [group, number]] = entry
		offset = next
	return not entries.is_empty()

func entry_count() -> int:
	return entries.size()

func find(group: int, number: int) -> Dictionary:
	return _by_key.get("%d,%d" % [group, number], {})

func stream_for(group: int, number: int) -> AudioStreamWAV:
	var e := find(group, number)
	if e.is_empty():
		return null
	return e.get("stream", null)

func _decode_wav(wav: PackedByteArray) -> AudioStreamWAV:
	if wav.size() < 44:
		return null
	if wav.slice(0, 4).get_string_from_ascii() != "RIFF" or wav.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null
	var pos := 12
	var channels := 1
	var rate := 22050
	var bits := 8
	var pcm := PackedByteArray()
	while pos + 8 <= wav.size():
		var chunk := wav.slice(pos, pos + 4).get_string_from_ascii()
		var size := _u32(wav, pos + 4)
		var body := pos + 8
		if chunk == "fmt " and body + 16 <= wav.size():
			channels = _u16(wav, body + 2)
			rate = _u32(wav, body + 4)
			bits = _u16(wav, body + 14)
		elif chunk == "data":
			var end := mini(body + size, wav.size())
			pcm = wav.slice(body, end)
			break
		pos = body + size + (size & 1)
	if pcm.is_empty():
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS if bits >= 16 else AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = clampi(rate, 8000, 192000)
	stream.stereo = channels == 2
	stream.data = pcm
	return stream

static func _u16(d: PackedByteArray, o: int) -> int:
	if o + 1 >= d.size():
		return 0
	return int(d[o]) | (int(d[o + 1]) << 8)

static func _u32(d: PackedByteArray, o: int) -> int:
	if o + 3 >= d.size():
		return 0
	return int(d[o]) | (int(d[o + 1]) << 8) | (int(d[o + 2]) << 16) | (int(d[o + 3]) << 24)
