package main
import sapp "sokol-odin/sokol/app"
import "core:fmt"

MM_Menu :: struct {

}

OPTIONS :: [?]string{ "New Game", "Settings", "About", "Quit" }

Scene_Main_Menu :: struct {
    current_option : int,
}

SCENE_MAIN_MENU_CALLBACKS : Scene_Callbacks(^Scene_Main_Menu) : {
    update_ui = proc(scene : ^Scene_Main_Menu) {
        ui := game_get_ui()

        options := [?]string{ "New Game", "Options", "About", "Quit" }
        
        anchor : Anchor = {
            container = ui_top_container(ui),
            parent    = {.5, .5},
            element   = {.5,  1},
        }
        SPACING :: 4
        
        mouse := game_get_mouse()
        
        for opt, i in options {
            rect, mouse_state, is_clicked := ui_draw_rect(                
                ui, hsv(0, 0, 0, 0),
                sizing      = { Fixed{160}, Fixed{32} },
                anchor      = anchor,
                interactive = {
                    id            = opt,
                    hovered_color = hsv(140, 0.5, 1, 0.2),
                    held_color    = hsv(140, 0.5, 0.8, 0.2),
                } 
            )

            if is_clicked {
                fmt.printfln("Pressed!")
            }
            
            ui_draw_text(
                ui, .Mono, opt,
                anchor      = anchor,
                color       = (
                    i == scene.current_option ?
                    hsv(140, 0.5, 1) :
                    hsv(140, 1, 0.8)
                ),
            )

            anchor.offset.y += rect.w + SPACING
        }
    },
    input_ui = proc(scene : ^Scene_Main_Menu, ev : sapp.Event) {
        if ev.type == .KEY_DOWN {
            #partial switch ev.key_code {
                case .DOWN:
                    scene.current_option += 1
                    scene.current_option %= len(OPTIONS)
                case .UP:
                    scene.current_option -= 1
                    if scene.current_option < 0 {
                        scene.current_option += len(OPTIONS)
                    }
                    scene.current_option %= len(OPTIONS)
                case .SPACE:
                case .ENTER:
                case .ESCAPE:
            }
        }
    }
}