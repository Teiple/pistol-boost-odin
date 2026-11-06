package main

import "core:strings"
import "core:math"
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
            look_speed = .001,
            yaw        = math.PI,
        }

        game_camera().position = {0, 0, 3}
    },
    destroy = proc(scene : ^Scene_Editor) {
        debug_draw_destroy(&scene.debug_draw)
    },
    update_3d = proc(scene : ^Scene_Editor, dt : f32) {
        debug_draw_begin(&scene.debug_draw)
        
        ray_origin, ray_direction := viewport_get_mouse_world_ray(
            game_viewport(),
            game_camera(),
            game_mouse().position
        )

        for p in scene.platforms {
            debug_draw_wire_box(
                &scene.debug_draw,
                position  = p.position,
                half_size = p.size * .5,
                color     = hsv(200, 0.4, 0.4),
            )
            debug_draw_box(
                &scene.debug_draw,
                position  = p.position,
                half_size = p.size * .5,
                color     = hsv(200),
            )
            // draggable box to resize the platform
            {
                box : type_of(p) = {
                    position = p.position + {1, 0, 0} * p.size * .5,
                    size     = .1
                }

                debug_draw_wire_box(
                    &scene.debug_draw,
                    position  = box.position,
                    half_size = box.size * .5,
                    color     = hsv(200, .4, .4),
                )
            }
        }

        free_camera_update_3d(&scene.free_cam, game_camera(), game_mouse(), dt)
    },
    draw_3d = proc(scene : ^Scene_Editor, renderer : ^Renderer) {
        debug_draw_3d(&scene.debug_draw, renderer)
    },
    update_ui = proc(scene : ^Scene_Editor, ui : ^Ui) {
        text := strings.to_string(ui.text_edit.builder)

        ui_push_text_edit(
            ui,
            text      = text,
            id        = "test_edit_box",
            font_id   = .Normal,
            font_size =  32,
            sizing    = {200, 48},
            anchor    = { parent = {.5, .5}, element = {.5, .5} }
        )

        ui_push_text_edit(
            ui,
            text      = text,
            id        = "test_edit_box",
            font_id   = .Normal,
            font_size =  32,
            sizing    = {200, 48},
            anchor    = { parent = {.5, .5}, element = {.5, .5}, offset = {0, 52} }
        )
    },
    input_ui =  proc(scene : ^Scene_Editor, ui : ^Ui, ev : sapp.Event) {
        ui_capture_input(ui)
        if ev.type == .KEY_DOWN && ev.key_code == .ESCAPE {
            game_request_quit()
            return
        }
        
        ui_text_edit_input(ui, ev)
    }, 
    input_3d = proc(scene : ^Scene_Editor, ev : sapp.Event) {
        free_camera_input(&scene.free_cam, game_camera(), ev)
    },

}


// Checking if the ray will collide with an axis-aligned box
check_intersection_between_ray_and_box :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    box_position  : [3]f32,
    box_half_size : [3]f32,
) -> bool {
    min_x := box_position.x - box_half_size.x
    max_x := box_position.x + box_half_size.x

    min_y := box_position.y - box_half_size.y
    max_y := box_position.y + box_half_size.y

    min_z := box_position.z - box_half_size.z
    max_z := box_position.z + box_half_size.z

    tx1 := (min_x - ray_origin.x) / ray_direction.x
    tx2 := (max_x - ray_origin.x) / ray_direction.x

    ty1 := (min_y - ray_origin.y) / ray_direction.y
    ty2 := (max_y - ray_origin.y) / ray_direction.y

    tz1 := (min_z - ray_origin.z) / ray_direction.z
    tz2 := (max_z - ray_origin.z) / ray_direction.z

    t_start := max(min(tx1, tx2), min(ty1, ty2), min(tz1, tz2))
    t_end   := min(max(tx1, tx2), max(ty1, ty2), max(tz1, tz2))
    
    // Miss if exited one slab before entering any of the others
    // if t_end < 0 the ray exited from behind the ray_origin, we shouldn't include it as a hit 
    return t_end > t_start && t_end > 0
}