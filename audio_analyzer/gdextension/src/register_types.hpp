#pragma once
// GDExtension 注册入口

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

void initialize_module(godot::ModuleInitializationLevel p_level);
void uninitialize_module(godot::ModuleInitializationLevel p_level);
