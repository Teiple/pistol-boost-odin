package main

import "core:fmt"
import sapp "sokol-odin/sokol/app"
import sg "sokol-odin/sokol/gfx"
import sglue "sokol-odin/sokol/glue"
import slog "sokol-odin/sokol/log"

VIEWPORT_BASE_WIDTH  :: 960
VIEWPORT_BASE_HEIGHT :: 540

Game :: struct {
	viewport   : Viewport,
	frame_time : Frame_Time,
	time       : Game_Time,
	camera     : Camera,
	renderer   : Renderer,
	ui         : Ui,

	mouse : Mouse_Input,
	
	scene           : Scene,
	scene_callbacks : Scene_Callbacks_Any,

	pending_scene : Maybe(Scene),

	language : Language,
}

@(private = "file")
game : Game 

game_init :: proc() {
	sg.setup({
		environment = sglue.environment(),
		logger      =  {
			func    = slog.func
		}
	})

	game_time_init(&game.time)

	viewport_init(&game.viewport, {
			VIEWPORT_BASE_WIDTH,
			VIEWPORT_BASE_HEIGHT
		}, {
			sapp.widthf(),
			sapp.heightf(),
	})

	camera_init_default(&game.camera, {0, 2, 10}, {0, 0, 0})
	renderer_init(&game.renderer)
	
	game.language = .English
	
	font_configs := load_lang_font_configs()
	defer unload_lang_font_configs(font_configs)
	
	ui_init(&game.ui, font_configs)

	mouse_init(&game.mouse)
	
	game.scene = Scene_Main_Menu{}
	game.scene_callbacks = scene_boot(&game.scene)
}

game_update :: proc(unscaled_dt : f32) {
	frame_time_raw_update(&game.frame_time, unscaled_dt)
	
	dt : f32 = game_time_raw_update(&game.time, unscaled_dt)

	ui_begin(&game.ui, &game.viewport, &game.mouse, game.language)
	{
		if game.scene_callbacks.update_ui != nil {
			game.scene_callbacks.update_ui(&game.scene, &game.ui)
		}
		// cursor drawed on top
		ui_push_cursor(&game.ui,
			position = game.mouse.position,
			size     = 16,
			tint     = hsv(200)
		)
		ui_end(&game.ui, &game.viewport)
	}

	if game.scene_callbacks.update_3d != nil {
		game.scene_callbacks.update_3d(&game.scene, dt)
	}

	viewport_begin(&game.viewport, {
		sapp.widthf(),
		sapp.heightf(),
	})
	{
		defer viewport_end(&game.viewport)
		
		renderer_begin(&game.renderer, &game.camera, &game.viewport)
		{
			defer renderer_end(&game.renderer)

			if game.scene_callbacks.draw_3d != nil {
				game.scene_callbacks.draw_3d(&game.scene, &game.renderer)
			}
		}
		ui_draw(&game.ui, &game.viewport)
	}

	mouse_input_endframe(&game.mouse)
	
	free_all(context.temp_allocator)

	// Scene switching
	if game.pending_scene != nil {
		scene_shutdown(&game.scene)

		game.scene = game.pending_scene.?
		game.pending_scene = nil
		
		game.scene_callbacks = scene_boot(&game.scene)
		game_time_reset_time_scale(&game.time)
	}
}

game_input :: proc(ev : ^sapp.Event) {
	mouse_input(&game.mouse, &game.viewport, ev^)
	
	if game.scene_callbacks.input_ui != nil {
		game.scene_callbacks.input_ui(&game.scene, &game.ui, ev^)
	}

	if !ui_is_capturing_input(&game.ui) &&
		game.scene_callbacks.input_3d != nil {
		game.scene_callbacks.input_3d(&game.scene, ev^)
	}
}

// You should put newly created scene in here, e.g Scene_Gameplay{}, Scene_Main_Menu{}
// In case scene needs extra initial data you can add some data such as Scene_Gameplay{level = 1} for example   
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

game_time :: proc() -> ^Game_Time {
	return &game.time
}

game_request_quit :: proc() {
	sapp.request_quit()
}

tr :: proc(term: Loc_Term, params : ..any) -> string {
	if len(params) > 0 {
		return fmt.tprintf(loc_map[game.language][term], params)
	}
	return loc_map[game.language][term]
}

game_lang_is_cjk :: proc() -> bool {
	#partial switch game.language {
		case .Japanese, .SimplifiedChinese:
			return true
		case:
			return false
	}
}

game_switch_lang :: proc(lang : Language) {
	game.language = lang
}

game_lang :: proc() -> Language {
	return game.language
}