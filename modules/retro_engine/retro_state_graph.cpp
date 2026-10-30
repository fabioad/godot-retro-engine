/**************************************************************************/
/*  retro_state_graph.cpp                                                 */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_state_graph.h"

#include "retro_util.h"

void RetroStateGraph::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup_from_input_map", "input"), &RetroStateGraph::setup_from_input_map);
	ClassDB::bind_method(D_METHOD("add_node", "state", "position", "duration"), &RetroStateGraph::add_node, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("update_node", "id", "data"), &RetroStateGraph::update_node);
	ClassDB::bind_method(D_METHOD("remove_node", "id"), &RetroStateGraph::remove_node);
	ClassDB::bind_method(D_METHOD("get_node", "id"), &RetroStateGraph::get_node);
	ClassDB::bind_method(D_METHOD("node_index", "id"), &RetroStateGraph::node_index);
	ClassDB::bind_method(D_METHOD("add_transition", "transition"), &RetroStateGraph::add_transition);
	ClassDB::bind_method(D_METHOD("update_transition", "id", "data"), &RetroStateGraph::update_transition);
	ClassDB::bind_method(D_METHOD("remove_transition", "id"), &RetroStateGraph::remove_transition);
	ClassDB::bind_method(D_METHOD("get_transition", "id"), &RetroStateGraph::get_transition);
	ClassDB::bind_method(D_METHOD("remove_transitions_between", "from", "to"), &RetroStateGraph::remove_transitions_between);
	ClassDB::bind_method(D_METHOD("transitions_from", "from"), &RetroStateGraph::transitions_from);
	ClassDB::bind_method(D_METHOD("validate", "input"), &RetroStateGraph::validate);
	ClassDB::bind_method(D_METHOD("generate_header", "platform"), &RetroStateGraph::generate_header);
	ClassDB::bind_method(D_METHOD("generate_source", "platform", "input"), &RetroStateGraph::generate_source);
	ClassDB::bind_method(D_METHOD("export_snes", "dir", "base", "input"), &RetroStateGraph::export_snes, DEFVAL("retro_state_machine"));
	ClassDB::bind_method(D_METHOD("export_sgdk", "dir", "base", "input"), &RetroStateGraph::export_sgdk, DEFVAL("retro_state_machine"));
	ClassDB::bind_method(D_METHOD("save", "path"), &RetroStateGraph::save);
	ClassDB::bind_method(D_METHOD("load", "path"), &RetroStateGraph::load);
	ClassDB::bind_method(D_METHOD("to_dict"), &RetroStateGraph::to_dict);
	ClassDB::bind_method(D_METHOD("from_dict", "data"), &RetroStateGraph::from_dict);

	ClassDB::bind_method(D_METHOD("set_platform", "value"), &RetroStateGraph::set_platform);
	ClassDB::bind_method(D_METHOD("get_platform"), &RetroStateGraph::get_platform);
	ClassDB::bind_method(D_METHOD("set_nodes", "value"), &RetroStateGraph::set_nodes);
	ClassDB::bind_method(D_METHOD("get_nodes"), &RetroStateGraph::get_nodes);
	ClassDB::bind_method(D_METHOD("set_transitions", "value"), &RetroStateGraph::set_transitions);
	ClassDB::bind_method(D_METHOD("get_transitions"), &RetroStateGraph::get_transitions);
	ClassDB::bind_method(D_METHOD("set_metadata", "value"), &RetroStateGraph::set_metadata);
	ClassDB::bind_method(D_METHOD("get_metadata"), &RetroStateGraph::get_metadata);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "platform"), "set_platform", "get_platform");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "nodes"), "set_nodes", "get_nodes");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "transitions"), "set_transitions", "get_transitions");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "metadata"), "set_metadata", "get_metadata");
}

static String _retro_graph_id(const String &p_text, const String &p_fallback) {
	String out = p_text.strip_edges().to_lower();
	for (int i = 0; i < out.length(); i++) {
		const char32_t c = out[i];
		if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')) {
			out = out.replace(String::chr(c), "_");
		}
	}
	return out.is_empty() ? p_fallback : out;
}

static String _retro_graph_enum(const String &p_state) {
	String out = p_state.to_upper();
	for (int i = 0; i < out.length(); i++) {
		const char32_t c = out[i];
		if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) {
			out = out.replace(String::chr(c), "_");
		}
	}
	return out.is_empty() ? "STATE" : out;
}

static int _retro_graph_mode(const String &p_mode) {
	if (p_mode == "held") return 1;
	if (p_mode == "released") return 2;
	return 0; // pressed
}

RetroStateGraph::RetroStateGraph() = default;

void RetroStateGraph::setup_from_input_map(const Ref<RetroInputMap> &p_input) {
	nodes = Array();
	transitions = Array();
	if (p_input.is_null()) {
		return;
	}
	platform = p_input->get_platform();
	const Array states = p_input->get_states();
	const Array durations = p_input->get_state_durations();
	for (int i = 0; i < states.size(); i++) {
		Dictionary n;
		n["id"] = _retro_graph_id(String(states[i]), "state_" + itos(i));
		n["state"] = String(states[i]);
		n["x"] = 40 + (i % 4) * 220;
		n["y"] = 40 + (i / 4) * 150;
		n["duration"] = i < durations.size() ? int(durations[i]) : 0;
		nodes.push_back(n);
	}
	const String start_id = nodes.is_empty() ? String() : String(Dictionary(nodes[0]).get("id", ""));
	const Array actions = p_input->get_actions();
	for (int i = 0; i < actions.size() && !start_id.is_empty(); i++) {
		const Dictionary a = actions[i];
		const String id = String(a.get("id", ""));
		const String target = String(a.get("state", ""));
		if (target.is_empty() || target == "IDLE") {
			continue;
		}
		int to = -1;
		for (int n = 0; n < nodes.size(); n++) {
			if (String(Dictionary(nodes[n]).get("state", "")) == target) {
				to = n;
				break;
			}
		}
		if (to < 0) {
			continue;
		}
		Dictionary t;
		t["id"] = "trans_" + itos(transitions.size() + 1);
		t["from"] = start_id;
		t["to"] = String(Dictionary(nodes[to]).get("id", ""));
		Array conds;
		Dictionary c;
		c["action"] = id;
		c["mode"] = "pressed";
		conds.push_back(c);
		t["conditions"] = conds;
		t["op"] = "all";
		t["cooldown"] = 0;
		t["priority"] = int(a.get("priority", 0));
		t["auto"] = false;
		transitions.push_back(t);
	}
	// Default return-to-idle transitions for states with animation duration.
	for (int n = 0; n < nodes.size(); n++) {
		const Dictionary node = nodes[n];
		const int duration = int(node.get("duration", 0));
		if (String(node.get("state", "")) == "IDLE" || duration <= 0) {
			continue;
		}
		Dictionary t;
		t["id"] = "trans_" + itos(transitions.size() + 1);
		t["from"] = String(node.get("id", ""));
		t["to"] = start_id;
		t["conditions"] = Array();
		t["op"] = "all";
		t["cooldown"] = 0;
		t["priority"] = 0;
		t["auto"] = true;
		transitions.push_back(t);
	}
}

void RetroStateGraph::add_node(const String &p_state, const Vector2 &p_position, int p_duration) {
	String base = _retro_graph_id(p_state, "state");
	String id = base;
	int suffix = 1;
	while (node_index(id) >= 0) {
		id = base + "_" + itos(suffix++);
	}
	Dictionary n;
	n["id"] = id;
	n["state"] = p_state.strip_edges().is_empty() ? id.capitalize() : p_state.strip_edges();
	n["x"] = int(p_position.x);
	n["y"] = int(p_position.y);
	n["duration"] = MAX(0, p_duration);
	nodes.push_back(n);
}

void RetroStateGraph::update_node(const String &p_id, const Dictionary &p_data) {
	const int idx = node_index(p_id);
	if (idx < 0) {
		return;
	}
	Dictionary n = nodes[idx];
	for (const Variant *K = p_data.next(nullptr); K; K = p_data.next(K)) {
		n[*K] = p_data[*K];
	}
	nodes[idx] = n;
}

void RetroStateGraph::remove_node(const String &p_id) {
	const int idx = node_index(p_id);
	if (idx < 0) {
		return;
	}
	nodes.remove_at(idx);
	Array kept;
	for (int i = 0; i < transitions.size(); i++) {
		const Dictionary t = transitions[i];
		if (String(t.get("from", "")) != p_id && String(t.get("to", "")) != p_id) {
			kept.push_back(t);
		}
	}
	transitions = kept;
}

Dictionary RetroStateGraph::get_node(const String &p_id) const {
	const int idx = node_index(p_id);
	return idx >= 0 ? Dictionary(nodes[idx]) : Dictionary();
}

int RetroStateGraph::node_index(const String &p_id) const {
	for (int i = 0; i < nodes.size(); i++) {
		if (String(Dictionary(nodes[i]).get("id", "")) == p_id) {
			return i;
		}
	}
	return -1;
}

void RetroStateGraph::add_transition(const Dictionary &p_transition) {
	Dictionary t = p_transition;
	String id = String(t.get("id", ""));
	if (id.is_empty() || get_transition(id).size() > 0) {
		id = "trans_" + itos(transitions.size() + 1);
	}
	t["id"] = id;
	if (!t.has("conditions")) t["conditions"] = Array();
	if (!t.has("op")) t["op"] = "all";
	if (!t.has("cooldown")) t["cooldown"] = 0;
	if (!t.has("priority")) t["priority"] = 0;
	if (!t.has("auto")) t["auto"] = false;
	transitions.push_back(t);
}

void RetroStateGraph::update_transition(const String &p_id, const Dictionary &p_data) {
	for (int i = 0; i < transitions.size(); i++) {
		Dictionary t = transitions[i];
		if (String(t.get("id", "")) != p_id) {
			continue;
		}
		for (const Variant *K = p_data.next(nullptr); K; K = p_data.next(K)) {
			t[*K] = p_data[*K];
		}
		transitions[i] = t;
		return;
	}
}

void RetroStateGraph::remove_transition(const String &p_id) {
	for (int i = 0; i < transitions.size(); i++) {
		if (String(Dictionary(transitions[i]).get("id", "")) == p_id) {
			transitions.remove_at(i);
			return;
		}
	}
}

Dictionary RetroStateGraph::get_transition(const String &p_id) const {
	for (int i = 0; i < transitions.size(); i++) {
		if (String(Dictionary(transitions[i]).get("id", "")) == p_id) {
			return transitions[i];
		}
	}
	return Dictionary();
}

void RetroStateGraph::remove_transitions_between(const String &p_from, const String &p_to) {
	Array kept;
	for (int i = 0; i < transitions.size(); i++) {
		const Dictionary t = transitions[i];
		if (String(t.get("from", "")) != p_from || String(t.get("to", "")) != p_to) {
			kept.push_back(t);
		}
	}
	transitions = kept;
}

Array RetroStateGraph::transitions_from(const String &p_from) const {
	Array out;
	for (int i = 0; i < transitions.size(); i++) {
		if (String(Dictionary(transitions[i]).get("from", "")) == p_from) {
			out.push_back(transitions[i]);
		}
	}
	return out;
}

Dictionary RetroStateGraph::validate(const Ref<RetroInputMap> &p_input) const {
	Dictionary out;
	Array errors;
	Array warnings;
	if (nodes.is_empty()) {
		errors.push_back("Graph has no states.");
	}
	Array state_names;
	for (int i = 0; i < nodes.size(); i++) {
		const Dictionary n = nodes[i];
		const String state = String(n.get("state", ""));
		if (state.is_empty()) {
			errors.push_back("Node " + String(n.get("id", "?")) + " has an empty state name.");
		}
		if (state_names.has(state)) {
			warnings.push_back("Duplicate state name: " + state);
		} else {
			state_names.push_back(state);
		}
		// A graph generated from MUGEN intentionally contains states that do not
		// exist in the project animation yet; importing them is an explicit step.
		const bool generated_mugen = String(metadata.get("source", "")) == "mugen";
		if (!generated_mugen && p_input.is_valid() && p_input->get_states().size() > 0 && !p_input->get_states().has(state)) {
			warnings.push_back(state + " is not in the input/animation state list.");
		}
	}
	for (int i = 0; i < transitions.size(); i++) {
		const Dictionary t = transitions[i];
		const String id = String(t.get("id", ""));
		const int from = node_index(String(t.get("from", "")));
		const int to = node_index(String(t.get("to", "")));
		if (from < 0 || to < 0) {
			errors.push_back(id + " references a missing node.");
			continue;
		}
		const bool auto_t = bool(t.get("auto", false));
		const Array conds = t.get("conditions", Array());
		if (!auto_t) {
			if (conds.is_empty()) {
				errors.push_back(id + " has no input condition.");
			}
			for (int c = 0; c < conds.size(); c++) {
				const Dictionary cond = conds[c];
				if (cond.has("sequence")) {
					const Array steps = cond.get("sequence", Array());
					if (steps.is_empty()) {
						errors.push_back(id + " has an empty command sequence.");
					}
					for (int st = 0; st < steps.size(); st++) {
						const Dictionary step = steps[st];
						const Array step_actions = step.get("actions", Array());
						if (step_actions.is_empty()) {
							errors.push_back(id + " has an empty command step.");
						}
						for (int a = 0; a < step_actions.size(); a++) {
							const String action = String(step_actions[a]);
							if (p_input.is_valid() && p_input->get_action(action).is_empty()) {
								errors.push_back(id + " command references unknown action '" + action + "'.");
							}
						}
						const String step_mode = String(step.get("mode", "pressed"));
						if (step_mode != "pressed" && step_mode != "held" && step_mode != "released") {
							errors.push_back(id + " has invalid command step mode '" + step_mode + "'.");
						}
					}
					continue;
				}
				const String action = String(cond.get("action", ""));
				if (p_input.is_valid()) {
					if (p_input->get_action(action).is_empty()) {
						errors.push_back(id + " references unknown action '" + action + "'.");
					} else if (p_input->action_mask(action, platform == "megadrive" ? "megadrive" : "snes") == 0) {
						warnings.push_back(id + " action '" + action + "' has a zero mask for this platform.");
					}
				}
				const String mode = String(cond.get("mode", "pressed"));
				if (mode != "pressed" && mode != "held" && mode != "released") {
					errors.push_back(id + " has invalid condition mode '" + mode + "'.");
				}
			}
		} else {
			const int duration = int(Dictionary(nodes[from]).get("duration", 0));
			if (duration <= 0) {
				warnings.push_back(id + " is an auto transition but source state has duration 0.");
			}
		}
	}
	out["ok"] = errors.is_empty();
	out["errors"] = errors;
	out["warnings"] = warnings;
	out["node_count"] = nodes.size();
	out["transition_count"] = transitions.size();
	return out;
}

String RetroStateGraph::generate_header(const String &p_platform) const {
	(void)p_platform;
	String out;
	out += "/* Generated by Godot Retro Engine state-graph exporter. */\n";
	out += "#ifndef RETRO_STATE_MACHINE_H\n#define RETRO_STATE_MACHINE_H\n\n";
	out += "typedef unsigned char retro_u8;\n";
	out += "typedef unsigned short retro_u16;\n";
	out += "typedef unsigned short retro_node;\n\n";
	out += "#define RETRO_NODE_COUNT " + itos(nodes.size()) + "\n";
	out += "#define RETRO_TRANSITION_COUNT " + itos(transitions.size()) + "\n";
	out += "#define RETRO_NONE 0xFFFF\n";
	out += "#define RETRO_COND_PRESSED 0\n";
	out += "#define RETRO_COND_HELD 1\n";
	out += "#define RETRO_COND_RELEASED 2\n\n";
	out += "enum RetroNode {\n";
	Array used;
	for (int i = 0; i < nodes.size(); i++) {
		String enum_name = _retro_graph_enum(String(Dictionary(nodes[i]).get("state", "STATE")));
		String candidate = enum_name;
		int suffix = 1;
		while (used.has(candidate)) {
			candidate = enum_name + "_" + itos(suffix++);
		}
		used.push_back(candidate);
		out += "\tRETRO_STATE_" + candidate + " = " + itos(i) + ",\n";
	}
	out += "\tRETRO_STATE_COUNT = " + itos(nodes.size()) + "\n";
	out += "};\n\n";
	out += "void retro_sm_init(void);\n";
	out += "retro_node retro_sm_update(retro_u16 current, retro_u16 pressed);\n";
	out += "retro_node retro_sm_tick(void);\n";
	out += "retro_node retro_sm_state(void);\n";
	out += "retro_node retro_sm_animation_end(void);\n";
	out += "retro_node retro_sm_force_state(retro_node node);\n";
	out += "retro_u16 retro_sm_frame(void);\n";
	out += "retro_u16 retro_sm_last_transition(void);\n";
	out += "const char *retro_sm_state_name(retro_node node);\n\n";
	out += "#endif\n";
	return out;
}

static String _retro_graph_hex(int p_mask) {
	return "0x" + String::num_int64(p_mask, 16).to_upper().pad_zeros(4);
}

String RetroStateGraph::generate_source(const String &p_platform, const Ref<RetroInputMap> &p_input) const {
	String out;
	out += "/* Generated by Godot Retro Engine state-graph exporter. */\n";
	out += "#include \"retro_state_machine.h\"\n\n";
	out += "static retro_node sm_node;\n";
	out += "static retro_u16 sm_elapsed;\n";
	out += "static retro_u16 sm_prev_pad;\n";
	out += "static retro_u16 sm_last_transition;\n";
	out += "static retro_u16 sm_cooldowns[" + itos(MAX(1, transitions.size())) + "];\n";
	out += "#define RETRO_SEQ_HISTORY 32\n";
	out += "static retro_u16 sm_hist_pressed[RETRO_SEQ_HISTORY];\n";
	out += "static retro_u16 sm_hist_released[RETRO_SEQ_HISTORY];\n";
	out += "static retro_u16 sm_hist_tick[RETRO_SEQ_HISTORY];\n";
	out += "static retro_u8 sm_hist_pos;\n";
	out += "static retro_u16 sm_tick;\n\n";
	out += "typedef struct { retro_u16 mask; retro_u8 mode; } RetroSequenceStep;\n";
	out += "typedef struct { retro_u16 mask; retro_u8 mode; retro_u16 seq_start; retro_u8 seq_count; retro_u8 window; } RetroCondition;\n";
	out += "typedef struct { retro_node from; retro_node to; retro_u16 cond_start; retro_u8 cond_count; retro_u8 op; retro_u16 cooldown; retro_u8 priority; retro_u8 auto_transition; } RetroTransition;\n\n";

	Array cond_entries;
	Array seq_entries;
	Array trans_entries;
	Array node_durations;
	Array node_names;
	for (int i = 0; i < nodes.size(); i++) {
		const Dictionary n = nodes[i];
		node_durations.push_back(MAX(0, int(n.get("duration", 0))));
		node_names.push_back(String(n.get("state", "")));
	}
	for (int i = 0; i < transitions.size(); i++) {
		const Dictionary t = transitions[i];
		Dictionary e;
		e["from"] = MAX(0, node_index(String(t.get("from", ""))));
		e["to"] = MAX(0, node_index(String(t.get("to", ""))));
		e["cond_start"] = cond_entries.size();
		const Array conds = t.get("conditions", Array());
		e["cond_count"] = conds.size();
		e["op"] = String(t.get("op", "all")) == "any" ? 1 : 0;
		e["cooldown"] = CLAMP(int(t.get("cooldown", 0)), 0, 65535);
		e["priority"] = CLAMP(int(t.get("priority", 0)), 0, 255);
		e["auto"] = bool(t.get("auto", false)) ? 1 : 0;
		trans_entries.push_back(e);
		for (int c = 0; c < conds.size(); c++) {
			const Dictionary cond = conds[c];
			Dictionary ce;
			if (cond.has("sequence")) {
				const Array steps = cond.get("sequence", Array());
				const int seq_start = seq_entries.size();
				for (int st = 0; st < steps.size(); st++) {
					const Dictionary step = steps[st];
					const Array step_actions = step.get("actions", Array());
					int step_mask = 0;
					String action_names;
					for (int a = 0; a < step_actions.size(); a++) {
						const String aid = String(step_actions[a]);
						if (p_input.is_valid()) {
							step_mask |= p_input->action_mask(aid, p_platform == "megadrive" ? "megadrive" : "snes");
						}
						if (!action_names.is_empty()) action_names += "+";
						action_names += aid;
					}
					Dictionary se;
					se["mask"] = step_mask;
					se["mode"] = _retro_graph_mode(String(step.get("mode", "pressed")));
					se["action"] = action_names;
					seq_entries.push_back(se);
				}
				ce["mask"] = _retro_graph_hex(0);
				ce["mode"] = 0;
				ce["seq_start"] = seq_start;
				ce["seq_count"] = steps.size();
				ce["window"] = CLAMP(int(cond.get("window", 15)), 0, 255);
				ce["action"] = String(cond.get("command", "sequence"));
			} else {
				const String action = String(cond.get("action", ""));
				const int mask = p_input.is_valid() ? p_input->action_mask(action, p_platform == "megadrive" ? "megadrive" : "snes") : 0;
				ce["mask"] = _retro_graph_hex(mask);
				ce["mode"] = _retro_graph_mode(String(cond.get("mode", "pressed")));
				ce["seq_start"] = 0;
				ce["seq_count"] = 0;
				ce["window"] = 0;
				ce["action"] = action;
			}
			cond_entries.push_back(ce);
		}
	}

	out += "static const retro_u16 retro_node_durations[" + itos(MAX(1, nodes.size())) + "] = {\n\t";
	for (int i = 0; i < node_durations.size(); i++) {
		if (i > 0) out += ", ";
		out += itos(int(node_durations[i]));
	}
	if (nodes.is_empty()) out += "0";
	out += "\n};\n\n";

	out += "static const RetroSequenceStep retro_sequence_steps[" + itos(MAX(1, seq_entries.size())) + "] = {\n";
	for (int i = 0; i < seq_entries.size(); i++) {
		const Dictionary q = seq_entries[i];
		out += "\t{ " + _retro_graph_hex(int(q.get("mask", 0))) + ", " + itos(int(q.get("mode", 0))) + " }, /* " + String(q.get("action", "")) + " */\n";
	}
	if (seq_entries.is_empty()) out += "\t{ 0x0000, 0 },\n";
	out += "};\n\n";
	out += "static const RetroCondition retro_conditions[" + itos(MAX(1, cond_entries.size())) + "] = {\n";
	for (int i = 0; i < cond_entries.size(); i++) {
		const Dictionary c = cond_entries[i];
		out += "\t{ " + String(c.get("mask", "0x0000")) + ", " + itos(int(c.get("mode", 0))) + ", " +
				itos(int(c.get("seq_start", 0))) + ", " + itos(int(c.get("seq_count", 0))) + ", " +
				itos(int(c.get("window", 0))) + " }, /* " + String(c.get("action", "")) + " */\n";
	}
	if (cond_entries.is_empty()) out += "\t{ 0x0000, 0, 0, 0, 0 },\n";
	out += "};\n\n";

	out += "static const RetroTransition retro_transitions[" + itos(MAX(1, trans_entries.size())) + "] = {\n";
	for (int i = 0; i < trans_entries.size(); i++) {
		const Dictionary e = trans_entries[i];
		out += "\t{ " + itos(int(e.get("from", 0))) + ", " + itos(int(e.get("to", 0))) + ", " +
				itos(int(e.get("cond_start", 0))) + ", " + itos(int(e.get("cond_count", 0))) + ", " +
				itos(int(e.get("op", 0))) + ", " + itos(int(e.get("cooldown", 0))) + ", " +
				itos(int(e.get("priority", 0))) + ", " + itos(int(e.get("auto", 0))) + " },\n";
	}
	if (trans_entries.is_empty()) out += "\t{ 0, 0, 0, 0, 0, 0, 0, 0 },\n";
	out += "};\n\n";

	out += "static const char *retro_node_names[" + itos(MAX(1, node_names.size())) + "] = {\n\t";
	for (int i = 0; i < node_names.size(); i++) {
		if (i > 0) out += ", ";
		out += "\"" + String(node_names[i]).replace("\"", "\\\"") + "\"";
	}
	if (node_names.is_empty()) out += "\"\"";
	out += "\n};\n\n";

	out += "void retro_sm_init(void)\n{\n";
	out += "\tretro_u16 i;\n\tsm_node = 0;\n\tsm_elapsed = 0;\n\tsm_prev_pad = 0;\n\tsm_last_transition = RETRO_NONE;\n";
	out += "\tsm_tick = 0;\n\tsm_hist_pos = 0;\n";
	out += "\tfor (i = 0; i < " + itos(MAX(1, transitions.size())) + "; i++) sm_cooldowns[i] = 0;\n";
	out += "\tfor (i = 0; i < RETRO_SEQ_HISTORY; i++) { sm_hist_pressed[i] = 0; sm_hist_released[i] = 0; sm_hist_tick[i] = 0; }\n";
	out += "}\n\n";
	out += "static retro_u8 _retro_seq_match(retro_u16 start, retro_u8 count, retro_u8 window)\n{\n";
	out += "\tretro_u8 i;\n\tretro_u8 step = count;\n\tretro_u16 newest = 0;\n\tretro_u16 oldest = 0;\n";
	out += "\tfor (i = 0; i < RETRO_SEQ_HISTORY && step > 0; i++)\n\t{\n";
	out += "\t\tretro_u16 idx = (retro_u16)((sm_hist_pos + RETRO_SEQ_HISTORY - 1 - i) % RETRO_SEQ_HISTORY);\n";
	out += "\t\tretro_u16 value;\n";
	out += "\t\tif (sm_hist_tick[idx] == 0) continue;\n";
	out += "\t\tvalue = retro_sequence_steps[start + step - 1].mode == RETRO_COND_RELEASED ? sm_hist_released[idx] : sm_hist_pressed[idx];\n";
	out += "\t\tif ((value & retro_sequence_steps[start + step - 1].mask) == retro_sequence_steps[start + step - 1].mask)\n\t\t{\n";
	out += "\t\t\tif (newest == 0) newest = sm_hist_tick[idx];\n";
	out += "\t\t\toldest = sm_hist_tick[idx];\n";
	out += "\t\t\tstep--;\n";
	out += "\t\t}\n\t}\n";
	out += "\tif (step != 0) return 0;\n";
	out += "\tif (window > 0)\n\t{\n";
	out += "\t\tif ((retro_u16)(sm_tick - newest) > window) return 0;\n";
	out += "\t\tif ((retro_u16)(newest - oldest) > window) return 0;\n";
	out += "\t}\n\treturn 1;\n}\n\n";
	out += "static retro_u8 _retro_cond_match(retro_u16 start, retro_u8 count, retro_u8 op, retro_u16 current, retro_u16 pressed, retro_u16 released)\n{\n";
	out += "\tretro_u8 i;\n\tretro_u16 value;\n\tretro_u8 ok;\n";
	out += "\tif (count == 0) return 0;\n";
	out += "\tif (op == 1)\n\t{\n";
	out += "\t\tfor (i = 0; i < count; i++)\n\t\t{\n";
	out += "\t\t\tif (retro_conditions[start + i].seq_count > 0) { if (_retro_seq_match(retro_conditions[start + i].seq_start, retro_conditions[start + i].seq_count, retro_conditions[start + i].window)) return 1; continue; }\n";
	out += "\t\t\tvalue = retro_conditions[start + i].mode == RETRO_COND_PRESSED ? pressed : (retro_conditions[start + i].mode == RETRO_COND_RELEASED ? released : current);\n";
	out += "\t\t\tif ((value & retro_conditions[start + i].mask) == retro_conditions[start + i].mask) return 1;\n";
	out += "\t\t}\n\t\treturn 0;\n\t}\n";
	out += "\tfor (i = 0; i < count; i++)\n\t{\n";
	out += "\t\tif (retro_conditions[start + i].seq_count > 0) { ok = _retro_seq_match(retro_conditions[start + i].seq_start, retro_conditions[start + i].seq_count, retro_conditions[start + i].window); if (!ok) return 0; continue; }\n";
	out += "\t\tvalue = retro_conditions[start + i].mode == RETRO_COND_PRESSED ? pressed : (retro_conditions[start + i].mode == RETRO_COND_RELEASED ? released : current);\n";
	out += "\t\tok = (retro_u8)((value & retro_conditions[start + i].mask) == retro_conditions[start + i].mask);\n";
	out += "\t\tif (!ok) return 0;\n\t}\n\treturn 1;\n}\n\n";
	out += "static void _retro_fire(retro_u16 index)\n{\n";
	out += "\tsm_node = retro_transitions[index].to;\n";
	out += "\tsm_elapsed = 0;\n";
	out += "\tsm_last_transition = index;\n";
	out += "\tsm_cooldowns[index] = retro_transitions[index].cooldown;\n";
	out += "}\n\n";
	out += "static retro_u16 _retro_find_auto(void)\n{\n";
	out += "\tretro_u16 i;\n\tretro_u16 best;\n\tretro_u8 best_priority;\n";
	out += "\tbest = RETRO_NONE;\n\tbest_priority = 0;\n";
	out += "\tfor (i = 0; i < " + itos(MAX(1, trans_entries.size())) + "; i++)\n\t{\n";
	out += "\t\tif (i >= RETRO_TRANSITION_COUNT) break;\n";
	out += "\t\tif (!retro_transitions[i].auto_transition || retro_transitions[i].from != sm_node || sm_cooldowns[i] != 0) continue;\n";
	out += "\t\tif (best == RETRO_NONE || retro_transitions[i].priority > best_priority) { best = i; best_priority = retro_transitions[i].priority; }\n";
	out += "\t}\n\treturn best;\n}\n\n";
	out += "retro_node retro_sm_update(retro_u16 current, retro_u16 pressed)\n{\n";
	out += "\tretro_u16 released = (retro_u16)(sm_prev_pad & (retro_u16)~current);\n";
	out += "\tretro_u16 i;\n\tretro_u16 best;\n\tretro_u8 best_priority;\n";
	out += "\tsm_prev_pad = current;\n";
	out += "\tsm_tick++;\n";
	out += "\tif (pressed != 0 || released != 0)\n\t{\n";
	out += "\t\tsm_hist_pressed[sm_hist_pos] = pressed;\n";
	out += "\t\tsm_hist_released[sm_hist_pos] = released;\n";
	out += "\t\tsm_hist_tick[sm_hist_pos] = sm_tick;\n";
	out += "\t\tsm_hist_pos = (retro_u8)((sm_hist_pos + 1) % RETRO_SEQ_HISTORY);\n";
	out += "\t}\n\tbest = RETRO_NONE;\n\tbest_priority = 0;\n";
	out += "\tfor (i = 0; i < " + itos(MAX(1, trans_entries.size())) + "; i++)\n\t{\n";
	out += "\t\tif (i >= RETRO_TRANSITION_COUNT) break;\n";
	out += "\t\tif (retro_transitions[i].auto_transition || retro_transitions[i].from != sm_node || sm_cooldowns[i] != 0) continue;\n";
	out += "\t\tif (!_retro_cond_match(retro_transitions[i].cond_start, retro_transitions[i].cond_count, retro_transitions[i].op, current, pressed, released)) continue;\n";
	out += "\t\tif (best == RETRO_NONE || retro_transitions[i].priority > best_priority) { best = i; best_priority = retro_transitions[i].priority; }\n";
	out += "\t}\n";
	out += "\tif (best != RETRO_NONE) _retro_fire(best);\n";
	out += "\treturn sm_node;\n}\n\n";
	out += "retro_node retro_sm_tick(void)\n{\n";
	out += "\tretro_u16 i;\n\tretro_u16 auto_index;\n\tretro_u16 duration;\n";
	out += "\tfor (i = 0; i < " + itos(MAX(1, transitions.size())) + "; i++) if (sm_cooldowns[i] > 0) sm_cooldowns[i]--;\n";
	out += "\tsm_elapsed++;\n";
	out += "\tduration = retro_node_durations[sm_node];\n";
	out += "\tif (duration != 0 && sm_elapsed >= duration)\n\t{\n";
	out += "\t\tauto_index = _retro_find_auto();\n";
	out += "\t\tif (auto_index != RETRO_NONE) _retro_fire(auto_index);\n\t\telse sm_elapsed = duration;\n";
	out += "\t}\n\treturn sm_node;\n}\n\n";
	out += "retro_node retro_sm_state(void) { return sm_node; }\n";
	out += "retro_u16 retro_sm_frame(void) { return sm_elapsed; }\n";
	out += "retro_u16 retro_sm_last_transition(void) { return sm_last_transition; }\n";
	out += "retro_node retro_sm_animation_end(void)\n{\n\tretro_u16 i = _retro_find_auto();\n\tif (i != RETRO_NONE) _retro_fire(i);\n\treturn sm_node;\n}\n";
	out += "retro_node retro_sm_force_state(retro_node node)\n{\n\tif (node < RETRO_NODE_COUNT) { sm_node = node; sm_elapsed = 0; sm_last_transition = RETRO_NONE; }\n\treturn sm_node;\n}\n";
	out += "const char *retro_sm_state_name(retro_node node) { return node < RETRO_NODE_COUNT ? retro_node_names[node] : \"?\"; }\n";
	return out;
}

Dictionary RetroStateGraph::export_snes(const String &p_dir, const String &p_base, const Ref<RetroInputMap> &p_input) const {
	DirAccess::make_dir_recursive_absolute(p_dir);
	const String h = RetroUtil::join(p_dir, p_base + ".h");
	const String c = RetroUtil::join(p_dir, p_base + ".c");
	const Error e1 = RetroUtil::write_text(h, generate_header("snes"));
	const Error e2 = RetroUtil::write_text(c, generate_source("snes", p_input));
	Dictionary out;
	out["ok"] = e1 == OK && e2 == OK;
	out["header"] = h;
	out["source"] = c;
	out["nodes"] = nodes.size();
	out["transitions"] = transitions.size();
	return out;
}

Dictionary RetroStateGraph::export_sgdk(const String &p_dir, const String &p_base, const Ref<RetroInputMap> &p_input) const {
	DirAccess::make_dir_recursive_absolute(p_dir);
	const String h = RetroUtil::join(p_dir, p_base + ".h");
	const String c = RetroUtil::join(p_dir, p_base + ".c");
	const Error e1 = RetroUtil::write_text(h, generate_header("megadrive"));
	const Error e2 = RetroUtil::write_text(c, generate_source("megadrive", p_input));
	Dictionary out;
	out["ok"] = e1 == OK && e2 == OK;
	out["header"] = h;
	out["source"] = c;
	out["nodes"] = nodes.size();
	out["transitions"] = transitions.size();
	return out;
}

Error RetroStateGraph::save(const String &p_path) const {
	return RetroUtil::save_json_file(p_path, to_dict());
}

Error RetroStateGraph::load(const String &p_path) {
	bool ok = false;
	const Dictionary d = RetroUtil::parse_json_file(p_path, &ok);
	if (!ok) {
		return ERR_FILE_CANT_READ;
	}
	from_dict(d);
	return OK;
}

Dictionary RetroStateGraph::to_dict() const {
	Dictionary d;
	d["format"] = "godot-retro-engine/state-graph";
	d["version"] = 1;
	d["platform"] = platform;
	d["nodes"] = nodes;
	d["transitions"] = transitions;
	d["metadata"] = metadata;
	return d;
}

void RetroStateGraph::from_dict(const Dictionary &p_data) {
	platform = p_data.get("platform", platform);
	nodes = p_data.get("nodes", nodes);
	transitions = p_data.get("transitions", transitions);
	metadata = p_data.get("metadata", metadata);
}
