package main
import sapp "sokol-odin/sokol/app"

Scene_Main_Menu :: struct {
	is_toggled : bool,
}

SCENE_MAIN_MENU_CALLBACKS : Scene_Callbacks(^Scene_Main_Menu) : {
    update_ui = proc(scene : ^Scene_Main_Menu) {
        ui_draw_text(&game.ui, .Normal,
            !scene.is_toggled ? "This is the main menu" : "Or is it?"
        )
    },
    input_ui = proc(scene : ^Scene_Main_Menu, ev : sapp.Event) {
        if ev.type == .KEY_DOWN && ev.key_code == .SPACE {
            scene.is_toggled = !scene.is_toggled
        }

        if ev.type == .KEY_DOWN && ev.key_code == .ENTER {
            game_request_switch_scene(Scene_Gameplay{})
        }
    }
}