package main

import "core:math/linalg"
import sapp "sokol-odin/sokol/app"
import sg "sokol-odin/sokol/gfx"
import sglue "sokol-odin/sokol/glue"
import slog "sokol-odin/sokol/log"
import fmt "core:fmt"

Game :: struct {
	viewport         : Viewport,
	renderer         : Renderer,
	camera           : Camera,
	time_since_start : f32,
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

	mesh := renderer_new_mesh(&game.renderer)
	mesh_init_box(mesh, {2, 1, 1})
}

game_update :: proc(dt : f32) {
	viewport_begin(&game.viewport, {
		sapp.widthf(),
		sapp.heightf(),
	})
	{
		game_draw_3d()
		game_draw_ui()
		
		viewport_end(&game.viewport)
	}
	
	game.time_since_start += dt		
}

game_draw_3d :: proc() {
	renderer_draw_mesh(
		&game.renderer,
		&game.camera,
		&game.viewport,
		&game.renderer.meshes[0],
		0,
		linalg.quaternion_from_pitch_yaw_roll(
			game.time_since_start,
			game.time_since_start * 0.25,
			game.time_since_start * 0.5,
		),
	)
}

game_draw_ui :: proc() {
	
}

game_destroy :: proc() {
	viewport_destroy(&game.viewport)
}