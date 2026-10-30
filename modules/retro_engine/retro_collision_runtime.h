/**************************************************************************/
/*  retro_collision_runtime.h - hitbox tables + hitstop/invulnerability    */
/**************************************************************************/

#ifndef RETRO_COLLISION_RUNTIME_H
#define RETRO_COLLISION_RUNTIME_H

#include "retro_animation.h"

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

class RetroCollisionRuntime : public RefCounted {
	GDCLASS(RetroCollisionRuntime, RefCounted);

	String platform = "snes";
	Array moves;
	Dictionary metadata;
	Array state_names;

protected:
	static void _bind_methods();

public:
	RetroCollisionRuntime();

	void setup_from_animation(const Ref<RetroAnimation> &p_animation);
	void set_move(const String &p_state, const Dictionary &p_move);
	Dictionary get_move(const String &p_state) const;
	void apply_hitdef(const String &p_state, const Dictionary &p_hitdef);
	void set_state_names(const Array &p_names);
	Array get_moves() const { return moves; }
	void set_moves(const Array &p_value) { moves = p_value; }

	String generate_header(const String &p_platform) const;
	String generate_source(const String &p_platform, const Ref<RetroAnimation> &p_animation) const;
	Dictionary export_snes(const String &p_dir, const String &p_base, const Ref<RetroAnimation> &p_animation);
	Dictionary export_sgdk(const String &p_dir, const String &p_base, const Ref<RetroAnimation> &p_animation);
	Error save(const String &p_path) const;
	Error load(const String &p_path);
	Dictionary to_dict() const;
	void from_dict(const Dictionary &p_data);

	void set_platform(const String &p_value) { platform = p_value; }
	String get_platform() const { return platform; }
};

#endif // RETRO_COLLISION_RUNTIME_H
