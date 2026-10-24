package main

import "core:math"
import "core:fmt"
import ins "base:intrinsics"
import sapp "sokol-odin/sokol/app"

Menu :: union {
    Main_Menu,
    Pause_Menu,
    Settings_Menu,
    Quit_Confirm_Popup_Menu,
    Language_Menu,
    Graphics_Menu,
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
        case Language_Menu:
            return convert_cbs(&m, LANGUAGE_MENU_CALLBACKS)
        case Graphics_Menu:
            return convert_cbs(&m, GRAPHICS_MENU_CALLBACKS)
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

// mainly used for language selection
Raw_Term :: struct {
    raw      : string,
    language : Language, 
}

Menu_Term :: union {
    Loc_Term,
    Raw_Term,
}

Menu_Item :: struct {
    id   : Ui_Id,
    term : Menu_Term, 
}

Menu_Item_Options :: struct($T: typeid) {
    item_id   : string, 
    item_term : Loc_Term, 
    options   : union {
        [T]Loc_Term,
        [T]string, // always English, there is no usecase for other languages yet
    }
}

Raw_Term_Enum_Array :: struct($T : typeid) {
    labels   : [T]string,
    language : Language
}

menu_helper_item_options :: proc(
    ui            : ^Ui,
    item          : Menu_Item_Options($T),
    
    current_value : T,
    is_active     : bool,
    anchor        : Anchor,
    
    item_height   : f32,
    switch_next   : bool,
    switch_prev   : bool,
) -> (new_value : T, changed : bool) where ins.type_is_enum(T) || ins.type_is_integer(T) {
    rect, _, clicked := ui_push_rect(
        ui,
        sizing      = { Grow{}, Fixed{item_height} },
        anchor      = anchor,
        interactive = {
            id            = item.item_id,
            hovered_color = hsv(140, 0.5, 1, 0.2),
            held_color    = hsv(140, 0.5, 0.5, 0.2),
        },
    )

    ui_push_container(ui, rect)
    {
        defer ui_pop_container(ui)
    
        ui_push_text(
            ui,
            text   = tr(item.item_term),
            anchor = { element = {0, .5}, parent = {0, .5}, offset = {8, 0} },
            color  = is_active ? hsv(140, 0.5, 1) : hsv(140, 1, 0.8),
        )

        opt_string: string
        is_number_range := false
        switch opts in item.options {
            case [T]Loc_Term:
                opt_string = tr(opts[current_value])
            case [T]string:
                opt_string = opts[current_value]
        }

        ui_push_text(
            ui,
            text   = opt_string,
            anchor = { element = {1, .5}, parent = {1, .5}, offset = {-8, 0} },
            color  = is_active ? hsv(42, 0.7, 1) : hsv(42, 1, 0.8),
        )

        if clicked || is_active {
            if switch_next || clicked {
                return cont_enum_next(current_value), true
            } else if switch_prev {
                return cont_enum_prev(current_value), true
            }
        }
    }

    return
}

menu_helper_item_spinner :: proc(
    ui : ^Ui,

    item_id   : string,
    item_term : Loc_Term,

    current_value : $T,
    min           : T,
    max           : T,
    step          : T,

    is_active   : bool,
    anchor      : Anchor,
    item_height : f32,
    switch_next : bool,
    switch_prev : bool,

    format      : string,

    allocator   := context.temp_allocator
) -> (new_value : T, changed : bool) where ins.type_is_numeric(T) {
    current_value := math.clamp(current_value, min, max) 

    rect, _, clicked := ui_push_rect(
        ui,
        sizing      = { Grow{}, Fixed{item_height} },
        anchor      = anchor,
        interactive = {
            id            = item_id,
            hovered_color = hsv(140, 0.5, 1, 0.2),
            held_color    = hsv(140, 0.5, 0.5, 0.2),
        },
    )

    ui_push_container(ui, rect)
    {
        defer ui_pop_container(ui)
    
        ui_push_text(
            ui,
            text   = tr(item_term),
            anchor = { element = {0, .5}, parent = {0, .5}, offset = {8, 0} },
            color  = is_active ? hsv(140, 0.5, 1) : hsv(140, 1, 0.8),
        )

        val_string := fmt.aprintf(format, current_value, allocator = allocator)

        ui_push_text(
            ui,
            text   = val_string,
            anchor = { element = {1, .5}, parent = {1, .5}, offset = {-8, 0} },
            color  = is_active ? hsv(42, 0.7, 1) : hsv(42, 1, 0.8),
        )

        if clicked || is_active {
            if switch_next || clicked {
                new_value := current_value + step
                if new_value > max {
                    new_value = min
                }
                return new_value, new_value != current_value
            } else if switch_prev {
                new_value := current_value - step
                if new_value < min {
                    new_value = max
                }
                return new_value, new_value != current_value
            }
        }
    }

    return
}

menu_helper_calculate_footer_layout :: proc(
    item_index    : int,
    item_count    : int,
    footer_height : f32 = 42,
    mid_btn_witdh : f32 = 200,
) -> (sizing : [2]Sizing, anchor : Anchor, text_anchor : Anchor) {
    sizing.y = Fixed{footer_height}
    if item_count == 1 {
        sizing.x    = Grow{}
        anchor      = { element = {0, 1}, parent = {0, 1} }
        text_anchor = { element = {.5, .5}, parent = {.5, .5} }
    } else if item_count >= 2 {
        mid_btn_count        := f32(item_count - 2) 
        mid_btn_total_width  := mid_btn_count * mid_btn_witdh

        // Two ends
        if item_index == 0 {
            sizing.x = PercentOffset{.5, -mid_btn_total_width * .5}
            anchor      = { element = {0, 1},   parent = {0, 1} }
            text_anchor = { element = {1, .5},  parent = {1, .5} }
        } else if item_index == item_count - 1 {
            sizing.x = PercentOffset{.5, -mid_btn_total_width * .5}
            anchor      = { element = {1, 1}, parent = {1, 1} }
            text_anchor = { element = {0, .5},  parent = {0, .5} }
        } else {
            // Middle small buttons
            mid_index  := f32(item_index) - 1

            sizing.x = Fixed{mid_btn_witdh}
            anchor = {
                element = {0, 1},
                parent = {0.5, 1},
                offset = {mid_index * mid_btn_witdh - .5 * mid_btn_total_width, 0}
            }
            text_anchor = { element = {.5, .5},  parent = {.5, .5} }
        }
    } 
    return
}

menu_helper_label_menu :: proc(
    menu             : ^$M,
    ui               : ^Ui,
    selected_current : bool,
    current_item     : $T,
    items            : [T]Menu_Item,
    anchor           : Anchor = {
        parent  = {.5, .5},
        element = {.5, .5},
    },
    item_size        : [2]f32 = { 200, 32 },
) -> (selected_option : T, selected : bool) where ins.type_is_enum(T)
{
    spacing   :: 4
    opt_count := cast(f32)len(T)

    // option container
    rect, _, _ := ui_push_rect(
        ui, 
        sizing = {
            Fixed{
                item_size.x
            },
            Fixed{
                item_size.y * opt_count + (opt_count - 1) * spacing,
            }
        },
        anchor = anchor
    )

    ui_push_container(ui, rect)
    {
        defer ui_pop_container(ui)

        item_anchor : Anchor

        for item, item_enum in items {
            rect, mouse_state, is_clicked := ui_push_rect(                
                ui,
                color       = hsv(0, 0, 0, 0),
                sizing      = { Fixed{item_size.x}, Fixed{item_size.y} },
                anchor      = item_anchor,
                interactive = {
                    id            = item.id,
                    hovered_color = hsv(140, 0.5, 1, 0.2),
                    held_color    = hsv(140, 0.5, 0.5, 0.2),
                }
            )

            is_clicked ||= selected_current && item_enum == current_item

            if is_clicked {
                selected_option = item_enum
                selected        = true
            }

            ui_push_container(ui, rect)
            {
                defer ui_pop_container(ui)

                raw_term, is_raw := item.term.(Raw_Term)
            
                prev_lang := ui.language

                if is_raw {
                    ui_set_lang(ui, raw_term.language)
                }

                text := is_raw ? raw_term.raw : tr(item.term.(Loc_Term))

                ui_push_text(
                    ui,
                    text        = text,
                    anchor      = {
                        element   = {.5, .5},
                        parent    = {.5, .5} 
                    },
                    color       = (
                        item_enum == current_item ?
                        hsv(140, 0.5, 1) :
                        hsv(140, 1, 0.8)
                    ),
                )

                if is_raw {
                    ui_set_lang(ui, prev_lang)
                }
            }

            item_anchor.offset.y += rect.w + spacing
        }
    }   
    
    return
}

menu_helper_label_menu_input :: proc(
    ui               : ^Ui,
    ev               : sapp.Event,
    selected_current : ^bool,
    current_item     : ^$T,
) -> (requested_to_close : bool) where ins.type_is_enum(T) && ins.type_enum_is_contiguous(T)
{
    ui_capture_input(ui)

    if ev.type == .KEY_DOWN {
        #partial switch ev.key_code {
            case .DOWN:
                current_item^ = cont_enum_next(current_item^)
            case .UP:
                current_item^ = cont_enum_prev(current_item^)
            case .SPACE, .ENTER:
                selected_current^ = true           
            case .ESCAPE:
                requested_to_close = true
        }
    }

    return
}

menu_helper_back_button :: proc(
    ui             : ^Ui,
    id             : Ui_Id,
    label          : Loc_Term,
    text_alignment : f32 = 0.5,
) -> (is_clicked : bool) {
    rect, mouse_state, clicked := ui_push_rect(                
        ui,
        color       = hsv(0, 0, 0, 0),
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

        anchor : Anchor = {
            element = text_alignment,
            parent  = text_alignment,
        }

        ui_push_text(
            ui,
            text        = tr(label),
            anchor      = anchor,
            color       = hsv(140, 1, 0.8),
        )
    }

    return clicked
}


Quit_Confirm_Popup_Menu :: struct{
    selected_current : bool,
    current_item     : bool,
}

QUIT_CONFIRM_POPUP_MENU_CALLBACKS : Menu_Callbacks(^Quit_Confirm_Popup_Menu) : {
    update_ui = proc(m : ^Quit_Confirm_Popup_Menu, ui : ^Ui) -> (res : Menu_Result) {
        defer m.selected_current = false
        
        yes, is_clicked := menu_helper_confirmation(
            ui,
            current_item   = m.current_item,
            selected_current = m.selected_current,
            yes_id           = "quit_confirm_popup_menu:yes",
            no_id            = "quit_confirm_popup_menu:no",
            message          = .Exit_Confirmation,
            yes_label        = .Yes,
            no_label         = .No,
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
            current_item   = &m.current_item,
        )
        
        return
    }
}

menu_helper_confirmation :: proc(
    ui               : ^Ui,
    message          : Loc_Term,
    yes_label        : Loc_Term,
    no_label         : Loc_Term,
    yes_id           : Ui_Id,
    no_id            : Ui_Id,
    current_item     : bool,
    selected_current : bool,
) -> (yes : bool, is_clicked : bool) {
    size       : [2]f32= {400, 200}
    padding    :: 16
    opt_height :: 32

    rect, _, _ := ui_push_rect(                
        ui,
        color  = hsv(0, 0, 0, .8),
        sizing = { Fixed{size.x}, Fixed{size.y}},
        anchor = { element = {.5, .5}, parent = {.5, .5}, offset = {0, -20}},
    )

    ui_push_container(ui, rect)
    {
        defer ui_pop_container(ui)
        
        inner_rect, _, _ := ui_push_rect(                
            ui,
            sizing = { Fixed{size.x - 2 * padding}, Fixed{size.y - 2 * padding}},
            anchor = { offset = padding },
        )

        ui_push_container(ui, inner_rect)
        {
            defer ui_pop_container(ui)
            
            // Content rect
            content_rect, _, _ := ui_push_rect(                
                ui,
                sizing = { Grow{}, Fixed{size.y - 2 * padding - opt_height}},
            )
            
            ui_push_container(ui, content_rect)
            {
                defer ui_pop_container(ui)
                
                ui_push_text(
                    ui,
                    text    = tr(message),
                    anchor  = { element = {.5, .5}, parent = {.5, .5} },
                    color   = hsv(140, 1, 0.8),
                )
            }

            // Yes/No rects
            yes_rect, _, yes_clicked := ui_push_rect(                
                ui,
                sizing      = { Percent{.5}, Fixed{opt_height}},
                anchor      = { element = {0, 1}, parent = {0, 1}},
                interactive = {
                    id            = yes_id,
                    hovered_color = hsv(140, 0.5, 1, 0.2),
                    held_color    = hsv(140, 0.5, 0.5, 0.2),
                }
            )

            yes_clicked ||= selected_current && current_item == true

            ui_push_container(ui, yes_rect)
            {
                defer ui_pop_container(ui)

                ui_push_text(
                    ui,
                    text    = tr(yes_label),
                    anchor  = { element = {.5, .5}, parent = {.5, .5} },
                    color   = current_item ? hsv(140, 0.5, 1) : hsv(140, 1, 0.8),
                )
            }

            no_rect, _, no_clicked := ui_push_rect(                
                ui,
                sizing      = { Percent{.5}, Fixed{opt_height}},
                anchor      = { element = {0, 1}, parent = {.5, 1}},
                interactive = {
                    id            = no_id,
                    hovered_color = hsv(140, 0.5, 1, 0.2),
                    held_color    = hsv(140, 0.5, 0.5, 0.2),
                }
            )

            no_clicked ||= selected_current && current_item == false
            
            ui_push_container(ui, no_rect)
            {
                defer ui_pop_container(ui)

                ui_push_text(
                    ui,
                    text    = tr(no_label),
                    anchor  = { element = {.5, .5}, parent = {.5, .5} },
                    color   = !current_item ? hsv(140, 0.5, 1) : hsv(140, 1, 0.8)
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
    current_item   : ^bool,
) -> (requested_to_close : bool)
{
    ui_capture_input(ui)

    cur := current_item^

    if ev.type == .KEY_DOWN {
        #partial switch ev.key_code {
            case .LEFT, .RIGHT:
                current_item^ = !cur
            case .SPACE, .ENTER:
                selected_current^ = true           
            case .ESCAPE:
                requested_to_close = true
        }
    }

    return
}
