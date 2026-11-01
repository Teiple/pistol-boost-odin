#+feature using-stmt
package main

import sapp "sokol-odin/sokol/app"

Scene_Editor :: struct {

}

@(rodata)
lanes := [?]sapp.Keycode {
    .Z,.X,.C,.V,.B,.N,.M,.COMMA,.PERIOD,.SLASH,
    .A,.S,.D,.F,.G,.H,.J,.K,.L,.SEMICOLON,
    .Q,.W,.E,.R,.T,.Y,.U,.I,.O,.P,
}

SCENE_DEBUG_CALLBACKS : Scene_Callbacks(^Scene_Editor) : {
    init = proc(scene : ^Scene_Editor) {

    },
    update_3d = proc(scene : ^Scene_Editor, dt : f32) {
  
    },
    destroy = proc(scene : ^Scene_Editor) {

    },
    input_3d = proc(scene : ^Scene_Editor, ev : sapp.Event) {

    }
}