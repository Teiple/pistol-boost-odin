package main

import "core:math/linalg"
import sapp "sokol-odin/sokol/app"
import sg "sokol-odin/sokol/gfx"
import sglue "sokol-odin/sokol/glue"
import slog "sokol-odin/sokol/log"

Game :: struct {
	viewport   : Viewport,
	frame_time : Frame_Time,
	camera     : Camera,
	renderer   : Renderer,
	ui         : Ui,
	
	scene            : Scene,
	scene_callbacks  : Scene_Callbacks,
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
	
	game.scene = Scene_Gameplay{}
	game.scene_callbacks = scene_boot(&game.scene)
}

game_update :: proc(dt : f32) {
	frame_time_update(&game.frame_time, dt)

	if game.scene_callbacks.update_ui != nil {
		game.scene_callbacks.update_ui(&game.scene)
	}
	
	ui_begin(&game.ui, &game.viewport)
	{
		if game.scene_callbacks.update_3d != nil {
			game.scene_callbacks.update_3d(&game.scene, dt)
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
}

game_destroy :: proc() {
	scene_shutdown(&game.scene)

	ui_destroy(&game.ui)
	renderer_destroy(&game.renderer)
	camera_destroy(&game.camera)
	viewport_destroy(&game.viewport)
}