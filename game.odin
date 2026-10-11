package main

import sapp "sokol-odin/sokol/app"
import sg "sokol-odin/sokol/gfx"
import sglue "sokol-odin/sokol/glue"
import slog "sokol-odin/sokol/log"
import ins "base:intrinsics"

Game :: struct {
	viewport   : Viewport,
	frame_time : Frame_Time,
	camera     : Camera,
	renderer   : Renderer,
	ui         : Ui,
	
	scene           : Scene,
	scene_callbacks : Scene_Callbacks_Any,

	pending_scene : Maybe(Scene), 
}

game : Game 

game_init :: proc() {
	sg.setup({
		environment = sglue.environment(),
		logger      =  {
			func    = slog.func
		}
	})

	viewport_init(&game.viewport, {800, 480})
	camera_init_default(&game.camera, {0, 2, 10}, {0, 0, 0})
	renderer_init(&game.renderer)
	ui_init_default(&game.ui)
	
	game.scene = Scene_Main_Menu{}
	game.scene_callbacks = scene_boot(&game.scene)
}

game_update :: proc(dt : f32) {
	frame_time_update(&game.frame_time, dt)

	if game.scene_callbacks.update_3d != nil {
		game.scene_callbacks.update_3d(&game.scene, dt)
	}
	
	ui_begin(&game.ui, &game.viewport)
	{
		if game.scene_callbacks.update_ui != nil {
			game.scene_callbacks.update_ui(&game.scene)
		}
		ui_end(&game.ui, &game.viewport)
	}

	viewport_begin(&game.viewport, {
		sapp.widthf(),
		sapp.heightf(),
	})
	{
		if game.scene_callbacks.draw_3d != nil {
			game.scene_callbacks.draw_3d(&game.scene)
		}
		ui_draw(&game.ui, &game.viewport)
		viewport_end(&game.viewport)
	}
	
	free_all(context.temp_allocator)

	// Scene switching
	if game.pending_scene != nil {
		scene_shutdown(&game.scene)

		game.scene = game.pending_scene.?
		game.pending_scene = nil
		
		game.scene_callbacks = scene_boot(&game.scene)
	}
}

game_input :: proc(ev : ^sapp.Event) {
	if game.scene_callbacks.input_ui != nil {
		game.scene_callbacks.input_ui(&game.scene, ev^)
	}

	if  !ui_is_capturing_input(&game.ui) &&
		game.scene_callbacks.input_3d != nil {
		game.scene_callbacks.input_3d(&game.scene, ev^)
	}
}

// you should put newly created scene in here, e.g Scene_Gameplay{}, Scene_Main_Menu{}
// i used #by_ptr here so it don't need to copy when passing as an argument
// the copy still happens when assigning to game.pending_scene thou,
// however this is also to make the code more various in syntax,
// Odin will pass by pointer for large struct argument anyways (> 16 bytes iirc)
game_request_switch_scene :: proc(#by_ptr uninitialized_scene : Scene){
	game.pending_scene = uninitialized_scene
}

game_destroy :: proc() {
	scene_shutdown(&game.scene)

	ui_destroy(&game.ui)
	renderer_destroy(&game.renderer)
	camera_destroy(&game.camera)
	viewport_destroy(&game.viewport)
}
