package main

import "core:fmt"
import sapp "sokol-odin/sokol/app"
import sg "sokol-odin/sokol/gfx"
import sglue "sokol-odin/sokol/glue"
import slog "sokol-odin/sokol/log"

VIEWPORT_BASE_WIDTH  :: 960
VIEWPORT_BASE_HEIGHT :: 540
GAME_VERSION         :: "0.0.0"
GAME_STARTUP_SCENE   :: Scene_Main_Menu{}

Game :: struct {
	viewport   : Viewport,
	frame_time : Frame_Time,
	time       : Game_Time,
	camera     : Camera,
	renderer   : Renderer,
	ui         : Ui,
	audio      : Audio,

	mouse_ui : Mouse_Input,
	mouse_3d : Mouse_Input,
	
	scene           : Scene,
	scene_callbacks : Scene_Callbacks_Any,

	pending_scene : Maybe(Scene),

	settings : Game_Settings,
}

@(private = "file")
game : Game 

@(private = "file")
game_context_make :: proc(game : ^Game, mouse : ^Mouse_Input) -> Game_Context {
	return {
		camera   = &game.camera,
		viewport = &game.viewport,
		mouse    = mouse,
		audio    = &game.audio,
		ui       = &game.ui,
		time     = &game.time,
		settings = &game.settings,
	}
}

game_init :: proc() {
	sg.setup({
		environment = sglue.environment(),
		logger      =  {
			func    = slog.func
		}
	})

	game_time_init(&game.time)

	viewport_init(&game.viewport,
		base_size   = {
			VIEWPORT_BASE_WIDTH,
			VIEWPORT_BASE_HEIGHT
		},
		window_size = {
			sapp.widthf(),
			sapp.heightf(),
		},
		clear_color = VIEWPORT_DEFAULT_CLEAR_COLOR,
	)

	camera_init_default(&game.camera, {0, .2, 2}, {0, 0, 0})
	renderer_init(&game.renderer)
	audio_init(&game.audio)
	
	game.settings = settings_load()
	settings_apply_all(game.settings)

	font_configs := load_lang_font_configs(allocator = context.allocator)
	defer unload_lang_font_configs(font_configs, allocator = context.allocator)
	
	ui_init(&game.ui, font_configs, proc() -> f32 {
		return game.time.scaled_time
	})

	mouse_init(&game.mouse_ui)
	mouse_init(&game.mouse_3d)
	
	game.scene = GAME_STARTUP_SCENE
	ctx := game_context_make(&game, &game.mouse_ui)
	game.scene_callbacks = scene_boot(&game.scene, ctx)
}

game_update :: proc(unscaled_dt : f32) {
	frame_time_raw_update(&game.frame_time, unscaled_dt)
	
	dt : f32 = game_time_raw_update(&game.time, unscaled_dt)

	ctx_ui := game_context_make(&game, &game.mouse_ui)
	ui_begin(&game.ui, &game.viewport, ctx_ui.mouse, game.settings.language)
	{
		if game.scene_callbacks.update_ui != nil {
			game.scene_callbacks.update_ui(&game.scene, ctx_ui)
		}
		// cursor drawed on top
		ui_push_cursor(&game.ui,
			position = game.mouse_ui.position,
			tint     = hsv(0, 0, 1)
		)
		ui_end(&game.ui, &game.viewport)
	}

	if ui_is_capturing_input(&game.ui) {
		mouse_interrupt(&game.mouse_3d)
	}

	ctx_3d := game_context_make(&game, &game.mouse_3d)
	if game.scene_callbacks.update_3d != nil {
		game.scene_callbacks.update_3d(&game.scene, ctx_3d, dt)
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
				game.scene_callbacks.draw_3d(&game.scene, ctx_3d, &game.renderer)
			}
		}
		ui_draw(&game.ui, &game.viewport)
	}

	mouse_input_frame_end(&game.mouse_ui)
	mouse_input_frame_end(&game.mouse_3d)
	
	free_all(context.temp_allocator)

	// Scene switching
	if game.pending_scene != nil {
		scene_shutdown(&game.scene, ctx_ui)

		game.scene = game.pending_scene.?
		game.pending_scene = nil
		
		// Reset clear color
		viewport_set_clear_color(&game.viewport, VIEWPORT_DEFAULT_CLEAR_COLOR)

		game.scene_callbacks = scene_boot(&game.scene, ctx_ui)
		game_time_reset_time_scale(&game.time)
	}
}

game_input :: proc(ev : ^sapp.Event) {
	mouse_input(&game.mouse_ui, &game.viewport, ev^)
	ui_input(&game.ui, ev^)
	
	ctx_ui := game_context_make(&game, &game.mouse_ui)
	if game.scene_callbacks.input_ui != nil {
		game.scene_callbacks.input_ui(&game.scene, ctx_ui, ev^)
	}

	if !ui_is_capturing_input(&game.ui) {
		mouse_input(&game.mouse_3d, &game.viewport, ev^)
		if game.scene_callbacks.input_3d != nil {
			ctx_3d := game_context_make(&game, &game.mouse_3d)
			game.scene_callbacks.input_3d(&game.scene, ctx_3d, ev^)
		}
	} else {
		if ev.type == .MOUSE_MOVE {
			mouse_sync_position(&game.mouse_3d, &game.mouse_ui)
		}
	}
}

// You should put newly created scene in here, e.g Scene_Gameplay{}, Scene_Main_Menu{}
// In case scene needs extra initial data you can add some data such as Scene_Gameplay{level = 1} for example   
game_request_switch_scene :: proc(#by_ptr uninitialized_scene : Scene){
	game.pending_scene = uninitialized_scene
}

game_destroy :: proc() {
	ctx := game_context_make(&game, &game.mouse_ui)
	scene_shutdown(&game.scene, ctx)

	ui_destroy(&game.ui)
	audio_destroy(&game.audio)
	renderer_destroy(&game.renderer)
	camera_destroy(&game.camera)
	viewport_destroy(&game.viewport)
}

// Localization function, basically doing term translation look up
tr :: proc(term: Loc_Term, params : ..any, allocator := context.temp_allocator) -> string {
	if len(params) > 0 {
		return fmt.aprintf(loc_map[game.settings.language][term], params)
	}
	return loc_map[game.settings.language][term]
}

// Accessing modules/module data

game_audio :: proc() -> ^Audio {
	return &game.audio
}

// Utilities
game_lang_is_cjk :: proc() -> bool {
	#partial switch game.settings.language {
		case .Japanese, .Simplified_Chinese:
			return true
		case:
			return false
	}
}

game_switch_lang :: proc(lang : Language) {
	game.settings.language = lang
}

game_request_quit :: proc() {
	sapp.request_quit()
}

game_set_gamma :: proc(gamma : f32) {
	viewport_set_gamma(&game.viewport, gamma)
}

game_set_fullscreen :: proc(fullscreen : bool) {
	if sapp.is_fullscreen() == fullscreen {
		return
	} else {
		sapp.toggle_fullscreen()
	}
}

game_request_size :: proc(size : [2]f32) {
	viewport_request_size(&game.viewport, size)
}

game_save_settings :: proc() {
	settings_save(game.settings)
}

game_set_mouse_sensitivity :: proc(sensitivity: [2]f32) {
	mouse_set_sensivity(&game.mouse_ui, sensitivity)
	mouse_set_sensivity(&game.mouse_3d, sensitivity)
}

game_set_mouse_invert_y :: proc(invert_y : bool) {
	mouse_set_invert_y(&game.mouse_ui, invert_y)
	mouse_set_invert_y(&game.mouse_3d, invert_y)
}