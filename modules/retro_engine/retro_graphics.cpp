/**************************************************************************/
/*  retro_graphics.cpp                                                    */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_graphics.h"

#include "retro_util.h"

#include "core/io/compression.h"
#include "core/io/file_access.h"
#include "core/templates/hash_map.h"

#include <algorithm>
#include <cmath>

static int _nearest_color(const Color &p_c, const PackedColorArray &p_palette, int p_start = 0) {
	int best = p_start;
	double best_d = 1e30;
	for (int i = p_start; i < p_palette.size(); i++) {
		const Color &c = p_palette[i];
		const double dr = (c.r - p_c.r) * 0.299;
		const double dg = (c.g - p_c.g) * 0.587;
		const double db = (c.b - p_c.b) * 0.114;
		const double d = dr * dr + dg * dg + db * db;
		if (d < best_d) {
			best_d = d;
			best = i;
		}
	}
	return best;
}

static Color _snes_color(uint16_t p_word) {
	const int r = p_word & 0x1F;
	const int g = (p_word >> 5) & 0x1F;
	const int b = (p_word >> 10) & 0x1F;
	return Color::from_rgba8((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2));
}

static uint16_t _to_snes_color(const Color &p_color) {
	const int r = CLAMP(int(std::round(p_color.r * 31.0)), 0, 31);
	const int g = CLAMP(int(std::round(p_color.g * 31.0)), 0, 31);
	const int b = CLAMP(int(std::round(p_color.b * 31.0)), 0, 31);
	return uint16_t(r | (g << 5) | (b << 10));
}

static Color _md_color(uint16_t p_word) {
	const int r = (p_word >> 1) & 0x7;
	const int g = (p_word >> 5) & 0x7;
	const int b = (p_word >> 9) & 0x7;
	return Color::from_rgba8((r << 5) | (r << 2) | (r >> 1), (g << 5) | (g << 2) | (g >> 1), (b << 5) | (b << 2) | (b >> 1));
}

static uint16_t _to_md_color(const Color &p_color) {
	const int r = CLAMP(int(std::round(p_color.r * 7.0)), 0, 7);
	const int g = CLAMP(int(std::round(p_color.g * 7.0)), 0, 7);
	const int b = CLAMP(int(std::round(p_color.b * 7.0)), 0, 7);
	return uint16_t((r << 1) | (g << 5) | (b << 9));
}

static uint32_t _crc32(const uint8_t *p_data, int p_len) {
	static uint32_t table[256];
	static bool init = false;
	if (!init) {
		for (uint32_t i = 0; i < 256; i++) {
			uint32_t c = i;
			for (int k = 0; k < 8; k++) {
				c = (c & 1) ? (0xEDB88320U ^ (c >> 1)) : (c >> 1);
			}
			table[i] = c;
		}
		init = true;
	}
	uint32_t c = 0xFFFFFFFFU;
	for (int i = 0; i < p_len; i++) {
		c = table[(c ^ p_data[i]) & 0xFF] ^ (c >> 8);
	}
	return c ^ 0xFFFFFFFFU;
}

static void _put_be32(Vector<uint8_t> &r_out, uint32_t p_v) {
	r_out.push_back(uint8_t((p_v >> 24) & 0xFF));
	r_out.push_back(uint8_t((p_v >> 16) & 0xFF));
	r_out.push_back(uint8_t((p_v >> 8) & 0xFF));
	r_out.push_back(uint8_t(p_v & 0xFF));
}

static void _png_chunk(Vector<uint8_t> &r_png, const char *p_type, const Vector<uint8_t> &p_data) {
	_put_be32(r_png, p_data.size());
	const int start = r_png.size();
	for (int i = 0; i < 4; i++) {
		r_png.push_back(uint8_t(p_type[i]));
	}
	for (int i = 0; i < p_data.size(); i++) {
		r_png.push_back(p_data[i]);
	}
	_put_be32(r_png, _crc32(r_png.ptr() + start, 4 + p_data.size()));
}

void RetroGraphics::_bind_methods() {
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("decode_palette", "data", "megadrive", "count"), &RetroGraphics::decode_palette, DEFVAL(false), DEFVAL(0));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("encode_palette", "colors", "megadrive"), &RetroGraphics::encode_palette, DEFVAL(false));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("decode_tiles", "data", "tiles_x", "bpp", "palette", "tile_size", "megadrive"), &RetroGraphics::decode_tiles, DEFVAL(8), DEFVAL(false));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("decode_tiles_indexed", "data", "tiles_x", "bpp", "tile_size", "megadrive"), &RetroGraphics::decode_tiles_indexed, DEFVAL(8), DEFVAL(false));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("encode_tiles", "image", "bpp", "palette", "tile_size", "megadrive"), &RetroGraphics::encode_tiles, DEFVAL(8), DEFVAL(false));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("encode_tiles_indexed", "indices", "bpp", "tile_size", "megadrive"), &RetroGraphics::encode_tiles_indexed, DEFVAL(8), DEFVAL(false));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("decode_tilemap", "data", "megadrive"), &RetroGraphics::decode_tilemap, DEFVAL(false));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("encode_tilemap", "entries", "megadrive"), &RetroGraphics::encode_tilemap, DEFVAL(false));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("render_tilemap", "map", "tiles", "map_w", "map_h", "tile_size", "palette", "megadrive", "column_major"), &RetroGraphics::render_tilemap, DEFVAL(false), DEFVAL(false));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("render_tilemap_indexed", "map", "indices", "map_w", "map_h", "tile_size", "palette", "megadrive", "column_major", "colors_per_palette"), &RetroGraphics::render_tilemap_indexed, DEFVAL(false), DEFVAL(false), DEFVAL(16));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("indices_from_image", "image", "palette", "transparent"), &RetroGraphics::indices_from_image, DEFVAL(true));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("image_from_indices", "indices", "width", "height", "palette"), &RetroGraphics::image_from_indices);
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("read_png_palette", "path"), &RetroGraphics::read_png_palette);
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("save_indexed_png", "path", "image", "palette"), &RetroGraphics::save_indexed_png);
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("extract_palette", "image", "max_colors", "reserve_transparent"), &RetroGraphics::extract_palette, DEFVAL(true));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("quantize", "image", "max_colors", "transparent"), &RetroGraphics::quantize, DEFVAL(true));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("map_to_palette", "image", "palette", "transparent"), &RetroGraphics::map_to_palette, DEFVAL(true));
	ClassDB::bind_static_method("RetroGraphics", D_METHOD("analyze_image", "image"), &RetroGraphics::analyze_image);
}

PackedColorArray RetroGraphics::decode_palette(const PackedByteArray &p_data, bool p_megadrive, int p_count) {
	PackedColorArray out;
	int count = p_count;
	if (count <= 0) {
		count = p_data.size() / 2;
	}
	for (int i = 0; i < count; i++) {
		if ((i * 2 + 1) < p_data.size()) {
			const int b0 = p_data[i * 2];
			const int b1 = p_data[i * 2 + 1];
			const uint16_t word = p_megadrive ? uint16_t((b0 << 8) | b1) : uint16_t(b0 | (b1 << 8));
			out.push_back(p_megadrive ? _md_color(word) : _snes_color(word));
		} else {
			out.push_back(Color(0, 0, 0));
		}
	}
	return out;
}

PackedByteArray RetroGraphics::encode_palette(const PackedColorArray &p_colors, bool p_megadrive) {
	PackedByteArray out;
	out.resize(p_colors.size() * 2);
	uint8_t *w = out.ptrw();
	for (int i = 0; i < p_colors.size(); i++) {
		const uint16_t word = p_megadrive ? _to_md_color(p_colors[i]) : _to_snes_color(p_colors[i]);
		if (p_megadrive) {
			w[i * 2] = uint8_t(word >> 8);
			w[i * 2 + 1] = uint8_t(word & 0xFF);
		} else {
			w[i * 2] = uint8_t(word & 0xFF);
			w[i * 2 + 1] = uint8_t(word >> 8);
		}
	}
	return out;
}

Ref<Image> RetroGraphics::decode_tiles(const PackedByteArray &p_data, int p_tiles_x, int p_bpp,
		const PackedColorArray &p_palette, int p_tile_size, bool p_megadrive) {
	const int bytes_per_tile = (p_bpp == 8) ? 64 : (p_tile_size * p_tile_size * p_bpp) / 8;
	if (bytes_per_tile <= 0 || p_tiles_x <= 0 || p_data.is_empty()) {
		return Ref<Image>();
	}
	const int tile_count = p_data.size() / bytes_per_tile;
	const int tiles_y = (tile_count + p_tiles_x - 1) / p_tiles_x;
	const int width = p_tiles_x * p_tile_size;
	const int height = MAX(1, tiles_y) * p_tile_size;
	Ref<Image> img = Image::create_empty(width, height, false, Image::FORMAT_RGBA8);
	img->fill(Color(0, 0, 0, 0));

	const uint8_t *r = p_data.ptr();
	for (int t = 0; t < tile_count; t++) {
		const int tx = (t % p_tiles_x) * p_tile_size;
		const int ty = (t / p_tiles_x) * p_tile_size;
		const uint8_t *tile = r + t * bytes_per_tile;
		for (int y = 0; y < p_tile_size; y++) {
			for (int x = 0; x < p_tile_size; x++) {
				int idx = 0;
				if (p_bpp == 8) {
					idx = tile[y * 8 + x];
				} else if (p_megadrive) {
					// Genesis: packed nibbles, two pixels per byte (low nibble first).
					const int row_bytes = (p_tile_size * p_bpp) / 8;
					const int byte_off = y * row_bytes + (x / 2);
					idx = (tile[byte_off] >> ((x & 1) ? 0 : 4)) & 0x0F;
				} else {
					// SNES: planes 0/1 first, then 2/3 for 4bpp.
					const int row_bytes = p_bpp / 2;
					for (int p = 0; p < p_bpp; p++) {
						const int plane_pair = p / 2;
						const int byte_off = plane_pair * 8 * row_bytes + y * row_bytes + (p % 2);
						const int bit = (tile[byte_off] >> (7 - x)) & 1;
						idx |= bit << p;
					}
				}
				if (idx == 0) {
					continue;
				}
				Color c = (idx < p_palette.size()) ? p_palette[idx] : Color(1, 0, 1);
				c.a = 1.0;
				img->set_pixel(tx + x, ty + y, c);
			}
		}
	}
	return img;
}

Ref<Image> RetroGraphics::decode_tiles_indexed(const PackedByteArray &p_data, int p_tiles_x, int p_bpp,
		int p_tile_size, bool p_megadrive) {
	const int bytes_per_tile = (p_bpp == 8) ? 64 : (p_tile_size * p_tile_size * p_bpp) / 8;
	if (bytes_per_tile <= 0 || p_tiles_x <= 0 || p_data.is_empty()) {
		return Ref<Image>();
	}
	const int tile_count = p_data.size() / bytes_per_tile;
	const int tiles_y = (tile_count + p_tiles_x - 1) / p_tiles_x;
	Ref<Image> img = Image::create_empty(p_tiles_x * p_tile_size, MAX(1, tiles_y) * p_tile_size, false, Image::FORMAT_R8);
	img->fill(Color(0, 0, 0, 1));
	const uint8_t *r = p_data.ptr();
	for (int t = 0; t < tile_count; t++) {
		const int tx = (t % p_tiles_x) * p_tile_size;
		const int ty = (t / p_tiles_x) * p_tile_size;
		const uint8_t *tile = r + t * bytes_per_tile;
		for (int y = 0; y < p_tile_size; y++) {
			for (int x = 0; x < p_tile_size; x++) {
				int idx = 0;
				if (p_bpp == 8) {
					idx = tile[y * 8 + x];
				} else if (p_megadrive) {
					const int row_bytes = (p_tile_size * p_bpp) / 8;
					const int byte_off = y * row_bytes + (x / 2);
					idx = (tile[byte_off] >> ((x & 1) ? 0 : 4)) & 0x0F;
				} else {
					const int row_bytes = p_bpp / 2;
					for (int p = 0; p < p_bpp; p++) {
						const int plane_pair = p / 2;
						const int byte_off = plane_pair * 8 * row_bytes + y * row_bytes + (p % 2);
						idx |= ((tile[byte_off] >> (7 - x)) & 1) << p;
					}
				}
				// R8 stores the raw palette index; 0 is transparent.
				img->set_pixel(tx + x, ty + y, Color::from_rgba8(idx, idx, idx));
			}
		}
	}
	return img;
}

PackedByteArray RetroGraphics::encode_tiles_indexed(const Ref<Image> &p_indices, int p_bpp,
		int p_tile_size, bool p_megadrive) {
	PackedByteArray out;
	if (p_indices.is_null()) {
		return out;
	}
	Ref<Image> img = p_indices->duplicate();
	if (img->get_format() != Image::FORMAT_R8) {
		img->convert(Image::FORMAT_R8);
	}
	const int tiles_x = (img->get_width() + p_tile_size - 1) / p_tile_size;
	const int tiles_y = (img->get_height() + p_tile_size - 1) / p_tile_size;
	const int bytes_per_tile = (p_bpp == 8) ? 64 : (p_tile_size * p_tile_size * p_bpp) / 8;
	out.resize(tiles_x * tiles_y * bytes_per_tile);
	out.fill(0);
	uint8_t *w = out.ptrw();
	for (int ty = 0; ty < tiles_y; ty++) {
		for (int tx = 0; tx < tiles_x; tx++) {
			const int t = ty * tiles_x + tx;
			uint8_t *tile = w + t * bytes_per_tile;
			for (int y = 0; y < p_tile_size; y++) {
				for (int x = 0; x < p_tile_size; x++) {
					const int idx = CLAMP(int(img->get_pixel(tx * p_tile_size + x, ty * p_tile_size + y).r * 255.0 + 0.5), 0, (1 << p_bpp) - 1);
					if (p_bpp == 8) {
						tile[y * 8 + x] = uint8_t(idx);
					} else if (p_megadrive) {
						const int row_bytes = (p_tile_size * p_bpp) / 8;
						tile[y * row_bytes + (x / 2)] |= uint8_t((idx & 0x0F) << ((x & 1) ? 0 : 4));
					} else {
						const int row_bytes = p_bpp / 2;
						for (int p = 0; p < p_bpp; p++) {
							const int plane_pair = p / 2;
							const int byte_off = plane_pair * 8 * row_bytes + y * row_bytes + (p % 2);
							tile[byte_off] |= uint8_t(((idx >> p) & 1) << (7 - x));
						}
					}
				}
			}
		}
	}
	return out;
}

PackedByteArray RetroGraphics::encode_tiles(const Ref<Image> &p_image, int p_bpp,
		const PackedColorArray &p_palette, int p_tile_size, bool p_megadrive) {
	PackedByteArray out;
	if (p_image.is_null()) {
		return out;
	}
	Ref<Image> img = p_image->duplicate();
	if (img->get_format() != Image::FORMAT_RGBA8) {
		img->convert(Image::FORMAT_RGBA8);
	}
	const int tiles_x = (img->get_width() + p_tile_size - 1) / p_tile_size;
	const int tiles_y = (img->get_height() + p_tile_size - 1) / p_tile_size;
	const int bytes_per_tile = (p_bpp == 8) ? 64 : (p_tile_size * p_tile_size * p_bpp) / 8;
	out.resize(tiles_x * tiles_y * bytes_per_tile);
	out.fill(0);
	uint8_t *w = out.ptrw();

	for (int ty = 0; ty < tiles_y; ty++) {
		for (int tx = 0; tx < tiles_x; tx++) {
			const int t = ty * tiles_x + tx;
			uint8_t *tile = w + t * bytes_per_tile;
			for (int y = 0; y < p_tile_size; y++) {
				for (int x = 0; x < p_tile_size; x++) {
					const Color c = img->get_pixel(tx * p_tile_size + x, ty * p_tile_size + y);
					int idx = 0;
					if (c.a >= 0.5) {
						idx = _nearest_color(c, p_palette, 0);
						idx = CLAMP(idx, 0, (1 << p_bpp) - 1);
					}
					if (p_bpp == 8) {
						tile[y * 8 + x] = uint8_t(idx);
					} else if (p_megadrive) {
						const int row_bytes = (p_tile_size * p_bpp) / 8;
						tile[y * row_bytes + (x / 2)] |= uint8_t((idx & 0x0F) << ((x & 1) ? 0 : 4));
					} else {
						const int row_bytes = p_bpp / 2;
						for (int p = 0; p < p_bpp; p++) {
							const int plane_pair = p / 2;
							const int byte_off = plane_pair * 8 * row_bytes + y * row_bytes + (p % 2);
							const int bit = (idx >> p) & 1;
							tile[byte_off] |= uint8_t(bit << (7 - x));
						}
					}
				}
			}
		}
	}
	return out;
}

Array RetroGraphics::decode_tilemap(const PackedByteArray &p_data, bool p_megadrive) {
	Array out;
	const int n = p_data.size() / 2;
	for (int i = 0; i < n; i++) {
		const int b0 = p_data[i * 2];
		const int b1 = p_data[i * 2 + 1];
		const uint16_t word = p_megadrive ? uint16_t((b0 << 8) | b1) : uint16_t(b0 | (b1 << 8));
		Dictionary e;
		if (p_megadrive) {
			e["tile"] = word & 0x7FF;
			e["hflip"] = (word >> 11) & 1;
			e["vflip"] = (word >> 12) & 1;
			e["palette"] = (word >> 13) & 3;
			e["priority"] = (word >> 15) & 1;
		} else {
			e["tile"] = word & 0x3FF;
			e["palette"] = (word >> 10) & 7;
			e["priority"] = (word >> 13) & 1;
			e["hflip"] = (word >> 14) & 1;
			e["vflip"] = (word >> 15) & 1;
		}
		out.push_back(e);
	}
	return out;
}

PackedByteArray RetroGraphics::encode_tilemap(const Array &p_entries, bool p_megadrive) {
	PackedByteArray out;
	out.resize(p_entries.size() * 2);
	uint8_t *w = out.ptrw();
	for (int i = 0; i < p_entries.size(); i++) {
		const Dictionary e = p_entries[i];
		const int tile = e.get("tile", 0);
		const int pal = e.get("palette", 0);
		const int prio = e.get("priority", 0);
		const int hf = e.get("hflip", 0);
		const int vf = e.get("vflip", 0);
		uint16_t word;
		if (p_megadrive) {
			word = uint16_t((tile & 0x7FF) | ((hf & 1) << 11) | ((vf & 1) << 12) | ((pal & 3) << 13) | ((prio & 1) << 15));
			w[i * 2] = uint8_t(word >> 8);
			w[i * 2 + 1] = uint8_t(word & 0xFF);
		} else {
			word = uint16_t((tile & 0x3FF) | ((pal & 7) << 10) | ((prio & 1) << 13) | ((hf & 1) << 14) | ((vf & 1) << 15));
			w[i * 2] = uint8_t(word & 0xFF);
			w[i * 2 + 1] = uint8_t(word >> 8);
		}
	}
	return out;
}

Ref<Image> RetroGraphics::render_tilemap_indexed(const PackedByteArray &p_map, const Ref<Image> &p_indices,
		int p_map_w, int p_map_h, int p_tile_size, const PackedColorArray &p_palette, bool p_megadrive,
		bool p_column_major, int p_colors_per_palette) {
	if (p_indices.is_null() || p_map_w <= 0 || p_map_h <= 0) {
		return Ref<Image>();
	}
	Ref<Image> indices = p_indices->duplicate();
	if (indices->get_format() != Image::FORMAT_R8) {
		indices->convert(Image::FORMAT_R8);
	}
	const int tiles_x = MAX(1, indices->get_width() / p_tile_size);
	Ref<Image> out = Image::create_empty(p_map_w * p_tile_size, p_map_h * p_tile_size, false, Image::FORMAT_RGBA8);
	out->fill(Color(0, 0, 0, 1));
	const Array entries = decode_tilemap(p_map, p_megadrive);
	for (int my = 0; my < p_map_h; my++) {
		for (int mx = 0; mx < p_map_w; mx++) {
			const int i = p_column_major ? (mx * p_map_h + my) : (my * p_map_w + mx);
			if (i >= entries.size()) {
				continue;
			}
			const Dictionary e = entries[i];
			const int tile = e.get("tile", 0);
			const int pal = e.get("palette", 0);
			const int hf = e.get("hflip", 0);
			const int vf = e.get("vflip", 0);
			const int sx = (tile % tiles_x) * p_tile_size;
			const int sy = (tile / tiles_x) * p_tile_size;
			for (int y = 0; y < p_tile_size; y++) {
				for (int x = 0; x < p_tile_size; x++) {
					const int px = sx + (hf ? (p_tile_size - 1 - x) : x);
					const int py = sy + (vf ? (p_tile_size - 1 - y) : y);
					if (px >= indices->get_width() || py >= indices->get_height()) {
						continue;
					}
					const int idx = int(indices->get_pixel(px, py).r * 255.0 + 0.5);
					if (idx == 0) {
						continue;
					}
					int ci = pal * p_colors_per_palette + idx;
					if (ci >= p_palette.size()) {
						ci = idx;
					}
					if (ci < 0 || ci >= p_palette.size()) {
						continue;
					}
					Color c = p_palette[ci];
					c.a = 1.0;
					out->set_pixel(mx * p_tile_size + x, my * p_tile_size + y, c);
				}
			}
		}
	}
	return out;
}

Ref<Image> RetroGraphics::render_tilemap(const PackedByteArray &p_map, const Ref<Image> &p_tiles,
		int p_map_w, int p_map_h, int p_tile_size, const PackedColorArray &p_palette, bool p_megadrive, bool p_column_major) {
	if (p_tiles.is_null() || p_map_w <= 0 || p_map_h <= 0) {
		return Ref<Image>();
	}
	Ref<Image> tiles = p_tiles->duplicate();
	if (tiles->get_format() != Image::FORMAT_RGBA8) {
		tiles->convert(Image::FORMAT_RGBA8);
	}
	const int tiles_x = MAX(1, tiles->get_width() / p_tile_size);
	Ref<Image> out = Image::create_empty(p_map_w * p_tile_size, p_map_h * p_tile_size, false, Image::FORMAT_RGBA8);
	out->fill(Color(0, 0, 0, 1));
	const Array entries = decode_tilemap(p_map, p_megadrive);
	for (int my = 0; my < p_map_h; my++) {
		for (int mx = 0; mx < p_map_w; mx++) {
			const int i = p_column_major ? (mx * p_map_h + my) : (my * p_map_w + mx);
			if (i >= entries.size()) {
				continue;
			}
			const Dictionary e = entries[i];
			const int tile = e.get("tile", 0);
			const int hf = e.get("hflip", 0);
			const int vf = e.get("vflip", 0);
			const int sx = (tile % tiles_x) * p_tile_size;
			const int sy = (tile / tiles_x) * p_tile_size;
			for (int y = 0; y < p_tile_size; y++) {
				for (int x = 0; x < p_tile_size; x++) {
					const int px = sx + (hf ? (p_tile_size - 1 - x) : x);
					const int py = sy + (vf ? (p_tile_size - 1 - y) : y);
					if (px >= tiles->get_width() || py >= tiles->get_height()) {
						continue;
					}
					const Color c = tiles->get_pixel(px, py);
					if (c.a > 0.01) {
						out->set_pixel(mx * p_tile_size + x, my * p_tile_size + y, c);
					}
				}
			}
		}
	}
	(void)p_palette;
	return out;
}

PackedByteArray RetroGraphics::indices_from_image(const Ref<Image> &p_image, const PackedColorArray &p_palette, bool p_transparent) {
	PackedByteArray out;
	if (p_image.is_null() || p_palette.is_empty()) {
		return out;
	}
	Ref<Image> img = p_image->duplicate();
	if (img->get_format() != Image::FORMAT_RGBA8) {
		img->convert(Image::FORMAT_RGBA8);
	}
	const int w = img->get_width();
	const int h = img->get_height();
	out.resize(w * h);
	uint8_t *o = out.ptrw();
	for (int y = 0; y < h; y++) {
		for (int x = 0; x < w; x++) {
			const Color c = img->get_pixel(x, y);
			if (p_transparent && c.a < 0.5) {
				o[y * w + x] = 0;
			} else {
				o[y * w + x] = uint8_t(CLAMP(_nearest_color(c, p_palette, p_transparent ? 1 : 0), 0, 255));
			}
		}
	}
	return out;
}

Ref<Image> RetroGraphics::image_from_indices(const PackedByteArray &p_indices, int p_width, int p_height, const PackedColorArray &p_palette) {
	Ref<Image> img = Image::create_empty(p_width, p_height, false, Image::FORMAT_RGBA8);
	img->fill(Color(0, 0, 0, 0));
	for (int y = 0; y < p_height; y++) {
		for (int x = 0; x < p_width; x++) {
			const int i = y * p_width + x;
			if (i >= p_indices.size()) {
				continue;
			}
			const int idx = p_indices[i];
			if (idx <= 0 || idx >= p_palette.size()) {
				continue;
			}
			Color c = p_palette[idx];
			c.a = 1.0;
			img->set_pixel(x, y, c);
		}
	}
	return img;
}

PackedColorArray RetroGraphics::read_png_palette(const String &p_path) {
	PackedColorArray out;
	const Vector<uint8_t> data = RetroUtil::read_bytes(p_path);
	if (data.size() < 8 || data[0] != 0x89 || data[1] != 'P') {
		return out;
	}
	int pos = 8;
	while (pos + 8 <= data.size()) {
		const uint32_t len = (uint32_t(data[pos]) << 24) | (uint32_t(data[pos + 1]) << 16) | (uint32_t(data[pos + 2]) << 8) | data[pos + 3];
		const String type = String::chr(data[pos + 4]) + String::chr(data[pos + 5]) + String::chr(data[pos + 6]) + String::chr(data[pos + 7]);
		pos += 8;
		if (pos + int(len) > data.size()) {
			break;
		}
		if (type == "PLTE") {
			for (uint32_t i = 0; i + 2 < len; i += 3) {
				out.push_back(Color::from_rgba8(data[pos + i], data[pos + i + 1], data[pos + i + 2]));
			}
		} else if (type == "IEND") {
			break;
		}
		pos += len + 4; // data + CRC
	}
	return out;
}

Error RetroGraphics::save_indexed_png(const String &p_path, const Ref<Image> &p_image, const PackedColorArray &p_palette) {
	if (p_image.is_null() || p_palette.is_empty()) {
		return ERR_INVALID_PARAMETER;
	}
	Ref<Image> img = p_image->duplicate();
	if (img->get_format() != Image::FORMAT_RGBA8) {
		img->convert(Image::FORMAT_RGBA8);
	}
	const int w = img->get_width();
	const int h = img->get_height();

	Vector<uint8_t> raw;
	raw.resize(h * (w + 1));
	PackedByteArray indices = indices_from_image(img, p_palette, true);
	const uint8_t *idx = indices.ptr();
	for (int y = 0; y < h; y++) {
		raw.write[y * (w + 1)] = 0;
		for (int x = 0; x < w; x++) {
			raw.write[y * (w + 1) + 1 + x] = idx[y * w + x];
		}
	}
	const int64_t max_z = Compression::get_max_compressed_buffer_size(raw.size(), Compression::MODE_DEFLATE);
	Vector<uint8_t> z;
	z.resize(max_z);
	const int64_t zlen = Compression::compress(z.ptrw(), raw.ptr(), raw.size(), Compression::MODE_DEFLATE);
	if (zlen <= 0) {
		return ERR_CANT_CREATE;
	}
	z.resize(zlen);

	Vector<uint8_t> png;
	const uint8_t sig[8] = { 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
	for (int i = 0; i < 8; i++) {
		png.push_back(sig[i]);
	}
	Vector<uint8_t> ihdr;
	_put_be32(ihdr, w);
	_put_be32(ihdr, h);
	ihdr.push_back(8); // bit depth
	ihdr.push_back(3); // palette
	ihdr.push_back(0);
	ihdr.push_back(0);
	ihdr.push_back(0);
	_png_chunk(png, "IHDR", ihdr);

	Vector<uint8_t> plte;
	for (int i = 0; i < p_palette.size(); i++) {
		plte.push_back(uint8_t(CLAMP(int(p_palette[i].r * 255.0), 0, 255)));
		plte.push_back(uint8_t(CLAMP(int(p_palette[i].g * 255.0), 0, 255)));
		plte.push_back(uint8_t(CLAMP(int(p_palette[i].b * 255.0), 0, 255)));
	}
	_png_chunk(png, "PLTE", plte);

	Vector<uint8_t> trns;
	trns.resize(p_palette.size());
	for (int i = 0; i < p_palette.size(); i++) {
		trns.write[i] = (i == 0) ? 0 : 255;
	}
	_png_chunk(png, "tRNS", trns);
	_png_chunk(png, "IDAT", z);
	_png_chunk(png, "IEND", Vector<uint8_t>());

	return RetroUtil::write_bytes(p_path, png);
}

namespace {

struct _PalColor {
	int r;
	int g;
	int b;
	int64_t count;
};

struct _PalBox {
	int begin = 0;
	int end = 0;
	int rmin = 0, rmax = 0;
	int gmin = 0, gmax = 0;
	int bmin = 0, bmax = 0;
	int64_t count = 0;
};

static void _box_bounds(const Vector<_PalColor> &p_colors, _PalBox &r_box) {
	r_box.rmin = r_box.gmin = r_box.bmin = 255;
	r_box.rmax = r_box.gmax = r_box.bmax = 0;
	r_box.count = 0;
	for (int i = r_box.begin; i <= r_box.end; i++) {
		const _PalColor &c = p_colors[i];
		r_box.rmin = MIN(r_box.rmin, c.r);
		r_box.rmax = MAX(r_box.rmax, c.r);
		r_box.gmin = MIN(r_box.gmin, c.g);
		r_box.gmax = MAX(r_box.gmax, c.g);
		r_box.bmin = MIN(r_box.bmin, c.b);
		r_box.bmax = MAX(r_box.bmax, c.b);
		r_box.count += c.count;
	}
}

static int _box_longest_channel(const _PalBox &p_box) {
	const int dr = p_box.rmax - p_box.rmin;
	const int dg = p_box.gmax - p_box.gmin;
	const int db = p_box.bmax - p_box.bmin;
	if (dr >= dg && dr >= db) {
		return 0;
	}
	return dg >= db ? 1 : 2;
}

// Median-cut reduces an arbitrary image to a palette that still represents
// rare but visually important details (for example the small subtitle of the
// Godot logo). Picking the first N unique colors in raster order, as a naive
// histogram does, drops those details.
static PackedColorArray _median_cut(const Vector<_PalColor> &p_source, int p_slots) {
	PackedColorArray out;
	if (p_source.is_empty() || p_slots <= 0) {
		return out;
	}
	Vector<_PalColor> colors = p_source;
	Vector<_PalBox> boxes;
	_PalBox first;
	first.begin = 0;
	first.end = colors.size() - 1;
	_box_bounds(colors, first);
	boxes.push_back(first);

	while (boxes.size() < p_slots) {
		int best = -1;
		double best_score = -1.0;
		for (int i = 0; i < boxes.size(); i++) {
			const _PalBox &box = boxes[i];
			if (box.end <= box.begin || box.count <= 0) {
				continue;
			}
			const int range = MAX(box.rmax - box.rmin, MAX(box.gmax - box.gmin, box.bmax - box.bmin));
			const double score = double(box.count) * double(range + 1);
			if (score > best_score) {
				best_score = score;
				best = i;
			}
		}
		if (best < 0) {
			break;
		}
		const _PalBox box = boxes[best];
		const int channel = _box_longest_channel(box);
		_PalColor *data = colors.ptrw();
		if (channel == 0) {
			std::sort(data + box.begin, data + box.end + 1, [](const _PalColor &a, const _PalColor &b) { return a.r < b.r; });
		} else if (channel == 1) {
			std::sort(data + box.begin, data + box.end + 1, [](const _PalColor &a, const _PalColor &b) { return a.g < b.g; });
		} else {
			std::sort(data + box.begin, data + box.end + 1, [](const _PalColor &a, const _PalColor &b) { return a.b < b.b; });
		}
		const int64_t half = box.count / 2;
		int64_t acc = 0;
		int split = box.begin;
		for (int i = box.begin; i <= box.end; i++) {
			acc += colors[i].count;
			if (acc >= half) {
				split = i;
				break;
			}
		}
		split = CLAMP(split, box.begin, box.end - 1);
		_PalBox left = box;
		left.end = split;
		_PalBox right = box;
		right.begin = split + 1;
		_box_bounds(colors, left);
		_box_bounds(colors, right);
		boxes.write[best] = left;
		boxes.push_back(right);
	}

	for (int i = 0; i < boxes.size() && out.size() < p_slots; i++) {
		const _PalBox &box = boxes[i];
		if (box.count <= 0) {
			continue;
		}
		int64_t sr = 0, sg = 0, sb = 0;
		for (int j = box.begin; j <= box.end; j++) {
			const _PalColor &c = colors[j];
			sr += int64_t(c.r) * c.count;
			sg += int64_t(c.g) * c.count;
			sb += int64_t(c.b) * c.count;
		}
		const int r = int((sr + box.count / 2) / box.count);
		const int g = int((sg + box.count / 2) / box.count);
		const int b = int((sb + box.count / 2) / box.count);
		out.push_back(Color::from_rgba8(CLAMP(r, 0, 255), CLAMP(g, 0, 255), CLAMP(b, 0, 255)));
	}
	return out;
}

} // namespace

PackedColorArray RetroGraphics::extract_palette(const Ref<Image> &p_image, int p_max_colors, bool p_reserve_transparent) {
	PackedColorArray out;
	if (p_image.is_null()) {
		return out;
	}
	Ref<Image> img = p_image->duplicate();
	if (img->get_format() != Image::FORMAT_RGBA8) {
		img->convert(Image::FORMAT_RGBA8);
	}
	if (p_reserve_transparent) {
		out.push_back(Color(0, 0, 0, 0));
	}
	HashMap<uint32_t, int> seen;
	Vector<_PalColor> histogram;
	const int w = img->get_width();
	const int h = img->get_height();
	for (int y = 0; y < h; y++) {
		for (int x = 0; x < w; x++) {
			const Color c = img->get_pixel(x, y);
			if (p_reserve_transparent && c.a < 0.5) {
				continue;
			}
			const int ri = CLAMP(int(c.r * 255), 0, 255);
			const int gi = CLAMP(int(c.g * 255), 0, 255);
			const int bi = CLAMP(int(c.b * 255), 0, 255);
			const uint32_t key = (uint32_t(ri) << 16) | (uint32_t(gi) << 8) | uint32_t(bi);
			int index = -1;
			if (seen.has(key)) {
				index = seen[key];
			} else {
				index = histogram.size();
				seen[key] = index;
				histogram.push_back({ ri, gi, bi, 0 });
			}
			histogram.write[index].count++;
		}
	}
	const int slots = MAX(0, p_max_colors - out.size());
	if (histogram.size() <= slots) {
		for (int i = 0; i < histogram.size(); i++) {
			out.push_back(Color::from_rgba8(histogram[i].r, histogram[i].g, histogram[i].b));
		}
		return out;
	}
	const PackedColorArray reduced = _median_cut(histogram, slots);
	for (int i = 0; i < reduced.size(); i++) {
		out.push_back(reduced[i]);
	}
	return out;
}

Ref<Image> RetroGraphics::quantize(const Ref<Image> &p_image, int p_max_colors, bool p_transparent) {
	PackedColorArray pal = extract_palette(p_image, p_max_colors, p_transparent);
	return map_to_palette(p_image, pal, p_transparent);
}

Ref<Image> RetroGraphics::map_to_palette(const Ref<Image> &p_image, const PackedColorArray &p_palette, bool p_transparent) {
	if (p_image.is_null()) {
		return Ref<Image>();
	}
	Ref<Image> img = p_image->duplicate();
	if (img->get_format() != Image::FORMAT_RGBA8) {
		img->convert(Image::FORMAT_RGBA8);
	}
	Ref<Image> out = Image::create_empty(img->get_width(), img->get_height(), false, Image::FORMAT_RGBA8);
	out->fill(Color(0, 0, 0, 0));
	for (int y = 0; y < img->get_height(); y++) {
		for (int x = 0; x < img->get_width(); x++) {
			const Color c = img->get_pixel(x, y);
			if (p_transparent && c.a < 0.5) {
				continue;
			}
			const int start = (p_transparent && p_palette.size() > 1) ? 1 : 0;
			const int i = _nearest_color(c, p_palette, start);
			Color o = p_palette[i];
			o.a = 1.0;
			out->set_pixel(x, y, o);
		}
	}
	return out;
}

Dictionary RetroGraphics::analyze_image(const Ref<Image> &p_image) {
	Dictionary out;
	if (p_image.is_null()) {
		return out;
	}
	Ref<Image> img = p_image->duplicate();
	if (img->get_format() != Image::FORMAT_RGBA8) {
		img->convert(Image::FORMAT_RGBA8);
	}
	HashMap<uint32_t, int> colors;
	int transparent = 0;
	for (int y = 0; y < img->get_height(); y++) {
		for (int x = 0; x < img->get_width(); x++) {
			const Color c = img->get_pixel(x, y);
			if (c.a < 0.5) {
				transparent++;
				continue;
			}
			const uint32_t key = (uint32_t(int(c.r * 255)) << 16) | (uint32_t(int(c.g * 255)) << 8) | uint32_t(int(c.b * 255));
			colors[key] = 1;
		}
	}
	out["width"] = img->get_width();
	out["height"] = img->get_height();
	out["colors"] = colors.size();
	out["has_transparency"] = transparent > 0;
	out["transparent_pixels"] = transparent;
	out["pixels"] = img->get_width() * img->get_height();
	return out;
}
