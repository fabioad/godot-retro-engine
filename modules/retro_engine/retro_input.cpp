/**************************************************************************/
/*  retro_input.cpp                                                       */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_input.h"

#include "retro_util.h"

void RetroInputMap::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup_defaults", "platform"), &RetroInputMap::setup_defaults);
	ClassDB::bind_method(D_METHOD("add_action", "action"), &RetroInputMap::add_action);
	ClassDB::bind_method(D_METHOD("update_action", "id", "action"), &RetroInputMap::update_action);
	ClassDB::bind_method(D_METHOD("remove_action", "id"), &RetroInputMap::remove_action);
	ClassDB::bind_method(D_METHOD("get_action", "id"), &RetroInputMap::get_action);
	ClassDB::bind_method(D_METHOD("action_index", "id"), &RetroInputMap::action_index);
	ClassDB::bind_method(D_METHOD("action_mask", "id", "platform"), &RetroInputMap::action_mask);
	ClassDB::bind_method(D_METHOD("mask_text", "id", "platform"), &RetroInputMap::mask_text);
	ClassDB::bind_method(D_METHOD("validate"), &RetroInputMap::validate);
	ClassDB::bind_method(D_METHOD("export_snes_header", "path"), &RetroInputMap::export_snes_header);
	ClassDB::bind_method(D_METHOD("export_snes_inc", "path"), &RetroInputMap::export_snes_inc);
	ClassDB::bind_method(D_METHOD("export_sgdk_header", "path"), &RetroInputMap::export_sgdk_header);
	ClassDB::bind_method(D_METHOD("export_state_machine_snes", "dir", "base"), &RetroInputMap::export_state_machine_snes, DEFVAL("retro_state_machine"));
	ClassDB::bind_method(D_METHOD("export_state_machine_sgdk", "dir", "base"), &RetroInputMap::export_state_machine_sgdk, DEFVAL("retro_state_machine"));
	ClassDB::bind_method(D_METHOD("generate_state_machine_header", "platform"), &RetroInputMap::generate_state_machine_header);
	ClassDB::bind_method(D_METHOD("generate_state_machine_source", "platform"), &RetroInputMap::generate_state_machine_source);
	ClassDB::bind_method(D_METHOD("save", "path"), &RetroInputMap::save);
	ClassDB::bind_method(D_METHOD("load", "path"), &RetroInputMap::load);
	ClassDB::bind_method(D_METHOD("to_dict"), &RetroInputMap::to_dict);
	ClassDB::bind_method(D_METHOD("from_dict", "data"), &RetroInputMap::from_dict);
	ClassDB::bind_static_method("RetroInputMap", D_METHOD("default_states"), &RetroInputMap::default_states);
	ClassDB::bind_static_method("RetroInputMap", D_METHOD("snes_buttons"), &RetroInputMap::snes_buttons);
	ClassDB::bind_static_method("RetroInputMap", D_METHOD("megadrive_buttons"), &RetroInputMap::megadrive_buttons);
	ClassDB::bind_static_method("RetroInputMap", D_METHOD("snes_bit", "name"), &RetroInputMap::snes_bit);
	ClassDB::bind_static_method("RetroInputMap", D_METHOD("megadrive_bit", "name"), &RetroInputMap::megadrive_bit);

	ClassDB::bind_method(D_METHOD("set_platform", "value"), &RetroInputMap::set_platform);
	ClassDB::bind_method(D_METHOD("get_platform"), &RetroInputMap::get_platform);
	ClassDB::bind_method(D_METHOD("set_actions", "value"), &RetroInputMap::set_actions);
	ClassDB::bind_method(D_METHOD("get_actions"), &RetroInputMap::get_actions);
	ClassDB::bind_method(D_METHOD("set_states", "value"), &RetroInputMap::set_states);
	ClassDB::bind_method(D_METHOD("get_states"), &RetroInputMap::get_states);
	ClassDB::bind_method(D_METHOD("set_state_durations", "value"), &RetroInputMap::set_state_durations);
	ClassDB::bind_method(D_METHOD("get_state_durations"), &RetroInputMap::get_state_durations);
	ClassDB::bind_method(D_METHOD("set_metadata", "value"), &RetroInputMap::set_metadata);
	ClassDB::bind_method(D_METHOD("get_metadata"), &RetroInputMap::get_metadata);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "platform"), "set_platform", "get_platform");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "actions"), "set_actions", "get_actions");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "states"), "set_states", "get_states");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "state_durations"), "set_state_durations", "get_state_durations");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "metadata"), "set_metadata", "get_metadata");
}

RetroInputMap::RetroInputMap() {
	setup_defaults("snes");
}

Array RetroInputMap::default_states() {
	Array out;
	out.push_back("IDLE");
	out.push_back("WALK");
	out.push_back("JUMP");
	out.push_back("CROUCH");
	out.push_back("ATTACK");
	out.push_back("HIT");
	out.push_back("BLOCK");
	out.push_back("SPECIAL");
	out.push_back("SUPER");
	out.push_back("THROW");
	return out;
}

Array RetroInputMap::snes_buttons() {
	Array out;
	out.push_back("B");
	out.push_back("Y");
	out.push_back("Select");
	out.push_back("Start");
	out.push_back("Up");
	out.push_back("Down");
	out.push_back("Left");
	out.push_back("Right");
	out.push_back("A");
	out.push_back("X");
	out.push_back("L");
	out.push_back("R");
	return out;
}

Array RetroInputMap::megadrive_buttons() {
	Array out;
	out.push_back("Up");
	out.push_back("Down");
	out.push_back("Left");
	out.push_back("Right");
	out.push_back("A");
	out.push_back("B");
	out.push_back("C");
	out.push_back("Start");
	out.push_back("X");
	out.push_back("Y");
	out.push_back("Z");
	out.push_back("MODE");
	return out;
}

int RetroInputMap::snes_bit(const String &p_name) {
	// Values match PVSnesLib KEY_* / padsCurrent().
	if (p_name == "B") return 0x8000;
	if (p_name == "Y") return 0x4000;
	if (p_name == "Select") return 0x2000;
	if (p_name == "Start") return 0x1000;
	if (p_name == "Up") return 0x0800;
	if (p_name == "Down") return 0x0400;
	if (p_name == "Left") return 0x0200;
	if (p_name == "Right") return 0x0100;
	if (p_name == "A") return 0x0080;
	if (p_name == "X") return 0x0040;
	if (p_name == "L") return 0x0020;
	if (p_name == "R") return 0x0010;
	return 0;
}

int RetroInputMap::megadrive_bit(const String &p_name) {
	// Values match SGDK BUTTON_* in <genesis.h>.
	if (p_name == "Up") return 0x0001;
	if (p_name == "Down") return 0x0002;
	if (p_name == "Left") return 0x0004;
	if (p_name == "Right") return 0x0008;
	if (p_name == "B") return 0x0010;
	if (p_name == "C") return 0x0020;
	if (p_name == "A") return 0x0040;
	if (p_name == "Start") return 0x0080;
	if (p_name == "Z") return 0x0100;
	if (p_name == "Y") return 0x0200;
	if (p_name == "X") return 0x0400;
	if (p_name == "MODE") return 0x0800;
	return 0;
}

static Array _retro_arr(std::initializer_list<String> p_values) {
	Array out;
	for (const String &v : p_values) {
		out.push_back(v);
	}
	return out;
}

static String _retro_input_id(const String &p_id) {
	String out = p_id.strip_edges().to_lower();
	for (int i = 0; i < out.length(); i++) {
		const char32_t c = out[i];
		if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')) {
			out = out.replace(String::chr(c), "_");
		}
	}
	return out.is_empty() ? "action" : out;
}

static String _retro_input_label(const String &p_name) {
	String out = p_name.to_upper();
	for (int i = 0; i < out.length(); i++) {
		const char32_t c = out[i];
		if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) {
			out = out.replace(String::chr(c), "_");
		}
	}
	return out;
}

static void _retro_add_default_action(Array &r_actions, const String &p_id, const String &p_label,
		const Array &p_snes, const Array &p_md, const Array &p_keys, const String &p_state) {
	Dictionary a;
	a["id"] = p_id;
	a["label"] = p_label;
	a["type"] = "button";
	a["snes"] = p_snes;
	a["md"] = p_md;
	a["keys"] = p_keys;
	a["gamepad"] = Array();
	a["state"] = p_state;
	a["next"] = "";
	a["hold"] = false;
	a["priority"] = 0;
	r_actions.push_back(a);
}

void RetroInputMap::setup_defaults(const String &p_platform) {
	platform = p_platform;
	states = default_states();
	state_durations = Array();
	for (int i = 0; i < states.size(); i++) {
		state_durations.push_back(0);
	}
	actions = Array();
	_retro_add_default_action(actions, "left", "Move Left", _retro_arr({"Left"}), _retro_arr({"Left"}), _retro_arr({"Left"}), "WALK");
	_retro_add_default_action(actions, "right", "Move Right", _retro_arr({"Right"}), _retro_arr({"Right"}), _retro_arr({"Right"}), "WALK");
	_retro_add_default_action(actions, "up", "Jump / Up", _retro_arr({"Up"}), _retro_arr({"Up"}), _retro_arr({"Up"}), "JUMP");
	_retro_add_default_action(actions, "down", "Crouch / Down", _retro_arr({"Down"}), _retro_arr({"Down"}), _retro_arr({"Down"}), "CROUCH");
	_retro_add_default_action(actions, "attack_a", "Attack A", _retro_arr({"B"}), _retro_arr({"A"}), _retro_arr({"Z"}), "ATTACK");
	_retro_add_default_action(actions, "attack_b", "Attack B", _retro_arr({"Y"}), _retro_arr({"B"}), _retro_arr({"X"}), "SPECIAL");
	_retro_add_default_action(actions, "attack_c", "Attack C", _retro_arr({"X"}), _retro_arr({"C"}), _retro_arr({"C"}), "SUPER");
	_retro_add_default_action(actions, "guard", "Guard", _retro_arr({"L"}), _retro_arr({"Y"}), _retro_arr({"A"}), "BLOCK");
	_retro_add_default_action(actions, "throw", "Throw", _retro_arr({"R"}), _retro_arr({"Z"}), _retro_arr({"S"}), "THROW");
	_retro_add_default_action(actions, "start", "Start", _retro_arr({"Start"}), _retro_arr({"Start"}), _retro_arr({"Enter"}), "IDLE");
	metadata["description"] = "Created by Godot Retro Engine";
	metadata["format_version"] = 1;
}

void RetroInputMap::add_action(const Dictionary &p_action) {
	Dictionary a = p_action;
	String id = _retro_input_id(String(a.get("id", "action")));
	int suffix = 1;
	String base = id;
	while (action_index(id) >= 0) {
		id = base + "_" + itos(suffix++);
	}
	a["id"] = id;
	if (!a.has("snes")) a["snes"] = Array();
	if (!a.has("md")) a["md"] = Array();
	if (!a.has("keys")) a["keys"] = Array();
	if (!a.has("gamepad")) a["gamepad"] = Array();
	if (!a.has("state")) a["state"] = "IDLE";
	if (!a.has("next")) a["next"] = "";
	if (!a.has("hold")) a["hold"] = false;
	if (!a.has("priority")) a["priority"] = 0;
	if (!a.has("type")) a["type"] = "button";
	if (!a.has("label")) a["label"] = id.capitalize();
	actions.push_back(a);
}

void RetroInputMap::update_action(const String &p_id, const Dictionary &p_action) {
	const int idx = action_index(p_id);
	if (idx < 0) {
		return;
	}
	Dictionary a = actions[idx];
	for (const Variant *K = p_action.next(nullptr); K; K = p_action.next(K)) {
		a[*K] = p_action[*K];
	}
	actions[idx] = a;
}

void RetroInputMap::remove_action(const String &p_id) {
	const int idx = action_index(p_id);
	if (idx >= 0) {
		actions.remove_at(idx);
	}
}

Dictionary RetroInputMap::get_action(const String &p_id) const {
	const int idx = action_index(p_id);
	return idx >= 0 ? Dictionary(actions[idx]) : Dictionary();
}

int RetroInputMap::action_index(const String &p_id) const {
	for (int i = 0; i < actions.size(); i++) {
		if (String(Dictionary(actions[i]).get("id", "")) == p_id) {
			return i;
		}
	}
	return -1;
}

int RetroInputMap::action_mask(const String &p_id, const String &p_platform) const {
	const Dictionary a = get_action(p_id);
	if (a.is_empty()) {
		return 0;
	}
	const Array buttons = a.get(p_platform == "megadrive" ? "md" : "snes", Array());
	int mask = 0;
	for (int i = 0; i < buttons.size(); i++) {
		mask |= p_platform == "megadrive" ? megadrive_bit(String(buttons[i])) : snes_bit(String(buttons[i]));
	}
	return mask;
}

String RetroInputMap::mask_text(const String &p_id, const String &p_platform) const {
	const Dictionary a = get_action(p_id);
	if (a.is_empty()) {
		return String();
	}
	const Array buttons = a.get(p_platform == "megadrive" ? "md" : "snes", Array());
	String out;
	for (int i = 0; i < buttons.size(); i++) {
		if (!out.is_empty()) {
			out += " | ";
		}
		out += (p_platform == "megadrive" ? "BUTTON_" : "KEY_") + String(buttons[i]).to_upper();
	}
	return out.is_empty() ? "0" : out;
}

Dictionary RetroInputMap::validate() const {
	Dictionary out;
	Array errors;
	Array warnings;
	Dictionary masks;
	for (int i = 0; i < actions.size(); i++) {
		const Dictionary a = actions[i];
		const String id = a.get("id", "");
		const String state = a.get("state", "");
		const int snes_mask = action_mask(id, "snes");
		const int md_mask = action_mask(id, "megadrive");
		if (snes_mask == 0) {
			warnings.push_back(id + ": no SNES button assigned");
		}
		if (md_mask == 0) {
			warnings.push_back(id + ": no Mega Drive button assigned");
		}
		if (!state.is_empty() && states.size() > 0 && !states.has(state)) {
			warnings.push_back(id + ": state '" + state + "' is not in the animation state list");
		}
		const String mask_key = itos(snes_mask) + "|" + state;
		if (snes_mask != 0 && masks.has(mask_key)) {
			warnings.push_back(id + ": SNES mask duplicates action '" + String(masks[mask_key]) + "' for state " + state);
		} else if (snes_mask != 0) {
			masks[mask_key] = id;
		}
		if (id.is_empty()) {
			errors.push_back("action with empty id at index " + itos(i));
		}
		if (String(a.get("next", "")) != "" && !states.has(a.get("next", ""))) {
			warnings.push_back(id + ": next state '" + String(a.get("next", "")) + "' is not in the animation state list");
		}
	}
	out["ok"] = errors.is_empty();
	out["errors"] = errors;
	out["warnings"] = warnings;
	out["action_count"] = actions.size();
	return out;
}

static int _retro_state_index(const Array &p_states, const String &p_name) {
	if (p_name.is_empty()) {
		return 0xFF;
	}
	for (int i = 0; i < p_states.size(); i++) {
		if (String(p_states[i]) == p_name) {
			return i;
		}
	}
	return 0xFF;
}

Dictionary RetroInputMap::export_snes_header(const String &p_path) const {
	String out;
	out += "/* Generated by Godot Retro Engine input exporter. */\n";
	out += "#ifndef RETRO_INPUT_H\n#define RETRO_INPUT_H\n\n";
	out += "#include <snes.h>\n\n";
	out += "#define RETRO_INPUT_COUNT " + itos(actions.size()) + "\n";
	out += "#define RETRO_INPUT_FLAG_HOLD 0x01\n";
	out += "#define RETRO_INPUT_NONE 0xFF\n\n";
	out += "/* Animation state indexes; keep in sync with the Animation editor. */\n";
	out += "enum RetroState {\n";
	for (int i = 0; i < states.size(); i++) {
		out += "\tRETRO_STATE_" + _retro_input_label(String(states[i])) + " = " + itos(i) + ",\n";
	}
	out += "\tRETRO_STATE_COUNT = " + itos(states.size()) + "\n";
	out += "};\n\n";
	out += "typedef struct {\n\tu16 mask;\n\tu8 state;\n\tu8 next;\n\tu8 flags;\n\tu8 priority;\n} RetroInputAction;\n\n";
	out += "static const RetroInputAction retro_input_actions[" + itos(MAX(1, actions.size())) + "] = {\n";
	for (int i = 0; i < actions.size(); i++) {
		const Dictionary a = actions[i];
		const int mask = action_mask(a.get("id", ""), "snes");
		const int st = _retro_state_index(states, a.get("state", ""));
		const int nx = _retro_state_index(states, a.get("next", ""));
		const int flags = bool(a.get("hold", false)) ? 1 : 0;
		out += "\t{ " + (mask == 0 ? "0" : mask_text(a.get("id", ""), "snes")) + ", " +
				(st == 0xFF ? "RETRO_INPUT_NONE" : itos(st)) + ", " +
				(nx == 0xFF ? "RETRO_INPUT_NONE" : itos(nx)) + ", " +
				itos(flags) + ", " + itos(int(a.get("priority", 0))) + " },\n";
	}
	if (actions.is_empty()) {
		out += "\t{ 0, RETRO_INPUT_NONE, RETRO_INPUT_NONE, 0, 0 },\n";
	}
	out += "};\n\n#endif\n";
	Dictionary result;
	result["ok"] = RetroUtil::write_text(p_path, out) == OK;
	result["path"] = p_path;
	result["actions"] = actions.size();
	return result;
}

Dictionary RetroInputMap::export_snes_inc(const String &p_path) const {
	String out;
	out += "; Generated by Godot Retro Engine input exporter.\n";
	out += "RETRO_INPUT_COUNT = " + itos(actions.size()) + "\n";
	out += "RETRO_INPUT_FLAG_HOLD = $01\n";
	out += "RETRO_INPUT_NONE = $FF\n";
	for (int i = 0; i < states.size(); i++) {
		out += "RETRO_STATE_" + _retro_input_label(String(states[i])) + " = " + itos(i) + "\n";
	}
	out += "\nretro_input_actions:\n";
	for (int i = 0; i < actions.size(); i++) {
		const Dictionary a = actions[i];
		const int mask = action_mask(a.get("id", ""), "snes");
		const int st = _retro_state_index(states, a.get("state", ""));
		const int nx = _retro_state_index(states, a.get("next", ""));
		const int flags = bool(a.get("hold", false)) ? 1 : 0;
		out += "\t.dw $" + String::num_int64(mask, 16).to_upper().pad_zeros(4) + "\n";
		out += "\t.db " + (st == 0xFF ? "$FF" : itos(st)) + ", " + (nx == 0xFF ? "$FF" : itos(nx)) + ", " + itos(flags) + ", " + itos(int(a.get("priority", 0))) + "\n";
	}
	if (actions.is_empty()) {
		out += "\t.dw $0000\n\t.db $FF, $FF, 0, 0\n";
	}
	Dictionary result;
	result["ok"] = RetroUtil::write_text(p_path, out) == OK;
	result["path"] = p_path;
	result["actions"] = actions.size();
	return result;
}

Dictionary RetroInputMap::export_sgdk_header(const String &p_path) const {
	String out;
	out += "/* Generated by Godot Retro Engine input exporter. */\n";
	out += "#ifndef RETRO_INPUT_H\n#define RETRO_INPUT_H\n\n";
	out += "#include <genesis.h>\n\n";
	out += "#define RETRO_INPUT_COUNT " + itos(actions.size()) + "\n";
	out += "#define RETRO_INPUT_FLAG_HOLD 0x01\n";
	out += "#define RETRO_INPUT_NONE 0xFF\n\n";
	out += "enum RetroState {\n";
	for (int i = 0; i < states.size(); i++) {
		out += "\tRETRO_STATE_" + _retro_input_label(String(states[i])) + " = " + itos(i) + ",\n";
	}
	out += "\tRETRO_STATE_COUNT = " + itos(states.size()) + "\n";
	out += "};\n\n";
	out += "typedef struct {\n\tu16 mask;\n\tu8 state;\n\tu8 next;\n\tu8 flags;\n\tu8 priority;\n} RetroInputAction;\n\n";
	out += "static const RetroInputAction retro_input_actions[" + itos(MAX(1, actions.size())) + "] = {\n";
	for (int i = 0; i < actions.size(); i++) {
		const Dictionary a = actions[i];
		const int mask = action_mask(a.get("id", ""), "megadrive");
		const int st = _retro_state_index(states, a.get("state", ""));
		const int nx = _retro_state_index(states, a.get("next", ""));
		const int flags = bool(a.get("hold", false)) ? 1 : 0;
		out += "\t{ " + (mask == 0 ? "0" : mask_text(a.get("id", ""), "megadrive")) + ", " +
				(st == 0xFF ? "RETRO_INPUT_NONE" : itos(st)) + ", " +
				(nx == 0xFF ? "RETRO_INPUT_NONE" : itos(nx)) + ", " +
				itos(flags) + ", " + itos(int(a.get("priority", 0))) + " },\n";
	}
	if (actions.is_empty()) {
		out += "\t{ 0, RETRO_INPUT_NONE, RETRO_INPUT_NONE, 0, 0 },\n";
	}
	out += "};\n\n#endif\n";
	Dictionary result;
	result["ok"] = RetroUtil::write_text(p_path, out) == OK;
	result["path"] = p_path;
	result["actions"] = actions.size();
	return result;
}

String RetroInputMap::generate_state_machine_header(const String &p_platform) const {
	(void)p_platform;
	String out;
	out += "/* Generated by Godot Retro Engine. Do not edit by hand. */\n";
	out += "#ifndef RETRO_STATE_MACHINE_H\n#define RETRO_STATE_MACHINE_H\n\n";
	out += "#include \"retro_input.h\"\n\n";
	out += "/* Feed the console pad state every frame.\n";
	out += " * SNES:     retro_sm_update(padsCurrent(0), padsDown(0));\n";
	out += " * MegaDrive: retro_sm_update(JOY_readJoypad(JOY_1), changed);\n";
	out += " */\n";
	out += "void retro_sm_init(void);\n";
	out += "u8 retro_sm_update(u16 current, u16 pressed);\n";
	out += "u8 retro_sm_state(void);\n";
	out += "u8 retro_sm_animation_end(void);\n";
	out += "u8 retro_sm_tick(void);\n";
	out += "u16 retro_sm_frame(void);\n";
	out += "u8 retro_sm_last_action(void);\n";
	out += "void retro_sm_force_state(u8 state);\n";
	out += "\n#endif\n";
	return out;
}

String RetroInputMap::generate_state_machine_source(const String &p_platform) const {
	(void)p_platform;
	String out;
	out += "/* Generated by Godot Retro Engine. Do not edit by hand. */\n";
	out += "#include \"retro_state_machine.h\"\n\n";
	out += "static u8 sm_state;\n";
	out += "static u16 sm_elapsed;\n";
	out += "static u8 sm_pending_next;\n";
	out += "static u8 sm_last_action;\n\n";
	out += "void retro_sm_init(void)\n{\n";
	out += "\tsm_state = 0;\n";
	out += "\tsm_elapsed = 0;\n";
	out += "\tsm_pending_next = RETRO_INPUT_NONE;\n";
	out += "\tsm_last_action = RETRO_INPUT_NONE;\n";
	out += "}\n\n";
	out += "/* Auto-transition durations in console frames; 0 disables auto-end. */\n";
	out += "static const u16 retro_state_durations[RETRO_STATE_COUNT] = {\n\t";
	for (int i = 0; i < states.size(); i++) {
		if (i > 0) out += ", ";
		if (i < state_durations.size()) {
			out += itos(int(state_durations[i]));
		} else {
			out += "0";
		}
	}
	out += "\n};\n\n";
	out += "u8 retro_sm_update(u16 current, u16 pressed)\n{\n";
	out += "\tu16 i;\n\tu16 mask;\n\tu16 value;\n\tu8 best;\n\tu8 best_priority;\n\tu8 prio;\n";
	out += "\tbest = RETRO_INPUT_NONE;\n\tbest_priority = 0;\n";
	out += "\tfor (i = 0; i < RETRO_INPUT_COUNT; i++)\n\t{\n";
	out += "\t\tmask = retro_input_actions[i].mask;\n";
	out += "\t\tif (mask == 0) continue;\n";
	out += "\t\tvalue = (retro_input_actions[i].flags & RETRO_INPUT_FLAG_HOLD) ? current : pressed;\n";
	out += "\t\tif ((value & mask) != mask) continue;\n";
	out += "\t\tprio = retro_input_actions[i].priority;\n";
	out += "\t\tif (best == RETRO_INPUT_NONE || prio > best_priority)\n\t\t{\n";
	out += "\t\t\tbest = (u8)i;\n\t\t\tbest_priority = prio;\n\t\t}\n";
	out += "\t}\n";
	out += "\tif (best != RETRO_INPUT_NONE)\n\t{\n";
	out += "\t\tif (retro_input_actions[best].state != RETRO_INPUT_NONE)\n";
	out += "\t\t{\n";
	out += "\t\t\tif (sm_state != retro_input_actions[best].state)\n";
	out += "\t\t\t\tsm_elapsed = 0;\n";
	out += "\t\t\tsm_state = retro_input_actions[best].state;\n";
	out += "\t\t}\n";
	out += "\t\tsm_pending_next = retro_input_actions[best].next;\n";
	out += "\t\tsm_last_action = best;\n";
	out += "\t}\n";
	out += "\treturn sm_state;\n}\n\n";
	out += "u8 retro_sm_state(void)\n{\n\treturn sm_state;\n}\n\n";
	out += "u8 retro_sm_animation_end(void)\n{\n";
	out += "\tif (sm_pending_next != RETRO_INPUT_NONE)\n\t{\n";
	out += "\t\tsm_state = sm_pending_next;\n\t\tsm_pending_next = RETRO_INPUT_NONE;\n\t\tsm_elapsed = 0;\n\t}\n";
	out += "\treturn sm_state;\n}\n\n";
	out += "u8 retro_sm_tick(void)\n{\n";
	out += "\tu16 duration = retro_state_durations[sm_state];\n";
	out += "\tsm_elapsed++;\n";
	out += "\tif (duration != 0 && sm_pending_next != RETRO_INPUT_NONE && sm_elapsed >= duration)\n\t{\n";
	out += "\t\tsm_state = sm_pending_next;\n\t\tsm_pending_next = RETRO_INPUT_NONE;\n\t\tsm_elapsed = 0;\n\t}\n";
	out += "\treturn sm_state;\n}\n\n";
	out += "u16 retro_sm_frame(void)\n{\n\treturn sm_elapsed;\n}\n\n";
	out += "u8 retro_sm_last_action(void)\n{\n\treturn sm_last_action;\n}\n\n";
	out += "void retro_sm_force_state(u8 state)\n{\n\tsm_state = state;\n\tsm_pending_next = RETRO_INPUT_NONE;\n\tsm_elapsed = 0;\n}\n";
	return out;
}

static Dictionary _retro_export_state_machine(const RetroInputMap *p_map, const String &p_platform,
		const String &p_dir, const String &p_base) {
	Dictionary result;
	DirAccess::make_dir_recursive_absolute(p_dir);
	const String input_path = RetroUtil::join(p_dir, "retro_input.h");
	const Dictionary input_res = p_platform == "megadrive"
			? p_map->export_sgdk_header(input_path)
			: p_map->export_snes_header(input_path);
	const String header_path = RetroUtil::join(p_dir, p_base + ".h");
	const String source_path = RetroUtil::join(p_dir, p_base + ".c");
	const Error e1 = RetroUtil::write_text(header_path, p_map->generate_state_machine_header(p_platform));
	const Error e2 = RetroUtil::write_text(source_path, p_map->generate_state_machine_source(p_platform));
	result["ok"] = bool(input_res.get("ok", false)) && e1 == OK && e2 == OK;
	result["input_header"] = input_path;
	result["header"] = header_path;
	result["source"] = source_path;
	result["actions"] = p_map->get_actions().size();
	result["states"] = p_map->get_states().size();
	return result;
}

Dictionary RetroInputMap::export_state_machine_snes(const String &p_dir, const String &p_base) const {
	return _retro_export_state_machine(this, "snes", p_dir, p_base);
}

Dictionary RetroInputMap::export_state_machine_sgdk(const String &p_dir, const String &p_base) const {
	return _retro_export_state_machine(this, "megadrive", p_dir, p_base);
}

Error RetroInputMap::save(const String &p_path) const {
	return RetroUtil::save_json_file(p_path, to_dict());
}

Error RetroInputMap::load(const String &p_path) {
	bool ok = false;
	const Dictionary d = RetroUtil::parse_json_file(p_path, &ok);
	if (!ok) {
		return ERR_FILE_CANT_READ;
	}
	from_dict(d);
	return OK;
}

Dictionary RetroInputMap::to_dict() const {
	Dictionary d;
	d["format"] = "godot-retro-engine/input-map";
	d["version"] = 1;
	d["platform"] = platform;
	d["actions"] = actions;
	d["states"] = states;
	d["state_durations"] = state_durations;
	d["metadata"] = metadata;
	return d;
}

void RetroInputMap::from_dict(const Dictionary &p_data) {
	platform = p_data.get("platform", platform);
	actions = p_data.get("actions", actions);
	states = p_data.get("states", states);
	state_durations = p_data.get("state_durations", state_durations);
	metadata = p_data.get("metadata", metadata);
}
