package main

import "core:math/linalg"
import sapp "sokol-odin/sokol/app"

Scene_Gameplay :: struct {
    meshes    : [dynamic]Mesh,
}

SCENE_GAMEPLAY_CALLBACKS : Scene_Callbacks(^Scene_Gameplay) : {
	init = proc(scene : ^Scene_Gameplay) {
        
        scene.meshes = make([dynamic]Mesh)
        append(&scene.meshes, mesh_create_box({2, 1, 1}))
    
    },
    draw_3d = proc(scene : ^Scene_Gameplay) {
    
        ren, cam, vp := &game.renderer, &game.camera, &game.viewport
    
        for &m in scene.meshes {
            renderer_draw_mesh(ren, cam, vp, &m, 
                {}, linalg.quaternion_from_pitch_yaw_roll(
                    game.frame_time.time,
                    game.frame_time.time * .25,
                    game.frame_time.time * .5,
                )
            )
        }
    
    },
    input_ui = proc(scene : ^Scene_Gameplay, ev : sapp.Event) {
        if ev.type == .KEY_DOWN && ev.key_code == .ENTER {
            game_request_switch_scene(Scene_Main_Menu{})
        }
    },
    destroy = proc(scene : ^Scene_Gameplay) {
    
        for &m in scene.meshes {
            mesh_destroy(&m)
        }

        delete(scene.meshes)
    }
}