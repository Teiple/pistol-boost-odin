package main

import "core:slice"
import "core:math"
import sapp "sokol-odin/sokol/app"


Platform :: struct{
    size     : [3]f32,
    position : [3]f32,
}

Scene_Editor :: struct {
    platforms              : [dynamic]Platform,
    debug_draw             : Debug_Draw, 
    free_cam               : Free_Camera,
    selected_platform      : int,
    next_selected_platform : int,
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

        ctx.camera.position = {0, 2, 10}

        scene.platforms = slice.clone_to_dynamic([]Platform {
            {size = {12.0, 0.4, 2.0}, position = {0,   -1.0, 0}},
            {size = {0.4,  8.0, 2.0}, position = {-6.0, 3.0, 0}},
            {size = {0.4,  8.0, 2.0}, position = {6.0,  3.0, 0}},
            {size = {12.0, 0.4, 2.0}, position = {0,    7.0, 0}},
            {size = {3.0,  0.3, 2.0}, position = {-2.5, 1.5, 0}},
            {size = {3.0,  0.3, 2.0}, position = {2.5,  3.5, 0}},
        })

        scene.selected_platform      = -1
        scene.next_selected_platform = -1
    },
    destroy = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        debug_draw_destroy(&scene.debug_draw)
    },
    update_3d = proc(scene : ^Scene_Editor, ctx : Game_Context, dt : f32) {
        debug_draw_begin(&scene.debug_draw)
        
        clicked := ui_get_mouse_button_state(ctx.ui) == .Pressed
        
        ray_origin, ray_direction : [3]f32
        if clicked {
            ray_origin, ray_direction = viewport_get_mouse_world_ray(
                ctx.viewport,
                ctx.camera,
                ctx.mouse.position
            )
        }

        min_select_dist := math.INF_F32
        for p,i in scene.platforms {
            if clicked {
                if dist, hit := check_ray_box(
                    ray_origin,
                    ray_direction,
                    p.position,
                    p.size * .5
                ); hit && dist < min_select_dist {
                    scene.next_selected_platform = i
                    min_select_dist              = dist
                }
            }

            debug_draw_wire_box(
                &scene.debug_draw,
                position  = p.position,
                half_size = p.size * .5,
                color     = i == scene.selected_platform ? hsv(54, .4, .4) : hsv(200, .4, .4),
            )
            debug_draw_box(
                &scene.debug_draw,
                position  = p.position,
                half_size = p.size * .5,
                color     = i == scene.selected_platform ? hsv(54) : hsv(200),
            )
        }

        free_camera_update_3d(&scene.free_cam, ctx.camera, ctx.mouse, dt)
    },
    draw_3d = proc(scene : ^Scene_Editor, ctx : Game_Context, renderer : ^Renderer) {
        debug_draw_3d(&scene.debug_draw, renderer)
    },
    update_ui = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        defer if scene.next_selected_platform >= 0 {
            scene.selected_platform      = scene.next_selected_platform
            scene.next_selected_platform = -1
        }
        
        if scene.selected_platform < 0 {
            return
        }
       
        ui := ctx.ui
        
        inspector_rect, _, _ := ui_push_rect(
            ui,
            sizing = { 300, Grow{}},
            anchor = { element = {1, 0}, parent = {1, 0} },
            color  = hsv(0, 0, 0.25),
        )

        inspector_padding    :: 8
        inspector_rect_width := inspector_rect.z - inspector_padding * 2

        ui_push_container(ui, inspector_rect)
        {
            defer ui_pop_container(ui)

            field_anchor : Anchor = { offset = {inspector_padding, inspector_padding} }

            field_anchor.offset.y += editor_scene_field_vector3(
                ui,
                label     = "Position",
                id        = "position",
                field_ids = {
                    {"position:x", "position:x:up", "position:x:down"},
                    {"position:y", "position:y:up", "position:y:down"},
                    {"position:z", "position:z:up", "position:z:down"},
                },
                vec3      = &scene.platforms[scene.selected_platform].position,
                width     = inspector_rect_width,
                anchor    = field_anchor,
            )

            field_anchor.offset.y += 16

            field_anchor.offset.y += editor_scene_field_vector3(
                ui,
                label     = "Size",
                id        = "size",
                field_ids = {
                    {"size:x", "size:x:up", "size:x:down"},
                    {"size:y", "size:y:up", "size:y:down"},
                    {"size:z", "size:z:up", "size:z:down"},
                },
                vec3      = &scene.platforms[scene.selected_platform].size,
                width     = inspector_rect_width,
                anchor    = field_anchor,
            )
        }
    },
    input_ui =  proc(scene : ^Scene_Editor, ctx : Game_Context, ev : sapp.Event) {
        ui := ctx.ui
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
check_ray_box :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    box_position  : [3]f32,
    box_half_size : [3]f32,
) -> (distance : f32, hit: bool) {
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
    // if t_start < 0 the ray entered from behind the ray_origin, we shouldn't include it as a hit 
    return t_start, t_end > t_start && t_start > 0
}

editor_scene_field_vector3 :: proc(
    ui             : ^Ui,
    vec3           : ^[3]f32,
    id             : Ui_Id,
    field_ids      : [3][3]Ui_Id,
    label          : string,
    width          : f32,
    anchor         : Anchor,
) -> (height: f32) {
    field_width  : [3]f32 = {32, width - 52, 20}
    field_height :: 42
    field_gap    :: 8

    anchor := anchor

    header_rect := ui_push_text(
        ui,
        text   = label,
        anchor = anchor,
    )

    anchor.offset.y += header_rect.w + field_gap

    // These are the wrong usage of swizzling, but it's fun, who cares
    if new, changed := ui_push_spinner(
        ui,
        id          = field_ids.x.x,
        control_ids = field_ids.x.yz,
        label       = "X", 
        value       = vec3.x,
        step        = .01,
        label_color = hsv(332),
        height      = field_height,
        width       = field_width,
        anchor      = anchor,
    ); changed do vec3.x = new

    anchor.offset.y += field_height + field_gap

    if new, changed := ui_push_spinner(
        ui,
        id          = field_ids.y.x,
        control_ids = field_ids.y.xy,
        label       = "Y", 
        value       = vec3.y,
        step        = .01,
        label_color = hsv(100),
        height      = field_height,
        width       = field_width,
        anchor      = anchor,
    ); changed do vec3.y = new

    anchor.offset.y += field_height + field_gap

    if new, changed := ui_push_spinner(
        ui,
        id          = field_ids.z.x,
        control_ids = field_ids.z.yz,
        label       = "Z", 
        step        = .01,
        value       = vec3.z,
        label_color = hsv(200),
        width       = field_width,
        height      = field_height,
        anchor      = anchor,
    ); changed do vec3.z = new

    return header_rect.w + 3 * field_gap + 3 * field_height
}