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
    menu_stack : Menu_Stack,    
}

SCENE_GAMEPLAY_CALLBACKS : Scene_Callbacks(^Scene_Gameplay) : {
	init = proc(scene : ^Scene_Gameplay) {
        scene.meshes = make([dynamic]Mesh)
        append(&scene.meshes, mesh_create_box({2, 1, 1}))
    
        menu_stack_init(&scene.menu_stack)
    },
    destroy = proc(scene : ^Scene_Gameplay) {
        menu_stack_destroy(&scene.menu_stack)
        
        for &m in scene.meshes {
            mesh_destroy(&m)
        }
        delete(scene.meshes)
    },
    update_ui = proc(scene : ^Scene_Gameplay, ui : ^Ui) {
        ui_push_text(
            ui,
            font_id = .Normal, 
            text    = tr(.Not_Defined), 
        )

        menu_stack_update_ui(&scene.menu_stack, ui)
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
        if menu_stack_top(&scene.menu_stack) != nil {
            menu_stack_input_ui(&scene.menu_stack, ui, ev)
            return
        } else if ev.type == .KEY_DOWN && ev.key_code == .ESCAPE {
            menu_stack_push_menu(&scene.menu_stack, Pause_Menu{})
        }
    }
}