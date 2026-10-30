/**************************************************************************/
/*  retro_code_index.cpp                                                  */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_code_index.h"

#include "retro_util.h"

#include "core/io/file_access.h"

static bool _retro_ident_char(char32_t c) {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

void RetroCodeIndex::_bind_methods() {
	ClassDB::bind_method(D_METHOD("scan_project", "project"), &RetroCodeIndex::scan_project);
	ClassDB::bind_method(D_METHOD("scan_file", "path"), &RetroCodeIndex::scan_file);
	ClassDB::bind_method(D_METHOD("find_symbol", "index", "name"), &RetroCodeIndex::find_symbol);
	ClassDB::bind_method(D_METHOD("associations_for_resource", "project", "resource_rel_path"), &RetroCodeIndex::associations_for_resource);
	ClassDB::bind_method(D_METHOD("preview", "path", "offset", "lines"), &RetroCodeIndex::preview, DEFVAL(0), DEFVAL(200));
}

Array RetroCodeIndex::scan_file(const String &p_path) {
	Array out;
	const String text = RetroUtil::read_text(p_path);
	if (text.is_empty()) {
		return out;
	}
	const PackedStringArray lines = text.split("\n");
	const String ext = p_path.get_extension().to_lower();
	for (int i = 0; i < lines.size(); i++) {
		const String line = lines[i];
		const String stripped = line.strip_edges();
		if (stripped.is_empty() || stripped.begins_with("//") || stripped.begins_with(";")) {
			continue;
		}
		Dictionary sym;
		bool found = false;
		if (ext == "c" || ext == "h" || ext == "cpp" || ext == "hpp") {
			if (stripped.begins_with("#include")) {
				const int q1 = stripped.find("\"");
				const int q2 = stripped.find("\"", q1 + 1);
				const int a1 = stripped.find("<");
				const int a2 = stripped.find(">", a1 + 1);
				String inc;
				if (q1 >= 0 && q2 > q1) {
					inc = stripped.substr(q1 + 1, q2 - q1 - 1);
				} else if (a1 >= 0 && a2 > a1) {
					inc = stripped.substr(a1 + 1, a2 - a1 - 1);
				}
				if (!inc.is_empty()) {
					sym["name"] = inc;
					sym["kind"] = "include";
					found = true;
				}
			} else {
				const int paren = stripped.find("(");
				if (paren > 0 && !stripped.ends_with(";")) {
					String head = stripped.substr(0, paren).strip_edges();
					// Strip return type and pointer stars: take the last identifier.
					int cut = head.length();
					while (cut > 0 && _retro_ident_char(head[cut - 1])) {
						cut--;
					}
					const String name = head.substr(cut);
					if (!name.is_empty() && name != "if" && name != "for" && name != "while" &&
							name != "switch" && name != "return" && name != "sizeof" &&
							!head.contains("=")) {
						sym["name"] = name;
						sym["kind"] = "function";
						found = true;
					}
				}
			}
		} else if (ext == "asm" || ext == "s" || ext == "inc") {
			if (stripped.ends_with(":") && !stripped.contains(" ")) {
				sym["name"] = stripped.trim_suffix(":");
				sym["kind"] = "label";
				found = true;
			}
		}
		if (found) {
			sym["file"] = p_path;
			sym["line"] = i + 1;
			sym["signature"] = stripped;
			out.push_back(sym);
			if (out.size() >= 5000) {
				break;
			}
		}
	}
	return out;
}

Array RetroCodeIndex::scan_project(const Ref<RetroProject> &p_project) {
	Array out;
	if (!p_project.is_valid()) {
		return out;
	}
	const Array sources = p_project->get_sources();
	for (int i = 0; i < sources.size(); i++) {
		const Dictionary s = sources[i];
		const String path = s.get("path", String());
		if (!path.is_empty() && FileAccess::exists(path)) {
			const Array syms = scan_file(path);
			for (int j = 0; j < syms.size(); j++) {
				Dictionary d = syms[j];
				d["rel_path"] = String(s.get("rel_path", path.get_file()));
				out.push_back(d);
			}
		}
	}
	return out;
}

Dictionary RetroCodeIndex::find_symbol(const Array &p_index, const String &p_name) {
	for (int i = 0; i < p_index.size(); i++) {
		const Dictionary d = p_index[i];
		if (String(d.get("name", "")) == p_name) {
			return d;
		}
	}
	return Dictionary();
}

Array RetroCodeIndex::associations_for_resource(const Ref<RetroProject> &p_project, const String &p_resource_rel_path) {
	Array out;
	if (!p_project.is_valid()) {
		return out;
	}
	const Array assoc = p_project->get_associations();
	for (int i = 0; i < assoc.size(); i++) {
		const Dictionary a = assoc[i];
		if (String(a.get("resource", "")) == p_resource_rel_path) {
			out.push_back(a);
		}
	}
	return out;
}

Dictionary RetroCodeIndex::preview(const String &p_path, int p_offset, int p_lines) {
	Dictionary out;
	if (!FileAccess::exists(p_path)) {
		out["ok"] = false;
		return out;
	}
	const String text = RetroUtil::read_text(p_path);
	const PackedStringArray lines = text.split("\n");
	Array slice;
	const int start = CLAMP(p_offset, 0, lines.size());
	const int end = MIN(lines.size(), start + MAX(1, p_lines));
	for (int i = start; i < end; i++) {
		slice.push_back(lines[i]);
	}
	out["ok"] = true;
	out["path"] = p_path;
	out["offset"] = start;
	out["total_lines"] = lines.size();
	out["lines"] = slice;
	out["text"] = text;
	return out;
}

