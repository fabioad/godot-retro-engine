/**************************************************************************/
/*  retro_native_bridge.cpp                                               */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_native_bridge.h"

#include "retro_graphics.h"
#include "retro_util.h"

void RetroNativeBridge::_bind_methods() {
	ClassDB::bind_method(D_METHOD("import_image", "image", "name", "dir", "platform", "frame_w", "frame_h",
			"palette_colors", "bpp", "tile_size", "source_scene"), &RetroNativeBridge::import_image,
			DEFVAL(0), DEFVAL(0), DEFVAL(16), DEFVAL(4), DEFVAL(8), DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("import_stage_image", "image", "name", "dir", "platform", "mode",
			"tile_size", "max_tiles", "palette_colors", "source_scene"), &RetroNativeBridge::import_stage_image,
			DEFVAL("mode1"), DEFVAL(8), DEFVAL(1024), DEFVAL(16), DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("export_scene_layout", "actors", "scene_meta", "path", "platform"),
			&RetroNativeBridge::export_scene_layout, DEFVAL("snes"));
	ClassDB::bind_method(D_METHOD("get_3d_profile", "id"), &RetroNativeBridge::get_3d_profile);
	ClassDB::bind_method(D_METHOD("get_3d_profiles"), &RetroNativeBridge::get_3d_profiles);
	ClassDB::bind_method(D_METHOD("export_3d_manifest", "profile", "scene_meta", "actors", "bake", "path"),
			&RetroNativeBridge::export_3d_manifest);
}

static String _retro_native_escape(const String &p_text) {
	return p_text.replace("\\", "\\\\").replace("\"", "\\\"");
}

Dictionary RetroNativeBridge::import_image(const Ref<Image> &p_image, const String &p_name, const String &p_dir,
		const String &p_platform, int p_frame_w, int p_frame_h, int p_palette_colors,
		int p_bpp, int p_tile_size, const String &p_source_scene) {
	Dictionary result;
	if (p_image.is_null() || p_image->is_empty()) {
		result["ok"] = false;
		result["error"] = "image is empty";
		return result;
	}
	const int colors = CLAMP(p_palette_colors, 4, 16);
	Ref<Image> source = p_image->duplicate();
	if (source->get_format() != Image::FORMAT_RGBA8) {
		source->convert(Image::FORMAT_RGBA8);
	}
	Ref<Image> quantized = RetroGraphics::quantize(source, colors, true);
	if (quantized.is_null()) {
		result["ok"] = false;
		result["error"] = "palette quantization failed";
		return result;
	}
	Ref<RetroSprite> sprite = RetroSprite::from_image(quantized, p_name);
	sprite->set_platform(p_platform);
	sprite->set_bpp(CLAMP(p_bpp, 2, 8));
	sprite->set_tile_size(CLAMP(p_tile_size, 8, 64));
	sprite->set_source_path(p_source_scene);
	sprite->set_palette(RetroGraphics::extract_palette(quantized, colors, true));
	if (p_frame_w > 0 && p_frame_h > 0) {
		sprite->split_grid(p_frame_w, p_frame_h, 0);
	}
	if (sprite->get_frames().is_empty()) {
		sprite->add_frame("frame_0", Rect2i(0, 0, quantized->get_width(), quantized->get_height()), 6);
	}
	DirAccess::make_dir_recursive_absolute(p_dir);
	const String png = RetroUtil::join(p_dir, p_name + ".png");
	const String json = RetroUtil::join(p_dir, p_name + ".retro_sprite.json");
	const Error png_error = sprite->save_png(png);
	const Dictionary snes = sprite->export_snes(p_dir, p_name);
	const Dictionary sgdk = sprite->export_sgdk(p_dir, p_name);
	const Error save_error = sprite->save(json);
	result["ok"] = png_error == OK && bool(snes.get("ok", false)) && bool(sgdk.get("ok", false)) && save_error == OK;
	result["sprite"] = sprite;
	result["png"] = png;
	result["sprite_json"] = json;
	result["snes"] = snes;
	result["sgdk"] = sgdk;
	result["frames"] = sprite->get_frames().size();
	result["palette_colors"] = sprite->get_palette().size();
	result["analysis"] = sprite->analyze();
	return result;
}

Dictionary RetroNativeBridge::import_stage_image(const Ref<Image> &p_image, const String &p_name, const String &p_dir,
		const String &p_platform, const String &p_mode, int p_tile_size, int p_max_tiles,
		int p_palette_colors, const String &p_source_scene) {
	Dictionary result;
	if (p_image.is_null() || p_image->is_empty()) {
		result["ok"] = false;
		result["error"] = "image is empty";
		return result;
	}
	const int tile = CLAMP(p_tile_size, 8, 64);
	const int colors = CLAMP(p_palette_colors, 4, 16);
	Ref<Image> source = p_image->duplicate();
	if (source->get_format() != Image::FORMAT_RGBA8) {
		source->convert(Image::FORMAT_RGBA8);
	}
	bool has_transparency = false;
	for (int y = 0; y < source->get_height() && !has_transparency; y++) {
		for (int x = 0; x < source->get_width(); x++) {
			if (source->get_pixel(x, y).a < 0.5) {
				has_transparency = true;
				break;
			}
		}
	}
	Ref<Image> quantized = RetroGraphics::quantize(source, colors, has_transparency);
	if (quantized.is_null()) {
		result["ok"] = false;
		result["error"] = "palette quantization failed";
		return result;
	}
	const int map_w = MAX(1, quantized->get_width() / tile);
	const int map_h = MAX(1, quantized->get_height() / tile);
	const int max_tiles = CLAMP(p_max_tiles, 1, p_platform == "megadrive" ? 2048 : 1024);

	HashMap<String, int> tile_lookup;
	Vector<Ref<Image>> tile_images;
	Array warnings;
	Vector<int> cell_tile;
	cell_tile.resize(map_w * map_h);
	int dropped = 0;
	for (int ty = 0; ty < map_h; ty++) {
		for (int tx = 0; tx < map_w; tx++) {
			Ref<Image> cell = Image::create_empty(tile, tile, false, Image::FORMAT_RGBA8);
			cell->fill(Color(0, 0, 0, 0));
			String key;
			for (int y = 0; y < tile; y++) {
				for (int x = 0; x < tile; x++) {
					const int sx = tx * tile + x;
					const int sy = ty * tile + y;
					Color c = Color(0, 0, 0, 0);
					if (sx < quantized->get_width() && sy < quantized->get_height()) {
						c = quantized->get_pixel(sx, sy);
					}
					cell->set_pixel(x, y, c);
					key += String::num_uint64(uint64_t(c.to_rgba32()));
					key += ",";
				}
			}
			int index = -1;
			if (tile_lookup.has(key)) {
				index = tile_lookup[key];
			} else if (tile_images.size() < max_tiles) {
				index = tile_images.size();
				tile_lookup[key] = index;
				tile_images.push_back(cell);
			} else {
				index = 0;
				dropped++;
			}
			cell_tile.write[ty * map_w + tx] = index;
		}
	}
	if (tile_images.is_empty()) {
		Ref<Image> blank = Image::create_empty(tile, tile, false, Image::FORMAT_RGBA8);
		blank->fill(Color(0, 0, 0, 0));
		tile_images.push_back(blank);
	}
	const int tiles_x = 16;
	const int tile_rows = (tile_images.size() + tiles_x - 1) / tiles_x;
	Ref<Image> tileset = Image::create_empty(tiles_x * tile, MAX(1, tile_rows) * tile, false, Image::FORMAT_RGBA8);
	tileset->fill(Color(0, 0, 0, 0));
	for (int i = 0; i < tile_images.size(); i++) {
		const int dx = (i % tiles_x) * tile;
		const int dy = (i / tiles_x) * tile;
		tileset->blit_rect(tile_images[i], Rect2i(0, 0, tile, tile), Vector2i(dx, dy));
	}
	PackedColorArray palette = RetroGraphics::extract_palette(quantized, colors, has_transparency);
	Ref<RetroStage> stage;
	stage.instantiate();
	stage->set_name(p_name);
	stage->set_platform(p_platform);
	stage->set_mode(p_mode);
	stage->set_bpp(4);
	stage->set_tile_size(tile);
	stage->set_tiles_x(tiles_x);
	stage->set_map_size(Point2i(map_w, map_h));
	PackedByteArray map_data;
	map_data.resize(map_w * map_h * 2);
	stage->set_map(map_data);
	stage->set_tileset(tileset);
	stage->set_palette(palette);
	stage->set_metadata({{"source", p_source_scene}, {"native", true}});
	for (int y = 0; y < map_h; y++) {
		for (int x = 0; x < map_w; x++) {
			stage->set_tile(x, y, cell_tile[y * map_w + x]);
		}
	}
	DirAccess::make_dir_recursive_absolute(p_dir);
	const String tileset_png = RetroUtil::join(p_dir, p_name + "_tiles.png");
	const String json = RetroUtil::join(p_dir, p_name + ".retro_stage.json");
	const Error tiles_error = tileset->save_png(tileset_png);
	const Dictionary snes = stage->export_snes(p_dir, p_name);
	const Dictionary sgdk = stage->export_sgdk(p_dir, p_name);
	const Error save_error = stage->save(json);
	if (dropped > 0) {
		warnings.push_back(itos(dropped) + " tiles exceeded the platform tile budget and reuse tile 0");
	}
	result["ok"] = tiles_error == OK && bool(snes.get("ok", false)) && bool(sgdk.get("ok", false)) && save_error == OK;
	result["stage"] = stage;
	result["tileset_png"] = tileset_png;
	result["stage_json"] = json;
	result["map_w"] = map_w;
	result["map_h"] = map_h;
	result["tiles"] = tile_images.size();
	result["palette_colors"] = palette.size();
	result["snes"] = snes;
	result["sgdk"] = sgdk;
	result["warnings"] = warnings;
	return result;
}

Dictionary RetroNativeBridge::export_scene_layout(const Array &p_actors, const Dictionary &p_scene_meta,
		const String &p_path, const String &p_platform) {
	Dictionary result;
	String path = p_path;
	if (!path.ends_with(".h")) {
		path = RetroUtil::join(path, String(p_scene_meta.get("name", "native_scene")) + "_scene.h");
	}
	String scene_name = String(p_scene_meta.get("name", path.get_file().get_basename()));
	String out;
	out += "/* Generated by Godot Retro Engine native scene bridge. */\n";
	out += "#ifndef RETRO_NATIVE_SCENE_H\n#define RETRO_NATIVE_SCENE_H\n\n";
	out += "typedef signed short retro_native_s16;\n";
	out += "typedef unsigned char retro_native_u8;\n\n";
	out += "#define RETRO_NATIVE_ACTOR_COUNT " + itos(p_actors.size()) + "\n";
	out += "#define RETRO_NATIVE_SCENE_WIDTH " + itos(int(p_scene_meta.get("width", 256))) + "\n";
	out += "#define RETRO_NATIVE_SCENE_HEIGHT " + itos(int(p_scene_meta.get("height", 224))) + "\n";
	out += "typedef struct { const char *name; retro_native_s16 x, y, z; retro_native_u8 type; const char *asset; const char *animation; } RetroNativeActor;\n\n";
	out += "static const RetroNativeActor retro_native_actors[" + itos(MAX(1, p_actors.size())) + "] = {\n";
	for (int i = 0; i < p_actors.size(); i++) {
		const Dictionary a = p_actors[i];
		const Vector3 pos = a.get("position", Vector3());
		out += "\t{ \"" + _retro_native_escape(String(a.get("name", "actor"))) + "\", " +
				itos(int(pos.x)) + ", " + itos(int(pos.y)) + ", " + itos(int(pos.z)) + ", " +
				itos(int(a.get("type", 0))) + ", \"" + _retro_native_escape(String(a.get("asset", ""))) +
				"\", \"" + _retro_native_escape(String(a.get("animation", ""))) + "\" },\n";
	}
	if (p_actors.is_empty()) {
		out += "\t{ \"\", 0, 0, 0, 0, \"\", \"\" },\n";
	}
	out += "};\n\n";
	out += "static const char *retro_native_scene_name = \"" + _retro_native_escape(scene_name) + "\";\n";
	out += "static const char *retro_native_scene_source = \"" + _retro_native_escape(String(p_scene_meta.get("source", ""))) + "\";\n";
	out += "static const char *retro_native_scene_platform = \"" + _retro_native_escape(p_platform) + "\";\n\n#endif\n";
	DirAccess::make_dir_recursive_absolute(path.get_base_dir());
	const Error write_error = RetroUtil::write_text(path, out);
	Dictionary json;
	json["format"] = "godot-retro-engine/native-scene";
	json["version"] = 1;
	json["platform"] = p_platform;
	json["meta"] = p_scene_meta;
	json["actors"] = p_actors;
	const String json_path = path.get_basename() + ".json";
	const Error json_error = RetroUtil::save_json_file(json_path, json);
	result["ok"] = write_error == OK && json_error == OK;
	result["header"] = path;
	result["json"] = json_path;
	result["actors"] = p_actors.size();
	return result;
}


static Dictionary _retro_3d_profile_superfx() {
	Dictionary d;
	d["id"] = "superfx";
	d["name"] = "Super FX / GSU (Star Fox reference)";
	d["platform"] = "snes";
	d["chip"] = "Super FX (MARIO Chip 1 / GSU-1)";
	d["reference"] = "Star Fox (1993)";
	d["clock"] = "10.74 MHz (MARIO Chip 1) / 21.47 MHz (GSU-1)";
	d["rom_mbit"] = 8;
	d["work_ram_kbit"] = 256;
	d["framebuffer"] = "224x192 4bpp";
	d["target_fps"] = 20;
	d["max_capture_w"] = 224;
	d["max_capture_h"] = 192;
	d["palette_colors"] = 16;
	d["max_bake_frames"] = 16;
	d["max_tile_budget"] = 1024;
	d["note"] = "3D scenes are baked to 2D sprite sheets for the base SNES. The chip profile is a frame-budget and asset reference; this build does not execute GSU code.";
	return d;
}

static Dictionary _retro_3d_profile_svp() {
	Dictionary d;
	d["id"] = "svp";
	d["name"] = "Sega Virtua Processor (Virtua Racing reference)";
	d["platform"] = "megadrive";
	d["chip"] = "SVP (Samsung SSP160x DSP)";
	d["reference"] = "Virtua Racing (1994)";
	d["clock"] = "23 MHz";
	d["rom_mbit"] = 16;
	d["work_ram_kb"] = 128;
	d["iram_kb"] = 2;
	d["framebuffer"] = "320x224 tile-converted";
	d["target_fps"] = 15;
	d["polygons_per_frame"] = 600;
	d["max_capture_w"] = 320;
	d["max_capture_h"] = 224;
	d["palette_colors"] = 16;
	d["max_bake_frames"] = 16;
	d["max_tile_budget"] = 2048;
	d["note"] = "3D scenes are baked to 2D sprite sheets for the base Mega Drive. The chip profile is a polygon/frame-budget reference; this build does not execute SVP DSP code.";
	return d;
}

static Dictionary _retro_3d_profile_sega32x() {
	Dictionary d;
	d["id"] = "sega32x";
	d["name"] = "Sega 32X (SH-2 dual + VDP32X)";
	d["platform"] = "megadrive";
	d["chip"] = "2x Hitachi SH-2 + Sega 32X VDP";
	d["reference"] = "Virtua Racing Deluxe / Star Wars Arcade";
	d["clock"] = "2x 23 MHz";
	d["rom_mbit"] = 32;
	d["work_ram_kb"] = 256;
	d["framebuffer"] = "320x224 15-bit";
	d["target_fps"] = 30;
	d["polygons_per_frame"] = 1200;
	d["max_capture_w"] = 320;
	d["max_capture_h"] = 224;
	d["palette_colors"] = 256;
	d["max_bake_frames"] = 32;
	d["max_tile_budget"] = 4096;
	d["note"] = "The 32X is an add-on with two SH-2 CPUs and the VDP32X. This profile exports geometry, assets and SH-2/68000 scaffold files; an SH-2 toolchain is not embedded.";
	return d;
}

Array RetroNativeBridge::get_3d_profiles() const {
	Array out;
	out.push_back(_retro_3d_profile_superfx());
	out.push_back(_retro_3d_profile_svp());
	out.push_back(_retro_3d_profile_sega32x());
	return out;
}

Dictionary RetroNativeBridge::get_3d_profile(const String &p_id) const {
	if (p_id == "superfx") return _retro_3d_profile_superfx();
	if (p_id == "svp") return _retro_3d_profile_svp();
	if (p_id == "sega32x") return _retro_3d_profile_sega32x();
	return Dictionary();
}

Dictionary RetroNativeBridge::export_3d_manifest(const String &p_profile, const Dictionary &p_scene_meta,
		const Array &p_actors, const Dictionary &p_bake, const String &p_path) const {
	Dictionary result;
	const Dictionary profile = get_3d_profile(p_profile);
	if (profile.is_empty()) {
		result["ok"] = false;
		result["error"] = "unknown 3D profile: " + p_profile;
		return result;
	}
	const String platform = String(profile.get("platform", "snes"));
	String path = p_path;
	if (!path.ends_with(".h")) {
		path = RetroUtil::join(path, String(p_scene_meta.get("name", "native_3d")) + "_3d_profile.h");
	}
	Array warnings;
	const int scene_w = int(p_scene_meta.get("width", profile.get("max_capture_w", 256)));
	const int scene_h = int(p_scene_meta.get("height", profile.get("max_capture_h", 224)));
	if (scene_w > int(profile.get("max_capture_w", 256)) || scene_h > int(profile.get("max_capture_h", 224))) {
		warnings.push_back("Scene capture " + itos(scene_w) + "x" + itos(scene_h) + " exceeds the reference framebuffer budget");
	}
	const int frames = int(p_bake.get("frames", 0));
	if (frames > int(profile.get("max_bake_frames", 16))) {
		warnings.push_back("Bake has " + itos(frames) + " frames; reference budget is " + itos(int(profile.get("max_bake_frames", 16))));
	}
	const int actor_count = p_actors.size();
	const bool snes = platform == "snes";
	String out;
	out += "/* Generated by Godot Retro Engine 3D reference profile. */\n";
	out += "#ifndef RETRO_3D_PROFILE_H\n#define RETRO_3D_PROFILE_H\n\n";
	out += "#define RETRO_3D_CHIP_" + String(p_profile).to_upper() + " 1\n";
	out += "#define RETRO_3D_SCENE_WIDTH " + itos(scene_w) + "\n";
	out += "#define RETRO_3D_SCENE_HEIGHT " + itos(scene_h) + "\n";
	out += "#define RETRO_3D_ACTOR_COUNT " + itos(actor_count) + "\n";
	out += "#define RETRO_3D_BAKE_FRAMES " + itos(frames) + "\n";
	out += "#define RETRO_3D_TARGET_FPS " + itos(int(profile.get("target_fps", 20))) + "\n";
	out += "#define RETRO_3D_PALETTE_COLORS " + itos(int(profile.get("palette_colors", 16))) + "\n";
	out += "#define RETRO_3D_MAX_TILE_BUDGET " + itos(int(profile.get("max_tile_budget", 1024))) + "\n\n";
	out += "typedef signed short retro_3d_s16;\n";
	out += "typedef unsigned char retro_3d_u8;\n\n";
	out += "typedef struct { const char *name; retro_3d_s16 x, y, z; retro_3d_u8 type; const char *asset; const char *animation; } Retro3DActor;\n\n";
	out += "static const Retro3DActor retro_3d_actors[" + itos(MAX(1, actor_count)) + "] = {\n";
	for (int i = 0; i < actor_count; i++) {
		const Dictionary a = p_actors[i];
		const Vector3 pos = a.get("position", Vector3());
		out += "\t{ \"" + _retro_native_escape(String(a.get("name", "actor"))) + "\", " +
				itos(int(pos.x)) + ", " + itos(int(pos.y)) + ", " + itos(int(pos.z)) + ", " +
				itos(int(a.get("type", 0))) + ", \"" + _retro_native_escape(String(a.get("asset", ""))) +
				"\", \"" + _retro_native_escape(String(a.get("animation", ""))) + "\" },\n";
	}
	if (actor_count == 0) {
		out += "\t{ \"\", 0, 0, 0, 0, \"\", \"\" },\n";
	}
	out += "};\n\n";
	out += "static const char *retro_3d_profile_name = \"" + _retro_native_escape(String(profile.get("name", p_profile))) + "\";\n";
	out += "static const char *retro_3d_chip = \"" + _retro_native_escape(String(profile.get("chip", ""))) + "\";\n";
	out += "static const char *retro_3d_reference = \"" + _retro_native_escape(String(profile.get("reference", ""))) + "\";\n";
	out += "static const char *retro_3d_note = \"" + _retro_native_escape(String(profile.get("note", ""))) + "\";\n\n#endif\n";
	DirAccess::make_dir_recursive_absolute(path.get_base_dir());
	const Error header_error = RetroUtil::write_text(path, out);
	Dictionary json;
	json["format"] = "godot-retro-engine/3d-profile";
	json["version"] = 1;
	json["profile"] = profile;
	json["platform"] = platform;
	json["scene"] = p_scene_meta;
	json["actors"] = p_actors;
	json["bake"] = p_bake;
	json["warnings"] = warnings;
	json["conversion"] = "3d-to-2d sprites";
	const String json_path = path.get_basename() + ".json";
	const Error json_error = RetroUtil::save_json_file(json_path, json);
	result["ok"] = header_error == OK && json_error == OK;
	result["header"] = path;
	result["json"] = json_path;
	result["profile"] = profile;
	result["warnings"] = warnings;
	result["actors"] = actor_count;
	return result;
}
