package main

import "core:os"
import "core:encoding/json"
import "base:runtime"
import "core:fmt"
import "core:time"
import "core:slice"
import "core:math/linalg"
import "core:math"
import "base:intrinsics"
import sapp "sokol-odin/sokol/app"

INSPECTOR_WIDTH      :: 250
STATUS_BAR_HEIGHT    :: 50
MIN_PLATFORM_SIZE    :: [3]f32{ .1, .1, .1}
DEFAULT_UNDO_TIMEOUT :: 300 * time.Millisecond
MAX_UNDO_SNAPSHOTS   :: 24

MAP_DIR       :: "."
MAP_FILE      :: "map.json"
MAP_FILE_PATH := MAP_DIR + "/" + MAP_FILE

Editor_View_Mode :: enum {
    Perspective,
    Ortho_Front,
    Ortho_Back,
}  

Editor_Snapshot :: struct {
    platforms         : []Platform,
    selected_platform : int, 
}

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

box_unit_face_quads := [Box_Face][4][3]f32 {
    .Negative_X = { {0, 0, 0}, {0, 0, 1}, {0, 1, 1}, {0, 1, 0} },
    .Positive_X = { {1, 0, 0}, {1, 1, 0}, {1, 1, 1}, {1, 0, 1} },
    .Negative_Y = { {0, 0, 0}, {1, 0, 0}, {1, 0, 1}, {0, 0, 1} },
    .Positive_Y = { {0, 1, 0}, {0, 1, 1}, {1, 1, 1}, {1, 1, 0} },
    .Negative_Z = { {0, 0, 0}, {0, 1, 0}, {1, 1, 0}, {1, 0, 0} },
    .Positive_Z = { {0, 0, 1}, {1, 0, 1}, {1, 1, 1}, {0, 1, 1} },
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


Platform_Type :: enum u8 {
    Box, Slope
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

Editor_Modifer_Key :: enum u8 {
    Shift, Ctrl, Alt,
}

Editor_Modifer_Key_State :: enum {
    None, Pressed, Down, Released,
}

Editor_Frame_Action :: enum u8 {
    Delete,
    Add,
    Duplicate,
    Undo, Redo,
    Save,
}

Editor_Settings :: struct {
    grid_size     : f32,
    view_mode     : Editor_View_Mode,
    next_platform : Platform_Type,
    lock_z        : bool,
    snap_to_grid  : bool,
}

DEFAULT_EDITOR_SETTINGS : Editor_Settings : {
    grid_size     = .125,
    view_mode     = .Perspective,
    next_platform = .Box,
    lock_z        = true,
    snap_to_grid  = true,
}

Scene_Editor :: struct {
    debug_draw        : Debug_Draw, 
    free_cam          : Free_Camera,
    platforms         : [dynamic]Platform,

    selection : struct {
        current : Maybe(int),
        is_new  : bool,
        pending : Pending_Action(int),
    },

    input : struct {
        modifiers      : [Editor_Modifer_Key]Editor_Modifer_Key_State,
        focused_region : Editor_Region,
    },

    drag_state : struct {
        face_extend : struct {
            extend_point     : [3]f32,
            initial_origin   : [3]f32,
            initial_size     : [3]f32,
            initial_distance : f32,
            extend_face      : Box_Face,
            is_active        : bool,
            has_delta        : bool,
        },
        move: struct {
            initial_offset   : [3]f32,
            initial_origin   : [3]f32,
            initial_height   : f32,
            vertical         : bool,
            is_active        : bool,
            has_delta        : bool,
        },
    },

    undo : struct {
        stack              : [MAX_UNDO_SNAPSHOTS]Editor_Snapshot,
        snapshot_allocator : runtime.Allocator,
        last_undo_time     : time.Tick,
        stack_current      : int,
        stack_max          : int,
        saved_index        : int,
    },

    frame_actions : bit_set[Editor_Frame_Action; u8],
}

editor_undo_init :: proc(scene : ^Scene_Editor, snapshot_allocator : runtime.Allocator) {
    scene.undo.stack_current      = -1
    scene.undo.saved_index        = 0
    scene.undo.snapshot_allocator = snapshot_allocator
    editor_push_snapshot(scene, skip_time_check = true)
}

editor_snapshot_make :: proc(scene : ^Scene_Editor) -> Editor_Snapshot {
    return {
        platforms         = slice.clone(scene.platforms[:], allocator = scene.undo.snapshot_allocator),
        selected_platform = scene.selection.current.? or_else -1,
    }
}

editor_push_snapshot :: proc(scene : ^Scene_Editor, skip_time_check := false) {
    if !skip_time_check && time.tick_diff(scene.undo.last_undo_time, time.tick_now()) <= DEFAULT_UNDO_TIMEOUT {
        return
    }
    snapshot := editor_snapshot_make(scene)

    scene.undo.stack_current += 1
    scene.undo.stack_max = scene.undo.stack_current

    resolved_index := scene.undo.stack_current % len(scene.undo.stack)
    delete(scene.undo.stack[resolved_index].platforms, allocator = scene.undo.snapshot_allocator)

    scene.undo.stack[resolved_index] = snapshot

    scene.undo.last_undo_time = time.tick_now()
}

editor_restore_snapshot :: proc(scene : ^Scene_Editor, snapshot : Editor_Snapshot, skip_selection_pending := false) {
    delete(scene.platforms)
    scene.platforms = slice.clone_to_dynamic(snapshot.platforms[:])
    
    if skip_selection_pending {
        scene.selection.current = snapshot.selected_platform
        return
    }

    if snapshot.selected_platform >= 0 {
        pending_action_set(&scene.selection.pending, &scene.selection.current, snapshot.selected_platform, forced = true)
    } else {
        pending_action_clear(&scene.selection.pending, forced = true)
    }
}

editor_undo :: proc(scene : ^Scene_Editor) {
    if !editor_has_undo(scene) {
        return
    } 
    scene.undo.stack_current -= 1
    editor_restore_snapshot(scene, scene.undo.stack[scene.undo.stack_current % len(scene.undo.stack)])
}

editor_has_undo :: proc(scene : ^Scene_Editor) -> bool {
    return scene.undo.stack_current > 0 && scene.undo.stack_current > scene.undo.stack_max - len(scene.undo.stack) + 1
}

editor_redo :: proc(scene : ^Scene_Editor) {
    if !editor_has_redo(scene) {
        return
    } 
    scene.undo.stack_current += 1
    editor_restore_snapshot(scene, scene.undo.stack[scene.undo.stack_current % len(scene.undo.stack)])
}

editor_has_redo :: proc(scene : ^Scene_Editor) -> bool {
    return scene.undo.stack_current < scene.undo.stack_max
}

SCENE_EDITOR_CALLBACKS : Scene_Callbacks(^Scene_Editor) : {
    init = proc(scene : ^Scene_Editor, ctx : Game_Context) {        
        debug_draw_init(&scene.debug_draw)

        ctx.camera.position = {.5, 2, 10}
        free_camera_init_default(&scene.free_cam, ctx.camera, ctx.viewport)

        snapshot_allocator := context.allocator
        editor_load_map(scene,  snapshot_allocator = snapshot_allocator, load_allocator = context.allocator)
        editor_undo_init(scene, snapshot_allocator = snapshot_allocator)
    },
    destroy = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        debug_draw_destroy(&scene.debug_draw)        
        delete(scene.platforms)
        for &snapshot in scene.undo.stack {
            delete(snapshot.platforms, allocator = scene.undo.snapshot_allocator)
        }

        editor_exit()
    },
    update_ui = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        ui := ctx.ui

        // Status bar
        status_bar_rect, _ := ui_push_rect(
            ui     = ui,
            sizing = { Percent{1}, STATUS_BAR_HEIGHT },
            anchor = { element = {0, 1}, parent = {0, 1} },
        )

        ui_push_rect(
            ui     = ui,
            sizing = { Percent{1}, STATUS_BAR_HEIGHT },
            anchor = { element = {0, 1}, parent = {0, 1} },
            color  = hsv(0, 0, .25),
        )

        ui_push_container(ui, status_bar_rect)
        {
            defer ui_pop_container(ui)

            layout := ui_layout_begin(ui, .Horizontal, pad = 4, gap = 8)

            if new_value, changed := ui_push_combo_box(
                ui      = ui,
                id      = "view_mode",
                slot    = ui_slot(&layout, 220),
                options = [Editor_View_Mode]string {
                    .Perspective = "Perspective",
                    .Ortho_Front = "Ortho Front",
                    .Ortho_Back  = "Ortho Back",
                },
                value   = ctx.settings.editor.view_mode,
            ); changed {
                switch new_value {
                    case .Perspective:
                        scene.free_cam.mode = .Perspective
                    case .Ortho_Front:
                        scene.free_cam.mode = .Orthogonal
                        scene.free_cam.mode_orthogonal.direction = {0, 0, -1}
                    case .Ortho_Back:
                        scene.free_cam.mode = .Orthogonal
                        scene.free_cam.mode_orthogonal.direction = {0, 0,  1}
                }
                ctx.settings.editor.view_mode = new_value
            }

            ui_push_checkbox(
                ui    = ui,
                id    = "lock_z",
                text  = "Lock Z",
                value = &ctx.settings.editor.lock_z,
                slot  = ui_slot(&layout, 140),
            )

            ui_push_checkbox(
                ui    = ui,
                id    = "grid_snap",
                text  = "Snap",
                value = &ctx.settings.editor.snap_to_grid,
                slot  = ui_slot(&layout, 140)
            )

            if new_value, changed := ui_push_spinner(
                ui              = ui,
                id              = "grid_size",
                up_control_id   = "grid_size:up",
                down_control_id = "grid_size:down",
                label           = "Grid Size",
                min_val         = .125,
                max_val         = 4,
                step            = .125,
                label_width     = 140,
                value           = ctx.settings.editor.grid_size,
                slot            = ui_slot(&layout, 250),
            ); changed {
                ctx.settings.editor.grid_size = new_value
            }

            if _, clicked := ui_push_label_button_with_icon(
                ui       = ui,
                id       = "undo",
                text     = "Undo",
                icon     = .Undo,
                slot     = ui_slot(&layout, 100),
                disabled = !editor_has_undo(scene),
            ); clicked {
                scene.frame_actions += {.Undo}
            }

            if _, clicked := ui_push_label_button_with_icon(
                ui       = ui,
                id       = "redo",
                text     = "Redo",
                icon     = .Redo,            
                slot     = ui_slot(&layout, 100),
                disabled = !editor_has_redo(scene),
            ); clicked {
                scene.frame_actions += {.Redo}
            }

            if new_value, changed := ui_push_combo_box(
                ui      = ui,
                id      = "add_platform",
                slot    = ui_slot(&layout, 150),
                options = [Platform_Type]string {
                    .Box   = "Box",
                    .Slope = "Slope",
                },
                value   = ctx.settings.editor.next_platform,
            ); changed {
                ctx.settings.editor.next_platform = new_value
            }

            if _, clicked := ui_push_label_button_with_icon(
                ui       = ui,
                id       = "add",
                text     = "Add",
                icon     = .Plus,
                slot     = ui_slot(&layout, 100),
            ); clicked {
                scene.frame_actions += { .Add }
            }
        }

        // Inspector
        if scene.selection.current != nil {
            inspector_rect, _ := ui_push_rect(
                ui     = ui,
                sizing = { INSPECTOR_WIDTH, Percent_Offset{1, -STATUS_BAR_HEIGHT}},
                anchor = { element = {1, 0}, parent = {1, 0} },
                color  = hsv(0, 0, .25),
            )
        
            ui_push_container(ui, inspector_rect)
            {
                defer ui_pop_container(ui)

                layout := ui_layout_begin(ui, .Vertical, pad = 8, gap = 8)

                platform := &scene.platforms[scene.selection.current.?]
                
                ui_push_layout_text(ui, &layout, fmt.tprintf("Index %03d", scene.selection.current.?))

                if new_value, changed := editor_property_vector3(
                    ui     = ui,
                    layout = &layout,
                    id     = "origin",
                    label  = "Origin",
                    value  = platform.origin,
                ); changed {
                    platform.origin = new_value
                    editor_push_snapshot(scene)
                }

                if new_value, changed := editor_property_vector3(
                    ui        = ui,
                    layout    = &layout,
                    id        = "size",
                    label     = "Size",
                    value  = platform.size,                    
                    min_value = MIN_PLATFORM_SIZE, 
                ); changed {
                    platform.size = new_value
                    editor_push_snapshot(scene)
                }

                if slope, ok := &platform.variant.(Platform_Slope); ok {
                    if new_value, changed := editor_property_slope_corner(
                        ui     = ui,
                        layout = &layout,
                        id     = "slope_corner",
                        label  = "Slope Corner",
                        value  = slope.corner
                    ); changed {
                        slope.corner = new_value
                        editor_push_snapshot(scene)
                    }
                }

                if _, clicked := ui_push_label_button_with_icon(
                    ui   = ui,
                    id   = "snap_to_grid",
                    text = "Snap to Grid",
                    icon = .Snap,
                    slot = ui_slot(&layout, 50),
                ); clicked {
                    snap_platform_to_grid(platform, ctx.settings.editor.grid_size)
                    editor_push_snapshot(scene)
                }

                if _, clicked := ui_push_label_button_with_icon(
                    ui   = ui,
                    id   = "reset_z",
                    text = "Reset Z",
                    icon = .Reset,
                    slot = ui_slot(&layout, 50),
                ); clicked {
                    platform.origin.z = 0
                    editor_push_snapshot(scene)
                }
            }
        }
        
                
    },
    update_3d = proc(scene : ^Scene_Editor, ctx : Game_Context, dt : f32) {
        get_move_plane_normal :: proc(scene : ^Scene_Editor) -> [3]f32 {
            return scene.free_cam.mode == .Perspective ? {0, 1, 0} : -scene.free_cam.mode_orthogonal.direction
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
                        ); hit && (dist < min_select_dist || (dist == min_select_dist && i == scene.selection.current)) {
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
            scene.input.focused_region =
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
            selected := scene.selection.current != nil && i == scene.selection.current.?
            if selected {
                if !scene.drag_state.face_extend.is_active && scene.input.modifiers[.Shift] == .Down {
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
                            scene.drag_state.face_extend = {
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
                if scene.drag_state.face_extend.is_active && ctx.mouse.state[.Left] == .Down {
                    ray_origin, ray_direction := viewport_get_mouse_world_ray(
                        ctx.viewport,
                        ctx.camera,
                        ctx.mouse.position
                    )

                    extend_direction := box_face_normals[scene.drag_state.face_extend.extend_face]

                    extend_distance, can_extend := ray_to_line(
                        ray_origin       = ray_origin,
                        ray_direction    = ray_direction,
                        line_point       = scene.drag_state.face_extend.extend_point,
                        line_direction   = box_face_normals[scene.drag_state.face_extend.extend_face],
                    )
                    extend_distance -= scene.drag_state.face_extend.initial_distance
                    scene.drag_state.face_extend.has_delta |= ctx.mouse.delta != 0

                    if can_extend {
                        min_size := MIN_PLATFORM_SIZE

                        extend_index   := box_face_normal_indices[scene.drag_state.face_extend.extend_face]
                        initial_origin := scene.drag_state.face_extend.initial_origin
                        initial_size   := scene.drag_state.face_extend.initial_size

                        if extend_direction[extend_index] > 0 {
                            current_face_pos := initial_origin[extend_index] + initial_size[extend_index] + extend_distance
                            if ctx.settings.editor.snap_to_grid {
                                current_face_pos = linalg.round(current_face_pos / ctx.settings.editor.grid_size) * ctx.settings.editor.grid_size
                            }
                            platform.origin = initial_origin
                            platform.size = initial_size
                            platform.size[extend_index] = max(min_size[extend_index], current_face_pos - initial_origin[extend_index])
                        } else {
                            fixed_opposite := initial_origin[extend_index] + initial_size[extend_index]
                            current_face_pos := initial_origin[extend_index] - extend_distance
                            if ctx.settings.editor.snap_to_grid {
                                current_face_pos = linalg.round(current_face_pos / ctx.settings.editor.grid_size) * ctx.settings.editor.grid_size
                            }
                            current_face_pos = min(current_face_pos, fixed_opposite - min_size[extend_index])
                            platform.origin = initial_origin
                            platform.origin[extend_index] = current_face_pos
                            platform.size = initial_size
                            platform.size[extend_index] = fixed_opposite - current_face_pos
                        }
                    }

                    // Draw current extending face
                    quad := get_box_quad_by_face(
                        box_origin = platform.origin,
                        box_size   = platform.size,
                        face       = scene.drag_state.face_extend.extend_face,
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

                if !scene.drag_state.face_extend.is_active {
                    hit := clicked_platform == scene.selection.current.?
                    hit |= ctx.mouse.state[.Left] == .Down && scene.selection.is_new
                    
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
                            scene.drag_state.move = {
                                is_active      = true,
                                initial_offset = point - platform.origin,
                                initial_origin = platform.origin,
                            }
                        }

                        if scene.input.modifiers[.Alt] == .Down {
                            if dist, ok := ray_to_line(
                                ray_origin     = ray_origin,
                                ray_direction  = ray_direction,
                                line_direction = {0, 1, 0}, 
                                line_point     = platform.origin, 
                            ); ok {
                                point := platform.origin + {0, 1, 0} * dist
                                
                                scene.drag_state.move.is_active      = true
                                scene.drag_state.move.vertical       = true
                                scene.drag_state.move.initial_height = point.y - platform.origin.y
                            }
                        }
                        
                    }
                }
                
                if scene.drag_state.move.is_active && ctx.mouse.state[.Left] == .Down {                    
                    ray_origin, ray_direction := viewport_get_mouse_world_ray(
                        viewport       = ctx.viewport,
                        camera         = ctx.camera,
                        mouse_position = ctx.mouse.position, 
                    )

                    if scene.input.modifiers[.Alt] != .Down {
                        scene.drag_state.move.vertical = false
                    }

                    if scene.input.modifiers[.Alt] == .Pressed || (scene.drag_state.move.vertical && scene.input.modifiers[.Alt] == .Down) {
                        if dist, ok := ray_to_line(
                            ray_origin      = ray_origin,
                            ray_direction   = ray_direction,
                            line_point      = platform.origin,
                            line_direction  = {0, 1, 0},
                        ); ok {
                            scene.drag_state.move.has_delta |= ctx.mouse.delta != 0
                            point := platform.origin + {0, 1, 0} * dist
                            if scene.input.modifiers[.Alt] == .Pressed {
                                scene.drag_state.move.vertical       = true
                                scene.drag_state.move.initial_height = point.y - platform.origin.y
                            } else {
                                platform.origin.y = point.y - scene.drag_state.move.initial_height
                                if ctx.settings.editor.snap_to_grid {
                                    platform.origin.y = linalg.round(platform.origin.y / ctx.settings.editor.grid_size) * ctx.settings.editor.grid_size
                                }
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
                            scene.drag_state.move.has_delta |= ctx.mouse.delta != 0
                            platform.origin = (1 - move_plane_normal) * (point - scene.drag_state.move.initial_offset) + 
                                platform.origin * move_plane_normal
                            if ctx.settings.editor.snap_to_grid {
                                platform.origin = linalg.round(platform.origin / ctx.settings.editor.grid_size) * ctx.settings.editor.grid_size
                            }
                            if ctx.settings.editor.lock_z {
                                platform.origin.z = scene.drag_state.move.initial_origin.z
                            }
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

        finish_hold_state :: proc(scene : ^Scene_Editor, ctx : Game_Context) {
            if scene.drag_state.face_extend.is_active {
                if scene.drag_state.face_extend.has_delta {
                    editor_push_snapshot(scene, skip_time_check = true)
                }
                scene.drag_state.face_extend = {}
            }
            if scene.drag_state.move.is_active {
                if scene.drag_state.move.has_delta {
                    editor_push_snapshot(scene, skip_time_check = true)
                }
                scene.drag_state.move = {}
            }
        }

        has_hold_state :: proc(scene : ^Scene_Editor, ctx : Game_Context) -> bool {
            return scene.drag_state.face_extend.is_active || scene.drag_state.move.is_active
        }

        if ctx.mouse.state[.Left] == .Released && scene.input.focused_region == .Region_3D {
            finish_hold_state(scene, ctx)
        }

        if clicked_on_3d && !has_hold_state(scene, ctx) {
            if clicked_platform < 0 {
                pending_action_clear(&scene.selection.pending)
            } else {
                pending_action_set(&scene.selection.pending, &scene.selection.current, clicked_platform)
            }
        }

        free_camera_update_3d(&scene.free_cam, ctx, dt)

        end_of_frame : {
            push_snapshot := false

            // Update modifiers
            for &state in scene.input.modifiers {
                if state == .Pressed {
                    state = .Down
                } else if state == .Released {
                    state = .None
                }
            }

            // Running actions, undo, redo and delete are exclusive of each other at the moment
            // Undo redo
            if .Undo in scene.frame_actions {
                editor_undo(scene)
            } else if .Redo in scene.frame_actions {
                editor_redo(scene)
            } else
            // Handle deletion
            if .Delete in scene.frame_actions {
                if selected_index, ok := scene.selection.current.?; ok {
                    unordered_remove(&scene.platforms, scene.selection.current.?)
                    pending_action_clear(&scene.selection.pending, forced = true)
                    // This would change selection so undo push will do after selection is resolved
                    push_snapshot = true
                }
            } else
            // Handle adding
            if .Add in scene.frame_actions {
                spawn_position : [3]f32   
                if scene.selection.current != nil {
                    spawn_position = scene.platforms[scene.selection.current.?].origin +
                        {0, scene.platforms[scene.selection.current.?].size.y, 0}
                }
                switch ctx.settings.editor.next_platform {
                    case .Box:
                        append(&scene.platforms, {
                            origin  = spawn_position,
                            size    = 1,
                            variant = Platform_Box {},
                        })
                    case .Slope:
                        append(&scene.platforms, {
                            origin  = spawn_position,
                            size    = 1,
                            variant = Platform_Slope {
                                corner = .Bottom_Left,
                            }
                        })
                }
                // We can technically push snapshot directly now but let go with a standard
                push_snapshot = true
            } else
            // Handle duplication
            if .Duplicate in scene.frame_actions {
                if selected_index, ok := scene.selection.current.?; ok {
                    duplicate_offset : [3]f32 : {0, 0, 0}
                    
                    platform := scene.platforms[selected_index]
                    platform.origin += duplicate_offset
                    scene.frame_actions += { .Duplicate }
                    append(&scene.platforms, platform)
                    pending_action_set(&scene.selection.pending, &scene.selection.current, len(scene.platforms) - 1)
                }
            } else
            // Handle saving
            if .Save in scene.frame_actions {
                scene.undo.saved_index = scene.undo.stack_current
                editor_save_map(scene)
            }

            // Handle new selection
            if selection_changed := pending_resolve(&scene.selection.pending, &scene.selection.current);
                selection_changed && scene.selection.current != nil {
                scene.selection.is_new = true
                finish_hold_state(scene, ctx)
                // It's not worth wasting memory to save undo snapshot with only the selection change
            } else {
                scene.selection.is_new = false
            }

            if push_snapshot {
                editor_push_snapshot(scene)
            }
            
            scene.frame_actions = {}
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
                    scene.input.modifiers[.Shift] = state
                case .LEFT_CONTROL, .RIGHT_CONTROL:
                    scene.input.modifiers[.Ctrl]  = state
                case .LEFT_ALT, .RIGHT_ALT:
                    scene.input.modifiers[.Alt]   = state
            }
        }

        ctrl  := ev.modifiers & sapp.MODIFIER_CTRL  != 0
        shift := ev.modifiers & sapp.MODIFIER_SHIFT != 0

        if ctrl && ev.type == .KEY_UP && ev.key_code == .D {
            scene.frame_actions += { .Duplicate }
        }

        if ctrl && ev.type == .KEY_DOWN && ev.key_code == .Z {
            scene.frame_actions += shift ? { .Redo } : { .Undo }
        }

        if (ev.type == .KEY_UP && ev.key_code == .DELETE) || (ctrl && ev.type == .KEY_UP && ev.key_code == .X)
        {
            scene.frame_actions += { .Delete }
        }

        if ev.type == .KEY_DOWN && ev.key_code == .V {
            free_cam := &scene.free_cam
            if free_cam.mode == .Perspective {
                free_cam.mode = .Orthogonal
                if (free_cam.camera.target - free_cam.camera.position).z < 0 {
                    free_cam.mode_orthogonal.direction = { 0, 0, -1}
                } else {
                    free_cam.mode_orthogonal.direction = { 0, 0, 1}
                }
                free_cam.mode_orthogonal.position.z = -free_cam.mode_orthogonal.direction.z * 10
            
                if scene.selection.current != nil {
                    selected := scene.platforms[scene.selection.current.?]
                    centroid := selected.origin + selected.size * .5
                    free_cam.mode_orthogonal.position.xy = centroid.xy
                } else {
                    centroid : [3]f32
                    for &p in scene.platforms {
                        centroid += p.origin + p.size * .5
                    }
                    if len(scene.platforms) > 0 {
                        centroid /= cast(f32)len(scene.platforms)
                    }
                    free_cam.mode_orthogonal.position.xy = centroid.xy
                }
            } else {
                free_cam.mode = .Perspective
            }
        }

        if ctrl && ev.type == .KEY_DOWN && ev.key_code == .S {
            scene.frame_actions += { .Save }
        }

        if shift && ev.type == .KEY_DOWN && ev.key_code == .A {
            scene.frame_actions += { .Add }
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
    layout : ^Ui_Layout,
    id     : Ui_Id,
    label  : string,
    value  : Slope_Corner,
) -> (new_value : Slope_Corner, changed : bool) {
    ui_push_layout_text(ui, layout, label)

    new_value, changed = ui_push_combo_box(
        ui      = ui,
        id      = id,
        value   = value,
        slot    = ui_slot(layout, 42),
        options = [Slope_Corner]string {
            .Bottom_Left  = "Bottom Left",
            .Bottom_Right = "Bottom Right",
            .Top_Left     = "Top Left",
            .Top_Right    = "Top Right",
        },
    )
    
    return 
}

editor_property_vector3 :: proc(
    ui        : ^Ui,
    layout    : ^Ui_Layout,
    id        : Ui_Id,
    label     : string,
    value     : [3]f32,
    min_value : Maybe([3]f32) = nil,
) -> (new_value : [3]f32, changed : bool) {
    new_value = value

    ui_push_layout_text(ui, layout, label)

    axis_labels   : [3]string = {"X", "Y", "Z"}
    axis_suffixes : [3]string = {"x", "y", "z"}
    axis_colors   : [3]f32    = {332, 100, 200}

    for i in 0..<3 {
        text_id := fmt.tprintf("%v:%s", id, axis_suffixes[i])
        up_id   := fmt.tprintf("%v:%s:up", id, axis_suffixes[i])
        down_id := fmt.tprintf("%v:%s:down", id, axis_suffixes[i])

        if new_field_value, field_value_changed := ui_push_spinner(
            ui              = ui,
            id              = text_id,
            up_control_id   = up_id,
            down_control_id = down_id,
            label           = axis_labels[i],
            value           = value[i],
            step            = .01,
            slot            = ui_slot(layout, 42),
            min_val         = min_value != nil ? min_value.?[0] : nil,
            label_color     = hsv(axis_colors[i]),
        ); field_value_changed {
            changed = true
            new_value[i] = new_field_value
        }
    }

    return
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
        return
    }
    t := linalg.dot(plane_point - ray_origin, plane_normal) / linalg.dot(ray_direction, plane_normal)
    if t < 0 do return
    return ray_origin + t * ray_direction, true
}

snap_platform_to_grid :: proc(platform : ^Platform, grid_unit : f32) {
    platform.origin = linalg.round(platform.origin / grid_unit) * grid_unit
    platform.size   = linalg.round(platform.size / grid_unit) * grid_unit
    platform.size   = linalg.max(platform.size, MIN_PLATFORM_SIZE)
}

editor_exit :: proc() {
    game_save_settings() 
}


editor_save_map :: proc(scene : ^Scene_Editor, allocator := context.allocator) {
    if !os.exists(MAP_DIR) {
        err := os.make_directory_all(MAP_DIR)
        if err != nil {
            fmt.eprintfln("Cannot create directory %v for save file", MAP_DIR)
            return
        }
    }

    map_data, marshal_err := json.marshal(
        scene.undo.stack[scene.undo.stack_current],
        {
            use_enum_names = true,
            pretty         = true,
        },
        allocator = allocator,
    )
    defer delete(map_data, allocator)

    if marshal_err != nil {
        fmt.eprintfln("Error marshalling editor map: %v", marshal_err)
    } else {
        save_err := os.write_entire_file(MAP_FILE_PATH, map_data)
        if save_err != nil {
            fmt.eprintfln("Error saving editor map: %v", save_err)
        }
    }
}

editor_load_map :: proc(scene : ^Scene_Editor, snapshot_allocator : runtime.Allocator, load_allocator := context.allocator) {
    if !os.exists(MAP_FILE_PATH) {
        panic("Map file doesn't exist!")
    }

    map_data, load_err := os.read_entire_file(MAP_FILE_PATH, allocator = load_allocator)
    defer delete(map_data, load_allocator)

    snapshot : Editor_Snapshot

    if load_err != nil {
        fmt.eprintfln("Error loading editor map: %v", load_err)
        return
    }

    // Must use the snapshot alloctor here (i guess) since the destroyer assumps it 
    unmarshal_err := json.unmarshal(map_data, &snapshot, allocator = snapshot_allocator)

    if unmarshal_err != nil {
        fmt.eprintfln("Error unmarshalling editor map: %v", unmarshal_err)
        return
    }

    editor_restore_snapshot(scene, snapshot, skip_selection_pending = true)
}
