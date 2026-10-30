/**************************************************************************/
/*  retro_state_graph.h - visual state graph + generated C runtime        */
/**************************************************************************/

#ifndef RETRO_STATE_GRAPH_H
#define RETRO_STATE_GRAPH_H

#include "retro_input.h"

#include "core/object/ref_counted.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

class RetroStateGraph : public RefCounted {
	GDCLASS(RetroStateGraph, RefCounted);

	String platform = "snes";
	Array nodes;
	Array transitions;
	Dictionary metadata;

protected:
	static void _bind_methods();

public:
	RetroStateGraph();

	void setup_from_input_map(const Ref<RetroInputMap> &p_input);
	void add_node(const String &p_state, const Vector2 &p_position, int p_duration = 0);
	void update_node(const String &p_id, const Dictionary &p_data);
	void remove_node(const String &p_id);
	Dictionary get_node(const String &p_id) const;
	int node_index(const String &p_id) const;
	void add_transition(const Dictionary &p_transition);
	void update_transition(const String &p_id, const Dictionary &p_data);
	void remove_transition(const String &p_id);
	Dictionary get_transition(const String &p_id) const;
	void remove_transitions_between(const String &p_from, const String &p_to);
	Array transitions_from(const String &p_from) const;

	Dictionary validate(const Ref<RetroInputMap> &p_input) const;
	String generate_header(const String &p_platform) const;
	String generate_source(const String &p_platform, const Ref<RetroInputMap> &p_input) const;
	Dictionary export_snes(const String &p_dir, const String &p_base, const Ref<RetroInputMap> &p_input) const;
	Dictionary export_sgdk(const String &p_dir, const String &p_base, const Ref<RetroInputMap> &p_input) const;
	Error save(const String &p_path) const;
	Error load(const String &p_path);
	Dictionary to_dict() const;
	void from_dict(const Dictionary &p_data);

	void set_platform(const String &p_value) { platform = p_value; }
	String get_platform() const { return platform; }
	void set_nodes(const Array &p_value) { nodes = p_value; }
	Array get_nodes() const { return nodes; }
	void set_transitions(const Array &p_value) { transitions = p_value; }
	Array get_transitions() const { return transitions; }
	void set_metadata(const Dictionary &p_value) { metadata = p_value; }
	Dictionary get_metadata() const { return metadata; }
};

#endif // RETRO_STATE_GRAPH_H
