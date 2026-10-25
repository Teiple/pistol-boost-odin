package main

import sapp "sokol-odin/sokol/app"

Mouse_Button_State :: enum {
    None,
    Pressed,
    Released,
    Down,
}

Mouse_Button :: enum {
    Left,
    Middle,
    Right,
}

// confined mouse, never escape window
Mouse_Input :: struct {
    state       : [Mouse_Button]Mouse_Button_State,
    position    : [2]f32, // relative to the viewport 
    delta       : [2]f32, // relative to the viewport
    sensitivity : [2]f32,
    invert_y    : bool,
}

mouse_init :: proc(mouse : ^Mouse_Input) {
    // we implement our virtual mouse since sokol does not ultilize
    // platform specific window manager's mouse constraints to make confined
    // mouse mode as oppose to, for example, Godot
    sapp.lock_mouse(true)
}

mouse_input :: proc(mouse : ^Mouse_Input, vp : ^Viewport, ev : sapp.Event) {
    if ev.type == .MOUSE_MOVE {
        mouse.position += viewport_get_vp_mouse_delta(vp, mouse.sensitivity * {ev.mouse_dx, ev.mouse_dy * (mouse.invert_y ? -1 : 1)})
        mouse.position  = viewport_get_vp_confine_mouse_pos(vp, mouse.position)
    }

    #partial switch ev.type {
        case .MOUSE_DOWN:
            #partial switch ev.mouse_button {
                case .LEFT  : mouse.state[.Left]   = .Pressed
                case .RIGHT : mouse.state[.Right]  = .Pressed
                case .MIDDLE: mouse.state[.Middle] = .Pressed
            }
            audio_play_sound(game_audio(), .Ui_Mouse_Click)
        case .MOUSE_UP:
            #partial switch ev.mouse_button {
                case .LEFT  : mouse.state[.Left]   = .Released
                case .RIGHT : mouse.state[.Right]  = .Released
                case .MIDDLE: mouse.state[.Middle] = .Released
            }
    }
}

mouse_set_sensivity :: proc(mouse : ^Mouse_Input, sensitivity : [2]f32) {
    mouse.sensitivity = sensitivity
}

mouse_set_invert_y :: proc(mouse : ^Mouse_Input, invert_y : bool) {
    mouse.invert_y = invert_y
}

mouse_input_end :: proc(mouse : ^Mouse_Input) {
    for &mb in mouse.state {
        if mb == .Pressed {
            mb = .Down
        } else if mb == .Released {
            mb = .None
        }
    }
}

mouse_is_inside_rect :: proc(mouse : ^Mouse_Input, rect : [4]f32) -> bool {
    mouse_pos := mouse.position

    return mouse_pos.x >= rect.x && mouse_pos.x <= rect.x + rect.z &&
        mouse_pos.y >= rect.y && mouse_pos.y <= rect.y + rect.w
}

mouse_state_inside_rect :: proc(mouse : ^Mouse_Input, rect : [4]f32, mouse_button : Mouse_Button) -> Mouse_Button_State {
    is_hovered := mouse_is_inside_rect(mouse, rect)

    if !is_hovered do return .None

    return mouse.state[mouse_button]
}