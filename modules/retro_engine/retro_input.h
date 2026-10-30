/**************************************************************************/
/*  retro_input.h - console input actions + state associations            */
/**************************************************************************/

#ifndef RETRO_INPUT_H
#define RETRO_INPUT_H

#include "core/object/ref_counted.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

class RetroInputMap : public RefCounted {
	GDCLASS(RetroInputMap, RefCounted);

	String platform = "snes";
	Array actions;
	Array states;
	Array state_durations;
	Dictionary metadata;

protected:
	static void _bind_methods();

public:
	RetroInputMap();

	static Array default_states();
	static Array snes_buttons();
	static Array megadrive_buttons();
	static int snes_bit(const String &p_name);
	static int megadrive_bit(const String &p_name);

	void setup_defaults(const String &p_platform);
	void add_action(const Dictionary &p_action);
	void update_action(const String &p_id, const Dictionary &p_action);
	void remove_action(const String &p_id);
	Dictionary get_action(const String &p_id) const;
	int action_index(const String &p_id) const;
	int action_mask(const String &p_id, const String &p_platform) const;
	String mask_text(const String &p_id, const String &p_platform) const;

	Dictionary validate() const;
	Dictionary export_snes_header(const String &p_path) const;
	Dictionary export_snes_inc(const String &p_path) const;
	Dictionary export_sgdk_header(const String &p_path) const;
	Dictionary export_state_machine_snes(const String &p_dir, const String &p_base = "retro_state_machine") const;
	Dictionary export_state_machine_sgdk(const String &p_dir, const String &p_base = "retro_state_machine") const;
	String generate_state_machine_header(const String &p_platform) const;
	String generate_state_machine_source(const String &p_platform) const;
	Error save(const String &p_path) const;
	Error load(const String &p_path);

	Dictionary to_dict() const;
	void from_dict(const Dictionary &p_data);

	void set_platform(const String &p_value) { platform = p_value; }
	String get_platform() const { return platform; }
	void set_actions(const Array &p_value) { actions = p_value; }
	Array get_actions() const { return actions; }
	void set_states(const Array &p_value) { states = p_value; }
	Array get_states() const { return states; }
	void set_state_durations(const Array &p_value) { state_durations = p_value; }
	Array get_state_durations() const { return state_durations; }
	void set_metadata(const Dictionary &p_value) { metadata = p_value; }
	Dictionary get_metadata() const { return metadata; }
};

#endif // RETRO_INPUT_H
