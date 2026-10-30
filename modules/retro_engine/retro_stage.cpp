/**************************************************************************/
/*  retro_stage.cpp                                                       */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_stage.h"

#include "retro_graphics.h"
#include "retro_util.h"

#include "core/core_bind.h"
#include "core/io/marshalls.h"

static PackedByteArray _retro_bytes_from_variant(const Variant &p_v) {
	if (p_v.get_type() == Variant::PACKED_BYTE_ARRAY) {
		return p_v;
	}
	if (p_v.get_type() == Variant::ARRAY) {
		const Array a = p_v;
		PackedByteArray out;
		out.resize(a.size());
		for (int i = 0; i < a.size(); i++) {
			out.write[i] = uint8_t(int(a[i]));
		}
		return out;
	}
	if (p_v.get_type() == Variant::STRING) {
		// Older sessions stored PackedByteArray via JSON.stringify, which
		// produces a comma-separated decimal string.
		const String s = p_v;
		PackedByteArray out;
		const PackedStringArray parts = s.split(",", false);
		out.resize(parts.size());
		for (int i = 0; i < parts.size(); i++) {
			out.write[i] = uint8_t(parts[i].strip_edges().to_int());
		}
		return out;
	}
	return PackedByteArray();
}

void RetroStage::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_snes", "tiles_path", "map_path", "palette_path", "map_w", "map_h", "tile_size", "bpp", "tiles_x", "column_major"),
			&RetroStage::load_snes, DEFVAL(32), DEFVAL(32), DEFVAL(8), DEFVAL(4), DEFVAL(16), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("load_image_tileset", "tiles_path", "map_path", "map_w", "map_h", "tile_size"),
			&RetroStage::load_image_tileset);
	ClassDB::bind_method(D_METHOD("save", "path"), &RetroStage::save);
	ClassDB::bind_method(D_METHOD("load", "path"), &RetroStage::load);
	ClassDB::bind_method(D_METHOD("render"), &RetroStage::render);
	ClassDB::bind_method(D_METHOD("render_region", "x", "y", "w", "h"), &RetroStage::render_region);
	ClassDB::bind_method(D_METHOD("export_snes", "dir", "base"), &RetroStage::export_snes);
	ClassDB::bind_method(D_METHOD("export_sgdk", "dir", "base", "res_file"), &RetroStage::export_sgdk, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("analyze"), &RetroStage::analyze);
	ClassDB::bind_method(D_METHOD("get_tile", "x", "y"), &RetroStage::get_tile);
	ClassDB::bind_method(D_METHOD("set_tile", "x", "y", "tile", "palette", "flip_h", "flip_v", "priority"),
			&RetroStage::set_tile, DEFVAL(0), DEFVAL(0), DEFVAL(0), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_tile_info", "x", "y"), &RetroStage::get_tile_info);
	ClassDB::bind_method(D_METHOD("add_layer", "name", "map"), &RetroStage::add_layer);
	ClassDB::bind_method(D_METHOD("paint_rect", "x", "y", "w", "h", "tile", "palette"), &RetroStage::paint_rect, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("to_dict"), &RetroStage::to_dict);
	ClassDB::bind_method(D_METHOD("from_dict", "data"), &RetroStage::from_dict);

	ClassDB::bind_method(D_METHOD("set_name", "value"), &RetroStage::set_name);
	ClassDB::bind_method(D_METHOD("get_name"), &RetroStage::get_name);
	ClassDB::bind_method(D_METHOD("set_platform", "value"), &RetroStage::set_platform);
	ClassDB::bind_method(D_METHOD("get_platform"), &RetroStage::get_platform);
	ClassDB::bind_method(D_METHOD("set_mode", "value"), &RetroStage::set_mode);
	ClassDB::bind_method(D_METHOD("get_mode"), &RetroStage::get_mode);
	ClassDB::bind_method(D_METHOD("set_tileset", "value"), &RetroStage::set_tileset);
	ClassDB::bind_method(D_METHOD("get_tileset"), &RetroStage::get_tileset);
	ClassDB::bind_method(D_METHOD("set_tile_indices", "value"), &RetroStage::set_tile_indices);
	ClassDB::bind_method(D_METHOD("get_tile_indices"), &RetroStage::get_tile_indices);
	ClassDB::bind_method(D_METHOD("set_palette", "value"), &RetroStage::set_palette);
	ClassDB::bind_method(D_METHOD("get_palette"), &RetroStage::get_palette);
	ClassDB::bind_method(D_METHOD("set_map", "value"), &RetroStage::set_map);
	ClassDB::bind_method(D_METHOD("get_map"), &RetroStage::get_map);
	ClassDB::bind_method(D_METHOD("set_map_size", "value"), &RetroStage::set_map_size);
	ClassDB::bind_method(D_METHOD("get_map_size"), &RetroStage::get_map_size);
	ClassDB::bind_method(D_METHOD("set_tile_size", "value"), &RetroStage::set_tile_size);
	ClassDB::bind_method(D_METHOD("get_tile_size"), &RetroStage::get_tile_size);
	ClassDB::bind_method(D_METHOD("set_bpp", "value"), &RetroStage::set_bpp);
	ClassDB::bind_method(D_METHOD("get_bpp"), &RetroStage::get_bpp);
	ClassDB::bind_method(D_METHOD("set_tiles_x", "value"), &RetroStage::set_tiles_x);
	ClassDB::bind_method(D_METHOD("get_tiles_x"), &RetroStage::get_tiles_x);
	ClassDB::bind_method(D_METHOD("set_column_major", "value"), &RetroStage::set_column_major);
	ClassDB::bind_method(D_METHOD("get_column_major"), &RetroStage::get_column_major);
	ClassDB::bind_method(D_METHOD("set_scroll", "value"), &RetroStage::set_scroll);
	ClassDB::bind_method(D_METHOD("get_scroll"), &RetroStage::get_scroll);
	ClassDB::bind_method(D_METHOD("set_camera_limits", "value"), &RetroStage::set_camera_limits);
	ClassDB::bind_method(D_METHOD("get_camera_limits"), &RetroStage::get_camera_limits);
	ClassDB::bind_method(D_METHOD("set_layers", "value"), &RetroStage::set_layers);
	ClassDB::bind_method(D_METHOD("get_layers"), &RetroStage::get_layers);
	ClassDB::bind_method(D_METHOD("set_collisions", "value"), &RetroStage::set_collisions);
	ClassDB::bind_method(D_METHOD("get_collisions"), &RetroStage::get_collisions);
	ClassDB::bind_method(D_METHOD("set_metadata", "value"), &RetroStage::set_metadata);
	ClassDB::bind_method(D_METHOD("get_metadata"), &RetroStage::get_metadata);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name"), "set_name", "get_name");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "platform"), "set_platform", "get_platform");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "mode"), "set_mode", "get_mode");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "tileset", PROPERTY_HINT_RESOURCE_TYPE, "Image"), "set_tileset", "get_tileset");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_COLOR_ARRAY, "palette"), "set_palette", "get_palette");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_BYTE_ARRAY, "map"), "set_map", "get_map");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "map_size"), "set_map_size", "get_map_size");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "tile_size"), "set_tile_size", "get_tile_size");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "bpp"), "set_bpp", "get_bpp");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "tiles_x"), "set_tiles_x", "get_tiles_x");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "column_major"), "set_column_major", "get_column_major");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "scroll"), "set_scroll", "get_scroll");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "camera_limits"), "set_camera_limits", "get_camera_limits");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "layers"), "set_layers", "get_layers");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "collisions"), "set_collisions", "get_collisions");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "metadata"), "set_metadata", "get_metadata");
}

Error RetroStage::load_snes(const String &p_tiles_path, const String &p_map_path, const String &p_palette_path,
		int p_map_w, int p_map_h, int p_tile_size, int p_bpp, int p_tiles_x, bool p_column_major) {
	const Vector<uint8_t> tiles = RetroUtil::read_bytes(p_tiles_path);
	const Vector<uint8_t> map_data = RetroUtil::read_bytes(p_map_path);
	if (tiles.is_empty() || map_data.is_empty()) {
		return ERR_FILE_CANT_READ;
	}
	map_w = p_map_w;
	map_h = p_map_h;
	tile_size = p_tile_size;
	bpp = p_bpp;
	tiles_x = MAX(1, p_tiles_x);
	column_major = p_column_major;
	map = map_data;
	const Vector<uint8_t> pal_data = RetroUtil::read_bytes(p_palette_path);
	PackedByteArray pal = pal_data;
	palette = RetroGraphics::decode_palette(pal, platform == "megadrive");
	if (palette.is_empty()) {
		palette.push_back(Color(0, 0, 0));
		palette.push_back(Color(1, 0, 1));
	}
	PackedByteArray tile_bytes = tiles;
	tile_indices = RetroGraphics::decode_tiles_indexed(tile_bytes, tiles_x, bpp, tile_size, platform == "megadrive");
	tileset = RetroGraphics::decode_tiles(tile_bytes, tiles_x, bpp, palette, tile_size, platform == "megadrive");
	if (tileset.is_null()) {
		return ERR_INVALID_DATA;
	}
	name = p_tiles_path.get_file().get_basename();
	metadata["tiles_path"] = p_tiles_path;
	metadata["map_path"] = p_map_path;
	metadata["palette_path"] = p_palette_path;
	return OK;
}

Error RetroStage::load_image_tileset(const String &p_tiles_path, const String &p_map_path, int p_map_w, int p_map_h, int p_tile_size) {
	Ref<Image> img = Image::load_from_file(p_tiles_path);
	if (img.is_null()) {
		return ERR_FILE_CANT_READ;
	}
	img->convert(Image::FORMAT_RGBA8);
	tileset = img;
	tile_size = p_tile_size;
	map_w = p_map_w;
	map_h = p_map_h;
	tiles_x = MAX(1, img->get_width() / p_tile_size);
	const Vector<uint8_t> map_data = RetroUtil::read_bytes(p_map_path);
	map = map_data;
	palette = RetroGraphics::read_png_palette(p_tiles_path);
	if (palette.is_empty()) {
		palette = RetroGraphics::extract_palette(img, 16, true);
	}
	name = p_tiles_path.get_file().get_basename();
	return OK;
}

Error RetroStage::save(const String &p_path) {
	return RetroUtil::save_json_file(p_path, to_dict());
}

Error RetroStage::load(const String &p_path) {
	bool ok = false;
	const Dictionary d = RetroUtil::parse_json_file(p_path, &ok);
	if (!ok) {
		return ERR_FILE_CANT_READ;
	}
	from_dict(d);
	return OK;
}

Ref<Image> RetroStage::render() {
	if (tileset.is_null() || map.is_empty()) {
		return Ref<Image>();
	}
	if (tile_indices.is_valid()) {
		return RetroGraphics::render_tilemap_indexed(map, tile_indices, map_w, map_h, tile_size, palette,
				platform == "megadrive", column_major, bpp == 8 ? 256 : 16);
	}
	return RetroGraphics::render_tilemap(map, tileset, map_w, map_h, tile_size, palette, platform == "megadrive", column_major);
}

Ref<Image> RetroStage::render_region(int p_x, int p_y, int p_w, int p_h) {
	Ref<Image> full = render();
	if (full.is_null()) {
		return Ref<Image>();
	}
	Ref<Image> out = Image::create_empty(p_w, p_h, false, Image::FORMAT_RGBA8);
	out->fill(Color(0, 0, 0, 1));
	for (int y = 0; y < p_h; y++) {
		for (int x = 0; x < p_w; x++) {
			const int sx = p_x + x;
			const int sy = p_y + y;
			if (sx >= 0 && sy >= 0 && sx < full->get_width() && sy < full->get_height()) {
				out->set_pixel(x, y, full->get_pixel(sx, sy));
			}
		}
	}
	return out;
}

Dictionary RetroStage::export_snes(const String &p_dir, const String &p_base) {
	Dictionary result;
	if (tileset.is_null() || map.is_empty()) {
		result["ok"] = false;
		result["error"] = "tileset/map not loaded";
		return result;
	}
	DirAccess::make_dir_recursive_absolute(p_dir);
	const PackedByteArray chr = tile_indices.is_valid()
			? RetroGraphics::encode_tiles_indexed(tile_indices, bpp, tile_size, false)
			: RetroGraphics::encode_tiles(tileset, bpp, palette, tile_size, false);
	const String chr_path = RetroUtil::join(p_dir, p_base + ".chr");
	RetroUtil::write_bytes(chr_path, chr);
	const String pal_path = RetroUtil::join(p_dir, p_base + ".pal");
	RetroUtil::write_bytes(pal_path, RetroGraphics::encode_palette(palette, false));
	const String map_path = RetroUtil::join(p_dir, p_base + ".map");
	RetroUtil::write_bytes(map_path, map);
	String inc = "; Generated by Godot Retro Engine\n";
	inc += p_base + "_tiles:\n\t.incbin \"" + p_base + ".chr\"\n";
	inc += p_base + "_palette:\n\t.incbin \"" + p_base + ".pal\"\n";
	inc += p_base + "_map:\n\t.incbin \"" + p_base + ".map\"\n";
	inc += p_base + "_map_w = " + itos(map_w) + "\n";
	inc += p_base + "_map_h = " + itos(map_h) + "\n";
	const String inc_path = RetroUtil::join(p_dir, p_base + "_stage.inc");
	RetroUtil::write_text(inc_path, inc);
	result["ok"] = true;
	result["chr"] = chr_path;
	result["pal"] = pal_path;
	result["map"] = map_path;
	result["inc"] = inc_path;
	result["bytes"] = chr.size() + map.size() + palette.size() * 2;
	return result;
}

Dictionary RetroStage::export_sgdk(const String &p_dir, const String &p_base, const String &p_res_file) {
	Dictionary result;
	if (tileset.is_null() || map.is_empty()) {
		result["ok"] = false;
		result["error"] = "tileset/map not loaded";
		return result;
	}
	DirAccess::make_dir_recursive_absolute(p_dir);
	const String tiles_png = RetroUtil::join(p_dir, p_base + "_tiles.png");
	const String map_png = RetroUtil::join(p_dir, p_base + "_map.png");
	Ref<Image> map_image = render();
	if (map_image.is_null()) {
		result["ok"] = false;
		result["error"] = "could not render the map image";
		return result;
	}
	Ref<Image> tiles_out = tileset->duplicate();
	Ref<Image> map_out = map_image->duplicate();
	if (tiles_out->get_format() != Image::FORMAT_RGBA8) {
		tiles_out->convert(Image::FORMAT_RGBA8);
	}
	if (map_out->get_format() != Image::FORMAT_RGBA8) {
		map_out->convert(Image::FORMAT_RGBA8);
	}
	PackedColorArray sgdk_palette = palette;
	if (sgdk_palette.size() > 64) {
		sgdk_palette = RetroGraphics::extract_palette(tiles_out, 64, true);
		tiles_out = RetroGraphics::map_to_palette(tiles_out, sgdk_palette, true);
		map_out = RetroGraphics::map_to_palette(map_out, sgdk_palette, true);
	}
	Error err = (!sgdk_palette.is_empty() && sgdk_palette.size() <= 256)
			? RetroGraphics::save_indexed_png(tiles_png, tiles_out, sgdk_palette)
			: tiles_out->save_png(tiles_png);
	if (err == OK) {
		err = (!sgdk_palette.is_empty() && sgdk_palette.size() <= 256)
				? RetroGraphics::save_indexed_png(map_png, map_out, sgdk_palette)
				: map_out->save_png(map_png);
	}
	if (err != OK) {
		result["ok"] = false;
		result["error"] = "could not write tileset/map PNG";
		return result;
	}
	String res_path = p_res_file;
	if (res_path.is_empty()) {
		res_path = RetroUtil::join(p_dir, p_base + ".res");
	}
	String res = RetroUtil::read_text(res_path);
	if (!res.contains("TILESET " + p_base + "_tileset ")) {
		// SGDK's rescomp builds the VDP nametable from the full map image; the
		// TILESET resource supplies the 8x8 tiles. This is the native SGDK
		// workflow, not a fake .map writer.
		res += "TILESET " + p_base + "_tileset \"" + tiles_png.get_file() + "\" BEST ALL\n";
		res += "MAP " + p_base + "_map \"" + map_png.get_file() + "\" " + p_base + "_tileset BEST 0\n";
		res += "PALETTE " + p_base + "_palette \"" + tiles_png.get_file() + "\"\n";
		res += "// source map: " + itos(map_w) + "x" + itos(map_h) + " tiles, " + itos(tile_size) + "px\n";
		RetroUtil::write_text(res_path, res);
	}
	result["ok"] = true;
	result["tiles_png"] = tiles_png;
	result["map_png"] = map_png;
	result["res"] = res_path;
	result["map_entries"] = map.size() / 2;
	result["palette_colors"] = sgdk_palette.size();
	return result;
}

Dictionary RetroStage::analyze() {
	Dictionary d;
	const int tile_count = map.size() / 2;
	const int tile_bytes = (bpp == 8) ? 64 : 32;
	const int unique_estimate = MAX(1, tile_count);
	d["map_w"] = map_w;
	d["map_h"] = map_h;
	d["tile_size"] = tile_size;
	d["map_entries"] = tile_count;
	d["vram_tiles_bytes"] = unique_estimate * tile_bytes;
	d["vram_map_bytes"] = tile_count * 2;
	d["palette_bytes"] = palette.size() * 2;
	d["palette_colors"] = palette.size();
	d["pixel_width"] = map_w * tile_size;
	d["pixel_height"] = map_h * tile_size;
	d["bpp"] = bpp;
	d["mode"] = mode;
	d["column_major"] = column_major;
	d["palette_banks"] = palette.size() / MAX(1, (bpp == 8 ? 256 : 16));
	d["has_tile_indices"] = tile_indices.is_valid();
	return d;
}

int RetroStage::get_tile(int p_x, int p_y) {
	if (p_x < 0 || p_y < 0 || p_x >= map_w || p_y >= map_h) {
		return -1;
	}
	const int i = (column_major ? (p_x * map_h + p_y) : (p_y * map_w + p_x)) * 2;
	if (i + 1 >= map.size()) {
		return -1;
	}
	const int word = platform == "megadrive" ? ((map[i] << 8) | map[i + 1]) : (map[i] | (map[i + 1] << 8));
	return word;
}

void RetroStage::set_tile(int p_x, int p_y, int p_tile, int p_palette, int p_flip_h, int p_flip_v, int p_priority) {
	if (p_x < 0 || p_y < 0 || p_x >= map_w || p_y >= map_h) {
		return;
	}
	const int i = (column_major ? (p_x * map_h + p_y) : (p_y * map_w + p_x)) * 2;
	if (i + 1 >= map.size()) {
		return;
	}
	uint16_t word;
	if (platform == "megadrive") {
		word = uint16_t((p_tile & 0x7FF) | ((p_flip_h & 1) << 11) | ((p_flip_v & 1) << 12) | ((p_palette & 3) << 13) | ((p_priority & 1) << 15));
		map.write[i] = uint8_t(word >> 8);
		map.write[i + 1] = uint8_t(word & 0xFF);
	} else {
		word = uint16_t((p_tile & 0x3FF) | ((p_palette & 7) << 10) | ((p_priority & 1) << 13) | ((p_flip_h & 1) << 14) | ((p_flip_v & 1) << 15));
		map.write[i] = uint8_t(word & 0xFF);
		map.write[i + 1] = uint8_t(word >> 8);
	}
}

Dictionary RetroStage::get_tile_info(int p_x, int p_y) {
	const int word = get_tile(p_x, p_y);
	if (word < 0) {
		return Dictionary();
	}
	Dictionary d;
	d["word"] = word;
	if (platform == "megadrive") {
		d["tile"] = word & 0x7FF;
		d["hflip"] = (word >> 11) & 1;
		d["vflip"] = (word >> 12) & 1;
		d["palette"] = (word >> 13) & 3;
		d["priority"] = (word >> 15) & 1;
	} else {
		d["tile"] = word & 0x3FF;
		d["palette"] = (word >> 10) & 7;
		d["priority"] = (word >> 13) & 1;
		d["hflip"] = (word >> 14) & 1;
		d["vflip"] = (word >> 15) & 1;
	}
	const int tile = d["tile"];
	d["px"] = p_x * tile_size;
	d["py"] = p_y * tile_size;
	d["tile_valid"] = tileset.is_valid() && (tile / tiles_x) < (tileset->get_height() / tile_size);
	return d;
}

void RetroStage::add_layer(const String &p_name, const PackedByteArray &p_map) {
	Dictionary l;
	l["name"] = p_name;
	l["map"] = p_map;
	l["parallax"] = 1.0;
	l["priority"] = layers.size();
	l["visible"] = true;
	layers.push_back(l);
}

void RetroStage::paint_rect(int p_x, int p_y, int p_w, int p_h, int p_tile, int p_palette) {
	for (int y = p_y; y < p_y + p_h; y++) {
		for (int x = p_x; x < p_x + p_w; x++) {
			set_tile(x, y, p_tile, p_palette);
		}
	}
}

Dictionary RetroStage::to_dict() const {
	Dictionary d;
	d["name"] = name;
	d["platform"] = platform;
	d["mode"] = mode;
	d["map_w"] = map_w;
	d["map_h"] = map_h;
	d["tile_size"] = tile_size;
	d["bpp"] = bpp;
	d["tiles_x"] = tiles_x;
	d["column_major"] = column_major;
	d["scroll"] = scroll;
	d["camera_limits"] = camera_limits;
	d["layers"] = layers;
	d["collisions"] = collisions;
	d["metadata"] = metadata;
	d["map_base64"] = CoreBind::Marshalls::get_singleton()->raw_to_base64(map);
	Array pal;
	for (int i = 0; i < palette.size(); i++) {
		pal.push_back(palette[i].to_html(true));
	}
	d["palette"] = pal;
	if (tileset.is_valid()) {
		const Vector<uint8_t> png = tileset->save_png_to_buffer();
		d["tileset_png_base64"] = CoreBind::Marshalls::get_singleton()->raw_to_base64(png);
		d["tileset_width"] = tileset->get_width();
		d["tileset_height"] = tileset->get_height();
	}
	if (tile_indices.is_valid()) {
		const Vector<uint8_t> png = tile_indices->save_png_to_buffer();
		d["tileset_indices_png_base64"] = CoreBind::Marshalls::get_singleton()->raw_to_base64(png);
		d["tileset_indices_width"] = tile_indices->get_width();
		d["tileset_indices_height"] = tile_indices->get_height();
	}
	return d;
}

void RetroStage::from_dict(const Dictionary &p_data) {
	name = p_data.get("name", name);
	platform = p_data.get("platform", platform);
	mode = p_data.get("mode", mode);
	map_w = p_data.get("map_w", map_w);
	map_h = p_data.get("map_h", map_h);
	tile_size = p_data.get("tile_size", tile_size);
	bpp = p_data.get("bpp", bpp);
	tiles_x = p_data.get("tiles_x", tiles_x);
	column_major = p_data.get("column_major", column_major);
	scroll = p_data.get("scroll", Dictionary());
	camera_limits = p_data.get("camera_limits", Dictionary());
	layers = p_data.get("layers", Array());
	for (int i = 0; i < layers.size(); i++) {
		Dictionary l = layers[i];
		if (l.has("map")) {
			l["map"] = _retro_bytes_from_variant(l["map"]);
			layers[i] = l;
		}
	}
	collisions = p_data.get("collisions", Array());
	for (int i = 0; i < collisions.size(); i++) {
		const Variant c = collisions[i];
		if (c.get_type() == Variant::RECT2I) {
			continue;
		}
		Rect2i r;
		if (c.get_type() == Variant::STRING) {
			String s = c;
			s = s.replace("(", "").replace(")", "");
			const PackedStringArray parts = s.split(",", false);
			if (parts.size() >= 4) {
				r = Rect2i(parts[0].to_int(), parts[1].to_int(), parts[2].to_int(), parts[3].to_int());
			}
		} else if (c.get_type() == Variant::ARRAY) {
			const Array a = c;
			if (a.size() >= 4) {
				r = Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]));
			}
		}
		collisions[i] = r;
	}
	metadata = p_data.get("metadata", Dictionary());
	if (p_data.has("map_base64")) {
		map = CoreBind::Marshalls::get_singleton()->base64_to_raw(String(p_data["map_base64"]));
	} else {
		map = _retro_bytes_from_variant(p_data.get("map", Variant()));
	}
	palette.clear();
	const Array pal = p_data.get("palette", Array());
	for (int i = 0; i < pal.size(); i++) {
		palette.push_back(Color::from_string(String(pal[i]), Color()));
	}
	if (p_data.has("tileset_png_base64")) {
		const Vector<uint8_t> png = CoreBind::Marshalls::get_singleton()->base64_to_raw(String(p_data["tileset_png_base64"]));
		Ref<Image> img = Image::create_empty(1, 1, false, Image::FORMAT_RGBA8);
		img->load_png_from_buffer(png);
		if (img.is_valid()) {
			tileset = img;
		}
	}
	if (p_data.has("tileset_indices_png_base64")) {
		const Vector<uint8_t> png = CoreBind::Marshalls::get_singleton()->base64_to_raw(String(p_data["tileset_indices_png_base64"]));
		Ref<Image> img = Image::create_empty(1, 1, false, Image::FORMAT_R8);
		img->load_png_from_buffer(png);
		if (img.is_valid()) {
			if (img->get_format() != Image::FORMAT_R8) {
				img->convert(Image::FORMAT_R8);
			}
			tile_indices = img;
		}
	}
}
