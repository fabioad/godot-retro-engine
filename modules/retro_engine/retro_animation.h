/**************************************************************************/
/*  retro_animation.h - frame based fighting-game animation document       */
/**************************************************************************/

#ifndef RETRO_ANIMATION_H
#define RETRO_ANIMATION_H

#include "core/object/ref_counted.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

class RetroAnimation : public RefCounted {
	GDCLASS(RetroAnimation, RefCounted);

	String name = "animation";
	String platform = "snes";
	String sprite_id;
	int fps = 60;
	Dictionary states;
	Dictionary metadata;

protected:
	static void _bind_methods();

public:
	RetroAnimation();
	static Array default_states();

	void add_state(const String &p_state, bool p_loop = true);
	void remove_state(const String &p_state);
	void add_frame(const String &p_state, int p_sprite_frame, int p_duration, const Rect2i &p_rect = Rect2i());
	void set_frame_duration(const String &p_state, int p_index, int p_duration);
	void add_hitbox(const String &p_state, int p_frame, const Rect2i &p_rect, const String &p_type = "hit");
	Array get_frame_hitboxes(const String &p_state, int p_frame) const;
	void set_frame_hitboxes(const String &p_state, int p_frame, const Array &p_boxes);
	void add_event(const String &p_state, int p_frame, const String &p_type, const String &p_value);
	void set_loop(const String &p_state, bool p_loop);
	void set_transition(const String &p_state, const String &p_next);

	Dictionary get_state(const String &p_state) const;
	Dictionary get_state_frame(const String &p_state, int p_index) const;
	int total_duration(const String &p_state) const;
	Dictionary sample(const String &p_state, float p_time) const;
	Dictionary analyze() const;

	Dictionary export_snes_inc(const String &p_path, const String &p_prefix = String());
	Dictionary export_sgdk_header(const String &p_path, const String &p_prefix = String());
	Dictionary export_hitboxes_snes(const String &p_path, const String &p_prefix = String()) const;
	Dictionary export_hitboxes_sgdk(const String &p_path, const String &p_prefix = String()) const;
	Dictionary collision_test(const String &p_state_a, int p_frame_a, const Point2i &p_pos_a,
			const String &p_state_b, int p_frame_b, const Point2i &p_pos_b) const;

	Error save(const String &p_path);
	Error load(const String &p_path);
	Dictionary to_dict() const;
	void from_dict(const Dictionary &p_data);

	void set_name(const String &p_value) { name = p_value; }
	String get_name() const { return name; }
	void set_platform(const String &p_value) { platform = p_value; }
	String get_platform() const { return platform; }
	void set_sprite_id(const String &p_value) { sprite_id = p_value; }
	String get_sprite_id() const { return sprite_id; }
	void set_fps(int p_value) { fps = MAX(1, p_value); }
	int get_fps() const { return fps; }
	void set_states(const Dictionary &p_value) { states = p_value; }
	Dictionary get_states() const { return states; }
	void set_metadata(const Dictionary &p_value) { metadata = p_value; }
	Dictionary get_metadata() const { return metadata; }
};

#endif // RETRO_ANIMATION_H
