/**************************************************************************/
/*  retro_animation.cpp                                                   */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_animation.h"

#include "retro_util.h"

static Rect2i _retro_anim_rect(const Variant &p_v) {
	if (p_v.get_type() == Variant::RECT2I) { return p_v; }
	if (p_v.get_type() == Variant::RECT2) { const Rect2 r = p_v; return Rect2i(r.position, r.size); }
	if (p_v.get_type() == Variant::STRING) {
		String s = p_v;
		s = s.replace("(", "").replace(")", "");
		const PackedStringArray parts = s.split(",", false);
		if (parts.size() >= 4) { return Rect2i(parts[0].to_int(), parts[1].to_int(), parts[2].to_int(), parts[3].to_int()); }
	}
	if (p_v.get_type() == Variant::ARRAY) {
		const Array a = p_v;
		if (a.size() >= 4) { return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3])); }
	}
	return Rect2i();
}

void RetroAnimation::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_state", "state", "loop"), &RetroAnimation::add_state, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("remove_state", "state"), &RetroAnimation::remove_state);
	ClassDB::bind_method(D_METHOD("add_frame", "state", "sprite_frame", "duration", "rect"), &RetroAnimation::add_frame, DEFVAL(Rect2i()));
	ClassDB::bind_method(D_METHOD("set_frame_duration", "state", "index", "duration"), &RetroAnimation::set_frame_duration);
	ClassDB::bind_method(D_METHOD("add_hitbox", "state", "frame", "rect", "type"), &RetroAnimation::add_hitbox, DEFVAL("hit"));
	ClassDB::bind_method(D_METHOD("get_frame_hitboxes", "state", "frame"), &RetroAnimation::get_frame_hitboxes);
	ClassDB::bind_method(D_METHOD("set_frame_hitboxes", "state", "frame", "boxes"), &RetroAnimation::set_frame_hitboxes);
	ClassDB::bind_method(D_METHOD("add_event", "state", "frame", "type", "value"), &RetroAnimation::add_event);
	ClassDB::bind_method(D_METHOD("set_loop", "state", "loop"), &RetroAnimation::set_loop);
	ClassDB::bind_method(D_METHOD("set_transition", "state", "next"), &RetroAnimation::set_transition);
	ClassDB::bind_method(D_METHOD("get_state", "state"), &RetroAnimation::get_state);
	ClassDB::bind_method(D_METHOD("get_state_frame", "state", "index"), &RetroAnimation::get_state_frame);
	ClassDB::bind_method(D_METHOD("total_duration", "state"), &RetroAnimation::total_duration);
	ClassDB::bind_method(D_METHOD("sample", "state", "time"), &RetroAnimation::sample);
	ClassDB::bind_method(D_METHOD("analyze"), &RetroAnimation::analyze);
	ClassDB::bind_method(D_METHOD("export_snes_inc", "path", "prefix"), &RetroAnimation::export_snes_inc, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("export_sgdk_header", "path", "prefix"), &RetroAnimation::export_sgdk_header, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("export_hitboxes_snes", "path", "prefix"), &RetroAnimation::export_hitboxes_snes, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("export_hitboxes_sgdk", "path", "prefix"), &RetroAnimation::export_hitboxes_sgdk, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("collision_test", "state_a", "frame_a", "pos_a", "state_b", "frame_b", "pos_b"), &RetroAnimation::collision_test);
	ClassDB::bind_method(D_METHOD("save", "path"), &RetroAnimation::save);
	ClassDB::bind_method(D_METHOD("load", "path"), &RetroAnimation::load);
	ClassDB::bind_method(D_METHOD("to_dict"), &RetroAnimation::to_dict);
	ClassDB::bind_method(D_METHOD("from_dict", "data"), &RetroAnimation::from_dict);
	ClassDB::bind_static_method("RetroAnimation", D_METHOD("default_states"), &RetroAnimation::default_states);

	ClassDB::bind_method(D_METHOD("set_name", "value"), &RetroAnimation::set_name);
	ClassDB::bind_method(D_METHOD("get_name"), &RetroAnimation::get_name);
	ClassDB::bind_method(D_METHOD("set_platform", "value"), &RetroAnimation::set_platform);
	ClassDB::bind_method(D_METHOD("get_platform"), &RetroAnimation::get_platform);
	ClassDB::bind_method(D_METHOD("set_sprite_id", "value"), &RetroAnimation::set_sprite_id);
	ClassDB::bind_method(D_METHOD("get_sprite_id"), &RetroAnimation::get_sprite_id);
	ClassDB::bind_method(D_METHOD("set_fps", "value"), &RetroAnimation::set_fps);
	ClassDB::bind_method(D_METHOD("get_fps"), &RetroAnimation::get_fps);
	ClassDB::bind_method(D_METHOD("set_states", "value"), &RetroAnimation::set_states);
	ClassDB::bind_method(D_METHOD("get_states"), &RetroAnimation::get_states);
	ClassDB::bind_method(D_METHOD("set_metadata", "value"), &RetroAnimation::set_metadata);
	ClassDB::bind_method(D_METHOD("get_metadata"), &RetroAnimation::get_metadata);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name"), "set_name", "get_name");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "platform"), "set_platform", "get_platform");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "sprite_id"), "set_sprite_id", "get_sprite_id");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "fps"), "set_fps", "get_fps");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "states"), "set_states", "get_states");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "metadata"), "set_metadata", "get_metadata");
}

RetroAnimation::RetroAnimation() {
	const Array defs = default_states();
	for (int i = 0; i < defs.size(); i++) {
		add_state(defs[i], true);
	}
}

Array RetroAnimation::default_states() {
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

void RetroAnimation::add_state(const String &p_state, bool p_loop) {
	if (states.has(p_state)) {
		return;
	}
	Dictionary s;
	s["name"] = p_state;
	s["loop"] = p_loop;
	s["frames"] = Array();
	s["next"] = String();
	states[p_state] = s;
}

void RetroAnimation::remove_state(const String &p_state) {
	states.erase(p_state);
}

void RetroAnimation::add_frame(const String &p_state, int p_sprite_frame, int p_duration, const Rect2i &p_rect) {
	add_state(p_state, true);
	Dictionary s = states[p_state];
	Array frames = s.get("frames", Array());
	Dictionary f;
	f["sprite_frame"] = p_sprite_frame;
	f["duration"] = MAX(1, p_duration);
	f["rect"] = p_rect;
	f["hitboxes"] = Array();
	f["events"] = Array();
	frames.push_back(f);
	s["frames"] = frames;
	states[p_state] = s;
}

void RetroAnimation::set_frame_duration(const String &p_state, int p_index, int p_duration) {
	if (!states.has(p_state)) {
		return;
	}
	Dictionary s = states[p_state];
	Array frames = s.get("frames", Array());
	if (p_index < 0 || p_index >= frames.size()) {
		return;
	}
	Dictionary f = frames[p_index];
	f["duration"] = MAX(1, p_duration);
	frames[p_index] = f;
	s["frames"] = frames;
	states[p_state] = s;
}

void RetroAnimation::add_hitbox(const String &p_state, int p_frame, const Rect2i &p_rect, const String &p_type) {
	if (!states.has(p_state)) {
		return;
	}
	Dictionary s = states[p_state];
	Array frames = s.get("frames", Array());
	if (p_frame < 0 || p_frame >= frames.size()) {
		return;
	}
	Dictionary f = frames[p_frame];
	Array boxes = f.get("hitboxes", Array());
	Dictionary b;
	b["rect"] = p_rect;
	b["type"] = p_type;
	boxes.push_back(b);
	f["hitboxes"] = boxes;
	frames[p_frame] = f;
	s["frames"] = frames;
	states[p_state] = s;
}

void RetroAnimation::add_event(const String &p_state, int p_frame, const String &p_type, const String &p_value) {
	if (!states.has(p_state)) {
		return;
	}
	Dictionary s = states[p_state];
	Array frames = s.get("frames", Array());
	if (p_frame < 0 || p_frame >= frames.size()) {
		return;
	}
	Dictionary f = frames[p_frame];
	Array events = f.get("events", Array());
	Dictionary e;
	e["type"] = p_type;
	e["value"] = p_value;
	events.push_back(e);
	f["events"] = events;
	frames[p_frame] = f;
	s["frames"] = frames;
	states[p_state] = s;
}

void RetroAnimation::set_loop(const String &p_state, bool p_loop) {
	if (!states.has(p_state)) {
		return;
	}
	Dictionary s = states[p_state];
	s["loop"] = p_loop;
	states[p_state] = s;
}

void RetroAnimation::set_transition(const String &p_state, const String &p_next) {
	if (!states.has(p_state)) {
		return;
	}
	Dictionary s = states[p_state];
	s["next"] = p_next;
	states[p_state] = s;
}

Dictionary RetroAnimation::get_state(const String &p_state) const {
	return states.get(p_state, Dictionary());
}

Dictionary RetroAnimation::get_state_frame(const String &p_state, int p_index) const {
	const Dictionary s = states.get(p_state, Dictionary());
	const Array frames = s.get("frames", Array());
	if (p_index >= 0 && p_index < frames.size()) {
		return frames[p_index];
	}
	return Dictionary();
}

int RetroAnimation::total_duration(const String &p_state) const {
	const Dictionary s = states.get(p_state, Dictionary());
	const Array frames = s.get("frames", Array());
	int total = 0;
	for (int i = 0; i < frames.size(); i++) {
		total += int(Dictionary(frames[i]).get("duration", 1));
	}
	return total;
}

Dictionary RetroAnimation::sample(const String &p_state, float p_time) const {
	Dictionary result;
	const Dictionary s = states.get(p_state, Dictionary());
	const Array frames = s.get("frames", Array());
	if (frames.is_empty()) {
		return result;
	}
	int total = 0;
	for (int i = 0; i < frames.size(); i++) {
		total += int(Dictionary(frames[i]).get("duration", 1));
	}
	const bool loop = s.get("loop", true);
	int frame_index = int(p_time * fps);
	if (loop && total > 0) {
		frame_index %= total;
	} else {
		frame_index = MIN(frame_index, total - 1);
	}
	int acc = 0;
	for (int i = 0; i < frames.size(); i++) {
		acc += int(Dictionary(frames[i]).get("duration", 1));
		if (frame_index < acc) {
			result = frames[i];
			result["index"] = i;
			result["state"] = p_state;
			result["frame_start"] = acc - int(Dictionary(frames[i]).get("duration", 1));
			return result;
		}
	}
	return result;
}

Dictionary RetroAnimation::analyze() const {
	Dictionary d;
	int total_frames = 0;
	int total_hitboxes = 0;
	Array state_names = states.keys();
	for (int i = 0; i < state_names.size(); i++) {
		const Dictionary s = states[state_names[i]];
		const Array frames = s.get("frames", Array());
		total_frames += frames.size();
		for (int j = 0; j < frames.size(); j++) {
			total_hitboxes += Array(Dictionary(frames[j]).get("hitboxes", Array())).size();
		}
	}
	d["states"] = state_names.size();
	d["frames"] = total_frames;
	d["hitboxes"] = total_hitboxes;
	d["fps"] = fps;
	// Approximate ROM cost of an exported table (12 bytes per frame + boxes).
	d["estimated_bytes"] = total_frames * 12 + total_hitboxes * 12 + state_names.size() * 8;
	return d;
}

Array RetroAnimation::get_frame_hitboxes(const String &p_state, int p_frame) const {
	const Dictionary s = states.get(p_state, Dictionary());
	const Array frames = s.get("frames", Array());
	if (p_frame < 0 || p_frame >= frames.size()) {
		return Array();
	}
	const Dictionary f = frames[p_frame];
	return f.get("hitboxes", Array());
}

void RetroAnimation::set_frame_hitboxes(const String &p_state, int p_frame, const Array &p_boxes) {
	if (!states.has(p_state)) {
		return;
	}
	Dictionary s = states[p_state];
	Array frames = s.get("frames", Array());
	if (p_frame < 0 || p_frame >= frames.size()) {
		return;
	}
	Dictionary f = frames[p_frame];
	f["hitboxes"] = p_boxes;
	frames[p_frame] = f;
	s["frames"] = frames;
	states[p_state] = s;
}

static String _retro_hit_state_label(const String &p_state) {
	String out = p_state.to_upper();
	for (int i = 0; i < out.length(); i++) {
		const char32_t c = out[i];
		if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) {
			out = out.replace(String::chr(c), "_");
		}
	}
	return out;
}

Dictionary RetroAnimation::export_hitboxes_snes(const String &p_path, const String &p_prefix) const {
	const String prefix = p_prefix.is_empty() ? name.to_lower().replace(" ", "_") : p_prefix;
	String out;
	out += "; Generated by Godot Retro Engine hitbox exporter.\n";
	out += "; type: 0 = hurtbox, 1 = hitbox\n";
	int total = 0;
	Array keys = states.keys();
	// Flat table: state index, frame index, type, x, y, w, h.
	out += prefix + "_hitbox_count = " + itos(total) + "\n";
	// Compute first so the count can be emitted before the data.
	int count = 0;
	for (int i = 0; i < keys.size(); i++) {
		const Dictionary s = states[keys[i]];
		const Array frames = s.get("frames", Array());
		for (int f = 0; f < frames.size(); f++) {
			count += Array(Dictionary(frames[f]).get("hitboxes", Array())).size();
		}
	}
	out = out.replace(prefix + "_hitbox_count = 0", prefix + "_hitbox_count = " + itos(count));
	out += prefix + "_hitboxes:\n";
	for (int i = 0; i < keys.size(); i++) {
		const Dictionary s = states[keys[i]];
		const Array frames = s.get("frames", Array());
		for (int f = 0; f < frames.size(); f++) {
			const Array boxes = Dictionary(frames[f]).get("hitboxes", Array());
			for (int b = 0; b < boxes.size(); b++) {
				const Dictionary box = boxes[b];
				const Rect2i r = box.get("rect", Rect2i());
				const int type = String(box.get("type", "hit")) == "hurt" ? 0 : 1;
				out += "\t.db " + itos(i) + ", " + itos(f) + ", " + itos(type) + "\n";
				out += "\t.dw " + itos(r.position.x) + ", " + itos(r.position.y) + ", " + itos(r.size.x) + ", " + itos(r.size.y) + "\n";
			}
		}
	}
	if (count == 0) {
		out += "\t.db $FF, $FF, $FF\n\t.dw 0, 0, 0, 0\n";
	}
	const Error err = RetroUtil::write_text(p_path, out);
	Dictionary result;
	result["ok"] = err == OK;
	result["path"] = p_path;
	result["count"] = count;
	return result;
}

Dictionary RetroAnimation::export_hitboxes_sgdk(const String &p_path, const String &p_prefix) const {
	const String prefix = p_prefix.is_empty() ? name.to_upper().replace(" ", "_") : String(p_prefix).to_upper();
	String out;
	out += "/* Generated by Godot Retro Engine hitbox exporter. */\n";
	out += "#ifndef " + prefix + "_HITBOX_H\n#define " + prefix + "_HITBOX_H\n\n";
	out += "#include <genesis.h>\n\n";
	out += "#define RETRO_HITBOX_HURT 0\n#define RETRO_HITBOX_HIT 1\n\n";
	out += "typedef struct { u16 state; u16 frame; u8 type; s16 x, y, w, h; } RetroHitbox;\n\n";
	Array keys = states.keys();
	int count = 0;
	for (int i = 0; i < keys.size(); i++) {
		const Dictionary s = states[keys[i]];
		const Array frames = s.get("frames", Array());
		for (int f = 0; f < frames.size(); f++) {
			count += Array(Dictionary(frames[f]).get("hitboxes", Array())).size();
		}
	}
	out += "static const RetroHitbox retro_hitboxes[" + itos(MAX(1, count)) + "] = {\n";
	if (count == 0) {
		out += "\t{ 0, 0, RETRO_HITBOX_HURT, 0, 0, 0, 0 },\n";
	}
	for (int i = 0; i < keys.size(); i++) {
		const Dictionary s = states[keys[i]];
		const Array frames = s.get("frames", Array());
		for (int f = 0; f < frames.size(); f++) {
			const Array boxes = Dictionary(frames[f]).get("hitboxes", Array());
			for (int b = 0; b < boxes.size(); b++) {
				const Dictionary box = boxes[b];
				const Rect2i r = box.get("rect", Rect2i());
				const String type = String(box.get("type", "hit")) == "hurt" ? "RETRO_HITBOX_HURT" : "RETRO_HITBOX_HIT";
				out += "\t{ " + itos(i) + ", " + itos(f) + ", " + type + ", " + itos(r.position.x) + ", " + itos(r.position.y) + ", " + itos(r.size.x) + ", " + itos(r.size.y) + " },\n";
			}
		}
	}
	out += "};\n\n#endif\n";
	const Error err = RetroUtil::write_text(p_path, out);
	Dictionary result;
	result["ok"] = err == OK;
	result["path"] = p_path;
	result["count"] = count;
	return result;
}

Dictionary RetroAnimation::collision_test(const String &p_state_a, int p_frame_a, const Point2i &p_pos_a,
		const String &p_state_b, int p_frame_b, const Point2i &p_pos_b) const {
	Dictionary out;
	Array hits;
	Array a_boxes = get_frame_hitboxes(p_state_a, p_frame_a);
	Array b_boxes = get_frame_hitboxes(p_state_b, p_frame_b);
	for (int i = 0; i < a_boxes.size(); i++) {
		const Dictionary ab = a_boxes[i];
		const Rect2i ar = ab.get("rect", Rect2i());
		const String at = String(ab.get("type", "hit"));
		for (int j = 0; j < b_boxes.size(); j++) {
			const Dictionary bb = b_boxes[j];
			const Rect2i br = bb.get("rect", Rect2i());
			const String bt = String(bb.get("type", "hit"));
			if (at == bt) {
				continue; // hit vs hit / hurt vs hurt are not contacts
			}
			const Rect2i wa = Rect2i(ar.position + p_pos_a, ar.size);
			const Rect2i wb = Rect2i(br.position + p_pos_b, br.size);
			if (wa.intersects(wb)) {
				Dictionary c;
				c["rect"] = wa.intersection(wb);
				c["a_type"] = at;
				c["b_type"] = bt;
				c["a_index"] = i;
				c["b_index"] = j;
				hits.push_back(c);
			}
		}
	}
	out["hit"] = !hits.is_empty();
	out["contacts"] = hits;
	out["a_boxes"] = a_boxes.size();
	out["b_boxes"] = b_boxes.size();
	return out;
}

Dictionary RetroAnimation::export_snes_inc(const String &p_path, const String &p_prefix) {
	Dictionary result;
	const String prefix = p_prefix.is_empty() ? name.to_lower().replace(" ", "_") : p_prefix;
	String out = "; Generated by Godot Retro Engine animation exporter\n";
	out += prefix + "_state_count = " + itos(states.size()) + "\n";
	out += prefix + "_state_table:\n";
	Array keys = states.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Dictionary s = states[keys[i]];
		const Array frames = s.get("frames", Array());
		String state_label = String(keys[i]).to_lower();
		for (int c = 0; c < state_label.length(); c++) {
			const char32_t ch = state_label[c];
			if (!((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9'))) {
				state_label = state_label.replace(String::chr(ch), "_");
			}
		}
		out += "\t.dw " + prefix + "_" + state_label + "_frames, " + itos(frames.size()) + ", " + itos(int(s.get("loop", true))) + "\n";
	}
	for (int i = 0; i < keys.size(); i++) {
		const Dictionary s = states[keys[i]];
		const Array frames = s.get("frames", Array());
		out += prefix + "_" + String(keys[i]).to_lower() + "_frames:\n";
		for (int j = 0; j < frames.size(); j++) {
			const Dictionary f = frames[j];
			const Rect2i r = f.get("rect", Rect2i());
			out += "\t.dw " + itos(int(f.get("sprite_frame", 0))) + ", " + itos(int(f.get("duration", 1)));
			out += ", " + itos(r.position.x) + ", " + itos(r.position.y) + ", " + itos(r.size.x) + ", " + itos(r.size.y) + "\n";
		}
	}
	const Error err = RetroUtil::write_text(p_path, out);
	result["ok"] = err == OK;
	result["path"] = p_path;
	result["states"] = keys.size();
	return result;
}

Dictionary RetroAnimation::export_sgdk_header(const String &p_path, const String &p_prefix) {
	Dictionary result;
	const String prefix = p_prefix.is_empty() ? name.to_upper().replace(" ", "_") : String(p_prefix).to_upper();
	String out = "/* Generated by Godot Retro Engine animation exporter */\n";
	out += "#ifndef " + prefix + "_ANIM_H\n#define " + prefix + "_ANIM_H\n\n";
	Array keys = states.keys();
	out += "typedef unsigned short " + prefix + "_u16;\n";
	out += "typedef signed short " + prefix + "_s16;\n\n";
	out += "typedef struct { " + prefix + "_u16 sprite_frame; " + prefix + "_u16 duration; " + prefix + "_s16 x, y, w, h; } " + prefix + "_Frame;\n\n";
	for (int i = 0; i < keys.size(); i++) {
		const Dictionary s = states[keys[i]];
		const Array frames = s.get("frames", Array());
		String state_label = String(keys[i]).to_upper();
		for (int c = 0; c < state_label.length(); c++) {
			const char32_t ch = state_label[c];
			if (!((ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9'))) {
				state_label = state_label.replace(String::chr(ch), "_");
			}
		}
		out += "static const " + prefix + "_Frame " + prefix + "_" + state_label + "_FRAMES[" + itos(MAX(1, frames.size())) + "] = {\n";
		for (int j = 0; j < frames.size(); j++) {
			const Dictionary f = frames[j];
			const Rect2i r = f.get("rect", Rect2i());
			out += "    { " + itos(int(f.get("sprite_frame", 0))) + ", " + itos(int(f.get("duration", 1))) + ", " + itos(r.position.x) + ", " + itos(r.position.y) + ", " + itos(r.size.x) + ", " + itos(r.size.y) + " },\n";
		}
		if (frames.is_empty()) {
			out += "    { 0, 1, 0, 0, 0, 0 },\n";
		}
		out += "};\n";
	}
	out += "\n#endif\n";
	const Error err = RetroUtil::write_text(p_path, out);
	result["ok"] = err == OK;
	result["path"] = p_path;
	result["states"] = keys.size();
	return result;
}

Error RetroAnimation::save(const String &p_path) {
	return RetroUtil::save_json_file(p_path, to_dict());
}

Error RetroAnimation::load(const String &p_path) {
	bool ok = false;
	const Dictionary d = RetroUtil::parse_json_file(p_path, &ok);
	if (!ok) {
		return ERR_FILE_CANT_READ;
	}
	from_dict(d);
	return OK;
}

Dictionary RetroAnimation::to_dict() const {
	Dictionary d;
	d["format"] = "godot-retro-engine/animation";
	d["version"] = 1;
	d["name"] = name;
	d["platform"] = platform;
	d["sprite_id"] = sprite_id;
	d["fps"] = fps;
	d["states"] = states;
	d["metadata"] = metadata;
	return d;
}

void RetroAnimation::from_dict(const Dictionary &p_data) {
	name = p_data.get("name", name);
	platform = p_data.get("platform", platform);
	sprite_id = p_data.get("sprite_id", sprite_id);
	fps = p_data.get("fps", fps);
	states = p_data.get("states", states);
	for (int i = 0; i < states.size(); i++) {
		const Variant key = states.get_key_at_index(i);
		Dictionary st = states[key];
		Array frames = st.get("frames", Array());
		for (int f = 0; f < frames.size(); f++) {
			Dictionary fr = frames[f];
			if (fr.has("rect")) {
				fr["rect"] = _retro_anim_rect(fr["rect"]);
			}
			Array boxes = fr.get("hitboxes", Array());
			for (int b = 0; b < boxes.size(); b++) {
				Dictionary box = boxes[b];
				if (box.has("rect")) {
					box["rect"] = _retro_anim_rect(box["rect"]);
					boxes[b] = box;
				}
			}
			fr["hitboxes"] = boxes;
			frames[f] = fr;
		}
		st["frames"] = frames;
		states[key] = st;
	}
	metadata = p_data.get("metadata", metadata);
}
