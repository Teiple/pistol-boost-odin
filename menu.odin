package main

import ins "base:intrinsics"
import sapp "sokol-odin/sokol/app"

Menu :: union {
    Main_Menu,
    Pause_Menu,
    Settings_Menu,
    Quit_Confirm_Popup_Menu,
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
        case Quit_Confirm_Popup_Menu:
            return convert_cbs(&m, QUIT_CONFIRM_POPUP_MENU_CALLBACKS)
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
        defer ui_pop_container(ui)

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

Text_Alignment :: enum {
    Left,
    Middle,
    Right
}

menu_helper_back_button :: proc(
    ui             : ^Ui,
    id             : Ui_Id,
    label          : string = "< Back",
    text_alignment : Text_Alignment = .Left,
) -> (is_clicked : bool) {
    rect, mouse_state, clicked := ui_push_rect(                
        ui, hsv(0, 0, 0, 0),
        sizing      = { Grow{}, Fixed{42}},
        anchor      = { element = {0, 1}, parent = {0, 1}},
        interactive = {
            id            = id,
            hovered_color = hsv(140, 0.5, 1, 0.2),
            held_color    = hsv(140, 0.5, 0.5, 0.2),
        }
    )

    ui_push_container(ui, rect)
    {
        defer ui_pop_container(ui)

        anchor : Anchor
        switch text_alignment {
            case .Middle:
                anchor = {
                    element   = {.5, .5},
                    parent    = {.5, .5} 
                }
            case .Left:
                anchor = {
                    element   = { 0, .5},
                    parent    = { 0, .5} 
                }
            case .Right:
                anchor = {
                    element   = { 1, .5},
                    parent    = { 1, .5} 
                }
        }

        ui_push_text(
            ui,
            font_id     = .Mono,
            text        = label,
            anchor      = anchor,
            color       = hsv(140, 1, 0.8),
        )
    }

    return clicked
}

Quit_Confirm_Popup_Menu :: struct{
    selected_current : bool,
    current_option   : bool,
}

QUIT_CONFIRM_POPUP_MENU_CALLBACKS : Menu_Callbacks(^Quit_Confirm_Popup_Menu) : {
    update_ui = proc(m : ^Quit_Confirm_Popup_Menu, ui : ^Ui) -> (res : Menu_Result) {
        defer m.selected_current = false
        
        yes, is_clicked := menu_helper_confirmation(
            ui,
            current_option   = m.current_option,
            selected_current = m.selected_current,
            yes_id           = "quit_confirm_popup_menu:yes",
            no_id            = "quit_confirm_popup_menu:no",
            message          = " Are you sure to\nexit the program?"
        )

        if is_clicked {
            if yes {
                game_request_quit()
            } else {
                res.close = true
            }
        }

        return
    },
    input_ui = proc(m : ^Quit_Confirm_Popup_Menu, ui : ^Ui, ev: sapp.Event) -> (res : Menu_Result) {
        res.close = menu_helper_confirmation_input(ui, ev,
            selected_current = &m.selected_current,
            current_option   = &m.current_option,
        )
        
        return
    }
}

menu_helper_confirmation :: proc(
    ui               : ^Ui,
    message          : string,
    yes_id           : Ui_Id,
    no_id            : Ui_Id,
    current_option   : bool,
    selected_current : bool,
    yes_label        : string = "Yes",
    no_label         : string = "No",
) -> (yes : bool, is_clicked : bool) {
    size       : [2]f32 : {400, 200}
    padding    :: 16
    opt_height :: 32

    rect, _, _ := ui_push_rect(                
        ui, hsv(0, 0, 0, .8),
        sizing      = { Fixed{size.x}, Fixed{size.y}},
        anchor      = { element = {.5, .5}, parent = {.5, .5}, offset = {0, -20}},
    )

    ui_push_container(ui, rect)
    {
        defer ui_pop_container(ui)
        
        inner_rect, _, _ := ui_push_rect(                
            ui, 0,
            sizing = { Fixed{size.x - 2 * padding}, Fixed{size.y - 2 * padding}},
            anchor = { offset = padding },
        )

        ui_push_container(ui, inner_rect)
        {
            defer ui_pop_container(ui)
            
            // Content rect
            content_rect, _, _ := ui_push_rect(                
                ui, hsv(0, 0, 0, 0),
                sizing = { Grow{}, Fixed{size.y - 2 * padding - opt_height}},
            )
            
            ui_push_container(ui, content_rect)
            {
                defer ui_pop_container(ui)
                
                ui_push_text(
                    ui,
                    font_id = .Mono,
                    text    = message,
                    anchor  = { element = {.5, .5}, parent = {.5, .5} },
                    color   = hsv(140, 1, 0.8),
                )
            }

            // Yes/No rects
            yes_rect, _, yes_clicked := ui_push_rect(                
                ui, hsv(0, 0, 0, 0),
                sizing      = { Percent{.5}, Fixed{opt_height}},
                anchor      = { element = {0, 1}, parent = {0, 1}},
                interactive = {
                    id            = yes_id,
                    hovered_color = hsv(140, 0.5, 1, 0.2),
                    held_color    = hsv(140, 0.5, 0.5, 0.2),
                }
            )

            yes_clicked ||= selected_current && current_option == true

            ui_push_container(ui, yes_rect)
            {
                defer ui_pop_container(ui)

                ui_push_text(
                    ui,
                    font_id = .Mono,
                    text    = yes_label,
                    anchor  = { element = {.5, .5}, parent = {.5, .5} },
                    color   = current_option ? hsv(140, 0.5, 1) : hsv(140, 1, 0.8),
                )
            }

            no_rect, _, no_clicked := ui_push_rect(                
                ui, hsv(0, 0, 0, 0),
                sizing      = { Percent{.5}, Fixed{opt_height}},
                anchor      = { element = {0, 1}, parent = {.5, 1}},
                interactive = {
                    id            = no_id,
                    hovered_color = hsv(140, 0.5, 1, 0.2),
                    held_color    = hsv(140, 0.5, 0.5, 0.2),
                }
            )

            no_clicked ||= selected_current && current_option == false
            
            ui_push_container(ui, no_rect)
            {
                defer ui_pop_container(ui)

                ui_push_text(
                    ui,
                    font_id = .Mono,
                    text    = no_label,
                    anchor  = { element = {.5, .5}, parent = {.5, .5} },
                    color   = !current_option ? hsv(140, 0.5, 1) : hsv(140, 1, 0.8)
                )
            }

            is_clicked = yes_clicked || no_clicked
            yes        = yes_clicked
        }
    }

    return
}


menu_helper_confirmation_input :: proc(
    ui               : ^Ui,
    ev               : sapp.Event,
    selected_current : ^bool,
    current_option   : ^bool,
) -> (requested_to_close : bool)
{
    ui_capture_input(ui)

    cur := current_option^

    if ev.type == .KEY_DOWN {
        #partial switch ev.key_code {
            case .LEFT, .RIGHT:
                current_option^ = !cur
                current_option^ = !cur
            case .SPACE, .ENTER:
                selected_current^ = true           
            case .ESCAPE:
                requested_to_close = true
        }
    }

    return
}
