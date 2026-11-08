package main
import sapp "sokol-odin/sokol/app"

Main_Menu_Item_Id :: enum u8 {
    New_Game,
    Editor,
    Settings,
    Archivements,
    About,
}

@(rodata)
main_menu_items := [Main_Menu_Item_Id]Menu_Item{
    .New_Game     = { id = "main_menu:new_game",     term = .New_Game },
    .Editor       = { id = "main_menu:editor",       term = {"Editor", .English} },
    .Settings     = { id = "main_menu:settings",     term = .Settings },
    .About        = { id = "main_menu:about",        term = .About },
    .Archivements = { id = "main_menu:archivements", term = .Archivements },
}

Main_Menu :: struct {
    current_item   : Main_Menu_Item_Id,
}

MAIN_MENU_CALLBACKS : Menu_Callbacks(^Main_Menu) : {
    update_ui = proc(menu : ^Main_Menu, ctx : Game_Context) -> (res : Menu_Result) {
        selected_opt, selected := menu_helper_label_menu(
            ctx              = ctx,
            current_item     = &menu.current_item,
            items            = main_menu_items,
        )

        if selected do #partial switch selected_opt {
            case .New_Game:
                game_request_switch_scene(Scene_Gameplay{
                    init = { selected_level = 1 },
                })
            case .Editor:
                game_request_switch_scene(Scene_Editor{})
            case .Settings:
                res.next_menu = Settings_Menu{}
        }
        
        if menu_helper_back_button(
            ui    = ctx.ui,
            id    = "settings_menu:back",
            label = .Exit,
        ) || ui_is_cancel_pressed(ctx.ui) {
            res.next_menu = Quit_Confirm_Popup_Menu{}
        }
        
        return
    },
}

Scene_Main_Menu :: struct {
    menu_stack : Menu_Stack,
}

SCENE_MAIN_MENU_CALLBACKS : Scene_Callbacks(^Scene_Main_Menu) : {
    init = proc(scene : ^Scene_Main_Menu, ctx : Game_Context) {
        menu_stack_init(&scene.menu_stack)
        menu_stack_push_menu(&scene.menu_stack, Main_Menu{}, ctx)

        audio_play_music(ctx.audio, .Main_Menu)
    },
    update_ui = proc(scene : ^Scene_Main_Menu, ctx : Game_Context) {
        menu_stack_update_ui(&scene.menu_stack, ctx)
    },
    destroy = proc(scene : ^Scene_Main_Menu, ctx : Game_Context) {
        menu_stack_destroy(&scene.menu_stack)
    }
}