package main

import "core:fmt"
import ins "base:intrinsics"
import sapp "sokol-odin/sokol/app"

Menu :: union {
    Main_Menu,
    Pause_Menu,
    Settings_Menu,
    // Graphics_Menu,
    // Audio_Menu,
    // Gameplay_Menu,
    // Controls_Menu,
}

Menu_Callbacks_Any :: Menu_Callbacks(^Menu)

Menu_Callbacks :: struct($T : typeid) where
    ins.type_is_pointer(T) &&
	(
		ins.type_elem_type(T) == Menu ||
		ins.type_is_variant_of(Menu, ins.type_elem_type(T))
	)
{
    update_ui : proc(menu: T, ui: ^Ui)                  -> Menu_Result,
    input_ui  : proc(menu: T, ui: ^Ui, ev : sapp.Event) -> Menu_Result,
    open      : proc(menu: T),
    close     : proc(menu: T),    
}

menu_get_callbacks :: proc(menu : ^Menu) -> Menu_Callbacks_Any {
    convert_cbs :: proc(menu : ^$T, cbs : Menu_Callbacks(^T)) -> Menu_Callbacks_Any {
        return transmute(Menu_Callbacks_Any)cbs
    }

    switch  &m in menu {
        case Main_Menu:
            return convert_cbs(&m, MAIN_MENU_CALLBACKS)
        case Pause_Menu:
            return convert_cbs(&m, PAUSE_MENU_CALLBACKS)
        case Settings_Menu:
            return convert_cbs(&m, SETTINGS_MENU_CALLBACKS)
    }
    
    panic("Unreachable")
}

Menu_Stack :: struct {
    menu_callbacks : Menu_Callbacks_Any,  
    stack          : [dynamic]Menu,
}

Menu_Result :: struct {
    next_menu : Menu,
    close     : bool,
}

menu_stack_top :: proc(menu_stack : ^Menu_Stack) -> ^Menu {
    return len(menu_stack.stack) > 0 ? &menu_stack.stack[len(menu_stack.stack) - 1] : nil
}

menu_stack_init :: proc(menu_stack : ^Menu_Stack) {
    menu_stack.stack = make([dynamic]Menu, 0, 8)
}

menu_stack_update_ui :: proc(menu_stack : ^Menu_Stack, ui : ^Ui) {
    if update_cb := menu_stack.menu_callbacks.update_ui; update_cb != nil {
        res := update_cb(menu_stack_top(menu_stack), ui)
        menu_stack_resolve_result(menu_stack, res)
    }
}

menu_stack_input_ui :: proc(menu_stack : ^Menu_Stack, ui : ^Ui, ev : sapp.Event) {
    if input_cb := menu_stack.menu_callbacks.input_ui; input_cb != nil {
        res := input_cb(menu_stack_top(menu_stack), ui, ev)
        menu_stack_resolve_result(menu_stack, res)
    }
}

menu_stack_resolve_result :: proc(menu_stack : ^Menu_Stack, res : Menu_Result) {
    assert(res.next_menu == nil || (res.next_menu != nil && !res.close))    
    if res.close {
        menu_stack_pop_menu(menu_stack)
    } else if res.next_menu != nil {
        menu_stack_push_menu(menu_stack, res.next_menu)
    }
}

menu_stack_destroy :: proc(menu_stack : ^Menu_Stack) {
    delete(menu_stack.stack)
}

menu_stack_push_menu :: proc(menu_stack : ^Menu_Stack, menu : Menu) {
    append(&menu_stack.stack, menu)
    
    top := menu_stack_top(menu_stack)
    menu_stack.menu_callbacks = menu_get_callbacks(top)
    
    if open_cb := menu_stack.menu_callbacks.open; open_cb != nil {
        open_cb(top)
    }
}

menu_stack_pop_menu :: proc(menu_stack : ^Menu_Stack) {
    top := menu_stack_top(menu_stack)

    if close_cb := menu_stack.menu_callbacks.close; close_cb != nil {
        close_cb(top)
    }
    
    pop(&menu_stack.stack)

    if len(menu_stack.stack) > 0 {
        menu_stack.menu_callbacks = menu_get_callbacks(menu_stack_top(menu_stack))
    } else {
        menu_stack.menu_callbacks = {}
    }
}

Menu_Option :: struct {
    id   : Ui_Id,
    name : string, 
}

Menu_Option_Select :: struct($S : typeid) where ins.type_is_enum(S) {
    using _     : Menu_Option,
    selectables : [S]string,
}

menu_helper_label_menu :: proc(
    menu             : ^$M,
    ui               : ^Ui,
    selected_current : bool,
    current_option   : $O,
    options          : [O]Menu_Option,
    anchor           : Anchor = {
        parent  = {.5, .5},
        element = {.5, .5},
    },
    option_size      : [2]f32 = { 200, 32 },
) -> (selected_option : O, selected : bool) where ins.type_is_enum(O)
{
    spacing   :: 4
    opt_count := cast(f32)len(O)

    // option container
    rect, _, _ := ui_push_rect(
        ui, 
        sizing = {
            Fixed{
                option_size.x
            },
            Fixed{
                option_size.y * opt_count + (opt_count - 1) * spacing,
            }
        },
        anchor = anchor
    )

    ui_push_container(ui, rect)
    {
        defer ui_push_container(ui, rect)

        opt_anchor : Anchor = {
            parent    = { 0, 0},
            element   = { 0, 0},
        }

        for opt, opt_enum in options {
            rect, mouse_state, is_clicked := ui_push_rect(                
                ui, hsv(0, 0, 0, 0),
                sizing      = { Fixed{option_size.x}, Fixed{option_size.y} },
                anchor      = opt_anchor,
                interactive = {
                    id            = opt.id,
                    hovered_color = hsv(140, 0.5, 1, 0.2),
                    held_color    = hsv(140, 0.5, 0.5, 0.2),
                }
            )

            is_clicked ||= selected_current && opt_enum == current_option

            if is_clicked {
                selected_option = opt_enum
                selected        = true
            }

            ui_push_container(ui, rect)
            {
                defer ui_pop_container(ui)

                ui_push_text(
                    ui,
                    font_id     = .Mono,
                    text        = opt.name,
                    anchor      = {
                        element   = {.5, .5},
                        parent    = {.5, .5} 
                    },
                    color       = (
                        opt_enum == current_option ?
                        hsv(140, 0.5, 1) :
                        hsv(140, 1, 0.8)
                    ),
                )
            }

            opt_anchor.offset.y += rect.w + spacing
        }
    }   
    
    return
}

menu_helper_label_menu_input :: proc(
    menu             : ^$M,
    ui               : ^Ui,
    ev               : sapp.Event,
    selected_current : ^bool,
    current_option   : ^$O,
) -> (requested_to_close : bool) where ins.type_is_enum(O)
{
    ui_capture_input(ui)

    cur := current_option^

    if ev.type == .KEY_DOWN {
        #partial switch ev.key_code {
            case .DOWN:
                current_option^ = cast(O)(
                    (cast(int)cur + 1) % len(O)
                )
            case .UP:
                prev := cast(int)cur - 1
                if prev < 0 {
                    current_option^ = cast(O)(prev + len(O))
                } else {
                    current_option^ = cast(O)(prev % len(O))
                }
            case .SPACE, .ENTER:
                selected_current^ = true           
            case .ESCAPE:
                requested_to_close = true
        }
    }

    return
}

menu_helper_options_menu :: proc(
    menu                  : ^$M,
    ui                    : ^Ui,
    selected_current      : bool,
    current_option        : $O,
    current_option_select : $S,
    option_selects        : [O]Menu_Option_Select(S),
    option_callbacks      : [O]proc(menu: ^M),
    anchor                : Anchor = {
        parent  = {.5, .5},
        element = {.5, .5},
    },
    option_size      : [2]f32 = { 200, 32 },
) where ins.type_is_enum(O)
{
    spacing   :: 4
    opt_count := cast(f32)len(O)

    // option container
    rect, _, _ := ui_push_rect(
        ui, 
        sizing = {
            Fixed{
                option_size.x
            },
            Fixed{
                option_size.y * opt_count + (opt_count - 1) * spacing,
            }
        },
        anchor = anchor
    )

    ui_push_container(ui, rect)
    {
        defer ui_push_container(ui, rect)

        opt_anchor : Anchor = {
            parent    = { 0, 0},
            element   = { 0, 0},
        }

        for opt, id in option_selects {
            rect, mouse_state, is_clicked := ui_push_rect(                
                ui, hsv(0, 0, 0, 0),
                sizing      = { Fixed{option_size.x}, Fixed{option_size.y} },
                anchor      = opt_anchor,
                interactive = {
                    id            = opt.id,
                    hovered_color = hsv(140, 0.5, 1, 0.2),
                    held_color    = hsv(140, 0.5, 0.5, 0.2),
                }
            )

            is_clicked ||= selected_current && id == current_option

            if is_clicked {
                if opt_cb := option_callbacks[id]; opt_cb != nil {
                    opt_cb(menu)
                }
            }

            ui_push_container(ui, rect)
            {
                defer ui_pop_container(ui)

                ui_push_text(
                    ui,
                    font_id     = .Mono,
                    text        = opt.name,
                    anchor      = {
                        element   = {.5, .5},
                        parent    = {.5, .5} 
                    },
                    color       = (
                        id == current_option ?
                        hsv(140, 0.5, 1) :
                        hsv(140, 1, 0.8)
                    ),
                )
            }

            opt_anchor.offset.y += rect.w + spacing
        }
    }   
}