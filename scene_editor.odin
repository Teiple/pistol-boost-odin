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

SCENE_EDITOR_CALLBACKS : Scene_Callbacks(^Scene_Editor) : {
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
                            if dist, face, hit := ray_box_intersect(
                                ray_origin    = ray_origin,
                                ray_direction = ray_direction,
                                box_origin    = platform.origin,
                                box_size      = platform.size,
                            ); hit && dist < min_select_dist {
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
                    // offset from edge
                    offset     = box_face_normals[face] * .01
                )
                center := (quad[0] + quad[1] + quad[2] + quad[3]) / 4

                debug_draw_push_quad(
                    draw    = &scene.debug_draw,
                    points  = quad,
                    color   = hsv(40),
                    overlay = true,
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
    offset     : [3]f32 = 0,
) -> [4][3]f32 {
    unit_quad := box_unit_face_quads[face]
    quad: [4][3]f32
    for i in 0..<4 {
        quad[i] = box_origin + unit_quad[i] * box_size + offset
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