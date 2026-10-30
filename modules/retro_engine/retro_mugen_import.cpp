/**************************************************************************/
/*  retro_mugen_import.cpp                                                */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_mugen_import.h"

#include "retro_hitbox_io.h"
#include "retro_util.h"

void RetroMugenImport::_bind_methods() {
	ClassDB::bind_method(D_METHOD("parse_states", "cns_path", "air_path"), &RetroMugenImport::parse_states);
	ClassDB::bind_method(D_METHOD("auto_map_states", "parsed"), &RetroMugenImport::auto_map_states);
	ClassDB::bind_method(D_METHOD("parse_commands", "cmd_path"), &RetroMugenImport::parse_commands);
	ClassDB::bind_method(D_METHOD("import_state", "cns_path", "air_path", "state_number", "animation", "target_state"), &RetroMugenImport::import_state);
	ClassDB::bind_method(D_METHOD("import_mapped_states", "parsed", "mapping", "animation", "air_path"), &RetroMugenImport::import_mapped_states);
	ClassDB::bind_method(D_METHOD("build_fight_graph", "parsed", "mapping", "input", "max_nodes", "commands"), &RetroMugenImport::build_fight_graph, DEFVAL(0), DEFVAL(Dictionary()));
}

static int _retro_mugen_int(const String &p_text) {
	int sign = 1;
	int found = 0;
	bool have = false;
	for (int i = 0; i < p_text.length(); i++) {
		const char32_t c = p_text[i];
		if (c == '-' && !have) sign = -1;
		else if (c >= '0' && c <= '9') { found = found * 10 + (c - '0'); have = true; }
		else if (have) break;
	}
	return have ? found * sign : 0;
}

static String _retro_mugen_suggest(int p_state, const String &p_name, const String &p_type, const String &p_movetype) {
	const String n = p_name.to_lower();
	if (n.contains("guard") || n.contains("block")) return "BLOCK";
	if (p_state >= 170 && p_state <= 189) return "WIN";
	if (p_state >= 190 && p_state <= 199) return "INTRO";
	if (p_state >= 150 && p_state <= 155) return "BLOCK";
	if (p_state >= 120 && p_state <= 132) return "FALL";
	if (p_state >= 100 && p_state <= 106) return "HIT";
	if (p_state >= 20 && p_state <= 24) return "JUMP";
	if (p_state >= 40 && p_state <= 47) return "JUMP_ATTACK";
	if (n.contains("throw")) return "THROW";
	if (n.contains("jump") || n.contains("air")) return "JUMP";
	if (n.contains("crouch")) return "CROUCH";
	if (n.contains("walk")) return "WALK";
	if (n.contains("hit") || n.contains("fall") || p_movetype == "H") return "HIT";
	if (n.contains("super") || p_state >= 2000) return "SUPER";
	if (n.contains("special") || (p_state >= 1000 && p_state < 2000)) return "SPECIAL";
	if (n.contains("idle") || n.contains("stand") || p_state == 0) return "IDLE";
	if (p_type == "A" || p_type == "L") return "ATTACK";
	if (p_state >= 200) return "ATTACK";
	return "IDLE";
}

Dictionary RetroMugenImport::parse_states(const String &p_cns_path, const String &p_air_path) {
	Dictionary out;
	const String text = RetroUtil::read_text(p_cns_path);
	if (text.is_empty()) {
		out["ok"] = false;
		out["error"] = "CNS unreadable";
		return out;
	}
	const PackedStringArray lines = text.split("\n");
	Array states;
	Dictionary by_number;
	int current_index = -1;
	int current_number = -1;
	bool in_statedef = false;
	String block_type;
	Dictionary block;
	Array triggers;
	auto flush_block = [&]() {
		if (current_index < 0 || block_type.is_empty()) {
			block = Dictionary();
			triggers = Array();
			return;
		}
		Dictionary st = states[current_index];
		block["triggers"] = triggers;
		if (block_type == "changeanim") {
			Array anims = st.get("change_anims", Array());
			anims.push_back(block);
			st["change_anims"] = anims;
		} else if (block_type == "changestate") {
			Array changes = st.get("changes", Array());
			changes.push_back(block);
			st["changes"] = changes;
		} else if (block_type == "hitdef") {
			Array defs = st.get("hitdefs", Array());
			defs.push_back(block);
			st["hitdefs"] = defs;
		}
		states[current_index] = st;
		block = Dictionary();
		triggers = Array();
	};
	for (int i = 0; i < lines.size(); i++) {
		String line = lines[i].strip_edges();
		if (line.is_empty() || line.begins_with(";") || line.begins_with("//")) {
			continue;
		}
		if (line.begins_with("[Statedef")) {
			flush_block();
			const String n = line.get_slice(" ", 1).trim_suffix("]");
			current_number = n.to_int();
			in_statedef = true;
			Dictionary st;
			st["number"] = current_number;
			st["name"] = "State " + itos(current_number);
			st["type"] = "S";
			st["movetype"] = "I";
			st["anim"] = current_number;
			st["change_anims"] = Array();
			st["changes"] = Array();
			st["hitdefs"] = Array();
			if (!by_number.has(current_number)) {
				current_index = states.size();
				by_number[current_number] = current_index;
				states.push_back(st);
			} else {
				current_index = int(by_number[current_number]);
				states[current_index] = st;
			}
			block_type = "";
			continue;
		}
		if (line.begins_with("[State")) {
			flush_block();
			if (current_index >= 0) {
				in_statedef = false;
				block_type = "other";
				const String label = line.get_slice("]", 0).get_slice(",", 1).strip_edges();
				block = Dictionary();
				block["label"] = label;
				block["state"] = current_number;
			}
			continue;
		}
		if (line.begins_with("[") && current_index >= 0) {
			flush_block();
			in_statedef = false;
			block_type = "other";
			continue;
		}
		if (current_index < 0 || !line.contains("=")) {
			continue;
		}
		const String key = line.get_slice("=", 0).strip_edges().to_lower();
		const String value = line.substr(line.find("=") + 1).strip_edges();
		String clean_value = value;
		const int comment = clean_value.find(";");
		if (comment >= 0) {
			clean_value = clean_value.substr(0, comment).strip_edges();
		}
		if (key == "type" && !in_statedef) {
			const String tv = clean_value.to_lower();
			if (tv.contains("changeanim")) block_type = "changeanim";
			else if (tv.contains("changestate")) block_type = "changestate";
			else if (tv.contains("hitdef")) block_type = "hitdef";
			else if (block_type.is_empty()) block_type = "other";
			if (block_type == "hitdef") {
				block["raw"] = Array();
			}
			continue;
		}
		if (key.begins_with("trigger")) {
			triggers.push_back(key + " = " + clean_value);
			block["triggers"] = triggers;
			continue;
		}
		if (block_type == "hitdef") {
			Array raw = block.get("raw", Array());
			raw.push_back(line);
			block["raw"] = raw;
		}
		if (key == "name") {
			block["name"] = clean_value.trim_prefix("\"").trim_suffix("\"");
		}
		if (in_statedef && (block_type.is_empty() || block_type == "other")) {
			if (key == "name") {
				Dictionary st = states[current_index];
				st["name"] = clean_value.trim_prefix("\"").trim_suffix("\"");
				states[current_index] = st;
			} else if (key == "type") {
				Dictionary st = states[current_index];
				st["type"] = clean_value;
				states[current_index] = st;
			} else if (key == "movetype") {
				Dictionary st = states[current_index];
				st["movetype"] = clean_value;
				states[current_index] = st;
			} else if (key == "anim") {
				Dictionary st = states[current_index];
				st["anim"] = _retro_mugen_int(clean_value);
				states[current_index] = st;
			}
			continue;
		}
		block[key] = clean_value;
	}
	flush_block();

	// HitDef properties from the shared CNS parser, associated by MUGEN state.
	RetroHitboxIO cns_io;
	const Dictionary cns = cns_io.parse_cns(p_cns_path);
	Dictionary hitdef_by_state;
	if (bool(cns.get("ok", false))) {
		const Array cns_defs = cns.get("hitdefs", Array());
		for (int i = 0; i < cns_defs.size(); i++) {
			const Dictionary hd = cns_defs[i];
			const int hs = int(hd.get("state", -1));
			if (hs >= 0 && !hitdef_by_state.has(hs)) {
				hitdef_by_state[hs] = hd;
			}
		}
	}

	// AIR actions for frame counts / hitbox counts.
	RetroHitboxIO io;
	const Dictionary air = io.parse_air(p_air_path);
	Dictionary air_map;
	if (bool(air.get("ok", false))) {
		const Array air_actions = air.get("actions", Array());
		for (int i = 0; i < air_actions.size(); i++) {
			const Dictionary a = air_actions[i];
			const Array frames = a.get("frames", Array());
			int hits = 0;
			int hurts = 0;
			int duration = 0;
			for (int f = 0; f < frames.size(); f++) {
				const Dictionary fr = frames[f];
				hits += Array(fr.get("clsn1", Array())).size();
				hurts += Array(fr.get("clsn2", Array())).size();
				duration += int(fr.get("duration", 1));
			}
			Dictionary am;
			am["frames"] = frames.size();
			am["hit_count"] = hits;
			am["hurt_count"] = hurts;
			am["duration"] = duration;
			am["action"] = int(a.get("action", 0));
			air_map[am["action"]] = am;
		}
	}
	for (int i = 0; i < states.size(); i++) {
		Dictionary st = states[i];
		const int number = int(st.get("number", 0));
		int anim = _retro_mugen_int(String(st.get("anim", itos(number))));
		if (anim == 0 && Array(st.get("change_anims", Array())).size() > 0) {
			anim = _retro_mugen_int(String(Dictionary(Array(st.get("change_anims", Array()))[0]).get("value", itos(number))));
		}
		if (!air_map.has(anim) && air_map.has(number)) {
			anim = number;
		}
		st["air_action"] = anim;
		if (air_map.has(anim)) {
			const Dictionary am = air_map[anim];
			st["air_frames"] = am.get("frames", 0);
			st["air_hits"] = am.get("hit_count", 0);
			st["air_hurts"] = am.get("hurt_count", 0);
			st["air_duration"] = am.get("duration", 10);
		} else {
			st["air_frames"] = 0;
			st["air_hits"] = 0;
			st["air_hurts"] = 0;
			st["air_duration"] = 10;
		}
		st["suggested"] = _retro_mugen_suggest(number, String(st.get("name", "")), String(st.get("type", "S")), String(st.get("movetype", "I")));
		st["hitdef_count"] = Array(st.get("hitdefs", Array())).size();
		if (hitdef_by_state.has(number)) {
			st["hitdef_data"] = hitdef_by_state[number];
		}
		states[i] = st;
	}
	out["ok"] = !states.is_empty();
	out["states"] = states;
	out["state_count"] = states.size();
	out["air_action_count"] = air_map.size();
	out["cns_path"] = p_cns_path;
	out["air_path"] = p_air_path;
	return out;
}

Dictionary RetroMugenImport::import_state(const String &p_cns_path, const String &p_air_path, int p_state_number,
		const Ref<RetroAnimation> &p_animation, const String &p_target_state) {
	Dictionary result;
	const Dictionary parsed = parse_states(p_cns_path, p_air_path);
	if (!bool(parsed.get("ok", false))) {
		result["ok"] = false;
		return result;
	}
	Dictionary target;
	const Array parsed_states = parsed.get("states", Array());
	for (int i = 0; i < parsed_states.size(); i++) {
		if (int(Dictionary(parsed_states[i]).get("number", -1)) == p_state_number) {
			target = parsed_states[i];
			break;
		}
	}
	if (target.is_empty()) {
		result["ok"] = false;
		result["error"] = "state not found";
		return result;
	}
	RetroHitboxIO io;
	const Dictionary air = io.parse_air(p_air_path);
	Array frames;
	const Array air_actions = air.get("actions", Array());
	for (int i = 0; i < air_actions.size(); i++) {
		if (int(Dictionary(air_actions[i]).get("action", -1)) == int(target.get("air_action", -1))) {
			frames = Dictionary(air_actions[i]).get("frames", Array());
			break;
		}
	}
	const Dictionary imported = io.import_air_frames(frames, p_animation, p_target_state);
	result["ok"] = bool(imported.get("ok", false));
	result["state"] = target;
	result["import"] = imported;
	result["mapping_state"] = p_state_number;
	result["mapping_target"] = p_target_state;
	return result;
}

Dictionary RetroMugenImport::import_mapped_states(const Dictionary &p_parsed, const Dictionary &p_mapping,
		const Ref<RetroAnimation> &p_animation, const String &p_air_path) {
	Dictionary result;
	if (!bool(p_parsed.get("ok", false)) || p_animation.is_null()) {
		result["ok"] = false;
		result["error"] = "parsed states and an animation are required";
		return result;
	}
	RetroHitboxIO io;
	const Dictionary air = io.parse_air(p_air_path);
	if (!bool(air.get("ok", false))) {
		result["ok"] = false;
		result["error"] = "AIR file unreadable";
		return result;
	}
	Dictionary actions;
	const Array air_actions = air.get("actions", Array());
	for (int i = 0; i < air_actions.size(); i++) {
		const Dictionary a = air_actions[i];
		actions[int(a.get("action", -1))] = a;
	}
	const Array states = p_parsed.get("states", Array());
	int imported = 0;
	int frames = 0;
	int hits = 0;
	int hurts = 0;
	Dictionary loop_by_target;
	for (int i = 0; i < states.size(); i++) {
		const Dictionary st = states[i];
		const int num = int(st.get("number", -1));
		const String key = itos(num);
		if (!p_mapping.has(key) && !p_mapping.has(num)) {
			continue;
		}
		const String target = String(p_mapping.get(key, p_mapping.get(num, "")));
		if (target.is_empty()) {
			continue;
		}
		const int action = int(st.get("air_action", -1));
		if (!actions.has(action)) {
			continue;
		}
		const Array action_frames = Dictionary(actions[action]).get("frames", Array());
		if (action_frames.is_empty()) {
			continue;
		}
		const Dictionary r = io.import_air_frames(action_frames, p_animation, target);
		if (!bool(r.get("ok", false))) {
			continue;
		}
		imported++;
		frames += int(r.get("frames", 0));
		hits += int(r.get("hit_boxes", 0));
		hurts += int(r.get("hurt_boxes", 0));
		const String suggested = String(st.get("suggested", "IDLE"));
		loop_by_target[target] = suggested == "IDLE" || suggested == "WALK" || suggested == "CROUCH" || suggested == "JUMP" || suggested == "BLOCK";
	}
	Dictionary animation_states = p_animation->get_states();
	for (const Variant *K = loop_by_target.next(nullptr); K; K = loop_by_target.next(K)) {
		const String target = String(*K);
		if (!animation_states.has(target)) {
			continue;
		}
		Dictionary state = animation_states[target];
		state["loop"] = bool(loop_by_target[*K]);
		animation_states[target] = state;
	}
	p_animation->set_states(animation_states);
	result["ok"] = imported > 0;
	result["states"] = imported;
	result["frames"] = frames;
	result["hit_boxes"] = hits;
	result["hurt_boxes"] = hurts;
	return result;
}

static Array _retro_mugen_command_step_actions(const String &p_token, const String &p_mode) {
	Array actions;
	String token = p_token.strip_edges();
	// MUGEN prefixes can be repeated (e.g. /$F for a held release).
	while (!token.is_empty() && (token[0] == '~' || token[0] == '/' || token[0] == '$' || token[0] == '>')) {
		token = token.substr(1).strip_edges();
	}
	if (token.is_empty()) {
		return actions;
	}
	// Direction tokens are uppercase combinations of U/D/F/B (DF, UB, ...).
	// Lowercase letters are buttons; b must not become the "back" direction.
	bool direction = true;
	for (int i = 0; i < token.length(); i++) {
		const char32_t c = token[i];
		if (c == 'U') actions.push_back("up");
		else if (c == 'D') actions.push_back("down");
		else if (c == 'F') actions.push_back("right");
		else if (c == 'B') actions.push_back("left");
		else { direction = false; break; }
	}
	if (direction && !actions.is_empty()) {
		return actions;
	}
	actions = Array();
	const String lower = token.to_lower();
	if (lower == "x" || lower == "a") actions.push_back("attack_a");
	else if (lower == "y" || lower == "b") actions.push_back("attack_b");
	else if (lower == "z" || lower == "c") actions.push_back("attack_c");
	else if (lower == "s" || lower == "start") actions.push_back("start");
	else if (lower == "guard" || lower == "g") actions.push_back("guard");
	else if (lower == "throw" || lower == "t") actions.push_back("throw");
	(void)p_mode;
	return actions;
}

Dictionary RetroMugenImport::parse_commands(const String &p_cmd_path) const {
	Dictionary out;
	// MUGEN .cmd files are often Shift-JIS. Command syntax is ASCII, so keep
	// ASCII bytes and replace non-ASCII comment bytes with spaces instead of
	// letting the UTF-8 decoder emit replacement warnings.
	const Vector<uint8_t> data = RetroUtil::read_bytes(p_cmd_path);
	String text;
	for (int i = 0; i < data.size(); i++) {
		const uint8_t b = data[i];
		if (b == '\n' || b == '\r' || b == '\t' || (b >= 32 && b < 127)) {
			text += String::chr((char32_t)b);
		} else {
			text += " ";
		}
	}
	if (text.is_empty()) {
		out["ok"] = false;
		out["error"] = "CMD unreadable";
		return out;
	}
	const PackedStringArray lines = text.split("\n");
	Array commands;
	Dictionary current;
	bool in_command = false;
	for (int i = 0; i < lines.size(); i++) {
		String line = lines[i].strip_edges();
		if (line.is_empty() || line.begins_with(";") || line.begins_with("//")) {
			continue;
		}
		if (line.begins_with("[")) {
			if (in_command && current.has("name") && current.has("command_raw")) {
				commands.push_back(current);
			}
			current = Dictionary();
			in_command = line.to_lower().begins_with("[command");
			continue;
		}
		if (!in_command || !line.contains("=")) {
			continue;
		}
		const String key = line.get_slice("=", 0).strip_edges().to_lower();
		String value = line.substr(line.find("=") + 1).strip_edges();
		const int comment = value.find(";");
		if (comment >= 0) {
			value = value.substr(0, comment).strip_edges();
		}
		if (key == "name") {
			current["name"] = value.trim_prefix("\"").trim_suffix("\"");
		} else if (key == "command") {
			current["command_raw"] = value;
		} else if (key == "time") {
			current["time"] = value.to_int();
		}
	}
	if (in_command && current.has("name") && current.has("command_raw")) {
		commands.push_back(current);
	}

	Dictionary by_name;
	Array warnings;
	for (int i = 0; i < commands.size(); i++) {
		Dictionary cmd = commands[i];
		const String name = String(cmd.get("name", "")).strip_edges().to_lower();
		const String raw = String(cmd.get("command_raw", ""));
		if (name.is_empty() || raw.is_empty()) {
			continue;
		}
		Array steps;
		bool step_ok = true;
		const PackedStringArray groups = raw.split(",");
		for (int g = 0; g < groups.size(); g++) {
			String group = groups[g].strip_edges();
			if (group.is_empty()) continue;
			String mode = "pressed";
			if (group.contains("$") || group.contains(">")) {
				mode = "held";
			} else if (group.contains("~") || group.contains("/")) {
				mode = "released";
			}
			while (group.begins_with("~") || group.begins_with("/") || group.begins_with("$") || group.begins_with(">")) {
				group = group.substr(1).strip_edges();
			}
			Array actions;
			const PackedStringArray tokens = group.replace(" ", "+").split("+", false);
			for (int t = 0; t < tokens.size(); t++) {
				const Array token_actions = _retro_mugen_command_step_actions(tokens[t], mode);
				if (token_actions.is_empty()) {
					step_ok = false;
					warnings.push_back(name + ": unknown command token '" + tokens[t] + "'");
					continue;
				}
				for (int a = 0; a < token_actions.size(); a++) {
					if (!actions.has(token_actions[a])) actions.push_back(token_actions[a]);
				}
			}
			if (actions.is_empty()) {
				step_ok = false;
				continue;
			}
			Dictionary step;
			step["actions"] = actions;
			step["mode"] = mode;
			steps.push_back(step);
		}
		Dictionary parsed_cmd;
		parsed_cmd["name"] = name;
		parsed_cmd["command_raw"] = raw;
		parsed_cmd["time"] = cmd.has("time") ? int(cmd["time"]) : 15;
		parsed_cmd["steps"] = steps;
		parsed_cmd["ok"] = step_ok && !steps.is_empty();
		by_name[name] = parsed_cmd;
	}
	out["ok"] = !by_name.is_empty();
	out["commands"] = by_name;
	out["command_count"] = by_name.size();
	out["path"] = p_cmd_path;
	out["warnings"] = warnings;
	return out;
}

static String _retro_mugen_trigger_command(const String &p_trigger);

Dictionary RetroMugenImport::auto_map_states(const Dictionary &p_parsed) const {
	Dictionary result;
	if (!bool(p_parsed.get("ok", false))) {
		result["ok"] = false;
		return result;
	}
	const Array states = p_parsed.get("states", Array());
	Dictionary mapping;
	Dictionary used;
	auto add = [&](const Dictionary &p_state, const String &p_force_base = String()) {
		const int num = int(p_state.get("number", -1));
		if (num < 0 || mapping.has(itos(num))) return;
		String base = p_force_base.is_empty() ? String(p_state.get("suggested", "STATE")) : p_force_base;
		if (base.is_empty()) base = "STATE";
		String target = base;
		if (used.has(target)) target = base + "_" + itos(num);
		int suffix = 2;
		while (used.has(target)) target = base + "_" + itos(num) + "_" + itos(suffix++);
		mapping[itos(num)] = target;
		used[target] = true;
	};
	// Stable priority: idle first, then command entries, HitDef attacks, rest.
	for (int i = 0; i < states.size(); i++) {
		const Dictionary st = states[i];
		if (int(st.get("number", -1)) == 0) add(st, "IDLE");
	}
	for (int i = 0; i < states.size(); i++) {
		const Dictionary st = states[i];
		const Array changes = st.get("changes", Array());
		bool has_command = false;
		for (int c = 0; c < changes.size() && !has_command; c++) {
			const Array triggers = Dictionary(changes[c]).get("triggers", Array());
			for (int t = 0; t < triggers.size(); t++) {
				if (!_retro_mugen_trigger_command(String(triggers[t])).is_empty()) {
					has_command = true;
					break;
				}
			}
		}
		if (has_command) add(st);
	}
	for (int i = 0; i < states.size(); i++) {
		const Dictionary st = states[i];
		if (int(st.get("hitdef_count", 0)) > 0) add(st);
	}
	for (int i = 0; i < states.size(); i++) {
		add(states[i]);
	}
	result["ok"] = true;
	result["mapping"] = mapping;
	result["count"] = mapping.size();
	return result;
}

static String _retro_mugen_canonical(int p_state) {
	switch (p_state) {
		case 0: return "IDLE";
		case 5: return "WALK";
		case 10: case 11: case 12: return "CROUCH";
		case 20: case 21: case 22: case 23: case 24: return "JUMP";
		case 40: case 41: case 42: case 43: case 44: case 45: case 46: case 47: return "JUMP_ATTACK";
		case 50: case 51: case 52: return "RUN";
		case 100: case 101: case 105: case 106: return "HIT";
		case 120: case 121: return "FALL";
		case 130: case 131: case 132: return "LIE";
		case 150: case 151: case 152: case 153: case 154: case 155: return "BLOCK";
		case 170: case 171: case 172: case 173: case 175: case 180: case 181: case 182: case 183: case 184: return "WIN";
		case 190: case 191: case 192: case 193: case 194: return "INTRO";
		default: return String();
	}
}

// Extract the quoted command from a trigger such as
// trigger1 = command = "holdfwd". Returns an empty string for
// negative comparisons (command != "...") and non-command triggers.
static String _retro_mugen_trigger_command(const String &p_trigger) {
	const String lower = p_trigger.to_lower();
	const int cmd = lower.find("command");
	if (cmd < 0) return String();
	const int neq = lower.find("!=", cmd);
	const int eq = lower.find("=", cmd);
	if (neq >= 0 && (eq < 0 || neq <= eq + 1)) return String();
	const int q1 = p_trigger.find("\"");
	if (q1 < 0) return String();
	const int q2 = p_trigger.find("\"", q1 + 1);
	if (q2 < 0) return String();
	return p_trigger.substr(q1 + 1, q2 - q1 - 1).strip_edges().to_lower();
}

static String _retro_mugen_resolve_action(const String &p_command, const Array &p_actions, String &r_mode) {
	String cmd = p_command.strip_edges().to_lower();
	r_mode = "pressed";
	if (cmd.begins_with("~")) {
		r_mode = "released";
		cmd = cmd.substr(1);
	}
	if (cmd.begins_with("hold")) {
		r_mode = "held";
		cmd = cmd.substr(4);
	} else if (cmd.begins_with("release")) {
		r_mode = "released";
		cmd = cmd.substr(7);
	} else if (cmd.begins_with("press")) {
		cmd = cmd.substr(5);
	}
	String resolved = cmd;
	if (cmd == "x" || cmd == "a") resolved = "attack_a";
	else if (cmd == "y" || cmd == "b") resolved = "attack_b";
	else if (cmd == "z" || cmd == "c") resolved = "attack_c";
	else if (cmd == "fwd" || cmd == "forward" || cmd == "pf") resolved = "right";
	else if (cmd == "back" || cmd == "pb") resolved = "left";
	else if (cmd == "guard" || cmd == "block") resolved = "guard";
	for (int i = 0; i < p_actions.size(); i++) {
		const String id = String(Dictionary(p_actions[i]).get("id", "")).to_lower();
		if (id == resolved) return id;
	}
	// Last-resort match for descriptive identifiers (never single letters).
	if (cmd.length() > 2) {
		for (int i = 0; i < p_actions.size(); i++) {
			const String id = String(Dictionary(p_actions[i]).get("id", "")).to_lower();
			if (id.contains(cmd) || cmd.contains(id)) return id;
		}
	}
	return String();
}

Dictionary RetroMugenImport::build_fight_graph(const Dictionary &p_parsed, const Dictionary &p_mapping,
		const Ref<RetroInputMap> &p_input, int p_max_nodes, const Dictionary &p_commands) {
	Dictionary result;
	if (!bool(p_parsed.get("ok", false))) {
		result["ok"] = false;
		result["error"] = "parse_states must succeed first";
		return result;
	}
	Ref<RetroStateGraph> graph;
	graph.instantiate();

	const Array states = p_parsed.get("states", Array());
	Dictionary by_number;
	for (int i = 0; i < states.size(); i++) {
		const Dictionary st = states[i];
		by_number[int(st.get("number", -1))] = st;
	}

	Dictionary node_by_number; // MUGEN state number -> graph node id
	Dictionary node_by_name;   // graph node state name -> graph node id
	Array warnings;
	int auto_nodes = 0;

	auto mapped_name = [&](int p_number, String &r_name) -> bool {
		const String key = itos(p_number);
		if (p_mapping.has(key)) {
			r_name = String(p_mapping[key]).strip_edges();
			return !r_name.is_empty();
		}
		if (p_mapping.has(p_number)) {
			r_name = String(p_mapping[p_number]).strip_edges();
			return !r_name.is_empty();
		}
		return false;
	};

	auto ensure_node = [&](int p_number, bool p_auto) -> String {
		if (node_by_number.has(p_number)) {
			return String(node_by_number[p_number]);
		}
		Dictionary st;
		if (by_number.has(p_number)) {
			st = by_number[p_number];
		}
		String name;
		const bool is_mapped = mapped_name(p_number, name);
		if (!is_mapped) {
			const String suggested = st.is_empty() ? String() : String(st.get("suggested", ""));
			const bool default_name = st.is_empty() || String(st.get("name", "")).begins_with("State ");
			if (default_name) {
				name = _retro_mugen_canonical(p_number);
			}
			if (name.is_empty()) {
				const String base = suggested.is_empty() ? String("STATE") : suggested;
				name = base + "_" + itos(p_number);
			}
			if (p_auto) auto_nodes++;
		}
		String id = String(node_by_name.get(name, ""));
		if (!id.is_empty() && !st.is_empty()) {
			// Reuse a canonical node that was first created as an auto target,
			// but upgrade its duration once a real state maps to it.
			if (int(graph->get_node(id).get("duration", 0)) <= 0) {
				graph->update_node(id, {{"duration", int(st.get("air_duration", 0))}});
			}
		}
		if (id.is_empty()) {
			const int duration = st.is_empty() ? 0 : int(st.get("air_duration", 0));
			const int slot = graph->get_nodes().size();
			graph->add_node(name, Vector2(40 + (slot % 5) * 210, 40 + (slot / 5) * 140), duration);
			for (int n = 0; n < graph->get_nodes().size(); n++) {
				const Dictionary node = graph->get_nodes()[n];
				if (String(node.get("state", "")) == name) {
					id = String(node.get("id", ""));
					break;
				}
			}
			node_by_name[name] = id;
		}
		node_by_number[p_number] = id;
		return id;
	};

	const int max_nodes = p_max_nodes <= 0 ? 0 : CLAMP(p_max_nodes, 4, 65535);
	auto has_command_change = [&](const Dictionary &p_state) -> bool {
		const Array changes = p_state.get("changes", Array());
		for (int c = 0; c < changes.size(); c++) {
			const Array triggers = Dictionary(changes[c]).get("triggers", Array());
			for (int t = 0; t < triggers.size(); t++) {
				if (!_retro_mugen_trigger_command(String(triggers[t])).is_empty()) {
					return true;
				}
			}
		}
		return false;
	};
	auto add_mapped_if_room = [&](int p_num) {
		if (max_nodes > 0 && graph->get_nodes().size() >= max_nodes) {
			return;
		}
		String name;
		if (mapped_name(p_num, name)) {
			(void)ensure_node(p_num, false);
		}
	};
	// Priority keeps the generated machine playable: idle first, then command
	// entries, attacks with HitDefs, remaining mapped states, and finally one
	// level of ChangeState targets. A full 200+ node MUGEN dump is not useful in
	// GraphEdit, so max_nodes defaults to 48 and is user-adjustable.
	for (int i = 0; i < states.size(); i++) {
		const Dictionary st = states[i];
		const int num = int(st.get("number", -1));
		String name;
		if (mapped_name(num, name) && (num == 0 || name == "IDLE")) {
			add_mapped_if_room(num);
		}
	}
	for (int i = 0; i < states.size(); i++) {
		const Dictionary st = states[i];
		if (has_command_change(st)) {
			add_mapped_if_room(int(st.get("number", -1)));
		}
	}
	for (int i = 0; i < states.size(); i++) {
		const Dictionary st = states[i];
		if (int(st.get("hitdef_count", 0)) > 0) {
			add_mapped_if_room(int(st.get("number", -1)));
		}
	}
	for (int i = 0; i < states.size(); i++) {
		add_mapped_if_room(int(Dictionary(states[i]).get("number", -1)));
	}
	if (graph->get_nodes().is_empty()) {
		(void)ensure_node(0, true);
	}

	// Add one level of ChangeState targets so the generated graph contains
	// real transitions instead of only isolated mapped nodes.
	for (int i = 0; i < states.size(); i++) {
		const Dictionary st = states[i];
		const int num = int(st.get("number", -1));
		if (!node_by_number.has(num)) {
			continue;
		}
		const Array changes = st.get("changes", Array());
		for (int c = 0; c < changes.size(); c++) {
			const int target_num = _retro_mugen_int(String(Dictionary(changes[c]).get("value", "")));
			if (target_num < 0 || node_by_number.has(target_num)) {
				continue;
			}
			if (max_nodes > 0 && graph->get_nodes().size() >= max_nodes) {
				break;
			}
			const bool known = by_number.has(target_num) || !_retro_mugen_canonical(target_num).is_empty();
			if (known) {
				(void)ensure_node(target_num, true);
			}
		}
	}
	if (max_nodes > 0 && graph->get_nodes().size() >= max_nodes) {
		warnings.push_back("Node cap " + itos(max_nodes) + " reached; set Max nodes to 0 to import all states");
	}

	const Array input_actions = p_input.is_valid() ? p_input->get_actions() : Array();
	Dictionary seen_edges;
	int skipped = 0;
	for (int i = 0; i < states.size(); i++) {
		const Dictionary st = states[i];
		const int num = int(st.get("number", -1));
		if (!node_by_number.has(num)) {
			continue;
		}
		const String source = String(node_by_number[num]);
		const Array changes = st.get("changes", Array());
		for (int c = 0; c < changes.size(); c++) {
			const Dictionary ch = changes[c];
			const int target_num = _retro_mugen_int(String(ch.get("value", "")));
			if (!node_by_number.has(target_num)) {
				continue;
			}
			const String target = String(node_by_number[target_num]);
			if (target == source) {
				continue; // A self transition would immediately reloop.
			}
			Array conds;
			bool auto_transition = false;
			const Array triggers = ch.get("triggers", Array());
			for (int t = 0; t < triggers.size(); t++) {
				const String trigger = String(triggers[t]);
				const String command = _retro_mugen_trigger_command(trigger);
				if (!command.is_empty()) {
					bool handled = false;
					if (p_commands.has(command)) {
						const Dictionary cd = p_commands[command];
						if (bool(cd.get("ok", false))) {
							Array steps = cd.get("steps", Array());
							Array checked_steps;
							bool all_actions = true;
							for (int s = 0; s < steps.size(); s++) {
								Dictionary step = steps[s];
								Array kept;
								const Array step_actions = step.get("actions", Array());
								for (int a = 0; a < step_actions.size(); a++) {
									const String aid = String(step_actions[a]);
									bool exists = false;
									for (int ia = 0; ia < input_actions.size(); ia++) {
										if (String(Dictionary(input_actions[ia]).get("id", "")) == aid) { exists = true; break; }
									}
									if (exists) kept.push_back(aid);
								}
								if (kept.is_empty()) { all_actions = false; break; }
								Dictionary checked = step;
								checked["actions"] = kept;
								checked_steps.push_back(checked);
							}
							if (all_actions && !checked_steps.is_empty()) {
								Dictionary cond;
								cond["sequence"] = checked_steps;
								cond["window"] = int(cd.get("time", 15));
								cond["command"] = command;
								conds.push_back(cond);
								handled = true;
							}
						}
					}
					if (!handled) {
						String mode;
						const String action = _retro_mugen_resolve_action(command, input_actions, mode);
						if (!action.is_empty()) {
							Dictionary cond;
							cond["action"] = action;
							cond["mode"] = mode;
							conds.push_back(cond);
						}
					}
				}
				const String lower = trigger.to_lower();
				if (command.is_empty() && (lower.contains("animelem") || lower.contains("animtime"))) {
					auto_transition = true;
				}
			}
			if (conds.is_empty() && !auto_transition) {
				skipped++;
				if (warnings.size() < 60) {
					warnings.push_back("State " + itos(num) + " -> " + itos(target_num) + ": trigger not mapped; transition skipped");
				}
				continue;
			}
			String signature = source + "|" + target + "|" + (auto_transition ? "auto" : "cond");
			if (!auto_transition) {
				for (int k = 0; k < conds.size(); k++) {
					signature += "|" + String(Dictionary(conds[k]).get("action", "")) + ":" + String(Dictionary(conds[k]).get("mode", ""));
				}
			}
			if (seen_edges.has(signature)) {
				continue;
			}
			seen_edges[signature] = true;
			Dictionary tr;
			tr["from"] = source;
			tr["to"] = target;
			tr["op"] = "all";
			tr["cooldown"] = 0;
			tr["priority"] = conds.is_empty() ? 0 : 10;
			tr["auto"] = auto_transition || conds.is_empty();
			tr["conditions"] = conds;
			graph->add_transition(tr);
		}
	}

	// States with animation duration but no explicit ChangeState return to idle.
	const String root = String(node_by_name.get("IDLE", graph->get_nodes().is_empty() ? String() : String(Dictionary(graph->get_nodes()[0]).get("id", ""))));
	if (!root.is_empty()) {
		Dictionary has_outgoing;
		const Array transitions = graph->get_transitions();
		for (int t = 0; t < transitions.size(); t++) {
			has_outgoing[String(Dictionary(transitions[t]).get("from", ""))] = true;
		}
		const Array nodes = graph->get_nodes();
		for (int n = 0; n < nodes.size(); n++) {
			const Dictionary node = nodes[n];
			const String id = String(node.get("id", ""));
			if (id == root || has_outgoing.has(id) || int(node.get("duration", 0)) <= 0) {
				continue;
			}
			Dictionary tr;
			tr["from"] = id;
			tr["to"] = root;
			tr["op"] = "all";
			tr["cooldown"] = 0;
			tr["priority"] = 0;
			tr["auto"] = true;
			tr["conditions"] = Array();
			graph->add_transition(tr);
		}
	}

	Array moves;
	Dictionary move_states;
	for (int i = 0; i < states.size(); i++) {
		const Dictionary st = states[i];
		const int num = int(st.get("number", -1));
		if (!node_by_number.has(num)) {
			continue;
		}
		const String target = String(Dictionary(graph->get_node(String(node_by_number[num]))).get("state", ""));
		if (target.is_empty() || move_states.has(target)) {
			continue;
		}
		const Dictionary hd = st.get("hitdef_data", Dictionary());
		Dictionary move;
		move["state"] = target;
		move["damage"] = int(hd.get("damage", 0));
		move["hitstop_attacker"] = int(hd.get("hitstop_attacker", 0));
		move["hitstop_defender"] = int(hd.get("hitstop_defender", 0));
		move["hitstun"] = int(hd.get("hitstun", 0));
		move["blockstun"] = int(hd.get("blockstun", 0));
		move["invuln"] = 0;
		move["guard"] = String(hd.get("guardflag", "M")).strip_edges() != "";
		move["priority"] = _retro_mugen_int(String(hd.get("priority", "0")));
		move["hit_id"] = int(hd.get("id", 0));
		move["pushback"] = abs(int(hd.get("ground_velocity", 0)));
		moves.push_back(move);
		move_states[target] = true;
	}

	graph->set_platform(p_input.is_valid() ? p_input->get_platform() : String("snes"));
	Dictionary graph_meta;
	graph_meta["source"] = "mugen";
	graph_meta["cns"] = String(p_parsed.get("cns_path", ""));
	graph_meta["air"] = String(p_parsed.get("air_path", ""));
	graph_meta["max_nodes"] = max_nodes;
	graph->set_metadata(graph_meta);
	result["ok"] = true;
	result["graph"] = graph;
	result["moves"] = moves;
	result["warnings"] = warnings;
	result["node_count"] = graph->get_nodes().size();
	result["transition_count"] = graph->get_transitions().size();
	result["auto_node_count"] = auto_nodes;
	result["skipped_transitions"] = skipped;
	return result;
}
