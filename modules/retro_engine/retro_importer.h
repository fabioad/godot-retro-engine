/**************************************************************************/
/*  retro_importer.h - non-destructive SDK project inspection/import      */
/**************************************************************************/

#ifndef RETRO_IMPORTER_H
#define RETRO_IMPORTER_H

#include "retro_project.h"

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

class RetroImporter : public RefCounted {
	GDCLASS(RetroImporter, RefCounted);

protected:
	static void _bind_methods();

	static Dictionary _classify_resource(const String &p_root, const String &p_file, const String &p_platform);
	static String _detect_platform(const String &p_root, const Array &p_makefiles, Dictionary &r_info);

public:
	Dictionary scan(const String &p_path, const String &p_platform_hint = String());
	Ref<RetroProject> import_project(const String &p_path, const String &p_platform_hint,
			const String &p_workspace, bool p_copy = true, const String &p_name = String());
	Dictionary inspect_resource(const String &p_path, const String &p_platform = String());
	Array detect_build_files(const String &p_path);
};

#endif // RETRO_IMPORTER_H
