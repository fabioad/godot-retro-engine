/**************************************************************************/
/*  retro_hitbox_io.cpp                                                   */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_hitbox_io.h"

#include "retro_util.h"

#include <cmath>
#include <cstdlib>

void RetroHitboxIO::_bind_methods() {
	ClassDB::bind_method(D_METHOD("parse_air", "path"), &RetroHitboxIO::parse_air);
	ClassDB::bind_method(D_METHOD("parse_cns", "path"), &RetroHitboxIO::parse_cns);
	ClassDB::bind_method(D_METHOD("import_air_frames", "frames", "animation", "state"), &RetroHitboxIO::import_air_frames);
	ClassDB::bind_method(D_METHOD("import_air_action", "action", "animation", "state"), &RetroHitboxIO::import_air_action);
	ClassDB::bind_method(D_METHOD("export_air", "animation", "state", "action", "path"), &RetroHitboxIO::export_air);
}

static Rect2i _retro_air_rect(const String &p_text) {
	String s = p_text;
	s = s.replace("=", " ");
	const PackedStringArray parts = s.replace(",", " ").split(" ", false);
	if (parts.size() < 4) {
		return Rect2i();
	}
	const int x1 = parts[0].to_int();
	const int y1 = parts[1].to_int();
	const int x2 = parts[2].to_int();
	const int y2 = parts[3].to_int();
	return Rect2i(x1, y1, x2 - x1, y2 - y1);
}

static int _retro_first_int(const String &p_text) {
	int sign = 1;
	int found = 0;
	bool have = false;
	for (int i = 0; i < p_text.length(); i++) {
		const char32_t c = p_text[i];
		if (c == '-' && !have) {
			sign = -1;
		} else if (c >= '0' && c <= '9') {
			found = found * 10 + (c - '0');
			have = true;
		} else if (have) {
			break;
		}
	}
	return have ? found * sign : 0;
}

static int _retro_second_int(const String &p_text) {
	// Use the last top-level comma: real MUGEN expressions such as
	// "11+(Helper(40000),var(0)),13" contain commas inside parentheses.
	const int comma = p_text.rfind(",");
	if (comma >= 0) {
		return _retro_first_int(p_text.substr(comma + 1));
	}
	return _retro_first_int(p_text);
}

Dictionary RetroHitboxIO::parse_air(const String &p_path) {
	Dictionary out;
	const String text = RetroUtil::read_text(p_path);
	if (text.is_empty()) {
		out["ok"] = false;
		out["error"] = "empty or unreadable AIR file";
		return out;
	}
	const PackedStringArray lines = text.split("\n");
	Array actions;
	Dictionary current;
	Array frames;
	int action = -1;
	Array defaults1;
	Array defaults2;
	Array explicit1;
	Array explicit2;
	bool has_explicit1 = false;
	bool has_explicit2 = false;
	int clsn_mode = 0; // 1=Clsn1, 2=Clsn2, 3=Clsn1Default, 4=Clsn2Default
	for (int i = 0; i < lines.size(); i++) {
		String line = lines[i].strip_edges();
		if (line.is_empty() || line.begins_with(";") || line.begins_with("//")) {
			continue;
		}
		if (line.begins_with("[Begin Action")) {
			if (action >= 0) {
				current["action"] = action;
				current["frames"] = frames;
				actions.push_back(current);
			}
			current = Dictionary();
			frames = Array();
			defaults1 = Array();
			defaults2 = Array();
			explicit1 = Array();
			explicit2 = Array();
			has_explicit1 = false;
			has_explicit2 = false;
			clsn_mode = 0;
			const String n = line.get_slice(" ", 2).trim_suffix("]");
			action = n.to_int();
			continue;
		}
		if (action < 0) {
			continue;
		}
		if (line.begins_with("Clsn1Default")) {
			clsn_mode = 3;
			continue;
		}
		if (line.begins_with("Clsn2Default")) {
			clsn_mode = 4;
			continue;
		}
		if (line.begins_with("Clsn1[") || line.begins_with("Clsn2[")) {
			const Rect2i r = _retro_air_rect(line);
			if (line.begins_with("Clsn1")) {
				if (clsn_mode == 3) {
					defaults1.push_back(r);
				} else {
					explicit1.push_back(r);
				}
			} else {
				if (clsn_mode == 4) {
					defaults2.push_back(r);
				} else {
					explicit2.push_back(r);
				}
			}
			continue;
		}
		if (line.begins_with("Clsn1")) {
			clsn_mode = 1;
			explicit1 = Array();
			has_explicit1 = true;
			continue;
		}
		if (line.begins_with("Clsn2")) {
			clsn_mode = 2;
			explicit2 = Array();
			has_explicit2 = true;
			continue;
		}
		// Frame line: group, image, x, y, time, flip, ...
		const PackedStringArray fields = line.split(",");
		if (fields.size() >= 5 && fields[0].strip_edges().is_valid_int()) {
			Dictionary f;
			f["sprite_group"] = fields[0].strip_edges().to_int();
			f["sprite_image"] = fields[1].strip_edges().to_int();
			f["x"] = fields[2].strip_edges().to_int();
			f["y"] = fields[3].strip_edges().to_int();
			f["duration"] = MAX(1, abs(fields[4].strip_edges().to_int()));
			String flip = fields.size() > 5 ? fields[5].strip_edges().to_upper() : String();
			f["hflip"] = flip.contains("H");
			f["vflip"] = flip.contains("V");
			f["clsn1"] = has_explicit1 ? explicit1 : defaults1;
			f["clsn2"] = has_explicit2 ? explicit2 : defaults2;
			frames.push_back(f);
			explicit1 = Array();
			explicit2 = Array();
			has_explicit1 = false;
			has_explicit2 = false;
			has_explicit1 = false;
			has_explicit2 = false;
			clsn_mode = 0;
		}
	}
	if (action >= 0) {
		current["action"] = action;
		current["frames"] = frames;
		actions.push_back(current);
	}
	out["ok"] = !actions.is_empty();
	out["actions"] = actions;
	last_air_actions = actions;
	out["path"] = p_path;
	out["action_count"] = actions.size();
	return out;
}

struct RetroMugenExpr {
	const String &s;
	int i = 0;
	bool ok = true;

	explicit RetroMugenExpr(const String &p_text) : s(p_text) {}

	void ws() {
		while (i < s.length() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) i++;
	}

	bool eat(char32_t p_char) {
		ws();
		if (i < s.length() && s[i] == p_char) {
			i++;
			return true;
		}
		return false;
	}

	bool number(double &r_out) {
		ws();
		const int start = i;
		bool dot = false;
		while (i < s.length()) {
			const char32_t c = s[i];
			if (c >= '0' && c <= '9') { i++; continue; }
			if (c == '.' && !dot) { dot = true; i++; continue; }
			break;
		}
		if (start == i) { ok = false; return false; }
		r_out = s.substr(start, i - start).to_float();
		return true;
	}

	bool identifier(String &r_out) {
		ws();
		const int start = i;
		while (i < s.length()) {
			const char32_t c = s[i];
			if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '.') i++;
			else break;
		}
		if (start == i) return false;
		r_out = s.substr(start, i - start).to_lower();
		return true;
	}

	bool skip_call() {
		// Consume the argument list of an unknown/unsupported function.
		int depth = 1;
		while (i < s.length() && depth > 0) {
			if (s[i] == '(') depth++;
			else if (s[i] == ')') depth--;
			i++;
		}
		return depth == 0;
	}

	bool condition(double &r_out) {
		double left = 0.0;
		if (!expression(left)) return false;
		ws();
		String op;
		if (i + 1 < s.length()) {
			const String two = s.substr(i, 2);
			if (two == "!=" || two == "<=" || two == ">=" || two == "==") { op = two; i += 2; }
		}
		if (op.is_empty() && i < s.length() && (s[i] == '=' || s[i] == '<' || s[i] == '>')) {
			op = String::chr(s[i]);
			i++;
		}
		if (op.is_empty()) {
			r_out = left != 0.0 ? 1.0 : 0.0;
			return true;
		}
		double right = 0.0;
		if (!expression(right)) return false;
		if (op == "!=") r_out = left != right ? 1.0 : 0.0;
		else if (op == "<") r_out = left < right ? 1.0 : 0.0;
		else if (op == ">") r_out = left > right ? 1.0 : 0.0;
		else if (op == "<=") r_out = left <= right ? 1.0 : 0.0;
		else if (op == ">=") r_out = left >= right ? 1.0 : 0.0;
		else r_out = left == right ? 1.0 : 0.0;
		return true;
	}

	bool factor(double &r_out) {
		ws();
		if (i >= s.length()) { ok = false; return false; }
		if (eat('+')) return factor(r_out);
		if (eat('-')) {
			double v = 0.0;
			if (!factor(v)) return false;
			r_out = -v;
			return true;
		}
		if (eat('!')) {
			double v = 0.0;
			if (!factor(v)) return false;
			r_out = v == 0.0 ? 1.0 : 0.0;
			return true;
		}
		if (eat('(')) {
			if (!expression(r_out)) return false;
			return eat(')');
		}
		if ((s[i] >= '0' && s[i] <= '9') || s[i] == '.') return number(r_out);
		String id;
		if (!identifier(id)) { ok = false; return false; }
		ws();
		if (i >= s.length() || s[i] != '(') {
			// Unknown bare identifiers (variables, constants) use safe defaults.
			r_out = 0.0;
			return true;
		}
		i++; // '('
		if (id == "ifelse") {
			double cond = 0.0;
			if (!condition(cond)) return false;
			if (!eat(',')) { ok = false; return false; }
			double a = 0.0;
			if (!expression(a)) return false;
			if (!eat(',')) { ok = false; return false; }
			double b = 0.0;
			if (!expression(b)) return false;
			if (!eat(')')) { ok = false; return false; }
			r_out = cond != 0.0 ? a : b;
			return true;
		}
		if (id == "var" || id == "const") {
			if (!skip_call()) return false;
			r_out = 0.0;
			return true;
		}
		if (id == "fvar") {
			if (!skip_call()) return false;
			r_out = 1.0;
			return true;
		}
		if (id == "helper" || id == "random" || id == "numhelper" || id == "rootdist" || id == "enemynear") {
			if (!skip_call()) return false;
			r_out = 0.0;
			return true;
		}
		if (id == "floor" || id == "ceil" || id == "abs" || id == "round") {
			double v = 0.0;
			if (!expression(v)) return false;
			if (!eat(')')) { ok = false; return false; }
			if (id == "floor") r_out = std::floor(v);
			else if (id == "ceil") r_out = std::ceil(v);
			else if (id == "abs") r_out = v < 0 ? -v : v;
			else r_out = std::floor(v + 0.5);
			return true;
		}
		if (id == "min" || id == "max") {
			double a = 0.0;
			double b = 0.0;
			if (!expression(a)) return false;
			if (!eat(',')) { ok = false; return false; }
			if (!expression(b)) return false;
			if (!eat(')')) { ok = false; return false; }
			r_out = id == "min" ? MIN(a, b) : MAX(a, b);
			return true;
		}
		// Unknown function: consume arguments and use zero.
		if (!skip_call()) return false;
		r_out = 0.0;
		return true;
	}

	bool term(double &r_out) {
		double v = 0.0;
		if (!factor(v)) return false;
		while (true) {
			ws();
			if (eat('*')) {
				double r = 0.0;
				if (!factor(r)) return false;
				v *= r;
			} else if (eat('/')) {
				double r = 0.0;
				if (!factor(r)) return false;
				if (r == 0.0) { ok = false; return false; }
				v /= r;
			} else if (eat('%')) {
				double r = 0.0;
				if (!factor(r)) return false;
				if (r == 0.0) { ok = false; return false; }
				v = std::fmod(v, r);
			} else break;
		}
		r_out = v;
		return true;
	}

	bool expression(double &r_out) {
		double v = 0.0;
		if (!term(v)) return false;
		while (true) {
			ws();
			if (eat('+')) {
				double r = 0.0;
				if (!term(r)) return false;
				v += r;
			} else if (eat('-')) {
				double r = 0.0;
				if (!term(r)) return false;
				v -= r;
			} else break;
		}
		r_out = v;
		return true;
	}
};

static bool _retro_mugen_eval_int(const String &p_text, int &r_out) {
	double value = 0.0;
	RetroMugenExpr expr(p_text);
	if (!expr.expression(value) || !expr.ok) {
		return false;
	}
	r_out = (int)value;
	return true;
}

Dictionary RetroHitboxIO::parse_cns(const String &p_path) {
	Dictionary out;
	const String text = RetroUtil::read_text(p_path);
	if (text.is_empty()) {
		out["ok"] = false;
		out["error"] = "empty or unreadable CNS file";
		return out;
	}
	const PackedStringArray lines = text.split("\n");
	Array hitdefs;
	int current_state = -1;
	Dictionary current;
	for (int i = 0; i < lines.size(); i++) {
		String line = lines[i].strip_edges();
		if (line.begins_with("[Statedef") || line.begins_with("[State ")) {
			if (!current.is_empty()) {
				hitdefs.push_back(current);
			}
			const String n = line.get_slice(" ", 1).trim_suffix("]").trim_suffix(",");
			current_state = n.to_int();
			current = Dictionary();
			continue;
		}
		if (line.begins_with("[") && !line.begins_with("[State ")) {
			if (!current.is_empty()) {
				hitdefs.push_back(current);
			}
			current = Dictionary();
			continue;
		}
		if (line.begins_with("type")) {
			if (!current.is_empty()) {
				hitdefs.push_back(current);
			}
			current = Dictionary();
			if (!line.contains("HitDef")) {
				continue;
			}
			current["state"] = current_state;
			current["raw"] = Array();
			continue;
		}
		if (current.is_empty() || !line.contains("=")) {
			continue;
		}
		const String key = line.get_slice("=", 0).strip_edges().to_lower();
		String value = line.substr(line.find("=") + 1).strip_edges();
		// MUGEN comments start at ';'. Strip them before numeric parsing so a
		// comma inside a Japanese comment cannot be mistaken for a value
		// separator (e.g. pausetime = ...,13 ; (自分,相手)).
		const int comment = value.find(";");
		if (comment >= 0) {
			value = value.substr(0, comment).strip_edges();
		}
		Array raw = current.get("raw", Array());
		raw.push_back(line);
		current["raw"] = raw;
		if (key == "damage") {
			current["damage_raw"] = value;
			int evaluated = 0;
			if (_retro_mugen_eval_int(value, evaluated)) {
				current["damage"] = evaluated;
			} else {
				current["damage"] = 0;
				current["damage_error"] = true;
			}
			current["damage_estimated"] = value.contains("var") || value.contains("ifelse") || value.contains("fvar") || value.contains("Helper");
		} else if (key == "pausetime") {
			current["pausetime_raw"] = value;
			current["hitstop_attacker"] = _retro_first_int(value);
			current["hitstop_defender"] = _retro_second_int(value);
		} else if (key == "guard.pausetime") {
			current["guard_pausetime_raw"] = value;
			current["blockstun"] = _retro_second_int(value);
		} else if (key == "ground.hittime") {
			current["hitstun"] = _retro_first_int(value);
		} else if (key == "air.hittime") {
			current["air_hitstun"] = _retro_first_int(value);
		} else if (key == "attr") {
			current["attr"] = value;
		} else if (key == "guardflag") {
			current["guardflag"] = value;
		} else if (key == "hitflag") {
			current["hitflag"] = value;
		} else if (key == "animtype") {
			current["animtype"] = value;
		} else if (key == "priority") {
			current["priority_raw"] = value;
			current["priority"] = _retro_first_int(value);
		} else if (key == "id") {
			current["id"] = _retro_first_int(value);
		} else if (key == "ground.velocity") {
			current["ground_velocity_raw"] = value;
			int velocity = 0;
			if (_retro_mugen_eval_int(value, velocity)) {
				current["ground_velocity"] = velocity;
			}
		}
	}
	if (!current.is_empty()) {
		hitdefs.push_back(current);
	}
	for (int i = 0; i < hitdefs.size(); i++) {
		Dictionary h = hitdefs[i];
		h["index"] = i;
		hitdefs[i] = h;
	}
	out["ok"] = !hitdefs.is_empty();
	out["hitdefs"] = hitdefs;
	out["path"] = p_path;
	out["hitdef_count"] = hitdefs.size();
	return out;
}

Dictionary RetroHitboxIO::import_air_frames(const Array &p_frames, const Ref<RetroAnimation> &p_animation, const String &p_state) const {
	Dictionary result;
	if (p_animation.is_null() || p_frames.is_empty()) {
		result["ok"] = false;
		return result;
	}
	Array frames;
	int hit_count = 0;
	int hurt_count = 0;
	for (int i = 0; i < p_frames.size(); i++) {
		const Dictionary src = p_frames[i];
		Dictionary f;
		f["sprite_frame"] = i;
		f["duration"] = MAX(1, int(src.get("duration", 1)));
		f["rect"] = Rect2i();
		Array boxes;
		const Array clsn1 = src.get("clsn1", Array());
		for (int b = 0; b < clsn1.size(); b++) {
			Dictionary box;
			box["rect"] = clsn1[b];
			box["type"] = "hit";
			boxes.push_back(box);
			hit_count++;
		}
		const Array clsn2 = src.get("clsn2", Array());
		for (int b = 0; b < clsn2.size(); b++) {
			Dictionary box;
			box["rect"] = clsn2[b];
			box["type"] = "hurt";
			boxes.push_back(box);
			hurt_count++;
		}
		f["hitboxes"] = boxes;
		f["events"] = Array();
		frames.push_back(f);
	}
	Dictionary states = p_animation->get_states();
	Dictionary st = states.get(p_state, Dictionary());
	if (!st.has("name")) {
		st["name"] = p_state;
		st["loop"] = true;
		st["next"] = "";
	}
	st["frames"] = frames;
	states[p_state] = st;
	p_animation->set_states(states);
	result["ok"] = true;
	result["state"] = p_state;
	result["frames"] = frames.size();
	result["hit_boxes"] = hit_count;
	result["hurt_boxes"] = hurt_count;
	return result;
}

Dictionary RetroHitboxIO::import_air_action(int p_action, const Ref<RetroAnimation> &p_animation, const String &p_state) {
	for (int i = 0; i < last_air_actions.size(); i++) {
		const Dictionary a = last_air_actions[i];
		if (int(a.get("action", -1)) == p_action) {
			return import_air_frames(a.get("frames", Array()), p_animation, p_state);
		}
	}
	Dictionary result;
	result["ok"] = false;
	result["error"] = "action not found; call parse_air first";
	return result;
}

Dictionary RetroHitboxIO::export_air(const Ref<RetroAnimation> &p_animation, const String &p_state, int p_action, const String &p_path) const {
	Dictionary result;
	if (p_animation.is_null()) {
		result["ok"] = false;
		return result;
	}
	const Dictionary state = p_animation->get_state(p_state);
	const Array frames = state.get("frames", Array());
	if (frames.is_empty()) {
		result["ok"] = false;
		result["error"] = "state has no frames";
		return result;
	}
	String out;
	out += "[Begin Action " + itos(p_action) + "]\n";
	for (int i = 0; i < frames.size(); i++) {
		const Dictionary f = frames[i];
		const Array boxes = f.get("hitboxes", Array());
		Array hits;
		Array hurts;
		for (int b = 0; b < boxes.size(); b++) {
			const Dictionary box = boxes[b];
			const Rect2i r = box.get("rect", Rect2i());
			if (String(box.get("type", "hit")) == "hurt") {
				hurts.push_back(r);
			} else {
				hits.push_back(r);
			}
		}
		if (!hurts.is_empty()) {
			out += "Clsn2:" + itos(hurts.size()) + "\n";
			for (int b = 0; b < hurts.size(); b++) {
				const Rect2i r = hurts[b];
				out += "  Clsn2[" + itos(b) + "] = " + itos(r.position.x) + "," + itos(r.position.y) + "," + itos(r.position.x + r.size.x) + "," + itos(r.position.y + r.size.y) + "\n";
			}
		}
		if (!hits.is_empty()) {
			out += "Clsn1:" + itos(hits.size()) + "\n";
			for (int b = 0; b < hits.size(); b++) {
				const Rect2i r = hits[b];
				out += "  Clsn1[" + itos(b) + "] = " + itos(r.position.x) + "," + itos(r.position.y) + "," + itos(r.position.x + r.size.x) + "," + itos(r.position.y + r.size.y) + "\n";
			}
		}
		const int sprite_frame = int(f.get("sprite_frame", i));
		const int duration = int(f.get("duration", 1));
		out += itos(sprite_frame) + ",0,0,0," + itos(duration) + ",,\n";
	}
	result["ok"] = RetroUtil::write_text(p_path, out) == OK;
	result["path"] = p_path;
	result["frames"] = frames.size();
	return result;
}
