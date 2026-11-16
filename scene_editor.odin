package main

import "core:math/linalg"
import "core:math"
import "base:intrinsics"
import sapp "sokol-odin/sokol/app"

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

box_face_normals := [Box_Face][3]f32 {
    .Negative_X = { -1,  0,  0},
    .Positive_X = {  1,  0,  0},
    .Negative_Y = {  0, -1,  0},
    .Positive_Y = {  0,  1,  0},
    .Negative_Z = {  0,  0, -1},
    .Positive_Z = {  0,  0,  1},
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

Face_Drag_State :: struct {
    extend_direction : [3]f32,
    extend_point     : [3]f32,
    initial_origin    : [3]f32,
    initial_size      : [3]f32,
    active           : bool,
}

Scene_Editor :: struct {
    debug_draw        : Debug_Draw, 
    free_cam          : Free_Camera,
    platforms         : [dynamic]Platform,
    mouse_hold_delta  : [2]f32,
    pending_selected  : Pending_Action(int),
    selected_platform : Maybe(int),
    modifier_shift    : bool,
    face_drag_state   : Face_Drag_State,
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

                platform := &scene.platforms[scene.selected_platform.?]
                origin, size : ^[3]f32 = &platform.origin, &platform.size 

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

                if slope, ok := &platform.variant.(Platform_Slope); ok {
                    editor_property_slope_corner(
                        ui     = ui,
                        value  = &slope.corner,
                        width  = inspector_width,
                        id     = "slope_corner",
                        label  = "Slope Corner",
                        anchor = prop_anchor,
                    )
                }
            }
        }

        // Platform selection
        if  ui_get_mouse_button_state(ctx.ui) == .Released {
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

                min_select_dist := max(f32)
                closest_index   := -1
                
                for &platform, i in scene.platforms {
                    switch &variant in platform.variant {
                        case Platform_Box:
                            if dist, hit := check_ray_box(
                                ray_origin    = ray_origin,
                                ray_direction = ray_direction,
                                box_position  = platform.origin + platform.size * .5,
                                box_half_size = platform.size * .5,
                            ); hit && dist < min_select_dist {
                                min_select_dist = dist
                                closest_index   = i
                            }
                        case Platform_Slope:
                            if dist, hit := check_ray_slope(
                                ray_origin    = ray_origin,
                                ray_direction = ray_direction,
                                slope         = platform_instance(&platform, &variant),
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
            size       = 50,
            axis_color = hsv(145, .8, .5), 
            sub_color  = hsv(0, 0, .2), 
            planes     = {.Y}
        )

        for &platform, i in scene.platforms {
            selected := scene.selected_platform != nil && i == scene.selected_platform.?
            if selected {
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
                )
                // offset from edge
                for &point in quad do point += box_face_normals[face] * .02
                
                center := (quad[0] + quad[1] + quad[2] + quad[3]) / 4

                debug_draw_push_quad(&scene.debug_draw, quad, hsv(40))
                debug_draw_push_box(
                    &scene.debug_draw, 
                    half_size = .02,
                    position  = center,
                    color     = hsv(40),
                )
                
                if ctx.mouse.state[.Left] == .Pressed {
                    scene.face_drag_state = {
                        active            = true,
                        extend_point      = center, 
                        extend_direction  = box_face_normals[face], 
                        initial_size      = platform.size,
                        initial_origin    = platform.origin,
                    }
                }

                // if ctx.mouse.state[.Left] == .Down && scene.face_drag_state.active {
                //     extend_distance, can_extend := closest_point_ray_to_line(
                //         ray_origin, ray_direction,
                //         scene.face_drag_state.extend_point,
                //         scene.face_drag_state.extend_direction,
                //     )

                //     if can_extend {
                //         position        := scene.face_drag_state.initial_origin + scene.face_drag_state.initial_size * .5  
                //         position        += scene.face_drag_state.extend_direction * extend_distance * .5
                //         platform.size    = scene.face_drag_state.initial_size + linalg.abs(scene.face_drag_state.extend_direction) * extend_distance
                //         platform.origin  = position - platform.size * .5 
                //     }
                // }
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

        // Clear modifers
        scene.modifier_shift = false

        ui_text_edit_input(ui, ev)
    }, 
    input_3d = proc(scene : ^Scene_Editor, ctx : Game_Context, ev : sapp.Event) {
        if ev.type == .KEY_DOWN && ev.key_code == .LEFT_SHIFT {
            scene.modifier_shift = true
        }
        if ev.type == .KEY_DOWN && ev.key_code == .LEFT_SHIFT {
            scene.modifier_shift = false
        }
        free_camera_input(&scene.free_cam, ctx.camera, ev)
    },
}

closest_point_ray_to_line :: proc(
    ray_origin     : [3]f32,
    ray_direction  : [3]f32,
    line_point     : [3]f32,
    line_direction : [3]f32,
) -> (distance_along_line : f32, ok : bool) {
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

check_ray_nearest_box_face :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    box_origin    : [3]f32,
    box_size      : [3]f32,
    normal_offset : f32,
) -> (
    center : [3]f32,
    rect   : [4][3]f32,
    face   : Box_Face,
) {
    @(static)
    face_rects   : [Box_Face][4][3]f32
    @(static)
    face_centers : [Box_Face][3]f32

    box_center := box_origin + box_size * .5
    min_box    := box_center - box_size * .5
    max_box    := box_center + box_size * .5

    face_centers = {
        .Negative_X = { min_box.x,    box_center.y, box_center.z },
        .Positive_X = { max_box.x,    box_center.y, box_center.z },
        .Negative_Y = { box_center.x, min_box.y,    box_center.z },
        .Positive_Y = { box_center.x, max_box.y,    box_center.z },
        .Negative_Z = { box_center.x, box_center.y, min_box.z },
        .Positive_Z = { box_center.x, box_center.y, max_box.z },
    }
    face_rects = {
        .Negative_X = {
            { min_box.x, min_box.y, min_box.z },
            { min_box.x, min_box.y, max_box.z },
            { min_box.x, max_box.y, max_box.z },
            { min_box.x, max_box.y, min_box.z },
        },
        .Positive_X = {
            { max_box.x, min_box.y, min_box.z },
            { max_box.x, max_box.y, min_box.z },
            { max_box.x, max_box.y, max_box.z },
            { max_box.x, min_box.y, max_box.z },
        },
        .Negative_Y = {
            { min_box.x, min_box.y, min_box.z },
            { max_box.x, min_box.y, min_box.z },
            { max_box.x, min_box.y, max_box.z },
            { min_box.x, min_box.y, max_box.z },
        },
        .Positive_Y ={
            { min_box.x, max_box.y, min_box.z },
            { min_box.x, max_box.y, max_box.z },
            { max_box.x, max_box.y, max_box.z },
            { max_box.x, max_box.y, min_box.z },
        },
        .Negative_Z = {
            { min_box.x, min_box.y, min_box.z },
            { min_box.x, max_box.y, min_box.z },
            { max_box.x, max_box.y, min_box.z },
            { max_box.x, min_box.y, min_box.z },
        },
        .Positive_Z = {
            { min_box.x, min_box.y, max_box.z },
            { max_box.x, min_box.y, max_box.z },
            { max_box.x, max_box.y, max_box.z },
            { min_box.x, max_box.y, max_box.z },
        },
    }

    nearest      := max(f32)
    nearest_face :  Box_Face

    for face in Box_Face {
        t := linalg.dot(face_centers[face] - ray_origin, ray_direction)
        if t < 0 do continue
        if linalg.dot(ray_direction, box_face_normals[face]) > 0 do continue

        projected    := ray_origin + t * ray_direction
        distance_sqr := linalg.length2(face_centers[face] - projected)

        if distance_sqr < nearest {
            nearest      = distance_sqr
            nearest_face = face
        }
    }

    if normal_offset == 0  do return face_centers[nearest_face], face_rects[nearest_face], nearest_face
    
    return face_centers[nearest_face] + box_face_normals[nearest_face] * normal_offset,
        {
            face_rects[nearest_face][0] + box_face_normals[nearest_face] * normal_offset,
            face_rects[nearest_face][1] + box_face_normals[nearest_face] * normal_offset,
            face_rects[nearest_face][2] + box_face_normals[nearest_face] * normal_offset,
            face_rects[nearest_face][3] + box_face_normals[nearest_face] * normal_offset,
        },
        nearest_face
}

check_ray_nearest_box_face_padding :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    box_origin    : [3]f32, 
    box_size      : [3]f32, 
    padding       : f32,
) {
    box_center   := box_origin + box_size * .5
    min_distance := max(f32)
    nearest_face : Maybe(Box_Face) 

    // Check distance to all 6 box faces  
    for face in Box_Face {
        normal := box_face_normals[face]
        pad_box_position  := box_center + normal * (box_size * .5 + padding * .5)
        pad_box_half_size := box_size * ({1, 1, 1} - linalg.abs(normal)) * .5 + linalg.abs(normal) * padding * .5
        
        if distance, hit := check_ray_box(
            ray_origin, ray_direction,
            pad_box_position, pad_box_half_size 
        ); hit && distance < min_distance {
            nearest_face = face
            min_distance = distance
        }
    }

    if face, ok := nearest_face.?; ok  {
        normal := box_face_normals[face]
        pad_box_position  := box_center + normal * (box_size * .5 + padding * .5)
        pad_box_half_size := box_size * ({1, 1, 1} - linalg.abs(normal)) * .5 + linalg.abs(normal) * padding * .5
        debug_draw_push_wire_box(
            debug_draw, pad_box_half_size,
            pad_box_position, color = hsv(54)
        )
    }
}

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

check_ray_slope :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    slope         : Platform_Instance(Platform_Slope),
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

// I think I should say sorry to my math teacher
// because I used llm to write this and have absolutely
// no idea how this work at all
check_ray_plane :: proc(
    plane_point   : [3]f32,
    plane_normal  : [3]f32,
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
) -> (distance : [3]f32, intersected : bool) {
    denom := linalg.dot(ray_direction, plane_normal)
    if abs(denom) < 1e-4 {
        return
    }
    t := linalg.dot(plane_point - ray_origin, plane_normal) / denom
    if t < 0 {
        return
    }
    return t, true
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

get_box_edges :: proc(box_origin, box_size: [3]f32) -> [12]Box_Edge {
    min_box := box_origin
    max_box := box_origin + box_size

    return [12]Box_Edge {
        { {min_box.x, min_box.y, min_box.z}, {max_box.x, min_box.y, min_box.z}, .Negative_Y, .Negative_Z },
        { {min_box.x, min_box.y, max_box.z}, {max_box.x, min_box.y, max_box.z}, .Negative_Y, .Positive_Z },
        { {min_box.x, max_box.y, min_box.z}, {max_box.x, max_box.y, min_box.z}, .Positive_Y, .Negative_Z },
        { {min_box.x, max_box.y, max_box.z}, {max_box.x, max_box.y, max_box.z}, .Positive_Y, .Positive_Z },

        { {min_box.x, min_box.y, min_box.z}, {min_box.x, max_box.y, min_box.z}, .Negative_X, .Negative_Z },
        { {min_box.x, min_box.y, max_box.z}, {min_box.x, max_box.y, max_box.z}, .Negative_X, .Positive_Z },
        { {max_box.x, min_box.y, min_box.z}, {max_box.x, max_box.y, min_box.z}, .Positive_X, .Negative_Z },
        { {max_box.x, min_box.y, max_box.z}, {max_box.x, max_box.y, max_box.z}, .Positive_X, .Positive_Z },

        { {min_box.x, min_box.y, min_box.z}, {min_box.x, min_box.y, max_box.z}, .Negative_X, .Negative_Y },
        { {min_box.x, max_box.y, min_box.z}, {min_box.x, max_box.y, max_box.z}, .Negative_X, .Positive_Y },
        { {max_box.x, min_box.y, min_box.z}, {max_box.x, min_box.y, max_box.z}, .Positive_X, .Negative_Y },
        { {max_box.x, max_box.y, min_box.z}, {max_box.x, max_box.y, max_box.z}, .Positive_X, .Positive_Y },
    }
}

check_ray_box_hit_face :: proc(ro, rd, min_box, max_box: [3]f32) -> (hit: bool, face: Box_Face) {
    t_min := [3]f32{
        (min_box.x - ro.x) / rd.x,
        (min_box.y - ro.y) / rd.y,
        (min_box.z - ro.z) / rd.z,
    }
    t_max := [3]f32{
        (max_box.x - ro.x) / rd.x,
        (max_box.y - ro.y) / rd.y,
        (max_box.z - ro.z) / rd.z,
    }

    t1 := linalg.min(t_min, t_max)
    t2 := linalg.max(t_min, t_max)

    t_near := max(t1.x, t1.y, t1.z)
    t_far  := min(t2.x, t2.y, t2.z)

    if t_far < t_near || t_near < 0 do return false, .Negative_X

    if t_near == t1.x {
        return true, .Negative_X if rd.x > 0 else .Positive_X
    } else if t_near == t1.y {
        return true, .Negative_Y if rd.y > 0 else .Positive_Y
    } else {
        return true, .Negative_Z if rd.z > 0 else .Positive_Z
    }
}

pick_box_face :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    box_origin    : [3]f32,
    box_size      : [3]f32,
) -> Box_Face {
    min_box := box_origin
    max_box := box_origin + box_size

    if hit, face := check_ray_box_hit_face(ray_origin, ray_direction, min_box, max_box); hit {
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

get_box_quad_by_face :: proc(
    box_origin : [3]f32,
    box_size   : [3]f32,
    face       : Box_Face,
) -> [4][3]f32 {
    box_center := box_origin + box_size * .5
    min_box    := box_center - box_size * .5
    max_box    := box_center + box_size * .5

    switch face {
        case .Negative_X: return {
            { min_box.x, min_box.y, min_box.z },
            { min_box.x, min_box.y, max_box.z },
            { min_box.x, max_box.y, max_box.z },
            { min_box.x, max_box.y, min_box.z },
        }
        case .Positive_X: return {
            { max_box.x, min_box.y, min_box.z },
            { max_box.x, max_box.y, min_box.z },
            { max_box.x, max_box.y, max_box.z },
            { max_box.x, min_box.y, max_box.z },
        }
        case .Negative_Y: return {
            { min_box.x, min_box.y, min_box.z },
            { max_box.x, min_box.y, min_box.z },
            { max_box.x, min_box.y, max_box.z },
            { min_box.x, min_box.y, max_box.z },
        }
        case .Positive_Y: return {
            { min_box.x, max_box.y, min_box.z },
            { min_box.x, max_box.y, max_box.z },
            { max_box.x, max_box.y, max_box.z },
            { max_box.x, max_box.y, min_box.z },
        }
        case .Negative_Z: return{
            { min_box.x, min_box.y, min_box.z },
            { min_box.x, max_box.y, min_box.z },
            { max_box.x, max_box.y, min_box.z },
            { max_box.x, min_box.y, min_box.z },
        }
        case .Positive_Z: return {
            { min_box.x, min_box.y, max_box.z },
            { max_box.x, min_box.y, max_box.z },
            { max_box.x, max_box.y, max_box.z },
            { min_box.x, max_box.y, max_box.z },
        }
        case: panic("Invalid face")
    }   
}