/**************************************************************************/
/*  retro_hardware.cpp                                                    */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_hardware.h"

#include "retro_sdk.h"

void RetroHardware::_bind_methods() {
	ClassDB::bind_static_method("RetroHardware", D_METHOD("specs", "platform", "mode"), &RetroHardware::specs, DEFVAL(String()));
	ClassDB::bind_static_method("RetroHardware", D_METHOD("estimate", "platform", "usage"), &RetroHardware::estimate);
	ClassDB::bind_static_method("RetroHardware", D_METHOD("sprite_line_check", "platform", "sprites", "line_width"), &RetroHardware::sprite_line_check, DEFVAL(0));
	ClassDB::bind_static_method("RetroHardware", D_METHOD("validate_stage", "platform", "mode", "stage"), &RetroHardware::validate_stage);
	ClassDB::bind_static_method("RetroHardware", D_METHOD("compare", "platform"), &RetroHardware::compare);
}

Dictionary RetroHardware::specs(const String &p_platform, const String &p_mode) {
	RetroSDK *sdk = RetroSDK::get_singleton();
	if (!sdk) {
		return Dictionary();
	}
	return sdk->get_limits(p_platform, p_mode);
}

Dictionary RetroHardware::estimate(const String &p_platform, const Dictionary &p_usage) {
	Dictionary out;
	const Dictionary spec = specs(p_platform, p_usage.get("mode", String()));
	if (spec.is_empty()) {
		return out;
	}
	Array issues;
	Array notes;

	const int tile_size = p_usage.get("tile_size", 8);
	const int bpp = p_usage.get("bpp", p_platform == "snes" ? 4 : 4);
	const int tile_count = p_usage.get("tile_count", 0);
	const int map_w = p_usage.get("map_w", 0);
	const int map_h = p_usage.get("map_h", 0);
	const int layers = p_usage.get("layers", 1);
	const int sprite_count = p_usage.get("sprites", 0);
	const int palette_colors = p_usage.get("palette_colors", 16);
	const int sprite_w = p_usage.get("sprite_w", 16);
	const int sprite_h = p_usage.get("sprite_h", 16);
	const int rom_bytes = p_usage.get("rom_bytes", 0);

	const int tile_bytes = (bpp == 8) ? 64 : (tile_size * tile_size * bpp) / 8;
	const int64_t vram_tiles = int64_t(tile_count) * tile_bytes;
	const int64_t vram_maps = int64_t(map_w) * int64_t(map_h) * 2 * MAX(1, layers);
	const int64_t vram_sprites = int64_t(sprite_count) * int64_t(MAX(1, sprite_w) * MAX(1, sprite_h) / (tile_size * tile_size)) * tile_bytes;
	const int64_t vram_total = vram_tiles + vram_maps + vram_sprites;
	const int64_t pal_bytes = int64_t(palette_colors) * 2;
	const int64_t vram_capacity = int64_t(spec.get("vram_bytes", 65536));
	const int max_colors = spec.get("palette_colors", 256);

	out["platform"] = p_platform;
	out["tile_bytes"] = tile_bytes;
	out["vram_tiles"] = int64_t(vram_tiles);
	out["vram_maps"] = int64_t(vram_maps);
	out["vram_sprites"] = int64_t(vram_sprites);
	out["vram_total"] = int64_t(vram_total);
	out["vram_capacity"] = int64_t(vram_capacity);
	out["vram_percent"] = double(vram_total) * 100.0 / double(vram_capacity);
	out["palette_bytes"] = int64_t(pal_bytes);
	out["palette_capacity"] = int64_t(spec.get("palette_colors", 256));
	out["palette_percent"] = double(palette_colors) * 100.0 / double(MAX(1, max_colors));
	out["rom_bytes"] = int64_t(rom_bytes);
	out["rom_capacity"] = int64_t(spec.get("max_rom_bytes", 1));

	if (vram_total > vram_capacity) {
		issues.push_back("VRAM over budget: " + itos(vram_total) + " / " + itos(vram_capacity) + " bytes.");
	}
	if (palette_colors > max_colors) {
		issues.push_back("Palette colors exceed console limit: " + itos(palette_colors) + " / " + itos(max_colors) + ".");
	}
	if (p_platform == "snes") {
		const int bg_layers = spec.get("bg_layers", 1);
		if (layers > bg_layers) {
			issues.push_back("Too many BG layers for " + String(spec.get("mode", "mode1")) + ": " + itos(layers) + " / " + itos(bg_layers) + ".");
		}
		const int sprite_limit = spec.get("sprites_total", 128);
		if (sprite_count > sprite_limit) {
			issues.push_back("Sprite count exceeds OAM limit: " + itos(sprite_count) + " / " + itos(sprite_limit) + ".");
		}
		if (bpp == 8 && String(spec.get("mode", "")) != "mode7") {
			issues.push_back("8bpp background tiles require Mode 7 on SNES.");
		}
	} else {
		if (sprite_count > int(spec.get("sprites_total", 80))) {
			issues.push_back("Sprite count exceeds VDP limit: " + itos(sprite_count) + " / 80.");
		}
		if (palette_colors > 64) {
			issues.push_back("CRAM holds only 64 colors (4 palettes x 16).");
		}
	}
	if (rom_bytes > int(spec.get("max_rom_bytes", 4194304))) {
		issues.push_back("ROM size exceeds the mapper limit for this configuration.");
	}
	if (map_w * tile_size > 2048) {
		notes.push_back("Large map: verify streaming/compression strategy; the PPU/VDP cannot display the full map at once.");
	}
	out["issues"] = issues;
	out["notes"] = notes;
	out["ok"] = issues.is_empty();
	return out;
}

Dictionary RetroHardware::sprite_line_check(const String &p_platform, const Array &p_sprites, int p_line_width) {
	Dictionary out;
	const Dictionary spec = specs(p_platform);
	const int per_line = spec.get("sprites_per_line", p_platform == "snes" ? 32 : 20);
	const int width = p_line_width > 0 ? p_line_width : int(spec.get("native_width", 320));
	Array counts;
	counts.resize(width);
	for (int i = 0; i < width; i++) {
		counts[i] = 0;
	}
	for (int i = 0; i < p_sprites.size(); i++) {
		const Dictionary s = p_sprites[i];
		const int x = s.get("x", 0);
		const int w = s.get("w", 8);
		for (int px = MAX(0, x); px < MIN(width, x + w); px++) {
			counts[px] = int(counts[px]) + 1;
		}
	}
	int worst = 0;
	int worst_x = 0;
	for (int i = 0; i < width; i++) {
		if (int(counts[i]) > worst) {
			worst = int(counts[i]);
			worst_x = i;
		}
	}
	out["limit_per_line"] = per_line;
	out["worst_count"] = worst;
	out["worst_x"] = worst_x;
	out["over_limit"] = worst > per_line;
	out["counts"] = counts;
	return out;
}

Dictionary RetroHardware::validate_stage(const String &p_platform, const String &p_mode, const Dictionary &p_stage) {
	Dictionary usage;
	usage["mode"] = p_mode;
	usage["tile_size"] = p_stage.get("tile_size", 8);
	usage["bpp"] = p_stage.get("bpp", 4);
	usage["tile_count"] = p_stage.get("tile_count", 256);
	usage["map_w"] = p_stage.get("map_w", 32);
	usage["map_h"] = p_stage.get("map_h", 32);
	usage["layers"] = p_stage.get("layers", 1);
	usage["palette_colors"] = p_stage.get("palette_colors", 16);
	usage["sprites"] = p_stage.get("sprites", 0);
	usage["rom_bytes"] = p_stage.get("rom_bytes", 0);
	Dictionary out = estimate(p_platform, usage);
	Array issues = out.get("issues", Array());
	if (p_platform == "snes" && p_mode == "mode7") {
		if (int(p_stage.get("map_w", 0)) > 128 || int(p_stage.get("map_h", 0)) > 128) {
			issues.push_back("Mode 7 tilemap is limited to 128x128 tiles (1024x1024 pixels).");
		}
		if (int(p_stage.get("tile_size", 8)) != 8) {
			issues.push_back("Mode 7 requires 8x8 tiles.");
		}
	}
	if (p_platform == "megadrive") {
		if (int(p_stage.get("map_w", 0)) > 128 || int(p_stage.get("map_h", 0)) > 128) {
			issues.push_back("VDP nametable addressing is limited to 128x128 cells in the largest plane layout.");
		}
	}
	out["issues"] = issues;
	out["ok"] = issues.is_empty();
	return out;
}

Array RetroHardware::compare(const String &p_platform) {
	Array out;
	const String other = p_platform == "snes" ? "megadrive" : "snes";
	out.push_back(specs(p_platform));
	out.push_back(specs(other));
	return out;
}
