package main

import ins "base:intrinsics"
import sapp "sokol-odin/sokol/app"

Scene :: union #no_nil {
	Scene_Title,
	Scene_Main_Menu,
	Scene_Gameplay,
}

Scene_Callbacks_Any :: Scene_Callbacks(rawptr)

Scene_Callbacks :: struct($T : typeid) where ins.type_is_pointer(T) {
	init      : proc(scene : T),
	update_3d : proc(scene : T, dt : f32),
	update_ui : proc(scene : T),
	draw_3d   : proc(scene : T),
	input_3d  : proc(scene : T, ev : sapp.Event),
	input_ui  : proc(scene : T, ev : sapp.Event),
	destroy   : proc(scene : T),
}

scene_get_callbacks :: proc(scene : ^Scene) -> Scene_Callbacks_Any {
	// too long to write
	Raw :: Scene_Callbacks_Any
	
	switch s in scene {
		case Scene_Title:
			return transmute(Raw)SCENE_TITLE_CALLBACKS
		case Scene_Gameplay:
			return transmute(Raw)SCENE_GAMEPLAY_CALLBACKS
		case Scene_Main_Menu:
			return transmute(Raw)SCENE_MAIN_MENU_CALLBACKS
	}
	panic("Unreachable")
}

// These two are just for cleaner game shell really
// you could've just call the callbacks directly
@require_results
scene_boot :: proc(scene : ^Scene) -> Scene_Callbacks(rawptr) {
	cbs := scene_get_callbacks(scene)
	if cbs.init != nil {
		cbs.init(scene)
	}
	return cbs
}

scene_shutdown :: proc(scene : ^Scene) {
	cbs := scene_get_callbacks(scene)
	if cbs.destroy != nil {
		cbs.destroy(scene)
	}
}