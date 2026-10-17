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
}

@(rodata)
settings_menu_options := [Settings_Menu_Option_Id]Menu_Option{
    .Gameplay = { id = "settings_menu:gameplay", name = "Gameplay"},
    .Controls = { id = "settings_menu:controls", name = "Controls"},
    .Graphics = { id = "settings_menu:graphics", name = "Graphics"},
    .Audio    = { id = "settings_menu:audio",    name = "Audio"},
}

SETTINGS_MENU_CALLBACKS : Menu_Callbacks(^Settings_Menu) : {
    update_ui = proc(menu : ^Settings_Menu, ui : ^Ui) -> Menu_Result {
        selected_opt, selected := menu_helper_label_menu(
            menu             = menu,
            ui               = ui,
            selected_current = menu.selected_current,
            current_option   = menu.current_option,
            options          = settings_menu_options,
        )

        if selected do #partial switch selected_opt {
        }

        return {}
    },
    input_ui = proc(menu : ^Settings_Menu, ui : ^Ui, ev : sapp.Event) -> (res : Menu_Result) {
        res.close = menu_helper_label_menu_input(
            menu             = menu,
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

@(rodata)
graphics_menu_option_ids := [Settings_Menu_Option_Id]Menu_Option{
    .Gameplay = { id = "settings_menu:gameplay", name = "Gameplay"},
    .Controls = { id = "settings_menu:controls", name = "Controls"},
    .Graphics = { id = "settings_menu:graphics", name = "Graphics"},
    .Audio    = { id = "settings_menu:audio",    name = "Audio"},
}


Graphics_Menu_Option_Id :: enum {
    Resolution,
    Vsync,
    Brightness,
    Gamma,
    Particles,
    Decals,
}

Audio_Menu_Option_Id :: enum {
    Master,
    Sound,
    Music,
    Subtitles,
}

Controls_Menu_Option_Id :: enum {
    Mouse,
    Keyboards_And_Gamepad,
}

Mouse_Menu_Option_Id :: enum {
    Mouse_Sensitivity,
}


