/**************************************************************************/
/*  retro_project.h - imported game project metadata                      */
/**************************************************************************/

#ifndef RETRO_PROJECT_H
#define RETRO_PROJECT_H

#include "core/object/ref_counted.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

class RetroProject : public RefCounted {
	GDCLASS(RetroProject, RefCounted);

	String name;
	String path; // working copy root
	String source_path; // original project root (never modified unless link-in-place)
	String platform = "snes";
	String sdk_path;
	String sdk_version;
	String build_system = "make";
	String build_file = "Makefile";
	String build_target;
	String clean_target = "clean";
	String build_command;
	String rom_path;
	String rom_title;
	String emulator_id;
	String mode = "mode1";
	Dictionary metadata;
	Array resources;
	Array sources;
	Array associations;
	Array warnings;
	bool linked_in_place = false;
	bool imported = false;

protected:
	static void _bind_methods();

public:
	RetroProject();

	void set_name(const String &p_name) { name = p_name; }
	String get_name() const { return name; }
	void set_path(const String &p_path) { path = p_path; }
	String get_path() const { return path; }
	void set_source_path(const String &p_path) { source_path = p_path; }
	String get_source_path() const { return source_path; }
	void set_platform(const String &p_platform) { platform = p_platform; }
	String get_platform() const { return platform; }
	void set_sdk_path(const String &p_path) { sdk_path = p_path; }
	String get_sdk_path() const { return sdk_path; }
	void set_sdk_version(const String &p_version) { sdk_version = p_version; }
	String get_sdk_version() const { return sdk_version; }
	void set_build_system(const String &p_value) { build_system = p_value; }
	String get_build_system() const { return build_system; }
	void set_build_file(const String &p_value) { build_file = p_value; }
	String get_build_file() const { return build_file; }
	void set_build_target(const String &p_value) { build_target = p_value; }
	String get_build_target() const { return build_target; }
	void set_clean_target(const String &p_value) { clean_target = p_value; }
	String get_clean_target() const { return clean_target; }
	void set_build_command(const String &p_value) { build_command = p_value; }
	String get_build_command() const { return build_command; }
	void set_rom_path(const String &p_value) { rom_path = p_value; }
	String get_rom_path() const { return rom_path; }
	void set_rom_title(const String &p_value) { rom_title = p_value; }
	String get_rom_title() const { return rom_title; }
	void set_emulator_id(const String &p_value) { emulator_id = p_value; }
	String get_emulator_id() const { return emulator_id; }
	void set_mode(const String &p_value) { mode = p_value; }
	String get_mode() const { return mode; }
	void set_linked_in_place(bool p_value) { linked_in_place = p_value; }
	bool get_linked_in_place() const { return linked_in_place; }
	void set_imported(bool p_value) { imported = p_value; }
	bool get_imported() const { return imported; }

	Dictionary get_metadata() const { return metadata; }
	void set_metadata(const Dictionary &p_value) { metadata = p_value; }
	Array get_resources() const { return resources; }
	void set_resources(const Array &p_value) { resources = p_value; }
	Array get_sources() const { return sources; }
	void set_sources(const Array &p_value) { sources = p_value; }
	Array get_associations() const { return associations; }
	void set_associations(const Array &p_value) { associations = p_value; }
	Array get_warnings() const { return warnings; }
	void set_warnings(const Array &p_value) { warnings = p_value; }

	Dictionary to_dict() const;
	void from_dict(const Dictionary &p_dict);

	Error save(const String &p_file = String());
	Error load(const String &p_file);

	Dictionary get_resource(const String &p_id) const;
	Array find_resources(const String &p_editor, bool p_editable_only = false) const;
	void add_association(const Dictionary &p_assoc);
	String metadata_path() const;
	String resolve(const String &p_relative) const;
};

#endif // RETRO_PROJECT_H
