/**************************************************************************/
/*  retro_s2_sprites.cpp - Sonic 2 disassembly sprite sheet extraction    */
/**************************************************************************/

#include "retro_s2_sprites.h"

#include "retro_graphics.h"
#include "retro_util.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/image.h"
#include "core/io/json.h"
#include "core/math/math_funcs.h"
#include "core/templates/hash_map.h"

#include <cstring>

namespace {

static PackedByteArray _read_packed(const String &p_path) {
	PackedByteArray out;
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::READ);
	if (f.is_null()) {
		return out;
	}
	const int64_t len = f->get_length();
	if (len <= 0) {
		return out;
	}
	out.resize(len);
	f->get_buffer(out.ptrw(), len);
	return out;
}

static String _strip_comment(const String &p_line) {
	const int pos = p_line.find(";");
	return pos >= 0 ? p_line.substr(0, pos) : p_line;
}

static int _parse_num(const String &p_text) {
	String t = p_text.strip_edges();
	bool negative = false;
	if (t.begins_with("-")) {
		negative = true;
		t = t.substr(1).strip_edges();
	} else if (t.begins_with("+")) {
		t = t.substr(1).strip_edges();
	}
	int value = 0;
	if (t.begins_with("$")) {
		value = t.substr(1).hex_to_int();
	} else if (t.begins_with("0x") || t.begins_with("0X")) {
		value = t.substr(2).hex_to_int();
	} else if (t.begins_with("%")) {
		for (int i = 1; i < t.length(); i++) {
			value = (value << 1) | (t[i] == '1' ? 1 : 0);
		}
	} else {
		value = t.to_int();
	}
	return negative ? -value : value;
}

static bool _is_label(const String &p_text) {
	if (p_text.is_empty()) {
		return false;
	}
	for (int i = 0; i < p_text.length(); i++) {
		const char32_t c = p_text[i];
		const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
				(c >= '0' && c <= '9') || c == '_' || c == '.';
		if (!ok) {
			return false;
		}
	}
	return true;
}

struct NemBitReader {
	const uint8_t *data = nullptr;
	int size = 0;
	int pos = 0;
	uint16_t field = 0;
	int bits = 0;

	int read_byte() {
		return pos < size ? data[pos++] : 0;
	}

	int pop_bit() {
		if (bits == 0) {
			field = uint16_t(read_byte() << 8);
			field |= uint16_t(read_byte());
			bits = 16;
		}
		const int bit = (field >> 15) & 1;
		field <<= 1;
		bits--;
		return bit;
	}

	int pop_bits(int p_count) {
		int value = 0;
		for (int i = 0; i < p_count; i++) {
			value = (value << 1) | pop_bit();
		}
		return value;
	}
};

struct NemCode {
	int value = -1;
	int length = 0;
	int bits = 0;
};

static bool _decompress_nemesis(const PackedByteArray &p_input, PackedByteArray &r_output) {
	if (p_input.size() < 4) {
		return false;
	}
	NemBitReader reader;
	reader.data = p_input.ptr();
	reader.size = p_input.size();

	const int header = (reader.read_byte() << 8) | reader.read_byte();
	const bool xor_mode = (header & 0x8000) != 0;
	const int total_tiles = header & 0x7FFF;
	if (total_tiles <= 0 || total_tiles > 0x8000) {
		return false;
	}

	NemCode table[256];
	int value = 0;
	for (;;) {
		const int byte = reader.read_byte();
		if (byte == 0xFF) {
			break;
		}
		if (byte & 0x80) {
			value = byte & 0x0F;
			continue;
		}
		const int length = ((byte >> 4) & 7) + 1;
		const int code_bits = byte & 0x0F;
		if (code_bits <= 0 || code_bits > 8) {
			return false;
		}
		const int code = reader.read_byte();
		const int index = code << (8 - code_bits);
		if (index < 0 || index >= 256) {
			return false;
		}
		table[index].value = value;
		table[index].length = length;
		table[index].bits = code_bits;
	}

	const int64_t total_nybbles = int64_t(total_tiles) * 64;
	int64_t remaining = total_nybbles;
	uint32_t output_buffer = 0;
	uint32_t previous_output = 0;
	int nybbles_done = 0;

	r_output.resize(int(total_tiles) * 32);
	uint8_t *out = r_output.ptrw();
	int out_pos = 0;

	while (remaining > 0) {
		const NemCode *entry = nullptr;
		int code = 0;
		int bits = 0;
		for (;;) {
			if (bits == 8) {
				return false;
			}
			code = (code << 1) | reader.pop_bit();
			bits++;
			if (bits == 6 && code == 0x3F) {
				entry = nullptr;
				break;
			}
			const NemCode &candidate = table[code << (8 - bits)];
			if (candidate.length != 0 && candidate.bits == bits) {
				entry = &candidate;
				break;
			}
		}

		int run_length;
		int nybble;
		if (entry != nullptr) {
			run_length = entry->length;
			nybble = entry->value;
		} else {
			run_length = reader.pop_bits(3) + 1;
			nybble = reader.pop_bits(4);
		}
		if (run_length <= 0 || run_length > remaining) {
			return false;
		}
		for (int i = 0; i < run_length; i++) {
			output_buffer = (output_buffer << 4) | uint32_t(nybble & 0x0F);
			nybbles_done++;
			if ((nybbles_done & 7) == 0) {
				const uint32_t final_output = output_buffer ^ (xor_mode ? previous_output : 0);
				if (out_pos + 4 > r_output.size()) {
					return false;
				}
				out[out_pos++] = uint8_t((final_output >> 24) & 0xFF);
				out[out_pos++] = uint8_t((final_output >> 16) & 0xFF);
				out[out_pos++] = uint8_t((final_output >> 8) & 0xFF);
				out[out_pos++] = uint8_t(final_output & 0xFF);
				previous_output = final_output;
			}
		}
		remaining -= run_length;
	}
	return out_pos == r_output.size();
}

struct KosBitReader {
	const uint8_t *data = nullptr;
	int size = 0;
	int pos = 0;
	uint16_t field = 0;
	int bits = 0;

	int read_byte() {
		return pos < size ? data[pos++] : 0;
	}

	int pop_bit() {
		if (bits == 0) {
			const int low = read_byte();
			const int high = read_byte();
			field = uint16_t(low | (high << 8));
			bits = 16;
		}
		const int bit = field & 1;
		field >>= 1;
		bits--;
		return bit;
	}
};

static bool _decompress_kosinski(const PackedByteArray &p_input, PackedByteArray &r_output) {
	if (p_input.is_empty()) {
		return false;
	}
	KosBitReader reader;
	reader.data = p_input.ptr();
	reader.size = p_input.size();

	for (;;) {
		if (reader.pop_bit()) {
			const int byte = reader.read_byte();
			r_output.push_back(uint8_t(byte));
		} else {
			int offset = 0;
			int count = 0;
			if (reader.pop_bit()) {
				const int low = reader.read_byte();
				const int high = reader.read_byte();
				offset = 0x2000 - (((high & 0xF8) << 5) | low);
				count = high & 7;
				if (count != 0) {
					count += 2;
				} else {
					count = reader.read_byte() + 1;
					if (count == 1) {
						break;
					}
					if (count == 2) {
						continue;
					}
				}
			} else {
				count = 2;
				if (reader.pop_bit()) {
					count += 2;
				}
				if (reader.pop_bit()) {
					count += 1;
				}
				offset = 0x100 - reader.read_byte();
			}
			const int source = r_output.size() - offset;
			if (source < 0 || count <= 0) {
				return false;
			}
			for (int i = 0; i < count; i++) {
				const int at = source + i;
				r_output.push_back(at >= 0 && at < r_output.size() ? r_output[at] : uint8_t(0));
			}
		}
		if (r_output.size() > 16 * 1024 * 1024) {
			return false;
		}
	}
	return true;
}

struct MapPiece {
	int x = 0;
	int y = 0;
	int w = 0;
	int h = 0;
	int tile = 0;
	int xflip = 0;
	int yflip = 0;
	int pal = 0;
	int pri = 0;
};

struct MapFrame {
	String name;
	Vector<MapPiece> pieces;
	int min_x = 0;
	int min_y = 0;
	int max_x = 8;
	int max_y = 8;
};

struct DplcEntry {
	int count = 0;
	int tile = 0;
};

static Array _table_labels(const PackedStringArray &p_lines) {
	Array labels;
	const String token = "mappingsTableEntry.w";
	for (int i = 0; i < p_lines.size(); i++) {
		const String line = _strip_comment(p_lines[i]).strip_edges();
		const int at = line.find(token);
		if (at < 0) {
			continue;
		}
		String label = line.substr(at + token.length()).strip_edges();
		if (!label.is_empty()) {
			labels.push_back(label);
		}
	}
	return labels;
}

static Vector<MapFrame> _parse_mappings(const String &p_path) {
	Vector<MapFrame> definitions;
	HashMap<String, int> index_by_label;
	String current;
	String text = RetroUtil::read_text(p_path);
	const PackedStringArray lines = text.split("\n");
	const Array table = _table_labels(lines);

	for (int i = 0; i < lines.size(); i++) {
		const String line = _strip_comment(lines[i]).strip_edges();
		if (line.is_empty()) {
			continue;
		}
		const int colon = line.find(":");
		if (colon > 0) {
			const String label = line.substr(0, colon).strip_edges();
			if (_is_label(label)) {
				if (label.ends_with("_End")) {
					current = String();
				} else {
					current = label;
					if (!index_by_label.has(label)) {
						index_by_label[label] = definitions.size();
						MapFrame frame;
						frame.name = label;
						definitions.push_back(frame);
					}
				}
			}
		}
		if (!line.begins_with("spritePiece") || current.is_empty() || !index_by_label.has(current)) {
			continue;
		}
		const String args_text = line.substr(String("spritePiece").length());
		PackedStringArray args = args_text.split(",");
		if (args.size() < 9) {
			// A few mapping files separate the fields with spaces.
			args = args_text.split(" ", false);
		}
		if (args.size() < 9) {
			continue;
		}
		MapPiece piece;
		piece.x = _parse_num(args[0]);
		piece.y = _parse_num(args[1]);
		piece.w = _parse_num(args[2]);
		piece.h = _parse_num(args[3]);
		piece.tile = _parse_num(args[4]);
		piece.xflip = _parse_num(args[5]);
		piece.yflip = _parse_num(args[6]);
		piece.pal = _parse_num(args[7]);
		piece.pri = _parse_num(args[8]);
		if (piece.w <= 0 || piece.h <= 0) {
			continue;
		}
		MapFrame &frame = definitions.write[index_by_label[current]];
		if (piece.x < frame.min_x) {
			frame.min_x = piece.x;
		}
		if (piece.y < frame.min_y) {
			frame.min_y = piece.y;
		}
		if (piece.x + piece.w * 8 > frame.max_x) {
			frame.max_x = piece.x + piece.w * 8;
		}
		if (piece.y + piece.h * 8 > frame.max_y) {
			frame.max_y = piece.y + piece.h * 8;
		}
		frame.pieces.push_back(piece);
	}

	Vector<MapFrame> out;
	if (table.is_empty()) {
		return definitions;
	}
	for (int i = 0; i < table.size(); i++) {
		const String label = String(table[i]);
		if (index_by_label.has(label)) {
			out.push_back(definitions[index_by_label[label]]);
		}
	}
	return out;
}

static Vector<Vector<DplcEntry>> _parse_dplc(const String &p_path) {
	Vector<Vector<DplcEntry>> definitions;
	HashMap<String, int> index_by_label;
	String current;
	String text = RetroUtil::read_text(p_path);
	const PackedStringArray lines = text.split("\n");
	const Array table = _table_labels(lines);

	for (int i = 0; i < lines.size(); i++) {
		const String line = _strip_comment(lines[i]).strip_edges();
		if (line.is_empty()) {
			continue;
		}
		const int colon = line.find(":");
		if (colon > 0) {
			const String label = line.substr(0, colon).strip_edges();
			if (_is_label(label)) {
				if (label.ends_with("_End")) {
					current = String();
				} else {
					current = label;
					if (!index_by_label.has(label)) {
						index_by_label[label] = definitions.size();
						definitions.push_back(Vector<DplcEntry>());
					}
				}
			}
		}
		if (!line.begins_with("dplcEntry") || current.is_empty() || !index_by_label.has(current)) {
			continue;
		}
		const String args_text = line.substr(String("dplcEntry").length());
		PackedStringArray args = args_text.split(",");
		if (args.size() < 2) {
			args = args_text.split(" ", false);
		}
		if (args.size() < 2) {
			continue;
		}
		DplcEntry entry;
		entry.count = _parse_num(args[0]);
		entry.tile = _parse_num(args[1]);
		if (entry.count <= 0) {
			continue;
		}
		definitions.write[index_by_label[current]].push_back(entry);
	}

	Vector<Vector<DplcEntry>> out;
	if (table.is_empty()) {
		for (int i = 0; i < definitions.size(); i++) {
			out.push_back(definitions[i]);
		}
		return out;
	}
	for (int i = 0; i < table.size(); i++) {
		const String label = String(table[i]);
		if (index_by_label.has(label)) {
			out.push_back(definitions[index_by_label[label]]);
		}
	}
	return out;
}

static PackedColorArray _load_palette(const String &p_root, const Array &p_palettes) {
	PackedColorArray out;
	for (int i = 0; i < p_palettes.size(); i++) {
		const Dictionary entry = p_palettes[i];
		const String rel = String(entry.get("path", "")).strip_edges();
		if (rel.is_empty()) {
			continue;
		}
		const String full = RetroUtil::join(p_root, rel);
		const PackedByteArray bytes = _read_packed(full);
		if (bytes.is_empty()) {
			continue;
		}
		const PackedColorArray part = RetroGraphics::decode_palette(bytes, true);
		for (int c = 0; c < part.size() && out.size() < 64; c++) {
			out.push_back(part[c]);
		}
	}
	if (out.is_empty()) {
		// Some Flex objects omit the palette even though they use the shared
		// Sonic/Tails palette loaded by the game.
		const String fallback = RetroUtil::join(p_root, "art/palettes/SonicAndTails.bin");
		if (FileAccess::exists(fallback)) {
			const PackedByteArray bytes = _read_packed(fallback);
			if (!bytes.is_empty()) {
				const PackedColorArray part = RetroGraphics::decode_palette(bytes, true);
				for (int c = 0; c < part.size() && out.size() < 64; c++) {
					out.push_back(part[c]);
				}
			}
		}
	}
	if (out.is_empty()) {
		for (int i = 0; i < 16; i++) {
			const int v = i * 17;
			out.push_back(Color::from_rgba8(v, v, v));
		}
	}
	while (out.size() < 16) {
		out.push_back(Color(0, 0, 0));
	}
	return out;
}

static bool _decompress_art(const String &p_path, const String &p_compression, int p_offset, PackedByteArray &r_out) {
	PackedByteArray raw = _read_packed(p_path);
	if (raw.is_empty()) {
		return false;
	}
	if (p_offset > 0 && p_offset < raw.size()) {
		raw = raw.slice(p_offset);
	}
	const String compression = p_compression.to_lower();
	if (compression == "uncompressed" || compression.is_empty()) {
		r_out = raw;
		return true;
	}
	if (compression == "nemesis") {
		return _decompress_nemesis(raw, r_out);
	}
	if (compression == "kosinski") {
		return _decompress_kosinski(raw, r_out);
	}
	return false;
}

static String _slugify(const String &p_text) {
	String out;
	for (int i = 0; i < p_text.length(); i++) {
		const char32_t c = p_text[i];
		if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) {
			out += String::chr(c);
		} else if (c >= 'A' && c <= 'Z') {
			out += String::chr(c + 32);
		} else if (c == ' ' || c == '-' || c == '_' || c == '/') {
			out += "_";
		}
	}
	while (out.contains("__")) {
		out = out.replace("__", "_");
	}
	out = out.strip_edges().trim_prefix("_").trim_suffix("_");
	return out.is_empty() ? "sprite" : out;
}

static Array _make_rect(int p_x, int p_y, int p_w, int p_h) {
	Array rect;
	rect.push_back(p_x);
	rect.push_back(p_y);
	rect.push_back(p_w);
	rect.push_back(p_h);
	return rect;
}

} // namespace

bool RetroS2Sprites::extract(const String &p_root, Array &r_resources, Array &r_warnings) {
	const String manifest_path = RetroUtil::join(p_root, "sonic2.flex.json");
	if (!FileAccess::exists(manifest_path)) {
		return false;
	}
	bool json_ok = false;
	const Dictionary manifest = RetroUtil::parse_json_file(manifest_path, &json_ok);
	if (!json_ok) {
		r_warnings.push_back("Sonic 2: could not parse sonic2.flex.json.");
		return true;
	}

	const String output_dir = RetroUtil::join(p_root, ".retro/generated/sprites");
	DirAccess::make_dir_recursive_absolute(output_dir);

	HashMap<String, bool> used_slugs;
	const Array objects = manifest.get("objects", Array());
	for (int group_index = 0; group_index < objects.size(); group_index++) {
		const Dictionary group = objects[group_index];
		const String group_name = String(group.get("name", "")).strip_edges();
		const Array children = group.get("children", Array());
		for (int child_index = 0; child_index < children.size(); child_index++) {
			const Dictionary child = children[child_index];
			const String sprite_name = String(child.get("name", "")).strip_edges();
			const Dictionary art = child.get("art", Dictionary());
			const String art_rel = String(art.get("path", "")).strip_edges();
			const String compression = String(art.get("compression", "")).strip_edges();
			const int art_offset = int(art.get("offset", 0));
			const Dictionary mappings = child.get("mappings", Dictionary());
			const String map_rel = String(mappings.get("path", "")).strip_edges();
			if (art_rel.is_empty() || art_rel == "elArt" || map_rel.is_empty()) {
				continue;
			}
			const String art_path = RetroUtil::join(p_root, art_rel);
			const String map_path = RetroUtil::join(p_root, map_rel);
			if (!FileAccess::exists(art_path) || !FileAccess::exists(map_path)) {
				continue;
			}

			Vector<MapFrame> frames = _parse_mappings(map_path);
			if (frames.is_empty()) {
				continue;
			}
			if (frames.size() > 512) {
				frames.resize(512);
			}

			Vector<Vector<DplcEntry>> dplc_frames;
			const Dictionary dplcs = child.get("dplcs", Dictionary());
			const bool has_dplc = bool(dplcs.get("enabled", false));
			const String dplc_rel = String(dplcs.get("path", "")).strip_edges();
			if (has_dplc && !dplc_rel.is_empty()) {
				const String dplc_path = RetroUtil::join(p_root, dplc_rel);
				if (FileAccess::exists(dplc_path)) {
					dplc_frames = _parse_dplc(dplc_path);
				}
			}

			PackedByteArray art_data;
			if (!_decompress_art(art_path, compression, art_offset, art_data)) {
				continue;
			}
			if (art_data.size() < 32) {
				continue;
			}
			const int art_tiles = art_data.size() / 32;
			PackedColorArray palette = _load_palette(p_root, child.get("palettes", Array()));
			int max_pal = 0;
			for (int f = 0; f < frames.size(); f++) {
				for (int p = 0; p < frames[f].pieces.size(); p++) {
					if (frames[f].pieces[p].pal > max_pal) {
						max_pal = frames[f].pieces[p].pal;
					}
				}
			}
			const int palette_lines = CLAMP(max_pal + 1, 1, 4);
			const int palette_size = palette_lines * 16;
			while (palette.size() < palette_size) {
				palette.push_back(Color(0, 0, 0));
			}
			if (palette.size() > palette_size) {
				palette.resize(palette_size);
			}
			palette.write[0] = Color(1, 0, 1);

			const Ref<Image> art_indexed = RetroGraphics::decode_tiles_indexed(art_data, 16, 4, 8, true);
			if (art_indexed.is_null()) {
				continue;
			}

			int cell_w = 8;
			int cell_h = 8;
			for (int f = 0; f < frames.size(); f++) {
				const int w = frames[f].max_x - frames[f].min_x;
				const int h = frames[f].max_y - frames[f].min_y;
				cell_w = MAX(cell_w, w);
				cell_h = MAX(cell_h, h);
			}
			cell_w = MIN(cell_w, 512);
			cell_h = MIN(cell_h, 512);
			if (cell_w <= 0 || cell_h <= 0) {
				continue;
			}

			const int count = frames.size();
			const int columns = MIN(16, MAX(1, int(Math::ceil(Math::sqrt(double(count))))));
			const int rows = (count + columns - 1) / columns;
			const int sheet_w = columns * (cell_w + 1);
			const int sheet_h = rows * (cell_h + 1);
			if (sheet_w <= 0 || sheet_h <= 0 || sheet_w > 4096 || sheet_h > 4096) {
				continue;
			}

			Vector<uint8_t> pixels;
			pixels.resize(sheet_w * sheet_h * 4);
			uint8_t *pixel_data = pixels.ptrw();
			memset(pixel_data, 0, pixels.size());

			Array frame_list;
			for (int f = 0; f < count; f++) {
				const MapFrame &frame = frames[f];
				const int frame_w = MAX(1, frame.max_x - frame.min_x);
				const int frame_h = MAX(1, frame.max_y - frame.min_y);
				const int col = f % columns;
				const int row = f / columns;
				const int base_x = col * (cell_w + 1);
				const int base_y = row * (cell_h + 1);

				Vector<int> loaded_tiles;
				if (!dplc_frames.is_empty() && f < dplc_frames.size()) {
					const Vector<DplcEntry> &entries = dplc_frames[f];
					for (int e = 0; e < entries.size(); e++) {
						for (int n = 0; n < entries[e].count; n++) {
							loaded_tiles.push_back(entries[e].tile + n);
						}
					}
				}

				for (int p = 0; p < frame.pieces.size(); p++) {
					const MapPiece &piece = frame.pieces[p];
					for (int cy = 0; cy < piece.h; cy++) {
						for (int cx = 0; cx < piece.w; cx++) {
							const int loaded_index = piece.tile + cx * piece.h + cy;
							int art_tile = loaded_index;
							if (!loaded_tiles.is_empty()) {
								if (loaded_index < 0 || loaded_index >= loaded_tiles.size()) {
									continue;
								}
								art_tile = loaded_tiles[loaded_index];
							}
							if (art_tile < 0 || art_tile >= art_tiles) {
								continue;
							}
							const int art_x = (art_tile % 16) * 8;
							const int art_y = (art_tile / 16) * 8;
							const int tile_x = piece.xflip ? (piece.w - 1 - cx) : cx;
							const int tile_y = piece.yflip ? (piece.h - 1 - cy) : cy;
							for (int py = 0; py < 8; py++) {
								for (int px = 0; px < 8; px++) {
									const int sx = art_x + (piece.xflip ? (7 - px) : px);
									const int sy = art_y + (piece.yflip ? (7 - py) : py);
									const int index = int(art_indexed->get_pixel(sx, sy).r * 255.0 + 0.5);
									if (index <= 0) {
										continue;
									}
									int palette_index = piece.pal * 16 + index;
									if (palette_index >= palette.size()) {
										palette_index = index;
									}
									if (palette_index <= 0 || palette_index >= palette.size()) {
										continue;
									}
									const Color color = palette[palette_index];
									const int dx = base_x + (piece.x - frame.min_x) + tile_x * 8 + px;
									const int dy = base_y + (piece.y - frame.min_y) + tile_y * 8 + py;
									if (dx < 0 || dy < 0 || dx >= sheet_w || dy >= sheet_h) {
										continue;
									}
									const int off = (dy * sheet_w + dx) * 4;
									pixel_data[off + 0] = uint8_t(CLAMP(color.r * 255.0, 0, 255));
									pixel_data[off + 1] = uint8_t(CLAMP(color.g * 255.0, 0, 255));
									pixel_data[off + 2] = uint8_t(CLAMP(color.b * 255.0, 0, 255));
									pixel_data[off + 3] = 255;
								}
							}
						}
					}

			}
				Dictionary frame_info;
				frame_info["name"] = frame.name;
				frame_info["rect"] = _make_rect(base_x, base_y, frame_w, frame_h);
				frame_info["duration"] = 6;
				frame_list.push_back(frame_info);
			}

			Ref<Image> sheet = Image::create_from_data(sheet_w, sheet_h, false, Image::FORMAT_RGBA8, pixels);
			if (sheet.is_null()) {
				continue;
			}
			String slug = _slugify(group_name + "_" + sprite_name);
			if (slug.is_empty()) {
				slug = "sprite";
			}
			if (used_slugs.has(slug)) {
				int suffix = 2;
				while (used_slugs.has(slug + "_" + itos(suffix))) {
					suffix++;
				}
				slug += "_" + itos(suffix);
			}
			used_slugs[slug] = true;

			const String output_rel = ".retro/generated/sprites/" + slug + ".png";
			const String output_path = RetroUtil::join(p_root, output_rel);
			if (RetroGraphics::save_indexed_png(output_path, sheet, palette) != OK) {
				continue;
			}

			Dictionary resource;
			resource["id"] = "sonic2_" + slug;
			resource["rel_path"] = output_rel;
			resource["path"] = output_path;
			resource["name"] = "S2 " + group_name + " - " + sprite_name;
			resource["ext"] = "png";
			resource["kind"] = "sonic2_sprite";
			resource["editor"] = "sprite";
			resource["editable"] = false;
			resource["size"] = int64_t(FileAccess::get_size(output_path));
			resource["note"] = "Generated from " + art_rel + " + " + map_rel + (has_dplc ? " + DPLC." : ".");
			resource["group"] = "sprite";
			resource["width"] = sheet_w;
			resource["height"] = sheet_h;
			resource["palette_size"] = palette.size();
			resource["has_alpha"] = true;
			resource["frame_w"] = cell_w;
			resource["frame_h"] = cell_h;
			resource["frames_count"] = frame_list.size();
			resource["frames"] = frame_list;
			resource["bpp"] = 4;
			resource["tile_size"] = 8;
			resource["source_art"] = art_rel;
			resource["source_mappings"] = map_rel;
			resource["source_group"] = group_name;
			r_resources.push_back(resource);
		}
	}
	return true;
}
