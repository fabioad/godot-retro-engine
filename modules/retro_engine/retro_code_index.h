/**************************************************************************/
/*  retro_code_index.h - C/assembly symbol index for code<->asset links     */
/**************************************************************************/

#ifndef RETRO_CODE_INDEX_H
#define RETRO_CODE_INDEX_H

#include "retro_project.h"

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

class RetroCodeIndex : public RefCounted {
	GDCLASS(RetroCodeIndex, RefCounted);

protected:
	static void _bind_methods();

public:
	Array scan_project(const Ref<RetroProject> &p_project);
	Array scan_file(const String &p_path);
	Dictionary find_symbol(const Array &p_index, const String &p_name);
	Array associations_for_resource(const Ref<RetroProject> &p_project, const String &p_resource_rel_path);
	Dictionary preview(const String &p_path, int p_offset = 0, int p_lines = 200);
};

#endif // RETRO_CODE_INDEX_H
