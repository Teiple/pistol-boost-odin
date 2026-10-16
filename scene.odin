package main

import sapp "sokol-odin/sokol/app"
import ins "base:intrinsics"

Scene :: union #no_nil {
	Scene_Title,
	Scene_Main_Menu,
	Scene_Gameplay,
}

// actually this could just be Scene_Callbacks(rawptr)
Scene_Callbacks_Any :: Scene_Callbacks(^Scene)

Scene_Callbacks :: struct($T: typeid) where ins.type_is_pointer(T) &&
	(
		ins.type_elem_type(T) == Scene || // either the general Scene union, aka. Scene_Callbacks_Any
		ins.type_is_variant_of(Scene, ins.type_elem_type(T))  // or its collapsed type
	)
{
	init      : proc(scene : T),
	update_3d : proc(scene : T, dt : f32),
	update_ui : proc(scene : T, ui : ^Ui),
	draw_3d   : proc(scene : T, renderer : ^Renderer),
	input_3d  : proc(scene : T, ev : sapp.Event),
	input_ui  : proc(scene : T, ui : ^Ui, ev : sapp.Event),
	destroy   : proc(scene : T),
}

scene_get_callbacks :: proc(scene : ^Scene) -> Scene_Callbacks_Any {
	// The reason it's parapoly is to ensure typesafety 
	convert_cbs :: #force_inline proc(cbs: Scene_Callbacks(^$S)) -> Scene_Callbacks_Any {
		return transmute(Scene_Callbacks_Any)cbs
	}
	
	switch s in scene {
		case Scene_Title:
			return convert_cbs(SCENE_TITLE_CALLBACKS)
		case Scene_Gameplay:
			return convert_cbs(SCENE_GAMEPLAY_CALLBACKS)
		case Scene_Main_Menu:
			return convert_cbs(SCENE_MAIN_MENU_CALLBACKS)
	}
	panic("Unreachable")
}

// These two are just for cleaner game shell really
// you could've just call the callbacks directly
@require_results
scene_boot :: proc(scene : ^Scene) -> Scene_Callbacks_Any {
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