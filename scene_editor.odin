package main

import "core:fmt"
import "core:slice"
import "core:math/linalg"
import "core:math"
import "base:intrinsics"
import sapp "sokol-odin/sokol/app"

INSPECTOR_WIDTH   :: 300
STATUS_BAR_HEIGHT :: 50
MIN_PLATFORM_SIZE :: [3]f32{ .1, .1, .1}

Platform :: struct {
    origin  : [3]f32,
    size    : [3]f32,
    variant : Platform_Variant
}

Box_Face :: enum u8 {
    Negative_X,
    Positive_X,
    Negative_Y,
    Positive_Y,
    Negative_Z,
    Positive_Z,
}

Editor_Region :: enum u8 {
    Region_3D,
    Region_Ui,
}

box_face_normals := [Box_Face][3]f32 {
    .Negative_X = { -1,  0,  0},
    .Positive_X = {  1,  0,  0},
    .Negative_Y = {  0, -1,  0},
    .Positive_Y = {  0,  1,  0},
    .Negative_Z = {  0,  0, -1},
    .Positive_Z = {  0,  0,  1},
}

box_face_normal_indices := [Box_Face]int {
    .Negative_X = 0,
    .Positive_X = 0,
    .Negative_Y = 1,
    .Positive_Y = 1,
    .Negative_Z = 2,
    .Positive_Z = 2,
}

Platform_Variant :: union {
    Platform_Box,
    Platform_Slope,
}

Platform_Box :: struct{}

Platform_Slope :: struct {
    corner : Slope_Corner,
}

Platform_Instance :: struct($T: typeid)
    where intrinsics.type_is_variant_of(Platform_Variant, T)
{
    using base : ^Platform,
    using var  : ^T,
}

platform_instance :: proc(platform: ^Platform, variant : ^$T) -> Platform_Instance(T) {
    return { base = platform, var = variant }
}

Slope_Corner :: enum u8 {
    Bottom_Left,
    Bottom_Right,
    Top_Left,
    Top_Right,
}

Face_Extend_State :: struct {
    extend_point     : [3]f32,
    initial_origin   : [3]f32,
    initial_size     : [3]f32,
    initial_distance : f32,
    extend_face      : Box_Face,
    is_active        : bool,
}

Move_State :: struct {
    initial_offset   : [3]f32,
    initial_height   : f32,
    vertical         : bool,
    is_active        : bool,
    lock_z           : bool,
}

Editor_Modifer_Key :: enum u8 {
    Shift, Ctrl, Alt,
}

Editor_Modifer_Key_State :: enum {
    None, Pressed, Down, Released,
}

Scene_Editor :: struct {
    debug_draw        : Debug_Draw, 
    free_cam          : Free_Camera,
    platforms         : [dynamic]Platform,
    mouse_hold_delta  : [2]f32,
    pending_selected  : Pending_Action(int),
    is_new_selection  : bool,
    selected_platform : Maybe(int),
    delete_selected   : bool,

    modifier_state    : [Editor_Modifer_Key]Editor_Modifer_Key_State,
    face_extend_state : Face_Extend_State,
    move_state        : Move_State,
    focused_region    : Editor_Region,
}

SCENE_EDITOR_CALLBACKS : Scene_Callbacks(^Scene_Editor) : {
    init = proc(scene : ^Scene_Editor, ctx : Game_Context) {        
        debug_draw_init(&scene.debug_draw)

        ctx.camera.position = {2, 4, 10}
        free_camera_init_default(&scene.free_cam, ctx.camera, ctx.viewport)

        append(&scene.platforms,
            Platform {
                origin  = {0,0,0},
                size    = {2,1,1},
                variant = Platform_Box {},
            },
            Platform {
                origin = {0,2,0},
                size   = {2,1,1},
                variant = Platform_Slope {
                    corner = .Bottom_Left,
                }
            },

        )
    },
    destroy = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        debug_draw_destroy(&scene.debug_draw)        
        delete(scene.platforms)
    },
    update_ui = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        ui := ctx.ui

        // View mode selection
        status_bar_rect, _ := ui_push_rect(
            ui     = ui,
            sizing = { PercentOffset{1, -INSPECTOR_WIDTH}, STATUS_BAR_HEIGHT },
            anchor = { element = {0, 1}, parent = {0, 1} }, 
        )

        ui_push_container(ui, status_bar_rect)
        {
            defer ui_pop_container(ui)

            prop_anchor : Anchor

            view_mode_rect, _ := ui_push_rect(
                ui     = ui,
                sizing = { 220, Percent{1} },
                anchor = prop_anchor
            )

            prop_anchor.offset.x += 220
            
            ui_push_container(ui, view_mode_rect)
            {
                defer ui_pop_container(ui)

                if new_value, changed := ui_push_combo_box(
                    ui      = ui,
                    id      = "view_mode",
                    width   = {170, 50},
                    height  = 50,
                    anchor  = { element = {0, 1}, parent = {0, 1} },         
                    options = [Free_Camera_Mode]string {
                        .Perspective = "Perspective",
                        .Ortho_Front = "Ortho Front",
                        .Ortho_Back  = "Ortho Back",
                    },
                    value   = scene.free_cam.mode,
                ); changed do scene.free_cam.mode = new_value
            }

            lock_z_rect, _ := ui_push_rect(
                ui     = ui,
                sizing = { 220, Percent{1} },
                anchor = prop_anchor
            )

            ui_push_container(ui, lock_z_rect)
            {
                defer ui_pop_container(ui)

                if new_value, changed := ui_push_combo_box(
                    ui      = ui,
                    id      = "view_mode",
                    width   = {170, 50},
                    height  = 50,
                    anchor  = { element = {0, 1}, parent = {0, 1} },         
                    options = [Free_Camera_Mode]string {
                        .Perspective = "Perspective",
                        .Ortho_Front = "Ortho Front",
                        .Ortho_Back  = "Ortho Back",
                    },
                    value   = scene.free_cam.mode,
                ); changed do scene.free_cam.mode = new_value
            }

            
        }
        

        // Inspector
        if scene.selected_platform != nil {
            inspector_rect, _ := ui_push_rect(
                ui     = ui,
                sizing = { INSPECTOR_WIDTH, Percent{1}},
                anchor = { element = {1, 0}, parent = {1, 0} },
                color  = hsv(0, 0, .25),
            )
        
            inspector_padding :: 8
            inspector_width   := inspector_rect.z - inspector_padding * 2

            ui_push_container(ui, inspector_rect)
            {
                defer ui_pop_container(ui)

                prop_gap    :: 16
                prop_anchor : Anchor = { offset = {inspector_padding, inspector_padding} }

                platform := &scene.platforms[scene.selected_platform.?]
                origin, size : ^[3]f32 = &platform.origin, &platform.size 

                index_rect := ui_push_text(
                    ui     = ui,
                    text   = fmt.tprintf("Index %03d", scene.selected_platform.?),
                    anchor = prop_anchor,
                )

                prop_anchor.offset.y += index_rect.w

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
                    min_value = MIN_PLATFORM_SIZE,
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

                if slope, ok := &platform.variant.(Platform_Slope); ok {
                    prop_anchor.offset.y += editor_property_slope_corner(
                        ui     = ui,
                        value  = &slope.corner,
                        width  = inspector_width,
                        id     = "slope_corner",
                        label  = "Slope Corner",
                        anchor = prop_anchor,
                    )
                }
                prop_anchor.offset.y += prop_gap

                snap_to_grid_rect, snap_to_grid_clicked := ui_push_label_button(
                    ui     = ui,
                    id     = "snap_to_grid",
                    text   = "Snap to Grid",
                    anchor = prop_anchor,
                    sizing = {inspector_width, 50},
                )
                prop_anchor.offset.y += snap_to_grid_rect.w + prop_gap

                reset_z_rect, reset_z_clicked := ui_push_label_button(
                    ui     = ui,
                    id     = "reset_z",
                    text   = "Reset Z",
                    anchor = prop_anchor,
                    sizing = {inspector_width, 50},
                )

                if reset_z_clicked {
                    platform.origin.z = 0
                }
            }
        }
        
                
    },
    update_3d = proc(scene : ^Scene_Editor, ctx : Game_Context, dt : f32) {
        get_move_plane_normal :: proc(scene : ^Scene_Editor) -> [3]f32 {
            return scene.free_cam.mode == .Perspective ? {0, 1, 0} : {0, 0, scene.free_cam.mode == .Ortho_Front ? 1 : -1}
        }
        get_platform_under_cursor :: proc(scene : ^Scene_Editor, ctx : Game_Context) -> (index: int) {
            ray_origin, ray_direction := viewport_get_mouse_world_ray(
                ctx.viewport,
                ctx.camera,
                ctx.mouse.position
            )

            min_select_dist := max(f32)
            closest_index   := -1
            
            for &platform, i in scene.platforms {
                switch &variant in platform.variant {
                    case Platform_Box:
                        if dist, _, hit := ray_box_intersect(
                            ray_origin    = ray_origin,
                            ray_direction = ray_direction,
                            box_origin    = platform.origin,
                            box_size      = platform.size,
                        ); hit && (dist < min_select_dist || (dist == min_select_dist && i == scene.selected_platform)) {
                            min_select_dist = dist
                            closest_index   = i
                        }
                    case Platform_Slope:
                        if dist, hit := ray_slope_interesect(
                            ray_origin    = ray_origin,
                            ray_direction = ray_direction,
                            slope_origin  = platform.origin,
                            slope_size    = platform.size,
                            slope_corner  = variant.corner,
                        ); hit && dist < min_select_dist {
                            min_select_dist = dist
                            closest_index   = i
                        }
                }
            }

            return closest_index    
        }

        debug_draw_begin(&scene.debug_draw)

        clicked_platform := -1
        clicked_on_3d    := false

        if ctx.mouse.state[.Left] == .Pressed && editor_is_position_in_3d_region(ctx, ctx.mouse.position) {
            clicked_on_3d = true
            scene.focused_region =
                editor_is_position_in_3d_region(ctx, ctx.mouse.position) ? .Region_3D : .Region_Ui
            clicked_platform = get_platform_under_cursor(scene, ctx)  
        }



        debug_draw_push_grid(
            draw       = &scene.debug_draw,
            unit       = 1,
            size       = 50,
            axis_color = hsv(145, .8, .5), 
            sub_color  = hsv(0, 0, .2), 
            planes     = {.Y}
        )

        for &platform, i in scene.platforms {
            selected := scene.selected_platform != nil && i == scene.selected_platform.?
            if selected {
                if !scene.face_extend_state.is_active && scene.modifier_state[.Shift] == .Down {
                    ray_origin, ray_direction := viewport_get_mouse_world_ray(
                        ctx.viewport,
                        ctx.camera,
                        ctx.mouse.position
                    )

                    face := pick_box_face(
                        ray_origin    = ray_origin,
                        ray_direction = ray_direction,
                        box_origin    = platform.origin,
                        box_size      = platform.size,
                    )

                    quad := get_box_quad_by_face(
                        box_origin = platform.origin,
                        box_size   = platform.size,
                        face       = face,
                        offset     = .01
                    )
                    center := (quad[0] + quad[1] + quad[2] + quad[3]) / 4    
                
                    debug_draw_push_quad(
                        draw    = &scene.debug_draw,
                        points  = quad,
                        color   = hsv(40),
                        overlay = true,
                    )

                    if clicked_on_3d {
                        if dist, ok := ray_to_line(
                            ray_origin       = ray_origin,
                            ray_direction    = ray_direction,
                            line_point       = center,
                            line_direction   = box_face_normals[face],
                        ); ok {
                            scene.face_extend_state = {
                                is_active        = true,
                                extend_point     = center, 
                                extend_face      = face,
                                initial_size     = platform.size,
                                initial_origin   = platform.origin,
                                initial_distance = dist,
                            }
                        }
                    }
                }
                if scene.face_extend_state.is_active && ctx.mouse.state[.Left] == .Down {
                    ray_origin, ray_direction := viewport_get_mouse_world_ray(
                        ctx.viewport,
                        ctx.camera,
                        ctx.mouse.position
                    )

                    extend_direction := box_face_normals[scene.face_extend_state.extend_face]

                    extend_distance, can_extend := ray_to_line(
                        ray_origin       = ray_origin,
                        ray_direction    = ray_direction,
                        line_point       = scene.face_extend_state.extend_point,
                        line_direction   = box_face_normals[scene.face_extend_state.extend_face],
                    )
                    extend_distance -= scene.face_extend_state.initial_distance

                    if can_extend {
                        min_size := MIN_PLATFORM_SIZE

                        extend_index := box_face_normal_indices[scene.face_extend_state.extend_face]
                        prev_size    := scene.face_extend_state.initial_size[extend_index]
                        
                        platform.size[extend_index] = prev_size + linalg.abs(extend_direction[extend_index]) * extend_distance
                        
                        if platform.size[extend_index] < min_size[extend_index] {
                            platform.size[extend_index] = min_size[extend_index]
                        }
                        
                        position := scene.face_extend_state.initial_origin + scene.face_extend_state.initial_size * .5  
                        position += extend_direction * (platform.size[extend_index] - prev_size) * .5
                        
                        platform.origin = position - platform.size * .5
                    
                        snap_platform_to_grid(&platform, .2)
                    }

                    // Draw current extending face
                    quad := get_box_quad_by_face(
                        box_origin = platform.origin,
                        box_size   = platform.size,
                        face       = scene.face_extend_state.extend_face,
                        offset     = .01
                    )
                    center := (quad[0] + quad[1] + quad[2] + quad[3]) / 4    
                
                    debug_draw_push_quad(
                        draw    = &scene.debug_draw,
                        points  = quad,
                        color   = hsv(40),
                        overlay = true,
                    )
                }

                if !scene.face_extend_state.is_active {
                    hit := clicked_platform == scene.selected_platform.?
                    hit |= ctx.mouse.state[.Left] == .Down && scene.is_new_selection
                    
                    if hit {
                        ray_origin, ray_direction := viewport_get_mouse_world_ray(
                            ctx.viewport,
                            ctx.camera,
                            ctx.mouse.position
                        )

                        if point, ok := ray_plane_intersect(
                            ray_origin    = ray_origin,
                            ray_direction = ray_direction,
                            plane_normal  = get_move_plane_normal(scene), 
                            plane_point   = platform.origin, 
                        ); ok {
                            scene.move_state = {
                                is_active      = true,
                                initial_offset = point - platform.origin,
                            }
                        }

                        if scene.modifier_state[.Alt] == .Down {
                            if dist, ok := ray_to_line(
                                ray_origin     = ray_origin,
                                ray_direction  = ray_direction,
                                line_direction = {0, 1, 0}, 
                                line_point     = platform.origin, 
                            ); ok {
                                point := platform.origin + {0, 1, 0} * dist
                                
                                scene.move_state.is_active      = true
                                scene.move_state.vertical       = true
                                scene.move_state.initial_height = point.y - platform.origin.y
                            }
                        }
                        
                    }
                }
                
                if scene.move_state.is_active && ctx.mouse.state[.Left] == .Down {                    
                    ray_origin, ray_direction := viewport_get_mouse_world_ray(
                        viewport       = ctx.viewport,
                        camera         = ctx.camera,
                        mouse_position = ctx.mouse.position, 
                    )

                    if scene.modifier_state[.Alt] == .Released {
                        scene.move_state.vertical = false
                    }

                    if scene.modifier_state[.Alt] == .Pressed || (scene.move_state.vertical && scene.modifier_state[.Alt] == .Down) {
                        if dist, ok := ray_to_line(
                            ray_origin      = ray_origin,
                            ray_direction   = ray_direction,
                            line_point      = platform.origin,
                            line_direction  = {0, 1, 0},
                        ); ok {
                            point := platform.origin + {0, 1, 0} * dist
                            
                            if scene.modifier_state[.Alt] == .Pressed {
                                scene.move_state.vertical       = true
                                scene.move_state.initial_height = point.y - platform.origin.y
                            } else {
                                platform.origin.y = point.y - scene.move_state.initial_height
                                snap_platform_to_grid(&platform, .2)
                            }
                        }
                    } else {
                        move_plane_normal := get_move_plane_normal(scene)
                        if point, ok := ray_plane_intersect(
                            ray_origin    = ray_origin,
                            ray_direction = ray_direction,
                            plane_normal  = move_plane_normal, 
                            plane_point   = platform.origin, 
                        ); ok {
                            fmt.println(move_plane_normal)
                            platform.origin = (1 - move_plane_normal) * (point - scene.move_state.initial_offset) + 
                                platform.origin * move_plane_normal
                            snap_platform_to_grid(&platform, .2)
                        }
                    }
                } 
            }

            switch &variant in platform.variant {
                case Platform_Box:
                    debug_draw_push_platform_box(
                        draw         = &scene.debug_draw,
                        box          = platform_instance(&platform, &variant),
                        color        = selected ? hsv(190, 1,  1) : hsv(200, 1, 1),
                        wire_color   = selected ? hsv(190, 1, .4) : hsv(200, .4, .4),
                    )
                case Platform_Slope: 
                    debug_draw_push_platform_slope(
                        draw         = &scene.debug_draw,
                        slope        = platform_instance(&platform, &variant),
                        color        = selected ? hsv(190, 1,  1) : hsv(200, 1, 1),
                        wire_color   = selected ? hsv(190, 1, .4) : hsv(200, .4, .4),
                    )
            }
        }

        clear_hold_state :: proc(scene : ^Scene_Editor, ctx : Game_Context) {
            if scene.face_extend_state.is_active do scene.face_extend_state = {}
            if scene.move_state.is_active        do scene.move_state = {}
        }

        has_hold_state :: proc(scene : ^Scene_Editor, ctx : Game_Context) -> bool {
            return scene.face_extend_state.is_active || scene.move_state.is_active
        }

        if ctx.mouse.state[.Left] == .Released && scene.focused_region == .Region_3D {
            clear_hold_state(scene, ctx)
        }

        if clicked_on_3d && !has_hold_state(scene, ctx) {
            if clicked_platform < 0 {
                pending_action_clear(&scene.pending_selected)
            } else {
                pending_action_set(&scene.pending_selected, &scene.selected_platform, clicked_platform)
            }
        }

        free_camera_update_3d(&scene.free_cam, ctx, dt)

        // End Of Frame:
    
        // Update modifiers
        for &state in scene.modifier_state {
            if state == .Pressed {
                state = .Down
            } else if state == .Released {
                state = .None
            }
        }

        // Handle deletion
        if scene.delete_selected {
            // we only use platform index for check selected platform for now, so unorder_remove kinda make sense
            unordered_remove(&scene.platforms, scene.selected_platform.?)                    
            pending_action_clear(&scene.pending_selected, forced = true)
            
            scene.delete_selected = false
        }

        // Handle new selection
        scene.is_new_selection = pending_resolve(&scene.pending_selected, &scene.selected_platform) && scene.selected_platform != nil
        
        if scene.is_new_selection {
            clear_hold_state(scene, ctx)
        }
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
        if ev.type == .KEY_DOWN || ev.type == .KEY_UP {
            state : Editor_Modifer_Key_State = ev.type == .KEY_DOWN ? .Pressed : .Released
            #partial switch ev.key_code {
                case .LEFT_SHIFT, .RIGHT_SHIFT:
                    scene.modifier_state[.Shift] = state
                case .LEFT_CONTROL, .RIGHT_CONTROL:
                    scene.modifier_state[.Ctrl]  = state
                case .LEFT_ALT, .RIGHT_ALT:
                    scene.modifier_state[.Alt]   = state
            }
        }

        ctrl := ev.modifiers & sapp.MODIFIER_CTRL != 0

        if ctrl && ev.type == .KEY_UP && ev.key_code == .D{
            // duplicate current selected platform
            duplicate_offset : [3]f32 : {0, 0, 0}
            if selected_index, ok := scene.selected_platform.?; ok {
                platform := scene.platforms[selected_index]
                platform.origin += duplicate_offset
                append(&scene.platforms, platform)
                pending_action_set(&scene.pending_selected, &scene.selected_platform, len(scene.platforms) - 1)
            }
        }

        if scene.selected_platform != nil && 
            ((ev.type == .KEY_UP && ev.key_code == .DELETE) ||
             (ctrl && ev.type == .KEY_UP && ev.key_code == .X))
        {
            scene.delete_selected = true
        }

        free_camera_input(&scene.free_cam, ev)
    },
}

editor_is_position_in_3d_region :: proc(ctx: Game_Context, position : [2]f32) -> bool {
    return position.x < ctx.viewport.base_size.x - INSPECTOR_WIDTH &&
        position.y < ctx.viewport.base_size.y - STATUS_BAR_HEIGHT
}


ray_to_line :: proc(
    ray_origin     : [3]f32,
    ray_direction  : [3]f32,
    line_point     : [3]f32,
    line_direction : [3]f32,
) -> (dist_along_line : f32, ok : bool) {
    w0 := ray_origin - line_point
    a  := linalg.dot(ray_direction,  ray_direction)
    b  := linalg.dot(ray_direction,  line_direction)
    c  := linalg.dot(line_direction, line_direction)
    d  := linalg.dot(ray_direction,  w0)
    e  := linalg.dot(line_direction, w0)
    denom := a * c - b * b

    if abs(denom) < 1e-4 do return
    return (a * e - b * d) / denom, true
}

ray_slope_interesect :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    slope_origin  : [3]f32,
    slope_size    : [3]f32,
    slope_corner  : Slope_Corner,
) -> (dist : f32, hit: bool) {
    min_box := slope_origin
    max_box := slope_origin + slope_size

    t_min := (min_box - ray_origin) / ray_direction
    t_max := (max_box - ray_origin) / ray_direction

    t1 := linalg.min(t_min, t_max)
    t2 := linalg.max(t_min, t_max)

    t_near := max(t1.x, t1.y, t1.z)
    t_far  := min(t2.x, t2.y, t2.z)

    if t_far < t_near || t_near < 0 do return 0, false

    // The diagonal plane
    nx, ny, plane_val : f32
    sx := slope_size.x
    sy := slope_size.y
    ox := slope_origin.x
    oy := slope_origin.y

    switch slope_corner {
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
        t_near = max(t_near, numer / denom)
    } else if denom > 0 {
        t_far  = min(t_far , numer / denom)
    } else if numer < 0 {
        return 0, false
    }

    return t_near, t_far > t_near && t_near > 0
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
    ui        : ^Ui,
    id        : Ui_Id,
    value     : ^[3]f32,
    axis_ids  : [3]struct {
        text_edit    : Ui_Id,
        up_control   : Ui_Id,
        down_control : Ui_Id,
    },
    label     : string,
    width     : f32,
    anchor    : Anchor,
    min_value : Maybe([3]f32) = nil, 
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
            min_val         = min_value != nil ? min_value.?[0] : nil,
            label_color     = hsv(axis_colors[i]),
            height          = axis_height,
            width           = axis_width,
            anchor          = anchor,
        ); changed do value[i] = new_value
        anchor.offset.y += axis_height + axis_gap
    }

    return header_rect.w + 3 * axis_gap + 3 * axis_height
}

ray_box_intersect :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    box_origin    : [3]f32,
    box_size      : [3]f32,
) -> (dist: f32, face: Box_Face, hit: bool) {
    min_box := box_origin
    max_box := box_origin + box_size

    t_min := (min_box - ray_origin) / ray_direction
    t_max := (max_box - ray_origin) / ray_direction

    t1 := linalg.min(t_min, t_max)
    t2 := linalg.max(t_min, t_max)

    t_near := max(t1.x, t1.y, t1.z)
    t_far  := min(t2.x, t2.y, t2.z)

    if t_far < t_near || t_near < 0 do return

    hit_face: Box_Face
    if t_near == t1.x {
        hit_face = .Negative_X if ray_direction.x > 0 else .Positive_X
    } else if t_near == t1.y {
        hit_face = .Negative_Y if ray_direction.y > 0 else .Positive_Y
    } else {
        hit_face = .Negative_Z if ray_direction.z > 0 else .Positive_Z
    }

    return t_near, hit_face, true
}

ray_segment_distance_sqr :: proc(ro, rd, p0, p1: [3]f32) -> f32 {
    u := p1 - p0
    v := rd
    w := p0 - ro

    a := linalg.dot(u, u)
    b := linalg.dot(u, v)
    c := linalg.dot(v, v)
    d := linalg.dot(u, w)
    e := linalg.dot(v, w)

    denom := a * c - b * b
    s: f32 = 0
    t: f32 = 0

    if abs(denom) < 1e-5 {
        s = 0
        t = e / c if c > 1e-5 else 0
    } else {
        s = (b * e - c * d) / denom
        t = (a * e - b * d) / denom
    }

    s = clamp(s, 0, 1)
    t = max(t, 0)

    closest_seg := p0 + s * u
    closest_ray := ro + t * v
    diff := closest_seg - closest_ray
    return linalg.dot(diff, diff)
}

Box_Edge :: struct {
    p0: [3]f32,
    p1: [3]f32,
    f0: Box_Face,
    f1: Box_Face,
}

pick_box_face :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    box_origin    : [3]f32,
    box_size      : [3]f32,
) -> Box_Face {
    if dist, face, hit := ray_box_intersect(
        ray_origin    = ray_origin,
        ray_direction = ray_direction,
        box_origin    = box_origin,
        box_size      = box_size,
    ); hit {
        return face
    }

    edges     := get_box_edges(box_origin, box_size)
    best_dist := max(f32)
    best_face := Box_Face.Negative_X

    for edge in edges {
        n0 := box_face_normals[edge.f0]
        n1 := box_face_normals[edge.f1]

        dot0 := linalg.dot(n0, ray_direction)
        dot1 := linalg.dot(n1, ray_direction)

        if (dot0 < 0) == (dot1 < 0) do continue

        dist := ray_segment_distance_sqr(ray_origin, ray_direction, edge.p0, edge.p1)
        if dist < best_dist {
            best_dist = dist
            best_face = edge.f0 if dot0 > dot1 else edge.f1
        }
    }

    return best_face
}

box_unit_face_quads := [Box_Face][4][3]f32 {
    .Negative_X = { {0, 0, 0}, {0, 0, 1}, {0, 1, 1}, {0, 1, 0} },
    .Positive_X = { {1, 0, 0}, {1, 1, 0}, {1, 1, 1}, {1, 0, 1} },
    .Negative_Y = { {0, 0, 0}, {1, 0, 0}, {1, 0, 1}, {0, 0, 1} },
    .Positive_Y = { {0, 1, 0}, {0, 1, 1}, {1, 1, 1}, {1, 1, 0} },
    .Negative_Z = { {0, 0, 0}, {0, 1, 0}, {1, 1, 0}, {1, 0, 0} },
    .Positive_Z = { {0, 0, 1}, {1, 0, 1}, {1, 1, 1}, {0, 1, 1} },
}

get_box_quad_by_face :: proc(
    box_origin : [3]f32,
    box_size   : [3]f32,
    face       : Box_Face,
    offset     : f32 = 0,
) -> [4][3]f32 {
    unit_quad := box_unit_face_quads[face]
    quad: [4][3]f32
    for i in 0..<4 {
        quad[i] = box_origin + unit_quad[i] * box_size +
            box_face_normals[face] * offset
    }
    return quad
}

Box_Unit_Edge :: struct {
    p0 : [3]f32,
    p1 : [3]f32,
    f0 : Box_Face,
    f1 : Box_Face,
}

box_unit_edges := [12]Box_Unit_Edge {
    { {0, 0, 0}, {1, 0, 0}, .Negative_Y, .Negative_Z },
    { {0, 0, 1}, {1, 0, 1}, .Negative_Y, .Positive_Z },
    { {0, 1, 0}, {1, 1, 0}, .Positive_Y, .Negative_Z },
    { {0, 1, 1}, {1, 1, 1}, .Positive_Y, .Positive_Z },

    { {0, 0, 0}, {0, 1, 0}, .Negative_X, .Negative_Z },
    { {0, 0, 1}, {0, 1, 1}, .Negative_X, .Positive_Z },
    { {1, 0, 0}, {1, 1, 0}, .Positive_X, .Negative_Z },
    { {1, 0, 1}, {1, 1, 1}, .Positive_X, .Positive_Z },

    { {0, 0, 0}, {0, 0, 1}, .Negative_X, .Negative_Y },
    { {0, 1, 0}, {0, 1, 1}, .Negative_X, .Positive_Y },
    { {1, 0, 0}, {1, 0, 1}, .Positive_X, .Negative_Y },
    { {1, 1, 0}, {1, 1, 1}, .Positive_X, .Positive_Y },
}

get_box_edges :: proc(box_origin, box_size: [3]f32) -> (edges: [12]Box_Edge) {
    for e, i in box_unit_edges {
        edges[i] = {
            p0 = box_origin + e.p0 * box_size,
            p1 = box_origin + e.p1 * box_size,
            f0 = e.f0,
            f1 = e.f1,
        }
    }
    return
}

ray_plane_intersect :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    plane_normal  : [3]f32,
    plane_point   : [3]f32,
) -> (point : [3]f32, hit: bool){
    if abs(linalg.dot(ray_direction, plane_normal)) < 1e-4 {
        fmt.println("dot: ", linalg.dot(ray_direction, plane_normal))
        return
    }
    
    t := linalg.dot(plane_point - ray_origin, plane_normal) / linalg.dot(ray_direction, plane_normal)
    
    if t < 0 {
        fmt.println("t: ", t)
        return
    }

    return ray_origin + t * ray_direction, true
}

snap_platform_to_grid :: proc(platform : ^Platform, grid_unit : f32) {
    platform.origin = linalg.round(platform.origin / grid_unit) * grid_unit
    platform.size   = linalg.round(platform.size / grid_unit) * grid_unit
    platform.size   = linalg.max(platform.size, MIN_PLATFORM_SIZE)
}
