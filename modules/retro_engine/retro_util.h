/**************************************************************************/
/*  retro_util.h - filesystem / process / JSON helpers                    */
/**************************************************************************/

#ifndef RETRO_UTIL_H
#define RETRO_UTIL_H

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/image.h"
#include "core/io/json.h"
#include "core/os/os.h"
#include "core/string/ustring.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

namespace RetroUtil {

String read_text(const String &p_path);
String decode_text(const uint8_t *p_data, int p_len);
Error write_text(const String &p_path, const String &p_text);
Vector<uint8_t> read_bytes(const String &p_path);
Error write_bytes(const String &p_path, const Vector<uint8_t> &p_data);
bool exists(const String &p_path);
bool is_dir(const String &p_path);
bool is_executable_file(const String &p_path);
String join(const String &p_a, const String &p_b);
String absolute(const String &p_path);
String normalize(const String &p_path);
String shell_quote(const String &p_value);
String which(const String &p_name);
Array which_all(const String &p_name);
Array list_files(const String &p_dir, bool p_recursive = false);
Array list_dirs(const String &p_dir, bool p_recursive = false);
Array find_files(const String &p_dir, const Vector<String> &p_extensions, int p_max_depth = 8);
String find_rom(const String &p_dir);
String human_size(uint64_t p_bytes);
Dictionary parse_json_file(const String &p_path, bool *r_ok = nullptr);
Error save_json_file(const String &p_path, const Dictionary &p_data);
String file_extension_lower(const String &p_path);
Array split_lines(const String &p_text);
bool looks_text(const String &p_path);
String sanitize_name(const String &p_name);
Error copy_tree(const String &p_from, const String &p_to, const Vector<String> &p_exclude_dirs = Vector<String>());
} // namespace RetroUtil

#endif // RETRO_UTIL_H
