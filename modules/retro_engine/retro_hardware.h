/**************************************************************************/
/*  retro_hardware.h - console resource limits and usage estimation        */
/**************************************************************************/

#ifndef RETRO_HARDWARE_H
#define RETRO_HARDWARE_H

#include "core/object/object.h"
#include "core/variant/dictionary.h"

class RetroHardware : public Object {
	GDCLASS(RetroHardware, Object);

protected:
	static void _bind_methods();

public:
	static Dictionary specs(const String &p_platform, const String &p_mode = String());
	static Dictionary estimate(const String &p_platform, const Dictionary &p_usage);
	static Dictionary sprite_line_check(const String &p_platform, const Array &p_sprites, int p_line_width = 0);
	static Dictionary validate_stage(const String &p_platform, const String &p_mode, const Dictionary &p_stage);
	static Array compare(const String &p_platform);
};

#endif // RETRO_HARDWARE_H
