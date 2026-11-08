package main

import "core:slice"
import "core:math"
import sapp "sokol-odin/sokol/app"


Platform :: struct{
    size     : [3]f32,
    position : [3]f32,
}

Scene_Editor :: struct {
    platforms  : [dynamic]Platform,
    debug_draw : Debug_Draw, 
    free_cam   : Free_Camera, 
}

SCENE_DEBUG_CALLBACKS : Scene_Callbacks(^Scene_Editor) : {
    init = proc(scene : ^Scene_Editor, ctx : Game_Context) {        
        debug_draw_init(&scene.debug_draw)
        
        scene.free_cam = {
            enabled    = true,
            move_speed = 3,
            look_speed = .01,
            yaw        = math.PI,
        }

        ctx.camera.position = {0, 0, 3}

        scene.platforms = slice.clone_to_dynamic([]Platform {
            {size = {12.0, 0.4, 2.0}, position = {0,   -1.0, 0}},
            {size = {0.4,  8.0, 2.0}, position = {-6.0, 3.0, 0}},
            {size = {0.4,  8.0, 2.0}, position = {6.0,  3.0, 0}},
            {size = {12.0, 0.4, 2.0}, position = {0,    7.0, 0}},
            {size = {3.0,  0.3, 2.0}, position = {-2.5, 1.5, 0}},
            {size = {3.0,  0.3, 2.0}, position = {2.5,  3.5, 0}},
        })
    },
    destroy = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        debug_draw_destroy(&scene.debug_draw)
    },
    update_3d = proc(scene : ^Scene_Editor, ctx : Game_Context, dt : f32) {
        debug_draw_begin(&scene.debug_draw)
        
        ray_origin, ray_direction := viewport_get_mouse_world_ray(
            ctx.viewport,
            ctx.camera,
            ctx.mouse.position
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
        }

        if !ui_is_capturing_input(ctx.ui) {
            free_camera_update_3d(&scene.free_cam, ctx.camera, ctx.mouse, dt)
        }
    },
    draw_3d = proc(scene : ^Scene_Editor, ctx : Game_Context, renderer : ^Renderer) {
        debug_draw_3d(&scene.debug_draw, renderer)
    },
    update_ui = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        ui := ctx.ui
        field_height :: 42
        field_gap    :: 8

        field_anchor : Anchor = {
            parent  = {.5, .5},
            element = {.5, .5}
        }

        x, y, z := expand_values(scene.platforms[0].size)

        if new, changed := ui_push_spinner(
            ui,
            id          = "spinner_1",
            label       = "X", 
            value       = x,
            label_color = hsv(332),
            height      = field_height,
            width       = { 50, 80 },
            anchor      = field_anchor,
        ); changed do x = new

        field_anchor.offset.y += field_height + field_gap

        if new, changed := ui_push_spinner(
            ui,
            id          = "spinner_2",
            label       = "Y", 
            value       = y,
            label_color = hsv(100),
            height      = field_height,
            width       = { 50, 80 },
            anchor      = field_anchor,
        ); changed do y  = new

        field_anchor.offset.y += field_height + field_gap

        if new, changed := ui_push_spinner(
            ui,
            id          = "spinner_3",
            label       = "Z", 
            value       = z,
            label_color = hsv(200),
            width       = { 50, 80 },
            height      = field_height,
            anchor      = { parent = {.5, .5}, element = {.5, .5}, offset = {0, 100} },
        ); changed do y  = new

        field_anchor.offset.y += field_height + field_gap

        scene.platforms[0].size = {x, y, z}
    },
    input_ui =  proc(scene : ^Scene_Editor, ctx : Game_Context, ev : sapp.Event) {
        ui := ctx.ui
        ui_capture_input(ui)
        if ev.type == .KEY_DOWN && ev.key_code == .ESCAPE {
            game_request_quit()
            return
        }
        
        ui_text_edit_input(ui, ev)
    }, 
    input_3d = proc(scene : ^Scene_Editor, ctx : Game_Context, ev : sapp.Event) {
        free_camera_input(&scene.free_cam, ctx.camera, ev)
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