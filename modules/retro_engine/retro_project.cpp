/**************************************************************************/
/*  retro_project.cpp                                                     */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_project.h"

#include "retro_util.h"

#include "core/os/time.h"

void RetroProject::_bind_methods() {
	ClassDB::bind_method(D_METHOD("to_dict"), &RetroProject::to_dict);
	ClassDB::bind_method(D_METHOD("from_dict", "data"), &RetroProject::from_dict);
	ClassDB::bind_method(D_METHOD("save", "file"), &RetroProject::save, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("load", "file"), &RetroProject::load);
	ClassDB::bind_method(D_METHOD("get_resource", "id"), &RetroProject::get_resource);
	ClassDB::bind_method(D_METHOD("find_resources", "editor", "editable_only"), &RetroProject::find_resources, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("add_association", "assoc"), &RetroProject::add_association);
	ClassDB::bind_method(D_METHOD("metadata_path"), &RetroProject::metadata_path);
	ClassDB::bind_method(D_METHOD("resolve", "relative"), &RetroProject::resolve);

	ClassDB::bind_method(D_METHOD("set_name", "value"), &RetroProject::set_name);
	ClassDB::bind_method(D_METHOD("get_name"), &RetroProject::get_name);
	ClassDB::bind_method(D_METHOD("set_path", "value"), &RetroProject::set_path);
	ClassDB::bind_method(D_METHOD("get_path"), &RetroProject::get_path);
	ClassDB::bind_method(D_METHOD("set_source_path", "value"), &RetroProject::set_source_path);
	ClassDB::bind_method(D_METHOD("get_source_path"), &RetroProject::get_source_path);
	ClassDB::bind_method(D_METHOD("set_platform", "value"), &RetroProject::set_platform);
	ClassDB::bind_method(D_METHOD("get_platform"), &RetroProject::get_platform);
	ClassDB::bind_method(D_METHOD("set_sdk_path", "value"), &RetroProject::set_sdk_path);
	ClassDB::bind_method(D_METHOD("get_sdk_path"), &RetroProject::get_sdk_path);
	ClassDB::bind_method(D_METHOD("set_sdk_version", "value"), &RetroProject::set_sdk_version);
	ClassDB::bind_method(D_METHOD("get_sdk_version"), &RetroProject::get_sdk_version);
	ClassDB::bind_method(D_METHOD("set_build_system", "value"), &RetroProject::set_build_system);
	ClassDB::bind_method(D_METHOD("get_build_system"), &RetroProject::get_build_system);
	ClassDB::bind_method(D_METHOD("set_build_file", "value"), &RetroProject::set_build_file);
	ClassDB::bind_method(D_METHOD("get_build_file"), &RetroProject::get_build_file);
	ClassDB::bind_method(D_METHOD("set_build_target", "value"), &RetroProject::set_build_target);
	ClassDB::bind_method(D_METHOD("get_build_target"), &RetroProject::get_build_target);
	ClassDB::bind_method(D_METHOD("set_clean_target", "value"), &RetroProject::set_clean_target);
	ClassDB::bind_method(D_METHOD("get_clean_target"), &RetroProject::get_clean_target);
	ClassDB::bind_method(D_METHOD("set_build_command", "value"), &RetroProject::set_build_command);
	ClassDB::bind_method(D_METHOD("get_build_command"), &RetroProject::get_build_command);
	ClassDB::bind_method(D_METHOD("set_rom_path", "value"), &RetroProject::set_rom_path);
	ClassDB::bind_method(D_METHOD("get_rom_path"), &RetroProject::get_rom_path);
	ClassDB::bind_method(D_METHOD("set_rom_title", "value"), &RetroProject::set_rom_title);
	ClassDB::bind_method(D_METHOD("get_rom_title"), &RetroProject::get_rom_title);
	ClassDB::bind_method(D_METHOD("set_emulator_id", "value"), &RetroProject::set_emulator_id);
	ClassDB::bind_method(D_METHOD("get_emulator_id"), &RetroProject::get_emulator_id);
	ClassDB::bind_method(D_METHOD("set_mode", "value"), &RetroProject::set_mode);
	ClassDB::bind_method(D_METHOD("get_mode"), &RetroProject::get_mode);
	ClassDB::bind_method(D_METHOD("set_linked_in_place", "value"), &RetroProject::set_linked_in_place);
	ClassDB::bind_method(D_METHOD("get_linked_in_place"), &RetroProject::get_linked_in_place);
	ClassDB::bind_method(D_METHOD("set_imported", "value"), &RetroProject::set_imported);
	ClassDB::bind_method(D_METHOD("get_imported"), &RetroProject::get_imported);
	ClassDB::bind_method(D_METHOD("set_metadata", "value"), &RetroProject::set_metadata);
	ClassDB::bind_method(D_METHOD("get_metadata"), &RetroProject::get_metadata);
	ClassDB::bind_method(D_METHOD("set_resources", "value"), &RetroProject::set_resources);
	ClassDB::bind_method(D_METHOD("get_resources"), &RetroProject::get_resources);
	ClassDB::bind_method(D_METHOD("set_sources", "value"), &RetroProject::set_sources);
	ClassDB::bind_method(D_METHOD("get_sources"), &RetroProject::get_sources);
	ClassDB::bind_method(D_METHOD("set_associations", "value"), &RetroProject::set_associations);
	ClassDB::bind_method(D_METHOD("get_associations"), &RetroProject::get_associations);
	ClassDB::bind_method(D_METHOD("set_warnings", "value"), &RetroProject::set_warnings);
	ClassDB::bind_method(D_METHOD("get_warnings"), &RetroProject::get_warnings);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name"), "set_name", "get_name");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "path"), "set_path", "get_path");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "source_path"), "set_source_path", "get_source_path");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "platform"), "set_platform", "get_platform");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "sdk_path"), "set_sdk_path", "get_sdk_path");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "sdk_version"), "set_sdk_version", "get_sdk_version");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "build_system"), "set_build_system", "get_build_system");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "build_file"), "set_build_file", "get_build_file");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "build_target"), "set_build_target", "get_build_target");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "clean_target"), "set_clean_target", "get_clean_target");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "build_command"), "set_build_command", "get_build_command");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "rom_path"), "set_rom_path", "get_rom_path");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "rom_title"), "set_rom_title", "get_rom_title");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "emulator_id"), "set_emulator_id", "get_emulator_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "mode"), "set_mode", "get_mode");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "linked_in_place"), "set_linked_in_place", "get_linked_in_place");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "imported"), "set_imported", "get_imported");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "metadata"), "set_metadata", "get_metadata");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "resources"), "set_resources", "get_resources");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "sources"), "set_sources", "get_sources");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "associations"), "set_associations", "get_associations");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "warnings"), "set_warnings", "get_warnings");
}

RetroProject::RetroProject() = default;

Dictionary RetroProject::to_dict() const {
	Dictionary d;
	d["format"] = "godot-retro-engine/project";
	d["format_version"] = 1;
	d["name"] = name;
	d["path"] = path;
	d["source_path"] = source_path;
	d["platform"] = platform;
	d["sdk_path"] = sdk_path;
	d["sdk_version"] = sdk_version;
	d["build_system"] = build_system;
	d["build_file"] = build_file;
	d["build_target"] = build_target;
	d["clean_target"] = clean_target;
	d["build_command"] = build_command;
	d["rom_path"] = rom_path;
	d["rom_title"] = rom_title;
	d["emulator_id"] = emulator_id;
	d["mode"] = mode;
	d["linked_in_place"] = linked_in_place;
	d["imported"] = imported;
	d["metadata"] = metadata;
	d["resources"] = resources;
	d["sources"] = sources;
	d["associations"] = associations;
	d["warnings"] = warnings;
	return d;
}

void RetroProject::from_dict(const Dictionary &p_dict) {
	name = p_dict.get("name", String());
	path = p_dict.get("path", String());
	source_path = p_dict.get("source_path", String());
	platform = p_dict.get("platform", String("snes"));
	sdk_path = p_dict.get("sdk_path", String());
	sdk_version = p_dict.get("sdk_version", String());
	build_system = p_dict.get("build_system", String("make"));
	build_file = p_dict.get("build_file", String("Makefile"));
	build_target = p_dict.get("build_target", String());
	clean_target = p_dict.get("clean_target", String("clean"));
	build_command = p_dict.get("build_command", String());
	rom_path = p_dict.get("rom_path", String());
	rom_title = p_dict.get("rom_title", String());
	emulator_id = p_dict.get("emulator_id", String());
	mode = p_dict.get("mode", String("mode1"));
	linked_in_place = p_dict.get("linked_in_place", false);
	imported = p_dict.get("imported", true);
	metadata = p_dict.get("metadata", Dictionary());
	resources = p_dict.get("resources", Array());
	sources = p_dict.get("sources", Array());
	associations = p_dict.get("associations", Array());
	warnings = p_dict.get("warnings", Array());
}

String RetroProject::metadata_path() const {
	return RetroUtil::join(path, ".retro/project.json");
}

Error RetroProject::save(const String &p_file) {
	const String file = p_file.is_empty() ? metadata_path() : p_file;
	metadata["last_saved"] = Time::get_singleton()->get_datetime_string_from_system();
	return RetroUtil::save_json_file(file, to_dict());
}

Error RetroProject::load(const String &p_file) {
	bool ok = false;
	const Dictionary d = RetroUtil::parse_json_file(p_file, &ok);
	if (!ok) {
		return ERR_FILE_CANT_READ;
	}
	from_dict(d);
	if (path.is_empty()) {
		path = p_file.get_base_dir().get_base_dir();
	}
	return OK;
}

Dictionary RetroProject::get_resource(const String &p_id) const {
	for (int i = 0; i < resources.size(); i++) {
		const Dictionary r = resources[i];
		if (String(r.get("id", "")) == p_id) {
			return r;
		}
	}
	return Dictionary();
}

Array RetroProject::find_resources(const String &p_editor, bool p_editable_only) const {
	Array out;
	for (int i = 0; i < resources.size(); i++) {
		const Dictionary r = resources[i];
		if (!p_editor.is_empty() && String(r.get("editor", "")) != p_editor) {
			continue;
		}
		if (p_editable_only && !bool(r.get("editable", false))) {
			continue;
		}
		out.push_back(r);
	}
	return out;
}

void RetroProject::add_association(const Dictionary &p_assoc) {
	associations.push_back(p_assoc);
}

String RetroProject::resolve(const String &p_relative) const {
	if (p_relative.is_absolute_path()) {
		return p_relative;
	}
	return RetroUtil::join(path, p_relative);
}
