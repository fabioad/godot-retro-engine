/**************************************************************************/
/*  retro_hitbox_io.h - AIR/CNS parsing and hitbox/animation exchange     */
/**************************************************************************/

#ifndef RETRO_HITBOX_IO_H
#define RETRO_HITBOX_IO_H

#include "retro_animation.h"

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

class RetroHitboxIO : public RefCounted {
	GDCLASS(RetroHitboxIO, RefCounted);

protected:
	static void _bind_methods();

public:
	Array last_air_actions;

	Dictionary parse_air(const String &p_path);
	Dictionary parse_cns(const String &p_path);
	Dictionary import_air_frames(const Array &p_frames, const Ref<RetroAnimation> &p_animation, const String &p_state) const;
	Dictionary import_air_action(int p_action, const Ref<RetroAnimation> &p_animation, const String &p_state);
	Dictionary export_air(const Ref<RetroAnimation> &p_animation, const String &p_state, int p_action, const String &p_path) const;
};

#endif // RETRO_HITBOX_IO_H
