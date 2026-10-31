package main

import "core:math"
import "core:fmt"
import "core:math/linalg"
import sapp "sokol-odin/sokol/app"

Scene_Init :: struct {
    selected_level : int,
}

Scene_Gameplay :: struct {
    meshes     : [dynamic]Mesh,
    physics    : Physics,
    init       : Scene_Init,
    menu_stack : Menu_Stack,
    test_model : Model,
    player     : Player,
}

SCENE_GAMEPLAY_CALLBACKS : Scene_Callbacks(^Scene_Gameplay) : {
	init = proc(scene : ^Scene_Gameplay) {
        scene.meshes = make([dynamic]Mesh)
        append(&scene.meshes, mesh_create_box({2, 1, 1}))
    
        menu_stack_init(&scene.menu_stack)
        model_init_from_gltf(&scene.test_model, #load("assets/models/pistol.glb"))
        
        physics_init(&scene.physics)
        player_init(&scene.player, scene.physics.world, {0, 0, 0})
    },
    destroy = proc(scene : ^Scene_Gameplay) {
        player_destroy(&scene.player)
        physics_destroy(&scene.physics)

        model_destroy(&scene.test_model)
        menu_stack_destroy(&scene.menu_stack)
        
        for &m in scene.meshes {
            mesh_destroy(&m)
        }
        delete(scene.meshes)
    },
    update_3d = proc(scene : ^Scene_Gameplay, dt : f32) {
        player_update_3d(
            &scene.player,
            game_camera(),
            game_viewport(),
            game_mouse(),
            game_audio(),
            dt
        )

        physics_update_3d(&scene.physics, dt)
    },
    update_ui = proc(scene : ^Scene_Gameplay, ui : ^Ui) {
        ui_push_text(
            ui,
            font_id = .Normal, 
            text    = tr(.Undefined), 
        )

        menu_stack_update_ui(&scene.menu_stack, ui)
    },
    draw_3d = proc(scene : ^Scene_Gameplay, renderer : ^Renderer) {
        player_draw_3d(&scene.player, renderer)
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