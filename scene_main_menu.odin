package main
import sapp "sokol-odin/sokol/app"

Main_Menu_Option_Id :: enum {
    New_Game,
    Settings,
    Archivements,
    About,
    Quit
}

@(rodata)
main_menu_option_names := [Main_Menu_Option_Id]string{
    .New_Game     = "New Game",
    .Settings     = "Settings",
    .About        = "About",
    .Archivements = "Archivements", 
    .Quit         = "Quit",
}

@(rodata)
main_menu_options := [Main_Menu_Option_Id]Menu_Option{
    .New_Game     = { id = "main_menu:new_game",     name = "New Game" },
    .Settings     = { id = "main_menu:settings",     name = "Settings" },
    .About        = { id = "main_menu:about",        name = "About" },
    .Archivements = { id = "main_menu:archivements", name = "Archivements" },
    .Quit         = { id = "main_menu:quit",         name = "Quit" },
}

Main_Menu :: struct {
    current_option   : Main_Menu_Option_Id,
    selected_current : bool,
}

MAIN_MENU_CALLBACKS : Menu_Callbacks(^Main_Menu) : {
    update_ui = proc(menu : ^Main_Menu, ui : ^Ui) -> (res : Menu_Result) {
        selected_opt, selected := menu_helper_label_menu(
            menu             = menu,
            ui               = ui,
            selected_current = menu.selected_current,
            current_option   = menu.current_option,
            options          = main_menu_options,
            
        )

        if selected do #partial switch selected_opt {
            case .New_Game:
                game_request_switch_scene(Scene_Gameplay{
                    init = { selected_level = 1 },
                })
            case .Quit:
                game_request_quit()
            case .Settings:
                res.next_menu = Settings_Menu{}
        }
        
        return
    },
    input_ui = proc(menu : ^Main_Menu, ui: ^Ui, ev : sapp.Event) -> (res : Menu_Result) {
        res.close = menu_helper_label_menu_input(
            menu             = menu,
            ui               = ui,
            ev               = ev,
            selected_current = &menu.selected_current,
            current_option   = &menu.current_option,
        )

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