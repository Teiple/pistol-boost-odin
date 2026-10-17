package main

import "core:mem"
import sapp "sokol-odin/sokol/app"

Pause_Menu_Option_Id :: enum {
    Continue,
    Settings,
    Main_Menu,
    Quit
}

@(rodata)
pause_menu_options := [Pause_Menu_Option_Id]Menu_Option{
    .Continue  = { id = "pause_menu:continue",  name = "Continue" },
    .Settings  = { id = "pause_menu:settings",  name = "Settings" },
    .Main_Menu = { id = "pause_menu:main_menu", name = "Main Menu" },
    .Quit      = { id = "pause_menu:quit",      name = "Quit" }
}

Pause_Menu :: struct {
    show             : bool,
    current_option   : Pause_Menu_Option_Id,
    selected_current : bool,
}

PAUSE_MENU_CALLBACKS : Menu_Callbacks(^Pause_Menu) : {
    update_ui = proc(menu : ^Pause_Menu, ui : ^Ui) -> (res : Menu_Result) {
        defer menu.selected_current = false

        if !menu.show {
            return {}
        }

        selected_opt, selected := menu_helper_label_menu(
            menu             = menu,
            ui               = ui,
            selected_current = menu.selected_current,
            current_option   = menu.current_option,
            options          = pause_menu_options,
            anchor           = {
                parent  = {1, .5},
                element = {1, .5},
            }
        )

        if selected do switch selected_opt {
            case .Continue:
                res.close = true
            case .Settings:
                res.next_menu = Settings_Menu{}
            case .Main_Menu:
                game_request_switch_scene(Scene_Main_Menu{})
            case .Quit:
                game_request_quit()
        }

        return
    },
    input_ui = proc(menu : ^Pause_Menu, ui: ^Ui, ev : sapp.Event) -> (res : Menu_Result) {
        res.close = menu_helper_label_menu_input(
            menu             = menu,
            ui               = ui,
            ev               = ev,
            selected_current = &menu.selected_current,
            current_option   = &menu.current_option,
        )
        return
    },
    open = proc(menu : ^Pause_Menu) {
        game_time_set_time_scale(game_time(), .Pause_Menu, 0)
        menu.show = true
    },
    close = proc(menu : ^Pause_Menu) {
        game_time_set_time_scale(game_time(), .Pause_Menu, 1)
        menu.show = false
    },
}
