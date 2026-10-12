package main
import sapp "sokol-odin/sokol/app"

MM_Menu :: struct {

}

Scene_Main_Menu :: struct {
    option : int,
}

SCENE_MAIN_MENU_CALLBACKS : Scene_Callbacks(^Scene_Main_Menu) : {
    update_ui = proc(scene : ^Scene_Main_Menu) {
        options := [?]string{ "New Game", "Options", "About", "Quit" }
        anchor : Anchor = {
            container = game.ui.builder.current_container,
            parent    = {.5, .5},
            element   = {.5,  1},
        }
        spacing :: 4
        for opt, i in options {
            rect := ui_draw_text(
                &game.ui, .Normal, opt,
                anchor      = anchor,
                color       = hsv(140, 1, 0.8),
                interactive = {
                    mouse         = game_get_mouse(),
                    hovered_color = hsv(300, 1, 1)
                }
            )

            anchor.offset.y += rect.w + spacing
        }
    },
    input_ui = proc(scene : ^Scene_Main_Menu, ev : sapp.Event) {
        if ev.type == .KEY_DOWN {
            #partial switch ev.key_code {
                case .DOWN:
                case .UP:
                case .SPACE:
                case .ENTER:
                case .ESCAPE:
            }
        }
    }
}