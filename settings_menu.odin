package main

import sapp "sokol-odin/sokol/app"

Settings_Menu :: struct {
    show             : bool,
    current_option   : Settings_Menu_Option_Id,
    selected_current : bool,
}

Settings_Menu_Option_Id :: enum {
    Gameplay,
    Controls,
    Graphics,
    Audio,
    Language,
}

@(rodata)
settings_menu_options := [Settings_Menu_Option_Id]Menu_Option{
    .Gameplay = { id = "settings_menu:gameplay", term = .Gameplay},
    .Controls = { id = "settings_menu:controls", term = .Controls},
    .Graphics = { id = "settings_menu:graphics", term = .Graphics},
    .Audio    = { id = "settings_menu:audio",    term = .Audio},
    .Language = { id = "settings_menu:language", term = .Language},
}

settings_menu_back_btn_id :: "settings_menu:id"

SETTINGS_MENU_CALLBACKS : Menu_Callbacks(^Settings_Menu) : {
    update_ui = proc(menu : ^Settings_Menu, ui : ^Ui) -> (res: Menu_Result) {
        selected_opt, selected := menu_helper_label_menu(
            menu             = menu,
            ui               = ui,
            selected_current = menu.selected_current,
            current_option   = menu.current_option,
            options          = settings_menu_options,
        )

        if selected do #partial switch selected_opt {
            case .Language:
                res.next_menu = Language_Menu{}
        }

        res.close = menu_helper_back_button(
            ui    = ui,
            label = tr(.Back),
            id    = settings_menu_back_btn_id,
        )

        return
    },
    input_ui = proc(menu : ^Settings_Menu, ui : ^Ui, ev : sapp.Event) -> (res : Menu_Result) {
        res.close = menu_helper_label_menu_input(
            ui               = ui,
            ev               = ev,
            selected_current = &menu.selected_current,
            current_option   = &menu.current_option,
        )
        return
    },
    open = proc(menu : ^Settings_Menu) {
        menu.show = true
    },
    close = proc(menu : ^Settings_Menu) {
        menu.show = false
    },
}

// @(rodata)
// graphics_menu_option_ids := [Settings_Menu_Option_Id]Menu_Option{
//     .Gameplay = { id = "settings_menu:gameplay", term = .Gameplay},
//     .Controls = { id = "settings_menu:controls", term = .Controls},
//     .Graphics = { id = "settings_menu:graphics", term = .Graphics},
//     .Audio    = { id = "settings_menu:audio",    term = .Audio},
// }


// Graphics_Menu_Option_Id :: enum {
//     Resolution,
//     Vsync,
//     Brightness,
//     Gamma,
//     Particles,
//     Decals,
// }

// Audio_Menu_Option_Id :: enum {
//     Master,
//     Sound,
//     Music,
//     Subtitles,
// }

// Controls_Menu_Option_Id :: enum {
//     Mouse,
//     Keyboards_And_Gamepad,
// }

// Mouse_Menu_Option_Id :: enum {
//     Mouse_Sensitivity,
// }


