/**************************************************************************/
/*  retro_stage.h - tile map / background / layer editor document         */
/**************************************************************************/

#ifndef RETRO_STAGE_H
#define RETRO_STAGE_H

#include "core/io/image.h"
#include "core/object/ref_counted.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

class RetroStage : public RefCounted {
	GDCLASS(RetroStage, RefCounted);

	String name = "stage";
	String platform = "snes";
	String mode = "mode1";
	Ref<Image> tileset;
	Ref<Image> tile_indices;
	PackedColorArray palette;
	PackedByteArray map;
	int map_w = 32;
	int map_h = 32;
	int tile_size = 8;
	int bpp = 4;
	int tiles_x = 16;
	bool column_major = false;
	Dictionary scroll; // {"h": bool, "v": bool, "speed_x": float, "speed_y": float}
	Dictionary camera_limits;
	Array layers; // {"name", "map", "parallax", "priority", "visible"}
	Array collisions; // Rect2i
	Dictionary metadata;
	Array source_palette_paths;

protected:
	static void _bind_methods();

public:
	Error load_snes(const String &p_tiles_path, const String &p_map_path, const String &p_palette_path,
			int p_map_w = 32, int p_map_h = 32, int p_tile_size = 8, int p_bpp = 4, int p_tiles_x = 16,
			bool p_column_major = false);
	Error load_image_tileset(const String &p_tiles_path, const String &p_map_path, int p_map_w, int p_map_h, int p_tile_size);
	Error save(const String &p_path);
	Error load(const String &p_path);

	Ref<Image> render();
	Ref<Image> render_region(int p_x, int p_y, int p_w, int p_h);
	Dictionary export_snes(const String &p_dir, const String &p_base);
	Dictionary export_sgdk(const String &p_dir, const String &p_base, const String &p_res_file = String());
	Dictionary analyze();

	int get_tile(int p_x, int p_y);
	void set_tile(int p_x, int p_y, int p_tile, int p_palette = 0, int p_flip_h = 0, int p_flip_v = 0, int p_priority = 0);
	Dictionary get_tile_info(int p_x, int p_y);
	void add_layer(const String &p_name, const PackedByteArray &p_map);
	void paint_rect(int p_x, int p_y, int p_w, int p_h, int p_tile, int p_palette = 0);
	Dictionary to_dict() const;
	void from_dict(const Dictionary &p_data);

	void set_name(const String &p_value) { name = p_value; }
	String get_name() const { return name; }
	void set_platform(const String &p_value) { platform = p_value; }
	String get_platform() const { return platform; }
	void set_mode(const String &p_value) { mode = p_value; }
	String get_mode() const { return mode; }
	void set_tileset(const Ref<Image> &p_value) { tileset = p_value; }
	Ref<Image> get_tileset() const { return tileset; }
	void set_tile_indices(const Ref<Image> &p_value) { tile_indices = p_value; }
	Ref<Image> get_tile_indices() const { return tile_indices; }
	void set_palette(const PackedColorArray &p_value) { palette = p_value; }
	PackedColorArray get_palette() const { return palette; }
	void set_map(const PackedByteArray &p_value) { map = p_value; }
	PackedByteArray get_map() const { return map; }
	void set_map_size(const Point2i &p_size) { map_w = p_size.x; map_h = p_size.y; }
	Point2i get_map_size() const { return Point2i(map_w, map_h); }
	void set_tile_size(int p_value) { tile_size = p_value; }
	int get_tile_size() const { return tile_size; }
	void set_bpp(int p_value) { bpp = p_value; }
	int get_bpp() const { return bpp; }
	void set_tiles_x(int p_value) { tiles_x = MAX(1, p_value); }
	int get_tiles_x() const { return tiles_x; }
	void set_column_major(bool p_value) { column_major = p_value; }
	bool get_column_major() const { return column_major; }
	void set_scroll(const Dictionary &p_value) { scroll = p_value; }
	Dictionary get_scroll() const { return scroll; }
	void set_camera_limits(const Dictionary &p_value) { camera_limits = p_value; }
	Dictionary get_camera_limits() const { return camera_limits; }
	void set_layers(const Array &p_value) { layers = p_value; }
	Array get_layers() const { return layers; }
	void set_collisions(const Array &p_value) { collisions = p_value; }
	Array get_collisions() const { return collisions; }
	void set_metadata(const Dictionary &p_value) { metadata = p_value; }
	Dictionary get_metadata() const { return metadata; }
};

#endif // RETRO_STAGE_H
