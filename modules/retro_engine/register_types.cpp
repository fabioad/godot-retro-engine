/**************************************************************************/
/*  register_types.cpp                                                    */
/*  Godot Retro Engine - SNES / Mega Drive development module             */
/**************************************************************************/

#include "register_types.h"

#include "retro_animation.h"
#include "retro_builder.h"
#include "retro_code_index.h"
#include "retro_collision_runtime.h"
#include "retro_emulator.h"
#include "retro_graphics.h"
#include "retro_hardware.h"
#include "retro_importer.h"
#include "retro_hitbox_io.h"
#include "retro_mugen_import.h"
#include "retro_native_bridge.h"
#include "retro_input.h"
#include "retro_project.h"
#include "retro_sdk.h"
#include "retro_sprite.h"
#include "retro_state_graph.h"
#include "retro_stage.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"

void initialize_retro_engine_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		GDREGISTER_CLASS(RetroSDK);
		GDREGISTER_CLASS(RetroProject);
		GDREGISTER_CLASS(RetroImporter);
		GDREGISTER_CLASS(RetroInputMap);
		GDREGISTER_CLASS(RetroStateGraph);
		GDREGISTER_CLASS(RetroHitboxIO);
		GDREGISTER_CLASS(RetroCollisionRuntime);
		GDREGISTER_CLASS(RetroMugenImport);
		GDREGISTER_CLASS(RetroNativeBridge);
		GDREGISTER_CLASS(RetroGraphics);
		GDREGISTER_CLASS(RetroHardware);
		GDREGISTER_CLASS(RetroSprite);
		GDREGISTER_CLASS(RetroStage);
		GDREGISTER_CLASS(RetroAnimation);
		GDREGISTER_CLASS(RetroBuilder);
		GDREGISTER_CLASS(RetroEmulator);
		GDREGISTER_CLASS(RetroCodeIndex);

		RetroSDK *sdk = memnew(RetroSDK);
		Engine::get_singleton()->add_singleton(
				Engine::Singleton("RetroSDK", sdk, "RetroSDK"));
	}

	if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		// Editor integration is implemented by the retro_engine editor plugin
		// (GDScript) shipped in ide/addons/retro_engine. Keeping the module at
		// scene level means the same backend also works from headless tools.
	}
}

void uninitialize_retro_engine_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		Engine::get_singleton()->remove_singleton("RetroSDK");
		RetroSDK *sdk = RetroSDK::get_singleton();
		if (sdk) {
			memdelete(sdk);
		}
	}
}
