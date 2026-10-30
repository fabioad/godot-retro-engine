/**************************************************************************/
/*  retro_sprite.h - editable sprite sheet + animation metadata            */
/**************************************************************************/

#ifndef RETRO_SPRITE_H
#define RETRO_SPRITE_H

#include "core/io/image.h"
#include "core/object/ref_counted.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

class RetroSprite : public RefCounted {
	GDCLASS(RetroSprite, RefCounted);

	String name = "sprite";
	String source_path;
	String platform = "snes";
	Ref<Image> image;
	PackedColorArray palette;
	int bpp = 4;
	int tile_size = 8;
	int origin_x = 0;
	int origin_y = 0;
	int frame_width = 0;
	int frame_height = 0;
	Array frames;
	Dictionary animations;
	Dictionary metadata;

protected:
	static void _bind_methods();

public:
	static Ref<RetroSprite> from_image(const Ref<Image> &p_image, const String &p_name = "sprite");

	Error load_image(const String &p_path);
	Error load_snes(const String &p_chr_path, const String &p_palette_path, int p_tiles_x = 16, int p_bpp = 4);
	Error load_sgdk(const String &p_png_path);
	Error save_png(const String &p_path);
	Error save(const String &p_path);
	Error load(const String &p_path);

	Dictionary export_snes(const String &p_dir, const String &p_base);
	Dictionary export_sgdk(const String &p_dir, const String &p_base, const String &p_res_file = String());
	Dictionary export_png_asset(const String &p_path);

	void split_grid(int p_frame_w, int p_frame_h, int p_start = 0);
	void add_frame(const String &p_name, const Rect2i &p_rect, int p_duration = 6);
	void remove_frame(int p_index);
	void add_hitbox(int p_frame, const Rect2i &p_rect, const String &p_type = "hit");
	void add_event(int p_frame, const String &p_type, const String &p_value);
	Ref<Image> render_frame(int p_index);
	Dictionary frame_info(int p_index);
	Dictionary analyze();

	void set_image(const Ref<Image> &p_image) { image = p_image; }
	Ref<Image> get_image() const { return image; }
	void set_palette(const PackedColorArray &p_palette) { palette = p_palette; }
	PackedColorArray get_palette() const { return palette; }
	void set_name(const String &p_value) { name = p_value; }
	String get_name() const { return name; }
	void set_source_path(const String &p_value) { source_path = p_value; }
	String get_source_path() const { return source_path; }
	void set_platform(const String &p_value) { platform = p_value; }
	String get_platform() const { return platform; }
	void set_bpp(int p_value) { bpp = p_value; }
	int get_bpp() const { return bpp; }
	void set_tile_size(int p_value) { tile_size = p_value; }
	int get_tile_size() const { return tile_size; }
	void set_origin(const Point2i &p_value) { origin_x = p_value.x; origin_y = p_value.y; }
	Point2i get_origin() const { return Point2i(origin_x, origin_y); }
	void set_frames(const Array &p_value) { frames = p_value; }
	Array get_frames() const { return frames; }
	void set_animations(const Dictionary &p_value) { animations = p_value; }
	Dictionary get_animations() const { return animations; }
	Dictionary to_dict() const;
	void from_dict(const Dictionary &p_data);
};

#endif // RETRO_SPRITE_H
