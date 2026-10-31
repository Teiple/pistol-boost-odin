package main

import "core:fmt"
import sapp "sokol-odin/sokol/app"
import b3 "vendor:box3d"

Scene_Init :: struct {
    selected_level : int,
}

Scene_Gameplay :: struct {
    meshes        : [dynamic]Mesh,
    physics       : Physics,
    follow_camera : Follow_Camera,
    init          : Scene_Init,
    menu_stack    : Menu_Stack,
    test_model    : Model,
    player        : Player,
    environment   : Environment,
}

SCENE_GAMEPLAY_CALLBACKS : Scene_Callbacks(^Scene_Gameplay) : {
	init = proc(scene : ^Scene_Gameplay) {
        scene.meshes = make([dynamic]Mesh)
        append(&scene.meshes, mesh_create_box({2, 1, 1}))
    
        menu_stack_init(&scene.menu_stack)
        model_init_from_gltf(&scene.test_model, #load("assets/models/pistol.glb"))
        
        physics_init(&scene.physics)
        player_init(&scene.player, &scene.physics, {0, 0, 0})
        follow_camera_init(&scene.follow_camera)

        viewport_set_clear_color(game_viewport(), hsv(140, 0.4, 0.2))

        environment_init(&scene.environment, &scene.physics)
    },
    destroy = proc(scene : ^Scene_Gameplay) {
        environment_destroy(&scene.environment)
        
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
        physics_update_3d(
            &scene.physics,dt
        )
        
        player_update_3d(
            &scene.player,
            {
                camera   = game_camera(),
                viewport = game_viewport(),
                mouse    = game_mouse(),
                audio    = game_audio(),
            },
            dt
        )

        follow_camera_update_3d(
            follow_cam    = &scene.follow_camera,
            camera        = game_camera(),
            target_pos    = player_get_interpolated_position(
                &scene.player,
                &scene.physics,
            ),
            dt = dt,
        )
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
        environment_draw(&scene.environment, renderer)
        player_draw_3d(&scene.player, &scene.physics, renderer)
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