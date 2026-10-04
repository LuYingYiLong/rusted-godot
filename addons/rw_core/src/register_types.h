#pragma once

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// 注册场景阶段使用的原生类
void initialize_rw_core_module(ModuleInitializationLevel p_level);
// 结束扩展模块的场景阶段
void uninitialize_rw_core_module(ModuleInitializationLevel p_level);
