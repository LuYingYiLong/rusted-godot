#include "register_types.h"

#include "rw_game_math.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

// 在场景初始化阶段注册原生类，供 GDScript 直接使用原有类名
void initialize_rw_core_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(RwGameMath);
}

void uninitialize_rw_core_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
	GDExtensionBool GDE_EXPORT rw_core_library_init(GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library, GDExtensionInitialization* initialization) {
		GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
		init.register_initializer(initialize_rw_core_module);
		init.register_terminator(uninitialize_rw_core_module);
		init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
		return init.init();
	}
}
