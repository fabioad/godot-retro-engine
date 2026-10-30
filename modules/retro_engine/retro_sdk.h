/**************************************************************************/
/*  retro_sdk.h - PVSnesLib / SGDK detection and configuration            */
/**************************************************************************/

#ifndef RETRO_SDK_H
#define RETRO_SDK_H

#include "core/object/object.h"
#include "core/variant/dictionary.h"

class RetroSDK : public Object {
	GDCLASS(RetroSDK, Object);

	static RetroSDK *singleton;

	String snes_home;
	String md_home;

protected:
	static void _bind_methods();

public:
	static RetroSDK *get_singleton();

	void configure(const String &p_platform, const String &p_path);
	String get_configured_path(const String &p_platform) const;

	Dictionary probe_snes(const String &p_path) const;
	Dictionary probe_megadrive(const String &p_path) const;
	Dictionary detect_all() const;
	Dictionary get_sdk(const String &p_platform) const;

	Dictionary get_limits(const String &p_platform, const String &p_mode = String()) const;
	Array get_modes(const String &p_platform) const;
	Array get_emulators(const String &p_platform) const;

	RetroSDK();
	~RetroSDK();
};

#endif // RETRO_SDK_H
