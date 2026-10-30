/**************************************************************************/
/*  retro_util.cpp                                                        */
/**************************************************************************/

#include "retro_util.h"

#include "core/config/project_settings.h"
#include "core/io/file_access.h"
#include "core/os/os.h"
#include "core/variant/array.h"

// Strict UTF-8 validator. Godot's String::utf8() prints an error for every
// invalid sequence, which floods the log when legacy text files (MUGEN CNS/AIR,
// old C sources, Latin-1 comments) are read. Validate first and fall back to
// Windows-1252/Latin-1 when the bytes are not valid UTF-8.
static bool _is_valid_utf8(const uint8_t *p_data, int p_len) {
	int i = 0;
	while (i < p_len) {
		const uint8_t c = p_data[i];
		if (c < 0x80) {
			i++;
			continue;
		}
		int extra = 0;
		uint32_t cp = 0;
		if ((c & 0xE0) == 0xC0) {
			extra = 1;
			cp = c & 0x1F;
		} else if ((c & 0xF0) == 0xE0) {
			extra = 2;
			cp = c & 0x0F;
		} else if ((c & 0xF8) == 0xF0) {
			extra = 3;
			cp = c & 0x07;
		} else {
			return false;
		}
		if (i + extra >= p_len) {
			return false;
		}
		for (int j = 1; j <= extra; j++) {
			const uint8_t cc = p_data[i + j];
			if ((cc & 0xC0) != 0x80) {
				return false;
			}
			cp = (cp << 6) | (cc & 0x3F);
		}
		// Reject overlong encodings, UTF-16 surrogates and out-of-range points.
		if ((extra == 1 && cp < 0x80) || (extra == 2 && cp < 0x800) ||
				(extra == 3 && (cp < 0x10000 || cp > 0x10FFFF)) ||
				(cp >= 0xD800 && cp <= 0xDFFF)) {
			return false;
		}
		i += extra + 1;
	}
	return true;
}

static char32_t _cp1252_codepoint(uint8_t p_byte) {
	static const char32_t table[32] = {
		0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
		0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
		0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
		0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178
	};
	if (p_byte >= 0x80 && p_byte <= 0x9F) {
		return table[p_byte - 0x80];
	}
	return p_byte;
}

static String _decode_cp1252(const uint8_t *p_data, int p_len) {
	String out;
	// resize_uninitialized() must include the terminating NUL in its size.
	out.resize_uninitialized(p_len + 1);
	char32_t *w = out.ptrw();
	for (int i = 0; i < p_len; i++) {
		w[i] = _cp1252_codepoint(p_data[i]);
	}
	w[p_len] = 0;
	return out;
}

String RetroUtil::decode_text(const uint8_t *p_data, int p_len) {
	if (p_data == nullptr || p_len <= 0) {
		return String();
	}
	const uint8_t *bytes = p_data;
	int len = p_len;
	// Skip a UTF-8 byte order mark; it is not part of the text itself.
	if (len >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
		bytes += 3;
		len -= 3;
	}
	if (len == 0) {
		return String();
	}
	if (_is_valid_utf8(bytes, len)) {
		return String::utf8(reinterpret_cast<const char *>(bytes), len);
	}
	// Legacy Windows-1252/Latin-1 text: decode silently instead of printing a
	// replacement-character warning for every accented byte.
	return _decode_cp1252(bytes, len);
}

String RetroUtil::read_text(const String &p_path) {
	const Vector<uint8_t> data = read_bytes(p_path);
	// Do not emit a UTF-8 replacement warning for binary files accidentally
	// scanned as source. Binary formats are handled by their own decoders.
	for (int i = 0; i < data.size(); i++) {
		if (data[i] == 0) {
			return String();
		}
	}
	return decode_text(data.ptr(), data.size());
}

Error RetroUtil::write_text(const String &p_path, const String &p_text) {
	const String dir = p_path.get_base_dir();
	if (!dir.is_empty()) {
		DirAccess::make_dir_recursive_absolute(dir);
	}
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::WRITE);
	if (f.is_null()) {
		return ERR_CANT_OPEN;
	}
	f->store_string(p_text);
	return OK;
}

Vector<uint8_t> RetroUtil::read_bytes(const String &p_path) {
	Vector<uint8_t> out;
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::READ);
	if (f.is_null()) {
		return out;
	}
	const uint64_t len = f->get_length();
	out.resize(len);
	if (len > 0) {
		f->get_buffer(out.ptrw(), len);
	}
	return out;
}

Error RetroUtil::write_bytes(const String &p_path, const Vector<uint8_t> &p_data) {
	const String dir = p_path.get_base_dir();
	if (!dir.is_empty()) {
		DirAccess::make_dir_recursive_absolute(dir);
	}
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::WRITE);
	if (f.is_null()) {
		return ERR_CANT_OPEN;
	}
	if (!p_data.is_empty()) {
		f->store_buffer(p_data.ptr(), p_data.size());
	}
	return OK;
}

bool RetroUtil::exists(const String &p_path) {
	return FileAccess::exists(p_path) || DirAccess::dir_exists_absolute(p_path);
}

bool RetroUtil::is_dir(const String &p_path) {
	return DirAccess::dir_exists_absolute(p_path);
}

bool RetroUtil::is_executable_file(const String &p_path) {
	if (!FileAccess::exists(p_path) || DirAccess::dir_exists_absolute(p_path)) {
		return false;
	}
#ifdef WINDOWS_ENABLED
	return true;
#else
	const uint32_t perms = FileAccess::get_unix_permissions(p_path);
	// Owner, group or other execute bit.
	return (perms & 0x49) != 0;
#endif
}

String RetroUtil::join(const String &p_a, const String &p_b) {
	if (p_a.is_empty()) {
		return p_b;
	}
	if (p_b.is_empty()) {
		return p_a;
	}
	return p_a.path_join(p_b);
}

String RetroUtil::absolute(const String &p_path) {
	if (p_path.is_absolute_path()) {
		return p_path.simplify_path();
	}
	return ProjectSettings::get_singleton()->globalize_path(p_path).simplify_path();
}

String RetroUtil::normalize(const String &p_path) {
	return p_path.replace("\\", "/").simplify_path();
}

String RetroUtil::shell_quote(const String &p_value) {
	return "'" + p_value.replace("'", "'\\''") + "'";
}

String RetroUtil::which(const String &p_name) {
	if (p_name.contains("/")) {
		return is_executable_file(p_name) ? p_name : String();
	}
	const String path_env = OS::get_singleton()->get_environment("PATH");
	const PackedStringArray dirs = path_env.split(":", false);
	for (const String &dir : dirs) {
		const String candidate = dir.path_join(p_name);
		if (is_executable_file(candidate)) {
			return candidate;
		}
	}
	return String();
}

Array RetroUtil::which_all(const String &p_name) {
	Array out;
	const String path_env = OS::get_singleton()->get_environment("PATH");
	const PackedStringArray dirs = path_env.split(":", false);
	for (const String &dir : dirs) {
		const String candidate = dir.path_join(p_name);
		if (is_executable_file(candidate)) {
			out.push_back(candidate);
		}
	}
	return out;
}

static void _collect_entries(const String &p_dir, bool p_recursive, bool p_files, Array &r_out, int p_depth) {
	if (p_depth > 24) {
		return;
	}
	Ref<DirAccess> da = DirAccess::open(p_dir);
	if (da.is_null()) {
		return;
	}
	da->list_dir_begin();
	String name = da->get_next();
	while (!name.is_empty()) {
		if (name == "." || name == "..") {
			name = da->get_next();
			continue;
		}
		const String full = p_dir.path_join(name);
		if (da->current_is_dir()) {
			if (p_recursive && name != ".git" && name != ".retro") {
				_collect_entries(full, true, p_files, r_out, p_depth + 1);
			}
		} else if (p_files) {
			r_out.push_back(full);
		}
		name = da->get_next();
	}
	da->list_dir_end();
}

Array RetroUtil::list_files(const String &p_dir, bool p_recursive) {
	Array out;
	_collect_entries(p_dir, p_recursive, true, out, 0);
	return out;
}

Array RetroUtil::list_dirs(const String &p_dir, bool p_recursive) {
	Array out;
	Ref<DirAccess> da = DirAccess::open(p_dir);
	if (da.is_null()) {
		return out;
	}
	da->list_dir_begin();
	String name = da->get_next();
	while (!name.is_empty()) {
		if (name != "." && name != ".." && da->current_is_dir()) {
			const String full = p_dir.path_join(name);
			out.push_back(full);
			if (p_recursive && name != ".git" && name != ".retro") {
				const Array sub = list_dirs(full, true);
				for (int i = 0; i < sub.size(); i++) {
					out.push_back(sub[i]);
				}
			}
		}
		name = da->get_next();
	}
	da->list_dir_end();
	return out;
}

Array RetroUtil::find_files(const String &p_dir, const Vector<String> &p_extensions, int p_max_depth) {
	Array out;
	Array dirs;
	dirs.push_back(p_dir);
	int depth = 0;
	while (!dirs.is_empty() && depth <= p_max_depth) {
		Array next;
		for (int i = 0; i < dirs.size(); i++) {
			const String dir = dirs[i];
			Ref<DirAccess> da = DirAccess::open(dir);
			if (da.is_null()) {
				continue;
			}
			da->list_dir_begin();
			String name = da->get_next();
			while (!name.is_empty()) {
				if (name == "." || name == "..") {
					name = da->get_next();
					continue;
				}
				const String full = dir.path_join(name);
				if (da->current_is_dir()) {
					if (name != ".git" && name != ".retro" && name != "node_modules" && name != "__pycache__") {
						next.push_back(full);
					}
				} else {
					const String ext = file_extension_lower(name);
					for (int e = 0; e < p_extensions.size(); e++) {
						if (ext == p_extensions[e]) {
							out.push_back(full);
							break;
						}
					}
				}
				name = da->get_next();
			}
			da->list_dir_end();
		}
		dirs = next;
		depth++;
	}
	return out;
}

String RetroUtil::find_rom(const String &p_dir) {
	const Vector<String> exts = { "sfc", "smc", "md", "gen", "bin" };
	Array files = find_files(p_dir, exts, 4);
	int best_score = -1000;
	uint64_t best_time = 0;
	String best;
	for (int i = 0; i < files.size(); i++) {
		const String f = files[i];
		const String lower = f.to_lower();
		if (lower.contains("/.retro/") || lower.contains("/src/") || lower.contains("/tools/")) {
			continue;
		}
		Ref<FileAccess> fa = FileAccess::open(f, FileAccess::READ);
		if (fa.is_null()) {
			continue;
		}
		const uint64_t size = fa->get_length();
		if (size < 32768) {
			continue;
		}
		const uint64_t m = FileAccess::get_modified_time(f);
		int score = 0;
		if (lower.ends_with(".sfc") || lower.ends_with(".smc") || lower.ends_with(".md") || lower.ends_with(".gen")) {
			score += 10;
		} else if (lower.ends_with("/rom.bin") || lower.ends_with("/out.bin")) {
			score += 8;
		} else {
			score += 2;
		}
		// Prefer the project's own linked ROM over build staging copies.
		if (lower.contains("/build/") || lower.contains("/out/")) {
			score -= 4;
		}
		if (lower.contains("staging") || lower.contains("backup") || lower.contains("_old")) {
			score -= 20;
		}
		// Shallower artifacts are usually the canonical output.
		const int rel_depth = f.trim_prefix(p_dir).count("/");
		score -= rel_depth;
		if (score > best_score || (score == best_score && m > best_time)) {
			best_score = score;
			best_time = m;
			best = f;
		}
	}
	return best;
}

String RetroUtil::human_size(uint64_t p_bytes) {
	if (p_bytes >= 1024ULL * 1024ULL) {
		return String::num(p_bytes / (1024.0 * 1024.0), 2) + " MiB";
	}
	if (p_bytes >= 1024ULL) {
		return String::num(p_bytes / 1024.0, 1) + " KiB";
	}
	return String::num_uint64(p_bytes) + " B";
}

Dictionary RetroUtil::parse_json_file(const String &p_path, bool *r_ok) {
	Dictionary out;
	if (!FileAccess::exists(p_path)) {
		if (r_ok) {
			*r_ok = false;
		}
		return out;
	}
	const String text = read_text(p_path);
	if (text.strip_edges().is_empty()) {
		if (r_ok) {
			*r_ok = false;
		}
		return out;
	}
	JSON json;
	if (json.parse(text) != OK) {
		if (r_ok) {
			*r_ok = false;
		}
		return out;
	}
	const Variant v = json.get_data();
	if (v.get_type() != Variant::DICTIONARY) {
		if (r_ok) {
			*r_ok = false;
		}
		return out;
	}
	if (r_ok) {
		*r_ok = true;
	}
	return v;
}

Error RetroUtil::save_json_file(const String &p_path, const Dictionary &p_data) {
	return write_text(p_path, JSON::stringify(p_data, "\t", false) + "\n");
}

String RetroUtil::file_extension_lower(const String &p_path) {
	return p_path.get_extension().to_lower();
}

Array RetroUtil::split_lines(const String &p_text) {
	Array out;
	PackedStringArray lines = p_text.replace("\r\n", "\n").split("\n");
	for (int i = 0; i < lines.size(); i++) {
		out.push_back(lines[i]);
	}
	return out;
}

bool RetroUtil::looks_text(const String &p_path) {
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::READ);
	if (f.is_null()) {
		return false;
	}
	const uint64_t n = MIN<uint64_t>(f->get_length(), 4096);
	Vector<uint8_t> buf;
	buf.resize(n);
	if (n > 0) {
		f->get_buffer(buf.ptrw(), n);
	}
	for (uint64_t i = 0; i < n; i++) {
		if (buf[i] == 0) {
			return false;
		}
	}
	return true;
}

String RetroUtil::sanitize_name(const String &p_name) {
	String out = p_name.strip_edges();
	const String invalid = "\\/:*?\"<>| ";
	for (int i = 0; i < invalid.length(); i++) {
		out = out.replace(String::chr(invalid[i]), "_");
	}
	return out.is_empty() ? "project" : out;
}

Error RetroUtil::copy_tree(const String &p_from, const String &p_to, const Vector<String> &p_exclude_dirs) {
	if (!is_dir(p_from)) {
		return ERR_INVALID_PARAMETER;
	}
	DirAccess::make_dir_recursive_absolute(p_to);
	Ref<DirAccess> da = DirAccess::open(p_from);
	if (da.is_null()) {
		return ERR_CANT_OPEN;
	}
	da->list_dir_begin();
	String name = da->get_next();
	while (!name.is_empty()) {
		if (name == "." || name == "..") {
			name = da->get_next();
			continue;
		}
		const String src = p_from.path_join(name);
		const String dst = p_to.path_join(name);
		if (da->current_is_dir()) {
			bool skip = name == ".git";
			for (int i = 0; i < p_exclude_dirs.size(); i++) {
				if (name == p_exclude_dirs[i]) {
					skip = true;
				}
			}
			if (!skip) {
				const Error err = copy_tree(src, dst, p_exclude_dirs);
				if (err != OK) {
					da->list_dir_end();
					return err;
				}
			}
		} else {
			const Error err = DirAccess::copy_absolute(src, dst, -1);
			if (err != OK) {
				// Fall back to byte copy (some virtual filesystems do not
				// support DirAccess::copy_absolute for large files).
				const Vector<uint8_t> data = read_bytes(src);
				if (write_bytes(dst, data) != OK) {
					da->list_dir_end();
					return err;
				}
			}
		}
		name = da->get_next();
	}
	da->list_dir_end();
	return OK;
}
