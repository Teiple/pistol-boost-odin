package main

import sapp "sokol-odin/sokol/app"

Platform :: struct{
    size     : [3]f32,
    position : [3]f32
}

Scene_Editor :: struct {
    platforms  : [dynamic]Platform,
    debug_draw : Debug_Draw, 
    free_cam   : Free_Camera, 
}

SCENE_DEBUG_CALLBACKS : Scene_Callbacks(^Scene_Editor) : {
    init = proc(scene : ^Scene_Editor) {
        scene.platforms = make([dynamic]Platform)
        
        debug_draw_init(&scene.debug_draw)
        append(&scene.platforms, {
            size = { 2, 1, 1},
        })

        scene.free_cam = {
            enabled    = true,
            move_speed = 3,
            look_speed = 10,
        }

        game_camera().position = {0, 0, -3}
    },
    destroy = proc(scene : ^Scene_Editor) {
        debug_draw_destroy(&scene.debug_draw)
    },
    update_3d = proc(scene : ^Scene_Editor, dt : f32) {
        debug_draw_begin(&scene.debug_draw)
        for p in scene.platforms {
            debug_draw_box(&scene.debug_draw, p.size * .5, hsv(200))
        }
        free_camera_update_3d(&scene.free_cam, game_camera(), dt)
    },
    draw_3d = proc(scene : ^Scene_Editor, renderer : ^Renderer) {
        debug_draw_3d(&scene.debug_draw, renderer)
    },
    input_3d = proc(scene : ^Scene_Editor, ev : sapp.Event) {
        if ev.type == .KEY_DOWN && ev.key_code == .ESCAPE {
            game_request_quit()
            return
        }

        free_camera_input(&scene.free_cam, game_camera(), ev)
    }
}