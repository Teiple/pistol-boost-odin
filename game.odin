package main

import sapp "sokol-odin/sokol/app"
import sg "sokol-odin/sokol/gfx"
import sglue "sokol-odin/sokol/glue"
import slog "sokol-odin/sokol/log"

Game :: struct {
	viewport : Viewport,
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
}

game_draw_3d :: proc() {

}

game_draw_ui :: proc() {
	
}

game_destroy :: proc() {
	viewport_destroy(&game.viewport)
}