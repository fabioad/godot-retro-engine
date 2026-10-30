/**************************************************************************/
/*  retro_emulator.h - external emulator discovery and launch              */
/**************************************************************************/

#ifndef RETRO_EMULATOR_H
#define RETRO_EMULATOR_H

#include "core/object/object.h"
#include "core/variant/dictionary.h"

class RetroEmulator : public Object {
	GDCLASS(RetroEmulator, Object);

protected:
	static void _bind_methods();

public:
	static Array detect(const String &p_platform = String());
	static Dictionary launch(const String &p_rom, const String &p_emulator_id = String(), const Array &p_extra_args = Array());
	static Dictionary launch_debug(const String &p_rom, const String &p_emulator_id = String());
	static Dictionary probe_rom(const String &p_rom);
	static bool supports_debug(const String &p_emulator_id);
	static bool is_running(int64_t p_pid);
	static void terminate(int64_t p_pid);
};

#endif // RETRO_EMULATOR_H
