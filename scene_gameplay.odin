package main

import "core:math/linalg"
Scene_Gameplay :: struct {
    meshes : [dynamic]Mesh
}

SCENE_GAMEPLAY_CALLBACKS : Scene_Callbacks : {
	init = proc(s : ^Scene) {
        s := &s.(Scene_Gameplay)
        
        s.meshes = make([dynamic]Mesh)
        append(&s.meshes, mesh_create_box({2, 1, 1}))
    },
    draw_3d = proc(s : ^Scene) {
        s := &s.(Scene_Gameplay)

        ren, cam, vp := &game.renderer, &game.camera, &game.viewport
        for &m in s.meshes {
            renderer_draw_mesh(ren, cam, vp, &m, 
                {}, linalg.quaternion_from_pitch_yaw_roll(
                    game.frame_time.time,
                    game.frame_time.time * .25,
                    game.frame_time.time * .5,
                )
            )
        }
    },
    destroy = proc(s : ^Scene) {
        s := &s.(Scene_Gameplay)

        for &m in s.meshes {
            mesh_destroy(&m)
        }

        delete(s.meshes)
    }
}