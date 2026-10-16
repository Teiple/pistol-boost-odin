package main

import sapp "sokol-odin/sokol/app"

Pause_Menu_Option_Id :: enum {
    Continue,
    Settings,
    Main_Menu,
    Quit
}

PAUSE_MENU_OPTION_NAMES := [Pause_Menu_Option_Id]string{
    .Continue  = "Continue",
    .Settings  = "Settings",
    .Main_Menu = "Main_Menu",
    .Quit      = "Quit"
}

Pause_Menu :: struct {
    show           : bool,
    current_option : Pause_Menu_Option_Id,
    selected_current       : bool, 
}

pause_menu_init :: proc(menu : ^Pause_Menu) {
    // nothing for now
}

pause_menu_destroy :: proc(menu : ^Pause_Menu) {
    // nothing for now
}

pause_menu_begin :: proc(menu : ^Pause_Menu) {
    // nothing for now
}

pause_menu_end   :: proc(menu : ^Pause_Menu) {
    menu.selected_current = false
}

pause_menu_update_ui :: proc(menu : ^Pause_Menu, ui : ^Ui) {
    if !menu.show {
        return
    }

    anchor : Anchor = {
        container = ui_top_container(ui),
        parent    = {.5, .5},
        element   = {0,  0},
    }

    spacing :: 4
    for opt, id in PAUSE_MENU_OPTION_NAMES {
        rect, mouse_state, is_clicked := ui_push_rect(                
            ui, hsv(0, 0, 0, 0),
            sizing      = { Fixed{160}, Fixed{32} },
            anchor      = anchor,
            interactive = {
                id            = opt,
                hovered_color = hsv(140, 0.5, 1, 0.2),
                held_color    = hsv(140, 0.5, 0.96, 0.2),
            } 
        )

        is_clicked ||= menu.selected_current && id == menu.current_option

        if is_clicked {
            switch id {
                case .Continue:
                    pause_menu_close(menu)
                case .Settings:
                case .Main_Menu:
                    game_request_switch_scene(Scene_Main_Menu{})
                case .Quit:
                    game_request_quit()
            }
        }

        ui_push_container(ui, rect)
        {
            defer ui_pop_container(ui)

            ui_push_text(
                ui,
                font_id     = .Mono,
                text        = opt,
                anchor      = {
                    container = ui_top_container(ui),
                    element   = {.5, .5},
                    parent    = {.5, .5} 
                },
                color       = (
                    id == menu.current_option ?
                    hsv(140, 0.5, 1) :
                    hsv(140, 1, 0.8)
                ),
            )
        }

        anchor.offset.y += rect.w + spacing
    }
}

pause_menu_open :: proc(menu : ^Pause_Menu) {
    game_time_set_time_scale(game_time(), .Pause_Menu, 0)
    menu.show = true
}

pause_menu_close :: proc(menu : ^Pause_Menu) {
    game_time_set_time_scale(game_time(), .Pause_Menu, 1)
    menu.show = false
}

pause_menu_input :: proc(menu : ^Pause_Menu, ui: ^Ui, ev : sapp.Event) {
    ui_capture_input(ui)

    if ev.type == .KEY_DOWN {
        #partial switch ev.key_code {
            case .DOWN:
                menu.current_option = cast(Pause_Menu_Option_Id)(
                    (cast(int)menu.current_option + 1) % len(Pause_Menu_Option_Id)
                )
            case .UP:
                cur := cast(int)menu.current_option - 1
                if cur < 0 {
                    menu.current_option = cast(Pause_Menu_Option_Id)(cur + len(Pause_Menu_Option_Id))
                } else {
                    menu.current_option = cast(Pause_Menu_Option_Id)(cur % len(Pause_Menu_Option_Id))
                }
            case .SPACE, .ENTER:
                menu.selected_current = true                
            case .ESCAPE:
                pause_menu_close(menu)
        }
    }
}