/**************************************************************************/
/*  retro_mugen_import.h - assisted MUGEN state / AIR / CNS import        */
/**************************************************************************/

#ifndef RETRO_MUGEN_IMPORT_H
#define RETRO_MUGEN_IMPORT_H

#include "retro_animation.h"
#include "retro_input.h"
#include "retro_state_graph.h"

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

class RetroMugenImport : public RefCounted {
	GDCLASS(RetroMugenImport, RefCounted);

protected:
	static void _bind_methods();

public:
	Dictionary parse_states(const String &p_cns_path, const String &p_air_path);
	Dictionary auto_map_states(const Dictionary &p_parsed) const;
	Dictionary parse_commands(const String &p_cmd_path) const;
	Dictionary import_state(const String &p_cns_path, const String &p_air_path, int p_state_number,
			const Ref<RetroAnimation> &p_animation, const String &p_target_state);
	Dictionary import_mapped_states(const Dictionary &p_parsed, const Dictionary &p_mapping,
			const Ref<RetroAnimation> &p_animation, const String &p_air_path);
	Dictionary build_fight_graph(const Dictionary &p_parsed, const Dictionary &p_mapping,
			const Ref<RetroInputMap> &p_input, int p_max_nodes = 0,
			const Dictionary &p_commands = Dictionary());
};

#endif // RETRO_MUGEN_IMPORT_H
