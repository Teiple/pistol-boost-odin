package main
import sapp "sokol-odin/sokol/app"

Main_Menu_Option_Id :: enum {
    New_Game,
    Settings,
    Archivements,
    About,
    Quit
}

MAIN_MENU_OPTION_NAMES := [Main_Menu_Option_Id]string{
    .New_Game     = "New Game",
    .Settings     = "Settings",
    .About        = "About",
    .Archivements = "Archivements", 
    .Quit         = "Quit"
}

Scene_Main_Menu :: struct {
    current_option : Main_Menu_Option_Id,
}

SCENE_MAIN_MENU_CALLBACKS : Scene_Callbacks(^Scene_Main_Menu) : {
    update_ui = proc(scene : ^Scene_Main_Menu, ui : ^Ui) {
        anchor : Anchor = {
            container = ui_top_container(ui),
            parent    = {.5, .5},
            element   = {.5,  1},
        }

        spacing :: 4
        for opt, id in MAIN_MENU_OPTION_NAMES {
            rect, mouse_state, is_clicked := ui_push_rect(                
                ui, hsv(0, 0, 0, 0),
                sizing      = { Fixed{200}, Fixed{32} },
                anchor      = anchor,
                interactive = {
                    id            = opt,
                    hovered_color = hsv(140, 0.5, 1, 0.2),
                    held_color    = hsv(140, 0.5, 0.96, 0.2),
                } 
            )

            if is_clicked {
                switch id {
                    case .New_Game:
                        game_request_switch_scene(Scene_Gameplay{
                            init = {
                                selected_level = 1,
                            }
                        })
                    case .Settings:
                    case .About:
                    case .Archivements:
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
                        id == scene.current_option ?
                        hsv(140, 0.5, 1) :
                        hsv(140, 1, 0.8)
                    ),
                )
            }

            anchor.offset.y += rect.w + spacing
        }
    },
    input_ui = proc(scene : ^Scene_Main_Menu, ui: ^Ui, ev : sapp.Event) {
        if ev.type == .KEY_DOWN {
            #partial switch ev.key_code {
                case .DOWN:
                    scene.current_option = cast(Main_Menu_Option_Id)(
                        (cast(int)scene.current_option + 1) % len(Main_Menu_Option_Id)
                    )
                case .UP:
                    cur := cast(int)scene.current_option - 1
                    if cur < 0 {
                        scene.current_option = cast(Main_Menu_Option_Id)(cur + len(Main_Menu_Option_Id))
                    } else {
                        scene.current_option = cast(Main_Menu_Option_Id)(cur % len(Main_Menu_Option_Id))
                    }
                case .SPACE:
                case .ENTER:
                case .ESCAPE:
            }
        }
    }
}