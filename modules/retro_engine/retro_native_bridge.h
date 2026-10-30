/**************************************************************************/
/*  retro_native_bridge.h - Godot native image/scene -> retro asset bridge */
/**************************************************************************/

#ifndef RETRO_NATIVE_BRIDGE_H
#define RETRO_NATIVE_BRIDGE_H

#include "retro_animation.h"
#include "retro_sprite.h"
#include "retro_stage.h"

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

class RetroNativeBridge : public RefCounted {
	GDCLASS(RetroNativeBridge, RefCounted);

protected:
	static void _bind_methods();

public:
	Dictionary import_image(const Ref<Image> &p_image, const String &p_name, const String &p_dir,
			const String &p_platform, int p_frame_w = 0, int p_frame_h = 0,
			int p_palette_colors = 16, int p_bpp = 4, int p_tile_size = 8,
			const String &p_source_scene = String());
	Dictionary import_stage_image(const Ref<Image> &p_image, const String &p_name, const String &p_dir,
			const String &p_platform, const String &p_mode = "mode1", int p_tile_size = 8,
			int p_max_tiles = 1024, int p_palette_colors = 16,
			const String &p_source_scene = String());
	Dictionary export_scene_layout(const Array &p_actors, const Dictionary &p_scene_meta,
			const String &p_path, const String &p_platform = "snes");
	Dictionary get_3d_profile(const String &p_id) const;
	Array get_3d_profiles() const;
	Dictionary export_3d_manifest(const String &p_profile, const Dictionary &p_scene_meta,
			const Array &p_actors, const Dictionary &p_bake, const String &p_path) const;
};

#endif // RETRO_NATIVE_BRIDGE_H
