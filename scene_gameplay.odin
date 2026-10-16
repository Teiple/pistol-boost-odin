package main

import "core:fmt"
import "core:math/linalg"
import sapp "sokol-odin/sokol/app"

Scene_Init :: struct {
    selected_level : int,
}

Scene_Gameplay :: struct {
    init       : Scene_Init,  
    meshes     : [dynamic]Mesh,
    pause_menu : Pause_Menu, 
}

SCENE_GAMEPLAY_CALLBACKS : Scene_Callbacks(^Scene_Gameplay) : {
	init = proc(scene : ^Scene_Gameplay) {
        scene.meshes = make([dynamic]Mesh)
        append(&scene.meshes, mesh_create_box({2, 1, 1}))
    
        pause_menu_init(&scene.pause_menu)
    },
    destroy = proc(scene : ^Scene_Gameplay) {
        pause_menu_destroy(&scene.pause_menu)
        
        for &m in scene.meshes {
            mesh_destroy(&m)
        }
        delete(scene.meshes)
    },
    update_ui = proc(scene : ^Scene_Gameplay, ui : ^Ui) {
        ui_push_text(
            ui,
            font_id = .Mono, 
            text    = fmt.tprintf("You are at level %d", scene.init.selected_level), 
        )

        pause_menu_begin(&scene.pause_menu)
        {
            defer pause_menu_end(&scene.pause_menu)
            
            pause_menu_update_ui(&scene.pause_menu, ui)
        }
    },
    draw_3d = proc(scene : ^Scene_Gameplay, renderer : ^Renderer) {
        for &m in scene.meshes {
            renderer_draw_mesh(renderer, &m, 
                {}, linalg.quaternion_from_pitch_yaw_roll(
                    game_time().scaled_time,
                    game_time().scaled_time * .25,
                    game_time().scaled_time * .5,
                )
            )
        }
    },
    input_ui = proc(scene : ^Scene_Gameplay, ui: ^Ui, ev : sapp.Event) {
        if !scene.pause_menu.show {
            if ev.type == .KEY_DOWN && ev.key_code == .ESCAPE {
                pause_menu_open(&scene.pause_menu)
            }
        } else {
            pause_menu_input(&scene.pause_menu, ui, ev)
        }
    }
}