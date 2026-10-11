package main

import sapp "sokol-odin/sokol/app"

Scene :: union #no_nil {
	Scene_Title,
	Scene_Main_Menu,
	Scene_Gameplay,
}

Scene_Callbacks :: struct {
	init      : proc(s : ^Scene),
	update_3d : proc(s : ^Scene, dt : f32),
	update_ui : proc(s : ^Scene),
	draw_3d   : proc(s : ^Scene),
	input     : proc(s : ^Scene, ev : sapp.Event),
	destroy   : proc(s : ^Scene),
}

scene_get_callbacks :: proc(scene : ^Scene) -> Scene_Callbacks {
	switch s in scene^ {
		case Scene_Title:
			return SCENE_TITLE_CALLBACKS
		case Scene_Gameplay:
			return SCENE_GAMEPLAY_CALLBACKS
		case Scene_Main_Menu:
			return SCENE_MAIN_MENU_CALLBACKS
	}
	panic("Unreachable")
}

scene_switch :: proc(from_scene : ^Scene, to_scene: ^Scene) -> Scene_Callbacks {
	from_cbs := scene_get_callbacks(from_scene)
	to_cbs   := scene_get_callbacks(to_scene)

	from_cbs.destroy(from_scene)
	to_cbs.init(to_scene)

	return to_cbs
}

// These two are just for cleaner game shell really
@require_results
scene_boot :: proc(scene : ^Scene) -> Scene_Callbacks {
	cbs := scene_get_callbacks(scene)
	cbs.init(scene)
	return cbs
}

scene_shutdown :: proc(scene : ^Scene){
	cbs := scene_get_callbacks(scene)
	cbs.destroy(scene)
}