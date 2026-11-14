package main

import "core:math"
import sapp "sokol-odin/sokol/app"

Platform_Box :: struct{
    origin : [3]f32,
    size   : [3]f32,
}

Platform_Slope :: struct {
    origin       : [3]f32,
    size         : [3]f32,
    corner : Slope_Corner,
}

Platform :: union {
    Platform_Box,
    Platform_Slope,
}

Slope_Corner :: enum u8 {
    Bottom_Left,
    Bottom_Right,
    Top_Left,
    Top_Right,
}

Editor_Runtime :: struct {
    platforms : [dynamic]Platform,
}

Scene_Editor :: struct {
    debug_draw        : Debug_Draw, 
    free_cam          : Free_Camera,
    selected_platform : Maybe(int),
    pending_selected  : Pending_Action(int),
    runtime           : Editor_Runtime,
}

SCENE_DEBUG_CALLBACKS : Scene_Callbacks(^Scene_Editor) : {
    init = proc(scene : ^Scene_Editor, ctx : Game_Context) {        
        debug_draw_init(&scene.debug_draw)
        
        scene.free_cam = {
            move_speed = 8,
            look_speed = .01,
            yaw        = math.PI,
        }
        ctx.camera.position = {0, 2, 10}

        append(&scene.runtime.platforms,
            Platform_Box{
                origin = {0,0,0},
                size   = {2,1,1}    
            },
            Platform_Slope{
                origin = {0,2,0},
                size   = {2,1,1},
                corner = .Bottom_Left,
            },

        )
    },
    destroy = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        debug_draw_destroy(&scene.debug_draw)        
        delete(scene.runtime.platforms)
    },
    update_ui = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        ui := ctx.ui

        ui_rects : [dynamic; 4][4]f32

        // View mode selection
        view_mode_rect, _ := ui_push_rect(
            ui     = ui,
            sizing = {220, 50},
            anchor = { element = {0, 1}, parent = {0, 1} } 
        )
        append(&ui_rects, view_mode_rect)
        
        ui_push_container(ui, view_mode_rect)
        {
            defer ui_pop_container(ui)

            if new_value, changed := ui_push_combo_box(
                ui      = ui,
                id      = "view_mode",
                width   = {170, 50},
                height  = 50,
                anchor  = { element = {0, 1}, parent = {0, 1} },         
                options = [enum { Perspective, Orthorgonal }]string {
                    .Perspective = "Perspective",
                    .Orthorgonal = "Orthorgonal"
                },
                value   = scene.free_cam.mode_orthorgonal ? .Orthorgonal : .Perspective,
            ); changed do scene.free_cam.mode_orthorgonal = new_value == .Orthorgonal
        }

        // Inspector
        if scene.selected_platform != nil {
            inspector_rect, _ := ui_push_rect(
                ui     = ui,
                sizing = { 300, Percent{1}},
                anchor = { element = {1, 0}, parent = {1, 0} },
                color  = hsv(0, 0, .25),
            )
            append(&ui_rects, inspector_rect)

            inspector_padding    :: 8
            inspector_width := inspector_rect.z - inspector_padding * 2

            ui_push_container(ui, inspector_rect)
            {
                defer ui_pop_container(ui)

                prop_gap    :: 16
                prop_anchor : Anchor = { offset = {inspector_padding, inspector_padding} }

                origin, size : ^[3]f32
                platform := &scene.runtime.platforms[scene.selected_platform.?]
                switch &p in platform {
                    case Platform_Box: {
                        origin = &p.origin; size = &p.size
                    }
                    case Platform_Slope: {
                        origin = &p.origin; size = &p.size
                    }
                }

                prop_anchor.offset.y += editor_property_vector3(
                    ui,
                    label     = "Origin",
                    id        = "origin",
                    axis_ids  = {
                        { text_edit = "origin:x", up_control = "origin:x:up", down_control = "origin:x:down"},
                        { text_edit = "origin:y", up_control = "origin:y:up", down_control = "origin:y:down"},
                        { text_edit = "origin:z", up_control = "origin:z:up", down_control = "origin:z:down"},
                    },
                    value     = origin,
                    width     = inspector_width,
                    anchor    = prop_anchor,
                )
                prop_anchor.offset.y += prop_gap

                prop_anchor.offset.y += editor_property_vector3(
                    ui,
                    label     = "Size",
                    id        = "size",
                    axis_ids  = {
                        { text_edit = "size:x", up_control = "size:x:up", down_control = "size:x:down"},
                        { text_edit = "size:y", up_control = "size:y:up", down_control = "size:y:down"},
                        { text_edit = "size:z", up_control = "size:z:up", down_control = "size:z:down"},
                    },
                    value     = size,
                    width     = inspector_width,
                    anchor    = prop_anchor,
                )
                prop_anchor.offset.y += prop_gap

                if p, ok := &platform.(Platform_Slope); ok {
                    editor_property_slope_corner(
                        ui     = ui,
                        value  = &p.corner,
                        width  = inspector_width,
                        id     = "slope_corner",
                        label  = "Slope Corner",
                        anchor = prop_anchor,
                    )
                }
            }
        }

        // Platform selection
        if  ui_get_mouse_button_state(ctx.ui) == .Pressed {
            mouse_on_ui := false 
            for &rect in ui_rects do if ui_mouse_is_inside_rect(ui, rect) {
                mouse_on_ui = true; break;
            }
            if !mouse_on_ui {
                ray_origin, ray_direction := viewport_get_mouse_world_ray(
                    ctx.viewport,
                    ctx.camera,
                    ctx.mouse.position
                )

                min_select_dist := math.INF_F32
                closest_index   := -1
                
                for platform, i in scene.runtime.platforms {
                    switch p in platform {
                        case Platform_Box:
                            if dist, hit := check_ray_box(
                                ray_origin    = ray_origin,
                                ray_direction = ray_direction,
                                box           = p,
                            ); hit && dist < min_select_dist {
                                min_select_dist = dist
                                closest_index   = i
                            }
                        case Platform_Slope:
                            if dist, hit := check_ray_slope(
                                ray_origin    = ray_origin,
                                ray_direction = ray_direction,
                                slope         = p,
                            ); hit && dist < min_select_dist {
                                min_select_dist = dist
                                closest_index   = i
                            }
                    }
                }

                if closest_index == -1 {
                    pending_action_clear(&scene.pending_selected)
                } else {            
                    pending_action_set(
                        &scene.pending_selected,
                        &scene.selected_platform,
                        closest_index
                    )
                }
            }

            // Handle new selection at end of frame
            pending_resolve(&scene.pending_selected, &scene.selected_platform)
        }
    },
    update_3d = proc(scene : ^Scene_Editor, ctx : Game_Context, dt : f32) {
        debug_draw_begin(&scene.debug_draw)

        debug_draw_push_grid(
            draw       = &scene.debug_draw,
            unit       = 1,
            size       = 30,
            axis_color = hsv(0, 0, .6), 
            sub_color  = hsv(0, 0, .3), 
        )

        for platform, i in scene.runtime.platforms {
            selected := i == scene.selected_platform
            switch p in platform {
                case Platform_Box:
                    debug_draw_push_platform_box(
                        draw         = &scene.debug_draw,
                        box          = p,
                        color        = selected ? hsv(54, 1, 1) : hsv(200, 1, 1),
                        bounding_box = selected,
                        origin       = selected,
                    )
                    debug_push_wire_platform_box(
                        draw  = &scene.debug_draw,
                        box   = p,
                        color = i == scene.selected_platform ? hsv(54, .4, .4) : hsv(200, .4, .4),
                    )
                case Platform_Slope:
                    debug_draw_push_platform_slope(
                        draw         = &scene.debug_draw,
                        slope        = p,
                        color        = selected ? hsv(54, 1, 1) : hsv(200, 1, 1),
                        bounding_box = selected,
                        origin       = selected,
                    )
                    debug_push_wire_platform_slope(
                        draw  = &scene.debug_draw,
                        slope = p,
                        color = selected ? hsv(54, .4, .4) : hsv(200, .4, .4),
                    )
            }

        }

        free_camera_update_3d(&scene.free_cam, ctx, dt)
    },
    draw_3d = proc(scene : ^Scene_Editor, ctx : Game_Context, renderer : ^Renderer) {
        debug_draw_3d(&scene.debug_draw, renderer)
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
    box           : Platform_Box,
) -> (distance : f32, hit: bool) {
    box_position  := box.origin + box.size * .5
    box_half_size := box.size * .5

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

// don't ask me, ask antigravity
check_ray_slope :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    slope         : Platform_Slope,
) -> (distance : f32, hit: bool) {
    min_x := slope.origin.x
    max_x := slope.origin.x + slope.size.x

    min_y := slope.origin.y
    max_y := slope.origin.y + slope.size.y

    min_z := slope.origin.z
    max_z := slope.origin.z + slope.size.z

    tx1 := (min_x - ray_origin.x) / ray_direction.x
    tx2 := (max_x - ray_origin.x) / ray_direction.x

    ty1 := (min_y - ray_origin.y) / ray_direction.y
    ty2 := (max_y - ray_origin.y) / ray_direction.y

    tz1 := (min_z - ray_origin.z) / ray_direction.z
    tz2 := (max_z - ray_origin.z) / ray_direction.z

    t_start := max(min(tx1, tx2), min(ty1, ty2), min(tz1, tz2))
    t_end   := min(max(tx1, tx2), max(ty1, ty2), max(tz1, tz2))

    nx, ny, plane_val : f32
    sx := slope.size.x
    sy := slope.size.y
    ox := slope.origin.x
    oy := slope.origin.y

    switch slope.corner {
    case .Bottom_Left:
        nx = sy
        ny = sx
        plane_val = sy * ox + sx * oy + sx * sy
    case .Bottom_Right:
        nx = -sy
        ny = sx
        plane_val = -sy * ox + sx * oy
    case .Top_Left:
        nx = sy
        ny = -sx
        plane_val = sy * ox - sx * oy
    case .Top_Right:
        nx = -sy
        ny = -sx
        plane_val = -sy * ox - sx * oy - sx * sy
    }

    denom := nx * ray_direction.x + ny * ray_direction.y
    numer := plane_val - (nx * ray_origin.x + ny * ray_origin.y)

    if denom < 0 {
        t_start = max(t_start, numer / denom)
    } else if denom > 0 {
        t_end = min(t_end, numer / denom)
    } else if numer < 0 {
        return 0, false
    }

    return t_start, t_end > t_start && t_start > 0
}

editor_property_slope_corner :: proc(
    ui     : ^Ui,
    id     : Ui_Id,
    width  : f32,
    label  : string,
    value  : ^Slope_Corner,
    anchor : Anchor,
) -> (height: f32) {
    row_height :: 42
    row_gap    :: 8

    anchor := anchor
    header_rect := ui_push_text(
        ui,
        text   = label,
        anchor = anchor,
    )
    anchor.offset.y += header_rect.w + row_gap

    if new_value, changed := ui_push_combo_box(
        ui      = ui,
        id      = id,
        value   = value^,
        width   = {width - 50, 50},
        options = [Slope_Corner]string {
            .Bottom_Left  = "Bottom Left",
            .Bottom_Right = "Bottom Right",
            .Top_Left     = "Top Left",
            .Top_Right    = "Top Right",
        },
        anchor  = anchor,
    ); changed do value^ = new_value

    return header_rect.w + row_gap + 50
}

editor_property_vector3 :: proc(
    ui       : ^Ui,
    id       : Ui_Id,
    value    : ^[3]f32,
    axis_ids : [3]struct {
        text_edit    : Ui_Id,
        up_control   : Ui_Id,
        down_control : Ui_Id,
    },
    label    : string,
    width    : f32,
    anchor   : Anchor,
) -> (height: f32) {
    axis_width  : [3]f32 = {32, width - 52, 20}
    axis_height :: 42
    axis_gap    :: 8

    anchor := anchor

    header_rect := ui_push_text(
        ui,
        text   = label,
        anchor = anchor,
    )

    anchor.offset.y += header_rect.w + axis_gap
    axis_labels : [3]string = {"X", "Y", "Z"}
    axis_colors : [3]f32    = {332, 100, 200}
    
    for i in 0..<3 {
        if new_value, changed := ui_push_spinner(
            ui,
            id              = axis_ids[i].text_edit,
            up_control_id   = axis_ids[i].up_control,
            down_control_id = axis_ids[i].down_control,
            label           = axis_labels[i], 
            value           = value[i],
            step            = .01,
            label_color     = hsv(axis_colors[i]),
            height          = axis_height,
            width           = axis_width,
            anchor          = anchor,
        ); changed do value[i] = new_value
        anchor.offset.y += axis_height + axis_gap
    }

    return header_rect.w + 3 * axis_gap + 3 * axis_height
}