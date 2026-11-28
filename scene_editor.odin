package main

import "core:os"
import "base:runtime"
import "core:fmt"
import "core:time"
import "core:slice"
import "core:math/linalg"
import "core:math"
import "base:intrinsics"
import sapp "sokol-odin/sokol/app"

INSPECTOR_WIDTH         :: 250
STATUS_BAR_HEIGHT       :: 50
UNDO_TIMEOUT            :: 300 * time.Millisecond
SAVED_MARKER_TIMEOUT    :: 1   * time.Second
DUPLICATE_NOTIF_TIMEOUT :: 1   * time.Second
UNDO_MAX_STEPS          :: 24

MAP_DIR       :: "."
MAP_FILE      :: "map.pbmp"
MAP_FILE_PATH := MAP_DIR + "/" + MAP_FILE

// Stole from ravn scene saving
MAP_SAVE_MAGIC   :: (u32('p') << 0) | (u32('b') << 8) | (u32('m') << 16) | (u32('p') << 24)
MAP_SAVE_VERSION :: 0

Range :: struct {
    offset : u32,
    length : u32,
}

Editor_Map_Save_Header :: struct {
    magic     : u32,
    version   : u32,

    platforms : Range,
    free_cam  : Free_Camera,
    selection : struct {
        set    : Range,
        leader : Maybe(i32),
    },
}

Editor_Map_Save :: struct {
    platforms : []Platform,
    free_cam  : Free_Camera,
    selection : struct {
        set    : []i32,
        leader : Maybe(i32) 
    },
}

Editor_View_Mode :: enum {
    Perspective,
    Ortho_Front,
    Ortho_Back,
}  

Editor_Snapshot :: struct {
    platforms : []Platform,
    selection : struct {
        set    : []i32,
        leader : Maybe(i32),
    }
}

Editor_Region :: enum u8 {
    Region_3D,
    Region_Ui,
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
    Delete_All,
    Select_All,
}

Editor_Settings :: struct {
    grid_size      : f32,
    view_mode      : Editor_View_Mode,
    next_platform  : Platform_Type,
    lock_z         : bool,
    snap_to_grid   : bool,
}

DEFAULT_EDITOR_SETTINGS : Editor_Settings : {
    grid_size     = .125,
    view_mode     = .Perspective,
    next_platform = .Box,
    lock_z        = true,
    snap_to_grid  = true,
}

Face_Extend_Target :: struct {
    initial_origin   : [3]f32,
    initial_size     : [3]f32,
    index            : i32,
}

Scene_Editor :: struct {
    debug_draw        : Debug_Draw, 
    free_cam          : Free_Camera,
    platforms         : [dynamic]Platform,

    selection : struct {
        set         : [dynamic]i32,
        leader      : Maybe(i32),
        new_counter : i8,
    },

    input : struct {
        modifiers      : [Editor_Modifer_Key]Editor_Modifer_Key_State,
        focused_region : Editor_Region,
    },

    drag_state : struct {
        data : struct {
            face_extend_targets : [dynamic]Face_Extend_Target,
        },

        face_extend : struct {
            targets           : []Face_Extend_Target,
            initial_distance  : f32,
            extend_face       : Box_Face,
            extend_point      : [3]f32,
            leader            : i32,

            is_active         : bool,
            has_delta         : bool,
        },
        move: struct {
            initial_offset   : [3]f32,
            initial_height   : f32,
            // vertical         : bool,
            is_active        : bool,
            has_delta        : bool,
        },
    },

    undo : struct {
        stack              : [UNDO_MAX_STEPS]Editor_Snapshot,
        snapshot_allocator : runtime.Allocator,
        last_undo_time     : time.Tick,
        stack_current      : int,
        stack_max          : int,
        saved_index        : int,
    },

    last_save_time      : time.Tick, 
    last_dup_time : time.Tick, 
    last_dup_count      : i32, 
    frame_actions       : bit_set[Editor_Frame_Action; u16],
}

editor_selection_contains :: proc(scene : ^Scene_Editor, index : i32) -> bool {
    for sel_index in scene.selection.set {
        if sel_index == index do return true
    }
    return false
}

editor_selection_clear :: proc(scene : ^Scene_Editor) {
    clear(&scene.selection.set)
    scene.selection.leader = nil
}

editor_selection_changed :: proc(scene : ^Scene_Editor) -> bool {
    return scene.selection.new_counter == 1
}

editor_selection_toggle :: proc(scene : ^Scene_Editor, index : i32) {
    for sel_index, set_index in scene.selection.set {
        if sel_index == index {
            unordered_remove(&scene.selection.set, set_index)
            // if delete the leader move the leader index elsewhere 
            if sel_index == scene.selection.leader {
                scene.selection.leader = len(scene.selection.set) == 0 ? nil : scene.selection.set[0]
            }
            return
        }
    }
    append(&scene.selection.set, index)
    if len(scene.selection.set) == 1 {
        scene.selection.leader = index
    }

    scene.selection.new_counter = 2
}

editor_selection_select_all :: proc(scene : ^Scene_Editor) {
    if len(scene.platforms) == 0 do return

    prev_leader := scene.selection.leader
    editor_selection_clear(scene)
    for _, index in scene.platforms {
        append(&scene.selection.set, i32(index))
    }
    if prev_leader != nil {
        scene.selection.leader = prev_leader
    } else {
        scene.selection.leader = scene.selection.set[0]
    }

    scene.selection.new_counter = 2
}

editor_undo_init :: proc(scene : ^Scene_Editor, snapshot_allocator : runtime.Allocator) {
    scene.undo.stack_current      = -1
    scene.undo.saved_index        = 0
    scene.undo.snapshot_allocator = snapshot_allocator
    editor_push_snapshot(scene, skip_time_check = true)
}

editor_snapshot_make :: proc(scene : ^Scene_Editor) -> Editor_Snapshot {
    return {
        platforms = slice.clone(scene.platforms[:],     allocator = scene.undo.snapshot_allocator),
        selection =  {
            set    = slice.clone(scene.selection.set[:], allocator = scene.undo.snapshot_allocator),
            leader = scene.selection.leader,
        }
    }
}

editor_push_snapshot :: proc(scene : ^Scene_Editor, skip_time_check := false) {
    if !skip_time_check && time.tick_diff(scene.undo.last_undo_time, time.tick_now()) <= UNDO_TIMEOUT {
        return
    }
    snapshot := editor_snapshot_make(scene)

    scene.undo.stack_current += 1
    scene.undo.stack_max = scene.undo.stack_current

    resolved_index := scene.undo.stack_current % len(scene.undo.stack)
    editor_destroy_snapshot(scene.undo.stack[resolved_index], allocator = scene.undo.snapshot_allocator)

    scene.undo.stack[resolved_index] = snapshot
    scene.undo.last_undo_time = time.tick_now()
}

editor_restore_snapshot :: proc(scene : ^Scene_Editor, snapshot : Editor_Snapshot, loc := #caller_location) {
    delete(scene.platforms)
    delete(scene.selection.set)

    scene.platforms        = slice.clone_to_dynamic(snapshot.platforms,     allocator = context.allocator)
    scene.selection.set    = slice.clone_to_dynamic(snapshot.selection.set, allocator = context.allocator)
    scene.selection.leader = snapshot.selection.leader 
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

        snapshot_allocator := context.allocator
        editor_load_map(scene, ctx)
        editor_undo_init(scene, snapshot_allocator = snapshot_allocator)
        
        scene.drag_state.data.face_extend_targets = make([dynamic]Face_Extend_Target, allocator = context.allocator)
    },
    destroy = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        debug_draw_destroy(&scene.debug_draw)        
        delete(scene.platforms)
        for &snapshot in scene.undo.stack {
            editor_destroy_snapshot(snapshot, allocator = scene.undo.snapshot_allocator)
        }
        delete(scene.selection.set)
        delete(scene.drag_state.data.face_extend_targets)

        editor_exit()
    },
    update_ui = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        ui := ctx.ui

        show_inspector := len(scene.selection.set) == 1

        // FPS counter
        ui_push_text(
            ui     = ui,
            text   = fmt.tprintf("FPS: % 4.f", ctx.frame_time.average_fps),
            anchor = {
                element = {1, 0},
                parent  = {1, 0},
                offset = { (show_inspector ? -INSPECTOR_WIDTH : 0) - 16, 0}
            } 
        )

        // Save/Dirty marker
        if scene.undo.saved_index != scene.undo.stack_current {
            ui_push_text(
                ui     = ui,
                text   = "*Unsaved",
                anchor = { offset = { 8, 0} }
            )
        } else if time.tick_diff(scene.last_save_time, time.tick_now()) < SAVED_MARKER_TIMEOUT {
            ui_push_text(
                ui     = ui,
                text   = "Saved!",
                anchor = { offset = { 8, 0} },
            )
        }

        if time.tick_diff(scene.last_dup_time, time.tick_now()) < DUPLICATE_NOTIF_TIMEOUT {
            ui_push_text(
                ui     = ui,
                text   = fmt.tprintf("Duplicated %v %v", scene.last_dup_count, scene.last_dup_count > 1 ? "items" : "item"),
                anchor = { offset = { 8, 32 } },
            )
        }

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
                editor_switch_view_mode(scene, ctx, new_value)
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
        if show_inspector {
            current_selection := scene.selection.set[0]

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

                platform := &scene.platforms[current_selection]
                
                ui_push_layout_text(ui, &layout, fmt.tprintf("Index %03d", current_selection))

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
        get_platform_under_cursor :: proc(scene : ^Scene_Editor, ctx : Game_Context) -> (index: Maybe(i32)) {
            ray_origin, ray_direction := viewport_get_mouse_world_ray(
                ctx.viewport,
                ctx.camera,
                ctx.mouse.position
            )

            min_select_dist : f32        = max(f32)
            closest_index   : Maybe(i32) = nil
            
            for &platform, i in scene.platforms {
                switch &variant in platform.variant {
                    case Platform_Box:
                        if dist, _, hit := ray_box_intersect(
                            ray_origin    = ray_origin,
                            ray_direction = ray_direction,
                            box_origin    = platform.origin,
                            box_size      = platform.size,
                        ); hit && (dist < min_select_dist || (dist == min_select_dist && editor_selection_contains(scene, i32(i)))) {
                            min_select_dist = dist
                            closest_index   = i32(i)
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
                            closest_index   = i32(i)
                        }
                }
            }

            return closest_index    
        }

        debug_draw_begin(&scene.debug_draw)

        clicked_platform : Maybe(i32) = nil 
        clicked_on_3d    : bool       = false

        if ctx.mouse.state[.Left] == .Pressed && editor_is_position_in_3d_region(ctx, ctx.mouse.position) {
            clicked_on_3d              = true
            scene.input.focused_region = editor_is_position_in_3d_region(ctx, ctx.mouse.position) ? .Region_3D : .Region_Ui
            clicked_platform           = get_platform_under_cursor(scene, ctx)  
        }

        debug_draw_push_grid(
            draw       = &scene.debug_draw,
            unit       = 1,
            size       = 50,
            axis_color = hsv(145, .8, .5), 
            sub_color  = hsv(0, 0, .2), 
            planes     = editor_get_grid_axis(ctx),
        )

        for &platform, i in scene.platforms {
            selected := editor_selection_contains(scene, i32(i))

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

        editor_drag_state_update(scene, ctx, clicked_platform, clicked_on_3d)

        if ctx.mouse.state[.Left] == .Released && scene.input.focused_region == .Region_3D {
            editor_drag_state_finish(scene, ctx)
        }

        if clicked_on_3d && !editor_drag_state_active(scene, ctx) {
            if index, ok := clicked_platform.?; ok {
                if scene.input.modifiers[.Ctrl] != .Down {
                    editor_selection_clear(scene)
                }
                editor_selection_toggle(scene, index)
            } else {
                editor_selection_clear(scene)
            }
        }

        free_camera_update_3d(&scene.free_cam, ctx, dt)
    },
    draw_3d = proc(scene : ^Scene_Editor, ctx : Game_Context, renderer : ^Renderer) {
        debug_draw_3d(&scene.debug_draw, renderer)
    },
    end_frame = proc(scene : ^Scene_Editor, ctx : Game_Context) {
        // Whether we should add an undo snapshot in end of frame or not
        push_snapshot := false

        // Update modifiers
        for &state in scene.input.modifiers {
            if state == .Pressed {
                state = .Down
            } else if state == .Released {
                state = .None
            }
        }

        // Running actions, undo, redo, delete, etc. are exclusive of each other at the moment
        // Undo redo
        if .Undo in scene.frame_actions {
            editor_undo(scene)
        } else if .Redo in scene.frame_actions {
            editor_redo(scene)
        } else
        // Handle deletion
        if .Delete in scene.frame_actions && len(scene.selection.set) > 0 {
            slice.reverse_sort(scene.selection.set[:])
            for index in scene.selection.set {
                unordered_remove(&scene.platforms, index)
            }
            editor_selection_clear(scene)
            push_snapshot = true
        } else
        // Handle deleting all platforms
        if .Delete_All in scene.frame_actions {
            clear(&scene.platforms)
            editor_selection_clear(scene)
            push_snapshot = true
        } else
        // Handle adding
        if .Add in scene.frame_actions {
            spawn_position : [3]f32 = 0
            spawn_size     : [3]f32 : 1

            if len(scene.selection.set) > 0 {
                spawn_position = min(f32)
                // find highest point above current selection set as a spawn point 
                for index in scene.selection.set {
                    point := scene.platforms[index].origin + scene.platforms[index].size
                    if point.y > spawn_position.y {
                        spawn_position = point
                    }
                }
                spawn_position.xz -= spawn_size.xz                                
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
        if .Duplicate in scene.frame_actions && len(scene.selection.set) > 0 {
            prev_leader := scene.selection.leader.?
            prev_leader_set_index := -1
            // Loop through all of the selected platforms, duplicate them in place and then select them
            for index, i in scene.selection.set {
                append(&scene.platforms, scene.platforms[index])
                scene.selection.set[i] = cast(i32)len(scene.platforms) - 1
                if index == prev_leader {
                    prev_leader_set_index  = i 
                }
            }
            scene.selection.leader = scene.selection.set[prev_leader_set_index] 
            
            scene.last_dup_count  = cast(i32)len(scene.selection.set)
            scene.last_dup_time   = time.tick_now()
            
            push_snapshot = true
        } else
        // Handle special selection
        if .Select_All in scene.frame_actions {
            editor_selection_select_all(scene)
        } else
        // Handle saving
        if .Save in scene.frame_actions {
            scene.undo.saved_index = scene.undo.stack_current
            editor_save_map(scene)
        }

        // Selection now resolve directly
        if push_snapshot {
            editor_push_snapshot(scene)
        }
        
        scene.selection.new_counter    -= 1
        if scene.selection.new_counter < 0 {
            scene.selection.new_counter = 0
        }

        scene.frame_actions = {}
    },
    input_ui  =  proc(scene : ^Scene_Editor, ctx : Game_Context, ev : sapp.Event) {
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
            view_mode := ctx.settings.editor.view_mode
            if view_mode == .Perspective {
                if (ctx.camera.target - ctx.camera.position).z < 0 {
                    view_mode = .Ortho_Front
                } else {
                    view_mode = .Ortho_Back
                }
            } else {
                view_mode = .Perspective
            }
            editor_switch_view_mode(scene, ctx, view_mode)
        }

        if ctrl && ev.type == .KEY_DOWN && ev.key_code == .S {
            scene.frame_actions += { .Save }
        }

        if ctrl && ev.type == .KEY_DOWN && ev.key_code == .A {
            scene.frame_actions += { .Add } if shift else { .Select_All } 
        }

        if ctrl && shift && ev.type == .KEY_DOWN && ev.key_code == .DELETE {
            scene.frame_actions += { .Delete_All }
        }

        free_camera_input(&scene.free_cam, ev)
    },
}

editor_switch_view_mode :: proc(scene : ^Scene_Editor, ctx : Game_Context, view_mode : Editor_View_Mode) {
    switch view_mode {
        case .Ortho_Back, .Ortho_Front:
            dir : f32 = view_mode == .Ortho_Front ? -1 : 1
            scene.free_cam.mode = .Orthogonal
            scene.free_cam.mode_orthogonal.direction = { 0, 0, dir}
            scene.free_cam.mode_orthogonal.position.z  = -dir * 10
            scene.free_cam.mode_orthogonal.position.xy = get_centroid_of_platforms(scene.platforms[:], scene.selection.set[:]).xy            
        case .Perspective:
            scene.free_cam.mode = .Perspective
    }
    ctx.settings.editor.view_mode = view_mode
}

editor_drag_state_update :: proc(scene : ^Scene_Editor, ctx : Game_Context, clicked_platform : Maybe(i32), clicked_on_3d : bool) {
    if len(scene.selection.set)   == 0 {
        return
    }

    // Face extend check 
    if !scene.drag_state.face_extend.is_active && scene.input.modifiers[.Shift] == .Down {
        ray_origin, ray_direction := viewport_get_mouse_world_ray(
            ctx.viewport,
            ctx.camera,
            ctx.mouse.position
        )

        lead_index, lead_face := pick_box_face_multi(
            ray_origin    = ray_origin,
            ray_direction = ray_direction,
            platforms     = scene.platforms[:],
            indices       = scene.selection.set[:],
        )

        clear(&scene.drag_state.data.face_extend_targets)

        pick_face_extend_targets(
            lead_index = lead_index, 
            lead_face  = lead_face,

            platforms  = scene.platforms[:],
            indices    = scene.selection.set[:],
        
            targets    = &scene.drag_state.data.face_extend_targets,  
        )

        lead_face_center : [3]f32
        for target in scene.drag_state.data.face_extend_targets {
            quad := get_box_quad_by_face(
                box_origin = scene.platforms[target.index].origin,
                box_size   = scene.platforms[target.index].size,
                face       = lead_face,
                offset     = .01
            )
            
            if target.index == lead_index {
                lead_face_center = (quad[0] + quad[1] + quad[2] + quad[3]) / 4
            }
        
            debug_draw_push_quad(
                draw    = &scene.debug_draw,
                points  = quad,
                color   = hsv(40),
                overlay = true,
            )
        }

        if clicked_on_3d {
            if dist, ok := ray_to_line(
                ray_origin     = ray_origin,
                ray_direction  = ray_direction,
                line_point     = lead_face_center,
                line_direction = box_face_normals[lead_face],
            ); ok {
                scene.drag_state.face_extend = {
                    is_active        = true,
                    initial_distance = dist,
                    extend_face      = lead_face,
                    extend_point     = lead_face_center,
                    targets          = scene.drag_state.data.face_extend_targets[:],
                }
            }
        }
    }

    
    // Face extend run
    if scene.drag_state.face_extend.is_active && ctx.mouse.state[.Left] == .Down {
        // Draw current extending faces
        for target in scene.drag_state.face_extend.targets {
            quad := get_box_quad_by_face(
                box_origin = scene.platforms[target.index].origin,
                box_size   = scene.platforms[target.index].size,
                face       = scene.drag_state.face_extend.extend_face,
                offset     = .01
            )
            
            debug_draw_push_quad(
                draw    = &scene.debug_draw,
                points  = quad,
                color   = hsv(50),
                overlay = true,
            )
        }

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

        if can_extend {
            min_size := MIN_PLATFORM_SIZE

            extend_index := box_face_normal_indices[scene.drag_state.face_extend.extend_face]
            
            for target in scene.drag_state.face_extend.targets {
                initial_origin := target.initial_origin
                initial_size   := target.initial_size

                platform       := &scene.platforms[target.index]
                prev_origin    := platform.origin
                prev_size      := platform.size

                if extend_direction[extend_index] > 0 {
                    current_face_pos := initial_origin[extend_index] + initial_size[extend_index] + extend_distance
                    if ctx.settings.editor.snap_to_grid {
                        current_face_pos = linalg.round(current_face_pos / ctx.settings.editor.grid_size) * ctx.settings.editor.grid_size
                    }
                    platform.origin = initial_origin
                    platform.size   = initial_size
                    platform.size[extend_index] = max(min_size[extend_index], current_face_pos - initial_origin[extend_index])
                } else {
                    fixed_opposite   := initial_origin[extend_index] + initial_size[extend_index]
                    current_face_pos := initial_origin[extend_index] - extend_distance
                    if ctx.settings.editor.snap_to_grid {
                        current_face_pos = linalg.round(current_face_pos / ctx.settings.editor.grid_size) * ctx.settings.editor.grid_size
                    }
                    current_face_pos = min(current_face_pos, fixed_opposite - min_size[extend_index])
                    platform.origin  = initial_origin
                    platform.origin[extend_index] = current_face_pos
                    platform.size = initial_size
                    platform.size[extend_index] = fixed_opposite - current_face_pos
                }

                // We don't compare to initial values here to match move state behavior, move state doesn't save intial values, just offsets
                scene.drag_state.face_extend.has_delta |= platform.origin != prev_origin || platform.size != prev_size
            }
        }
    }
    

    // Move check
    get_move_plane_normal :: proc(scene : ^Scene_Editor) -> [3]f32 {
        return scene.free_cam.mode == .Perspective ? {0, 1, 0} : -scene.free_cam.mode_orthogonal.direction
    }

    get_lowest_in_selection :: proc(scene : ^Scene_Editor) -> i32 {
        lowest_origin : [3]f32 = max(f32)
        lowest_index  : i32    = 0
        for index in scene.selection.set {
            if scene.platforms[index].origin.y < lowest_origin.y {
                lowest_origin = scene.platforms[index].origin
                lowest_index  = index
            }
        }
        return lowest_index
    }

    mouse_on_selection := clicked_platform != nil && editor_selection_contains(scene, clicked_platform.?) ||
        (ctx.mouse.state[.Left] == .Down && editor_selection_changed(scene))

    if !scene.drag_state.move.is_active && !scene.drag_state.face_extend.is_active && len(scene.selection.set) > 0 && mouse_on_selection {
        ray_origin, ray_direction := viewport_get_mouse_world_ray(
            ctx.viewport,
            ctx.camera,
            ctx.mouse.position
        )

        lowest_origin := scene.platforms[get_lowest_in_selection(scene)].origin

        if point, ok := ray_plane_intersect(
            ray_origin    = ray_origin,
            ray_direction = ray_direction,
            plane_normal  = get_move_plane_normal(scene), 
            plane_point   = lowest_origin, 
        ); ok {
            scene.drag_state.move = {
                is_active      = true,
                initial_offset = point - lowest_origin,
            }
        }

        if scene.input.modifiers[.Alt] == .Down {
            if dist, ok := ray_to_line(
                ray_origin     = ray_origin,
                ray_direction  = ray_direction,
                line_direction = {0, 1, 0}, 
                line_point     = lowest_origin, 
            ); ok {
                point := lowest_origin + {0, 1, 0} * dist
                
                scene.drag_state.move.is_active      = true
                scene.drag_state.move.initial_height = point.y - lowest_origin.y
            }
        }
    }

    
    // Move run
    if scene.drag_state.move.is_active && ctx.mouse.state[.Left] == .Down {                 
        ray_origin, ray_direction := viewport_get_mouse_world_ray(
            viewport       = ctx.viewport,
            camera         = ctx.camera,
            mouse_position = ctx.mouse.position, 
        )

        lowest_index := get_lowest_in_selection(scene)

        if scene.input.modifiers[.Alt] == .Pressed || scene.input.modifiers[.Alt] == .Down {
            if dist, ok := ray_to_line(
                ray_origin      = ray_origin,
                ray_direction   = ray_direction,
                line_point      = scene.platforms[lowest_index].origin,
                line_direction  = {0, 1, 0},
            ); ok {
                base_platform := &scene.platforms[lowest_index]
                prev_origin   := base_platform.origin
                move_vector   := base_platform.origin + {0, 1, 0} * dist

                if scene.input.modifiers[.Alt] == .Pressed {
                    scene.drag_state.move.initial_height = move_vector.y - base_platform.origin.y
                }
                else {
                    base_platform.origin.y = move_vector.y - scene.drag_state.move.initial_height
                    if ctx.settings.editor.snap_to_grid {
                        base_platform.origin.y = linalg.round(base_platform.origin.y / ctx.settings.editor.grid_size) * ctx.settings.editor.grid_size
                    }
                }

                delta := base_platform.origin - prev_origin
                
                scene.drag_state.move.has_delta |= delta != 0

                for index in scene.selection.set do if index != lowest_index {
                    scene.platforms[index].origin += delta
                }
            }
        } else {
            if (scene.input.modifiers[.Alt] == .Released) {
                if point, ok := ray_plane_intersect(
                    ray_origin    = ray_origin,
                    ray_direction = ray_direction,
                    plane_normal  = get_move_plane_normal(scene), 
                    plane_point   = scene.platforms[lowest_index].origin, 
                ); ok {
                    scene.drag_state.move.initial_offset = point - scene.platforms[lowest_index].origin
                }
            }

            move_plane_normal := get_move_plane_normal(scene)
            if point, ok := ray_plane_intersect(
                ray_origin    = ray_origin,
                ray_direction = ray_direction,
                plane_normal  = move_plane_normal, 
                plane_point   = scene.platforms[lowest_index].origin, 
            ); ok {
                base_platform := &scene.platforms[lowest_index]
                prev_origin   := base_platform.origin
                
                base_platform.origin = (1 - move_plane_normal) * (point - scene.drag_state.move.initial_offset) + base_platform.origin * move_plane_normal
                
                if ctx.settings.editor.snap_to_grid {
                    base_platform.origin = linalg.round(base_platform.origin / ctx.settings.editor.grid_size) * ctx.settings.editor.grid_size
                }
                if ctx.settings.editor.lock_z {
                    base_platform.origin.z = prev_origin.z
                }

                delta := base_platform.origin - prev_origin

                scene.drag_state.move.has_delta |= delta != 0

                for index in scene.selection.set do if index != lowest_index {
                    scene.platforms[index].origin += delta
                }
            }
        }
    }
    
}

editor_drag_state_finish :: proc(scene : ^Scene_Editor, ctx : Game_Context) {
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

editor_drag_state_active :: proc(scene : ^Scene_Editor, ctx : Game_Context) -> bool {
    return scene.drag_state.face_extend.is_active || scene.drag_state.move.is_active
}

editor_is_position_in_3d_region :: proc(ctx: Game_Context, position : [2]f32) -> bool {
    return position.x < ctx.viewport.base_size.x - INSPECTOR_WIDTH &&
        position.y < ctx.viewport.base_size.y - STATUS_BAR_HEIGHT
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

    header := Editor_Map_Save_Header {
        magic     = MAP_SAVE_MAGIC,
        version   = MAP_SAVE_VERSION,
        free_cam  = scene.free_cam,
        platforms = Range{},
        selection = {
            leader = scene.selection.leader,
            set    = Range{},
        }
    }

    offset := cast(u32)size_of(header)

    platforms_bytes      := slice.to_bytes(scene.platforms[:])
    header.platforms      = Range{ offset = offset, length = cast(u32)len(platforms_bytes)}
    offset               += header.platforms.length
    selection_set_bytes  := slice.to_bytes(scene.selection.set[:])
    header.selection.set  = Range{ offset = offset, length = cast(u32)len(selection_set_bytes)}
    offset               += header.selection.set.length
    
    buf := make([dynamic]byte, allocator = allocator)
    defer delete(buf)

    append(&buf, ..slice.bytes_from_ptr(&header, size_of(header)))
    append(&buf, ..platforms_bytes)
    append(&buf, ..selection_set_bytes)

    err := os.write_entire_file(MAP_FILE_PATH, buf[:])
    if err != nil {
        fmt.eprintfln("Error saving map file!")
        return
    }

    scene.last_save_time = time.tick_now()
}

editor_load_map :: proc(scene : ^Scene_Editor, ctx : Game_Context, allocator := context.allocator) -> (ok : bool) {
    if !os.exists(MAP_FILE_PATH) {
        free_camera_init_default(&scene.free_cam, ctx.viewport)
        return
    }

    map_data, err := os.read_entire_file(MAP_FILE_PATH, allocator = allocator)
    defer delete(map_data, allocator = allocator)

    if err != nil {
        fmt.eprintfln("Cannot read map file!")
        return
    }

    header := cast(^Editor_Map_Save_Header)raw_data(map_data)

    if header.magic != MAP_SAVE_MAGIC {
        fmt.eprintfln("Incorrect magic!")
        return
    }

    if header.version != MAP_SAVE_VERSION {
        fmt.eprintfln("Incorrect version!")
        return
    }

    map_save := Editor_Map_Save {
        free_cam  = header.free_cam,
        platforms = slice.reinterpret(
            []Platform,
            map_data[header.platforms.offset:][:header.platforms.length],
        ),
        selection = {
            set    = slice.reinterpret(
                []i32,
                map_data[header.selection.set.offset:][:header.selection.set.length],
            ),
            leader = header.selection.leader, 
        }

    }

    // Do call editor_destroy_snapshot on this one, since the platforms point to the map_data
    // We will free map_data once the scope ends
    snapshot := Editor_Snapshot {
        selection = {
            set    = map_save.selection.set,
            leader = map_save.selection.leader,
        },
        platforms = map_save.platforms,
    }

    editor_restore_snapshot(scene, snapshot)
    scene.free_cam = map_save.free_cam

    return true
}

editor_destroy_snapshot :: proc(snapshot : Editor_Snapshot, allocator : runtime.Allocator) {
    delete(snapshot.platforms,     allocator = allocator)
    delete(snapshot.selection.set, allocator = allocator)
}

editor_get_grid_axis :: proc(ctx : Game_Context) -> bit_set[Debug_Grid_Axis; u8] {
    return ctx.settings.editor.view_mode == .Perspective ? { .Y } : { .Z }
}