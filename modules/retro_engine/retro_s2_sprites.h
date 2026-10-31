/**************************************************************************/
/*  retro_s2_sprites.h - Sonic 2 disassembly sprite sheet extraction      */
/**************************************************************************/

#ifndef RETRO_S2_SPRITES_H
#define RETRO_S2_SPRITES_H

#include "core/string/ustring.h"
#include "core/variant/array.h"

class RetroS2Sprites {
public:
	// Reads sonic2.flex.json, decodes the referenced art/mappings/DPLC and
	// writes one indexed PNG sheet per sprite under .retro/generated/sprites.
	// Returns false when the project has no Flex 2 manifest.
	static bool extract(const String &p_root, Array &r_resources, Array &r_warnings);
};

#endif // RETRO_S2_SPRITES_H
