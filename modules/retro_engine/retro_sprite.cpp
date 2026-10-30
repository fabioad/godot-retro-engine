/**************************************************************************/
/*  retro_sprite.cpp                                                      */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_sprite.h"

#include "retro_graphics.h"
#include "retro_util.h"

#include "core/core_bind.h"
#include "core/io/marshalls.h"

static Rect2i _retro_rect2i(const Variant &p_v) {
	if (p_v.get_type() == Variant::RECT2I) {
		return p_v;
	}
	if (p_v.get_type() == Variant::RECT2) {
		const Rect2 r = p_v;
		return Rect2i(r.position, r.size);
	}
	if (p_v.get_type() == Variant::STRING) {
		String s = p_v;
		s = s.replace("(", "").replace(")", "");
		const PackedStringArray parts = s.split(",", false);
		if (parts.size() >= 4) {
			return Rect2i(parts[0].to_int(), parts[1].to_int(), parts[2].to_int(), parts[3].to_int());
		}
	}
	if (p_v.get_type() == Variant::ARRAY) {
		const Array a = p_v;
		if (a.size() >= 4) {
			return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]));
		}
	}
	return Rect2i();
}

static Point2i _retro_point2i(const Variant &p_v) {
	if (p_v.get_type() == Variant::VECTOR2I) {
		return p_v;
	}
	if (p_v.get_type() == Variant::VECTOR2) {
		const Vector2 v = p_v;
		return Point2i(v);
	}
	if (p_v.get_type() == Variant::STRING) {
		String s = p_v;
		s = s.replace("(", "").replace(")", "");
		const PackedStringArray parts = s.split(",", false);
		if (parts.size() >= 2) {
			return Point2i(parts[0].to_int(), parts[1].to_int());
		}
	}
	return Point2i();
}

void RetroSprite::_bind_methods() {
	ClassDB::bind_static_method("RetroSprite", D_METHOD("from_image", "image", "name"), &RetroSprite::from_image, DEFVAL("sprite"));
	ClassDB::bind_method(D_METHOD("load_image", "path"), &RetroSprite::load_image);
	ClassDB::bind_method(D_METHOD("load_snes", "chr_path", "palette_path", "tiles_x", "bpp"), &RetroSprite::load_snes, DEFVAL(16), DEFVAL(4));
	ClassDB::bind_method(D_METHOD("load_sgdk", "png_path"), &RetroSprite::load_sgdk);
	ClassDB::bind_method(D_METHOD("save_png", "path"), &RetroSprite::save_png);
	ClassDB::bind_method(D_METHOD("save", "path"), &RetroSprite::save);
	ClassDB::bind_method(D_METHOD("load", "path"), &RetroSprite::load);
	ClassDB::bind_method(D_METHOD("export_snes", "dir", "base"), &RetroSprite::export_snes);
	ClassDB::bind_method(D_METHOD("export_sgdk", "dir", "base", "res_file"), &RetroSprite::export_sgdk, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("export_png_asset", "path"), &RetroSprite::export_png_asset);
	ClassDB::bind_method(D_METHOD("split_grid", "frame_w", "frame_h", "start"), &RetroSprite::split_grid, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("add_frame", "name", "rect", "duration"), &RetroSprite::add_frame, DEFVAL(6));
	ClassDB::bind_method(D_METHOD("remove_frame", "index"), &RetroSprite::remove_frame);
	ClassDB::bind_method(D_METHOD("add_hitbox", "frame", "rect", "type"), &RetroSprite::add_hitbox, DEFVAL("hit"));
	ClassDB::bind_method(D_METHOD("add_event", "frame", "type", "value"), &RetroSprite::add_event);
	ClassDB::bind_method(D_METHOD("render_frame", "index"), &RetroSprite::render_frame);
	ClassDB::bind_method(D_METHOD("frame_info", "index"), &RetroSprite::frame_info);
	ClassDB::bind_method(D_METHOD("analyze"), &RetroSprite::analyze);
	ClassDB::bind_method(D_METHOD("to_dict"), &RetroSprite::to_dict);
	ClassDB::bind_method(D_METHOD("from_dict", "data"), &RetroSprite::from_dict);

	ClassDB::bind_method(D_METHOD("set_image", "image"), &RetroSprite::set_image);
	ClassDB::bind_method(D_METHOD("get_image"), &RetroSprite::get_image);
	ClassDB::bind_method(D_METHOD("set_palette", "palette"), &RetroSprite::set_palette);
	ClassDB::bind_method(D_METHOD("get_palette"), &RetroSprite::get_palette);
	ClassDB::bind_method(D_METHOD("set_name", "value"), &RetroSprite::set_name);
	ClassDB::bind_method(D_METHOD("get_name"), &RetroSprite::get_name);
	ClassDB::bind_method(D_METHOD("set_source_path", "value"), &RetroSprite::set_source_path);
	ClassDB::bind_method(D_METHOD("get_source_path"), &RetroSprite::get_source_path);
	ClassDB::bind_method(D_METHOD("set_platform", "value"), &RetroSprite::set_platform);
	ClassDB::bind_method(D_METHOD("get_platform"), &RetroSprite::get_platform);
	ClassDB::bind_method(D_METHOD("set_bpp", "value"), &RetroSprite::set_bpp);
	ClassDB::bind_method(D_METHOD("get_bpp"), &RetroSprite::get_bpp);
	ClassDB::bind_method(D_METHOD("set_tile_size", "value"), &RetroSprite::set_tile_size);
	ClassDB::bind_method(D_METHOD("get_tile_size"), &RetroSprite::get_tile_size);
	ClassDB::bind_method(D_METHOD("set_origin", "value"), &RetroSprite::set_origin);
	ClassDB::bind_method(D_METHOD("get_origin"), &RetroSprite::get_origin);
	ClassDB::bind_method(D_METHOD("set_frames", "value"), &RetroSprite::set_frames);
	ClassDB::bind_method(D_METHOD("get_frames"), &RetroSprite::get_frames);
	ClassDB::bind_method(D_METHOD("set_animations", "value"), &RetroSprite::set_animations);
	ClassDB::bind_method(D_METHOD("get_animations"), &RetroSprite::get_animations);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "image", PROPERTY_HINT_RESOURCE_TYPE, "Image"), "set_image", "get_image");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_COLOR_ARRAY, "palette"), "set_palette", "get_palette");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name"), "set_name", "get_name");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "source_path"), "set_source_path", "get_source_path");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "platform"), "set_platform", "get_platform");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "bpp"), "set_bpp", "get_bpp");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "tile_size"), "set_tile_size", "get_tile_size");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "origin"), "set_origin", "get_origin");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "frames"), "set_frames", "get_frames");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "animations"), "set_animations", "get_animations");
}

Ref<RetroSprite> RetroSprite::from_image(const Ref<Image> &p_image, const String &p_name) {
	Ref<RetroSprite> s;
	s.instantiate();
	s->name = p_name;
	s->image = p_image;
	if (p_image.is_valid()) {
		s->frame_width = p_image->get_width();
		s->frame_height = p_image->get_height();
		s->palette = RetroGraphics::extract_palette(p_image, 16, true);
	}
	return s;
}

Error RetroSprite::load_image(const String &p_path) {
	Ref<Image> img = Image::load_from_file(p_path);
	if (img.is_null()) {
		return ERR_FILE_CANT_READ;
	}
	img->convert(Image::FORMAT_RGBA8);
	image = img;
	source_path = p_path;
	name = p_path.get_file().get_basename();
	frame_width = img->get_width();
	frame_height = img->get_height();
	palette = RetroGraphics::read_png_palette(p_path);
	if (palette.is_empty()) {
		palette = RetroGraphics::extract_palette(img, platform == "megadrive" ? 16 : 16, true);
	}
	return OK;
}

Error RetroSprite::load_snes(const String &p_chr_path, const String &p_palette_path, int p_tiles_x, int p_bpp) {
	const Vector<uint8_t> chr = RetroUtil::read_bytes(p_chr_path);
	if (chr.is_empty()) {
		return ERR_FILE_CANT_READ;
	}
	PackedByteArray pal_bytes = RetroUtil::read_bytes(p_palette_path);
	palette = RetroGraphics::decode_palette(pal_bytes, platform == "megadrive");
	if (palette.is_empty()) {
		palette.push_back(Color(0, 0, 0, 0));
	}
	PackedByteArray data = chr;
	bpp = p_bpp;
	image = RetroGraphics::decode_tiles(data, p_tiles_x, p_bpp, palette, tile_size, platform == "megadrive");
	if (image.is_null()) {
		return ERR_INVALID_DATA;
	}
	source_path = p_chr_path;
	name = p_chr_path.get_file().get_basename();
	frame_width = image->get_width();
	frame_height = image->get_height();
	return OK;
}

Error RetroSprite::load_sgdk(const String &p_png_path) {
	platform = "megadrive";
	return load_image(p_png_path);
}

Error RetroSprite::save_png(const String &p_path) {
	if (image.is_null()) {
		return ERR_UNCONFIGURED;
	}
	if (!palette.is_empty() && palette.size() <= 256) {
		return RetroGraphics::save_indexed_png(p_path, image, palette);
	}
	return image->save_png(p_path);
}

Error RetroSprite::save(const String &p_path) {
	return RetroUtil::save_json_file(p_path, to_dict());
}

Error RetroSprite::load(const String &p_path) {
	bool ok = false;
	const Dictionary d = RetroUtil::parse_json_file(p_path, &ok);
	if (!ok) {
		return ERR_FILE_CANT_READ;
	}
	from_dict(d);
	return OK;
}

void RetroSprite::split_grid(int p_frame_w, int p_frame_h, int p_start) {
	if (image.is_null() || p_frame_w <= 0 || p_frame_h <= 0) {
		return;
	}
	int idx = p_start;
	for (int y = 0; y + p_frame_h <= image->get_height(); y += p_frame_h) {
		for (int x = 0; x + p_frame_w <= image->get_width(); x += p_frame_w) {
			Dictionary f;
			f["name"] = "frame_" + itos(idx);
			f["rect"] = Rect2i(x, y, p_frame_w, p_frame_h);
			f["duration"] = 6;
			f["hitboxes"] = Array();
			f["events"] = Array();
			frames.push_back(f);
			idx++;
		}
	}
	frame_width = p_frame_w;
	frame_height = p_frame_h;
}

void RetroSprite::add_frame(const String &p_name, const Rect2i &p_rect, int p_duration) {
	Dictionary f;
	f["name"] = p_name;
	f["rect"] = p_rect;
	f["duration"] = p_duration;
	f["hitboxes"] = Array();
	f["events"] = Array();
	frames.push_back(f);
}

void RetroSprite::remove_frame(int p_index) {
	if (p_index >= 0 && p_index < frames.size()) {
		frames.remove_at(p_index);
	}
}

void RetroSprite::add_hitbox(int p_frame, const Rect2i &p_rect, const String &p_type) {
	if (p_frame < 0 || p_frame >= frames.size()) {
		return;
	}
	Dictionary f = frames[p_frame];
	Array boxes = f.get("hitboxes", Array());
	Dictionary b;
	b["rect"] = p_rect;
	b["type"] = p_type;
	boxes.push_back(b);
	f["hitboxes"] = boxes;
	frames[p_frame] = f;
}

void RetroSprite::add_event(int p_frame, const String &p_type, const String &p_value) {
	if (p_frame < 0 || p_frame >= frames.size()) {
		return;
	}
	Dictionary f = frames[p_frame];
	Array events = f.get("events", Array());
	Dictionary e;
	e["type"] = p_type;
	e["value"] = p_value;
	events.push_back(e);
	f["events"] = events;
	frames[p_frame] = f;
}

Ref<Image> RetroSprite::render_frame(int p_index) {
	if (image.is_null() || p_index < 0 || p_index >= frames.size()) {
		return Ref<Image>();
	}
	const Dictionary f = frames[p_index];
	const Rect2i r = f.get("rect", Rect2i(0, 0, image->get_width(), image->get_height()));
	Ref<Image> out = Image::create_empty(r.size.x, r.size.y, false, Image::FORMAT_RGBA8);
	out->fill(Color(0, 0, 0, 0));
	Ref<Image> src = image;
	if (src->get_format() != Image::FORMAT_RGBA8) {
		src = src->duplicate();
		src->convert(Image::FORMAT_RGBA8);
	}
	for (int y = 0; y < r.size.y; y++) {
		for (int x = 0; x < r.size.x; x++) {
			const int sx = r.position.x + x;
			const int sy = r.position.y + y;
			if (sx >= 0 && sy >= 0 && sx < src->get_width() && sy < src->get_height()) {
				out->set_pixel(x, y, src->get_pixel(sx, sy));
			}
		}
	}
	return out;
}

Dictionary RetroSprite::frame_info(int p_index) {
	if (p_index < 0 || p_index >= frames.size()) {
		return Dictionary();
	}
	Dictionary f = frames[p_index];
	f["index"] = p_index;
	return f;
}

Dictionary RetroSprite::analyze() {
	Dictionary d;
	if (image.is_valid()) {
		d = RetroGraphics::analyze_image(image);
	}
	d["frames"] = frames.size();
	d["animations"] = animations.size();
	d["palette_size"] = palette.size();
	d["bpp"] = bpp;
	d["vram_bytes"] = image.is_valid() ? (image->get_width() / tile_size) * (image->get_height() / tile_size) * (bpp == 8 ? 64 : 32) : 0;
	return d;
}

Dictionary RetroSprite::export_snes(const String &p_dir, const String &p_base) {
	Dictionary result;
	if (image.is_null()) {
		result["ok"] = false;
		result["error"] = "no image loaded";
		return result;
	}
	DirAccess::make_dir_recursive_absolute(p_dir);
	PackedByteArray chr = RetroGraphics::encode_tiles(image, bpp, palette, tile_size, false);
	const String chr_path = RetroUtil::join(p_dir, p_base + ".chr");
	RetroUtil::write_bytes(chr_path, chr);
	const String pal_path = RetroUtil::join(p_dir, p_base + ".pal");
	RetroUtil::write_bytes(pal_path, RetroGraphics::encode_palette(palette, false));

	// Human-readable include with a per-frame table. Tile indices assume a
	// regular tile grid (tiles_x tiles per row).
	const int tiles_x = MAX(1, image->get_width() / tile_size);
	String inc;
	inc += "; Generated by Godot Retro Engine\n";
	inc += p_base + "_palette:\n\t.incbin \"" + p_base + ".pal\"\n";
	inc += p_base + "_tiles:\n\t.incbin \"" + p_base + ".chr\"\n";
	inc += p_base + "_frames:\n";
	for (int i = 0; i < frames.size(); i++) {
		const Dictionary f = frames[i];
		const Rect2i r = f.get("rect", Rect2i(0, 0, tile_size, tile_size));
		const int tx = r.position.x / tile_size;
		const int ty = r.position.y / tile_size;
		const int duration = f.get("duration", 6);
		inc += "\t.dw " + itos(tx) + ", " + itos(ty) + ", " + itos(MAX(1, r.size.x / tile_size)) + ", " + itos(MAX(1, r.size.y / tile_size)) + ", " + itos(duration) + "\n";
	}
	inc += p_base + "_frames_end:\n";
	inc += "; total tiles: " + itos(tiles_x) + " per row, " + itos(chr.size()) + " bytes\n";
	const String inc_path = RetroUtil::join(p_dir, p_base + "_sprite.inc");
	RetroUtil::write_text(inc_path, inc);

	result["ok"] = true;
	result["chr"] = chr_path;
	result["pal"] = pal_path;
	result["inc"] = inc_path;
	result["bytes"] = chr.size();
	result["palette_colors"] = palette.size();
	return result;
}

Dictionary RetroSprite::export_sgdk(const String &p_dir, const String &p_base, const String &p_res_file) {
	Dictionary result;
	if (image.is_null()) {
		result["ok"] = false;
		result["error"] = "no image loaded";
		return result;
	}
	DirAccess::make_dir_recursive_absolute(p_dir);
	const String png_path = RetroUtil::join(p_dir, p_base + ".png");
	const Error err = save_png(png_path);
	if (err != OK) {
		result["ok"] = false;
		result["error"] = "could not write PNG";
		return result;
	}
	const int fw = frame_width > 0 ? frame_width : tile_size;
	const int fh = frame_height > 0 ? frame_height : tile_size;
	const int cols = MAX(1, image->get_width() / fw);
	const int rows = MAX(1, image->get_height() / fh);
	String res_line = "SPRITE " + p_base + " \"" + png_path.get_file() + "\" " + itos(cols) + " " + itos(rows) + " FAST 5\n";
	String res_path = p_res_file;
	if (res_path.is_empty()) {
		res_path = RetroUtil::join(p_dir, p_base + ".res");
	}
	String existing = RetroUtil::read_text(res_path);
	if (!existing.contains(res_line)) {
		RetroUtil::write_text(res_path, existing + res_line);
	}
	result["ok"] = true;
	result["png"] = png_path;
	result["res"] = res_path;
	result["res_line"] = res_line;
	return result;
}

Dictionary RetroSprite::export_png_asset(const String &p_path) {
	Dictionary result;
	const Error err = save_png(p_path);
	result["ok"] = err == OK;
	result["path"] = p_path;
	result["palette_preserved"] = !palette.is_empty() && palette.size() <= 256;
	if (err != OK) {
		result["error"] = "write failed";
	}
	return result;
}

Dictionary RetroSprite::to_dict() const {
	Dictionary d;
	d["name"] = name;
	d["source_path"] = source_path;
	d["platform"] = platform;
	d["bpp"] = bpp;
	d["tile_size"] = tile_size;
	d["origin"] = Point2i(origin_x, origin_y);
	d["frame_width"] = frame_width;
	d["frame_height"] = frame_height;
	d["frames"] = frames;
	d["animations"] = animations;
	d["metadata"] = metadata;
	Array pal;
	for (int i = 0; i < palette.size(); i++) {
		pal.push_back(palette[i].to_html(true));
	}
	d["palette"] = pal;
	if (image.is_valid()) {
		Vector<uint8_t> png = image->save_png_to_buffer();
		d["image_png_base64"] = CoreBind::Marshalls::get_singleton()->raw_to_base64(png);
		d["width"] = image->get_width();
		d["height"] = image->get_height();
	}
	return d;
}

void RetroSprite::from_dict(const Dictionary &p_data) {
	name = p_data.get("name", name);
	source_path = p_data.get("source_path", source_path);
	platform = p_data.get("platform", platform);
	bpp = p_data.get("bpp", bpp);
	tile_size = p_data.get("tile_size", tile_size);
	const Point2i o = _retro_point2i(p_data.get("origin", Variant()));
	origin_x = o.x;
	origin_y = o.y;
	frame_width = p_data.get("frame_width", frame_width);
	frame_height = p_data.get("frame_height", frame_height);
	frames = p_data.get("frames", Array());
	for (int i = 0; i < frames.size(); i++) {
		Dictionary f = frames[i];
		if (f.has("rect")) {
			f["rect"] = _retro_rect2i(f["rect"]);
		}
		Array boxes = f.get("hitboxes", Array());
		for (int b = 0; b < boxes.size(); b++) {
			Dictionary box = boxes[b];
			if (box.has("rect")) {
				box["rect"] = _retro_rect2i(box["rect"]);
				boxes[b] = box;
			}
		}
		f["hitboxes"] = boxes;
		frames[i] = f;
	}
	animations = p_data.get("animations", Dictionary());
	metadata = p_data.get("metadata", Dictionary());
	palette.clear();
	const Array pal = p_data.get("palette", Array());
	for (int i = 0; i < pal.size(); i++) {
		palette.push_back(Color::from_string(String(pal[i]), Color()));
	}
	if (p_data.has("image_png_base64")) {
		const Vector<uint8_t> png = CoreBind::Marshalls::get_singleton()->base64_to_raw(String(p_data["image_png_base64"]));
		Ref<Image> img = Image::create_empty(1, 1, false, Image::FORMAT_RGBA8);
		img->load_png_from_buffer(png);
		if (img.is_valid()) {
			image = img;
		}
	}
}
