package main
import sapp "sokol-odin/sokol/app"

Main_Menu_Item_Id :: enum {
    New_Game,
    Settings,
    Archivements,
    About,
}

@(rodata)
main_menu_items := [Main_Menu_Item_Id]Menu_Item{
    .New_Game     = { id = "main_menu:new_game",     term = .New_Game },
    .Settings     = { id = "main_menu:settings",     term = .Settings },
    .About        = { id = "main_menu:about",        term = .About },
    .Archivements = { id = "main_menu:archivements", term = .Archivements },
}

Main_Menu :: struct {
    current_item   : Main_Menu_Item_Id,
    selected_current : bool,
}

MAIN_MENU_CALLBACKS : Menu_Callbacks(^Main_Menu) : {
    update_ui = proc(menu : ^Main_Menu, ui : ^Ui) -> (res : Menu_Result) {
        defer menu.selected_current = false

        selected_opt, selected := menu_helper_label_menu(
            menu             = menu,
            ui               = ui,
            selected_current = menu.selected_current,
            current_item     = menu.current_item,
            items            = main_menu_items,
        )

        if selected do #partial switch selected_opt {
            case .New_Game:
                game_request_switch_scene(Scene_Gameplay{
                    init = { selected_level = 1 },
                })
            case .Settings:
                res.next_menu = Settings_Menu{}
        }
        
        if menu_helper_back_button(
            ui    = ui,
            id    = settings_menu_back_btn_id,
            label = .Exit,
        ) {
            res.next_menu = Quit_Confirm_Popup_Menu{}
        }
        
        return
    },
    input_ui = proc(menu : ^Main_Menu, ui: ^Ui, ev : sapp.Event) -> (res : Menu_Result) {
        quit := menu_helper_label_menu_input(
            ui               = ui,
            ev               = ev,
            selected_current = &menu.selected_current,
            current_item     = &menu.current_item,
        )
        if quit {
            res.next_menu = Quit_Confirm_Popup_Menu{}
        }

        return
    }
}

Scene_Main_Menu :: struct {
    menu_stack : Menu_Stack,
}

SCENE_MAIN_MENU_CALLBACKS : Scene_Callbacks(^Scene_Main_Menu) : {
    init = proc(scene : ^Scene_Main_Menu) {
        menu_stack_init(&scene.menu_stack)
        menu_stack_push_menu(&scene.menu_stack, Main_Menu{})

        audio_play_music(game_audio(), .Main_Menu)
    },
    update_ui = proc(scene : ^Scene_Main_Menu, ui : ^Ui) {
        menu_stack_update_ui(&scene.menu_stack, ui)
    },
    input_ui = proc(scene : ^Scene_Main_Menu, ui: ^Ui, ev : sapp.Event) {
        menu_stack_input_ui(&scene.menu_stack, ui, ev)
    },
    destroy = proc(scene : ^Scene_Main_Menu) {
        menu_stack_destroy(&scene.menu_stack)
    }
}