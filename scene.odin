package main

import sapp "sokol-odin/sokol/app"

Scene :: union #no_nil {
	Scene_Title,
	Scene_Main_Menu,
	Scene_Gameplay,
}

Scene_Callbacks :: struct {
	init    : proc(s : ^Scene),
	update  : proc(s : ^Scene, dt : f32),
	draw_3d : proc(s : ^Scene),
	draw_ui : proc(s : ^Scene),
	input   : proc(s : ^Scene, ev : sapp.Event),
}

scene_get_callbacks :: proc(scene : Scene) -> Scene_Callbacks {
	switch s in scene {
		case Scene_Title:
			return SCENE_TITLE_CALLBACKS
		case Scene_Gameplay:
			return SCENE_GAMEPLAY_CALLBACKS
		case Scene_Main_Menu:
			return SCENE_MAIN_MENU_CALLBACKS
	}
	panic("Unreachable")
}