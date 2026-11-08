package main

import sapp "sokol-odin/sokol/app"

Scene_Init :: struct {
    selected_level : int,
}

Scene_Gameplay :: struct {
    meshes        : [dynamic]Mesh,
    physics       : Physics,
    follow_camera : Follow_Camera,
    init          : Scene_Init,
    menu_stack    : Menu_Stack,
    player        : Player,
    arena         : Arena,
    debug_draw    : Debug_Draw, 
    
}

SCENE_GAMEPLAY_CALLBACKS : Scene_Callbacks(^Scene_Gameplay) : {
	init = proc(scene : ^Scene_Gameplay, ctx : Game_Context) {
        scene.meshes = make([dynamic]Mesh)
        append(&scene.meshes, mesh_create_box({2, 1, 1}))
    
        menu_stack_init(&scene.menu_stack)
        
        physics_init(&scene.physics)
        player_init(&scene.player, &scene.physics, {0, 0, 0})
        follow_camera_init(&scene.follow_camera)

        viewport_set_clear_color(ctx.viewport, hsv(140, 0.4, 0.2))

        arena_init(&scene.arena, &scene.physics)
        debug_draw_init(&scene.debug_draw)
    },
    destroy = proc(scene : ^Scene_Gameplay, ctx : Game_Context) {
        debug_draw_destroy(&scene.debug_draw)
        arena_destroy(&scene.arena)
        
        player_destroy(&scene.player)
        physics_destroy(&scene.physics)

        menu_stack_destroy(&scene.menu_stack)
        
        for &m in scene.meshes {
            mesh_destroy(&m)
        }
        delete(scene.meshes)
    },
    update_3d = proc(scene : ^Scene_Gameplay, ctx : Game_Context, dt : f32) {        
        debug_draw_begin(&scene.debug_draw)

        physics_update_3d(
            &scene.physics,dt
        )
        
        player_update_3d(
            &scene.player,
            {
                camera   = ctx.camera,
                viewport = ctx.viewport,
                mouse    = ctx.mouse,
                audio    = ctx.audio,
            },
            dt
        )

        follow_camera_update_3d(
            follow_cam    = &scene.follow_camera,
            camera        = ctx.camera,
            target_pos    = player_get_interpolated_position(
                &scene.player,
                &scene.physics,
            ),
            dt = dt,
        )
    },
    update_ui = proc(scene : ^Scene_Gameplay, ctx : Game_Context) {
        ui_push_text(
            ctx.ui,
            font_id = .Normal, 
            text    = tr(.Undefined), 
        )

        menu_stack_update_ui(&scene.menu_stack, ctx)
    },
    draw_3d = proc(scene : ^Scene_Gameplay, ctx : Game_Context, renderer : ^Renderer) {
        arena_draw_3d(&scene.arena, renderer)
        player_draw_3d(&scene.player, &scene.physics, renderer)
        debug_draw_3d(&scene.debug_draw, renderer)
    },
    input_ui = proc(scene : ^Scene_Gameplay, ctx : Game_Context, ev : sapp.Event) {
        if  ev.type == .KEY_DOWN &&
            ev.key_code == .ESCAPE &&
            menu_stack_top(&scene.menu_stack) == nil
        {
            menu_stack_push_menu(&scene.menu_stack, Pause_Menu{}, ctx)
        }
    }
}