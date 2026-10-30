/**************************************************************************/
/*  retro_graphics.h - console-native tile / palette conversions          */
/**************************************************************************/

#ifndef RETRO_GRAPHICS_H
#define RETRO_GRAPHICS_H

#include "core/io/image.h"
#include "core/object/object.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

class RetroGraphics : public Object {
	GDCLASS(RetroGraphics, Object);

protected:
	static void _bind_methods();

public:
	// Palettes. SNES uses 15-bit BGR555 little-endian, Mega Drive uses
	// 9-bit 0BGR big-endian words (as written to CRAM).
	static PackedColorArray decode_palette(const PackedByteArray &p_data, bool p_megadrive, int p_count = 0);
	static PackedByteArray encode_palette(const PackedColorArray &p_colors, bool p_megadrive);

	// Tiles. SNES: planar 2/4/8 bpp, MD: interleaved 4 bpp.
	static Ref<Image> decode_tiles(const PackedByteArray &p_data, int p_tiles_x, int p_bpp,
			const PackedColorArray &p_palette, int p_tile_size = 8, bool p_megadrive = false);
	static Ref<Image> decode_tiles_indexed(const PackedByteArray &p_data, int p_tiles_x, int p_bpp,
			int p_tile_size = 8, bool p_megadrive = false);
	static PackedByteArray encode_tiles(const Ref<Image> &p_image, int p_bpp,
			const PackedColorArray &p_palette, int p_tile_size = 8, bool p_megadrive = false);
	static PackedByteArray encode_tiles_indexed(const Ref<Image> &p_indices, int p_bpp,
			int p_tile_size = 8, bool p_megadrive = false);

	// Tile maps.
	static Array decode_tilemap(const PackedByteArray &p_data, bool p_megadrive);
	static PackedByteArray encode_tilemap(const Array &p_entries, bool p_megadrive);
	static Ref<Image> render_tilemap(const PackedByteArray &p_map, const Ref<Image> &p_tiles,
			int p_map_w, int p_map_h, int p_tile_size, const PackedColorArray &p_palette,
			bool p_megadrive, bool p_column_major = false);
	static Ref<Image> render_tilemap_indexed(const PackedByteArray &p_map, const Ref<Image> &p_indices,
			int p_map_w, int p_map_h, int p_tile_size, const PackedColorArray &p_palette,
			bool p_megadrive, bool p_column_major = false, int p_colors_per_palette = 16);

	// Indexed images / palettes.
	static PackedByteArray indices_from_image(const Ref<Image> &p_image, const PackedColorArray &p_palette, bool p_transparent = true);
	static Ref<Image> image_from_indices(const PackedByteArray &p_indices, int p_width, int p_height, const PackedColorArray &p_palette);
	static PackedColorArray read_png_palette(const String &p_path);
	static Error save_indexed_png(const String &p_path, const Ref<Image> &p_image, const PackedColorArray &p_palette);
	static PackedColorArray extract_palette(const Ref<Image> &p_image, int p_max_colors, bool p_reserve_transparent = true);
	static Ref<Image> quantize(const Ref<Image> &p_image, int p_max_colors, bool p_transparent = true);
	static Ref<Image> map_to_palette(const Ref<Image> &p_image, const PackedColorArray &p_palette, bool p_transparent = true);

	// Inspection helpers used by the Hardware Monitor.
	static Dictionary analyze_image(const Ref<Image> &p_image);
};

#endif // RETRO_GRAPHICS_H
