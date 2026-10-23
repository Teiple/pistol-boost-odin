package main

import fmt "core:fmt"
import ins "base:intrinsics"
import sapp "sokol-odin/sokol/app"

Settings_Menu :: struct {
    show             : bool,
    current_item     : Settings_Menu_Item_Id,
    selected_current : bool,
}

Settings_Menu_Item_Id :: enum {
    Gameplay,
    Controls,
    Graphics,
    Audio,
    Language,
}

@(rodata)
settings_menu_items := [Settings_Menu_Item_Id]Menu_Item{
    .Gameplay = { id = "settings_menu:gameplay", term = .Gameplay},
    .Controls = { id = "settings_menu:controls", term = .Controls},
    .Graphics = { id = "settings_menu:graphics", term = .Graphics},
    .Audio    = { id = "settings_menu:audio",    term = .Audio},
    .Language = { id = "settings_menu:language", term = .Language},
}

settings_menu_back_btn_id :: "settings_menu:back"

SETTINGS_MENU_CALLBACKS : Menu_Callbacks(^Settings_Menu) : {
    update_ui = proc(menu : ^Settings_Menu, ui : ^Ui) -> (res: Menu_Result) {
        defer menu.selected_current = false

        selected_opt, selected := menu_helper_label_menu(
            menu             = menu,
            ui               = ui,
            selected_current = menu.selected_current,
            current_item     = menu.current_item,
            items            = settings_menu_items,
        )

        if selected do #partial switch selected_opt {
            case .Language:
                res.next_menu = Language_Menu{}
            case .Graphics:
                res.next_menu = Graphics_Menu{}
        }

        res.close = menu_helper_back_button(
            ui    = ui,
            label = .Back,
            id    = settings_menu_back_btn_id,
        )

        return
    },
    input_ui = proc(menu : ^Settings_Menu, ui : ^Ui, ev : sapp.Event) -> (res : Menu_Result) {
        res.close = menu_helper_label_menu_input(
            ui               = ui,
            ev               = ev,
            selected_current = &menu.selected_current,
            current_item     = &menu.current_item,
        )
        return
    },
    open = proc(menu : ^Settings_Menu) {
        menu.show = true
    },
    close = proc(menu : ^Settings_Menu) {
        menu.show = false
    },
}

@(rodata)
graphics_setting_config_default : Graphics_Setting_Config = {
    resolution = .Res_960x540,       
    vsync      = .On,       
    fullscreen = .On,
}

Graphics_Setting_Config :: struct {
    resolution : Resolution,       
    vsync      : ToggleState,       
    fullscreen : ToggleState,
}

Graphics_Setting_Footer_Item_Id :: enum {
    Back,
    Defaults,
    Apply,    
}

Graphics_Menu :: struct {
    current_menu_item   : Graphics_Setting_Menu_Item_Id,
    current_footer_item : Graphics_Setting_Footer_Item_Id,
    saved_config        : Graphics_Setting_Config,
    current_config      : Graphics_Setting_Config,
    switch_next         : bool,
    switch_prev         : bool,
    focus_area          : enum {
        Menu,
        Footer,
    }
}

Resolution :: enum {
    Res_800x480,
    Res_800x600,
    Res_960x540,
}

ToggleState :: enum {
    On,
    Off,
}

Graphics_Quality :: enum {
    Low,
    Medium,
    High,
}

Graphics_Setting_Menu_Item :: union {
    Menu_Item_Options(Resolution),
    Menu_Item_Options(ToggleState),
}

Graphics_Setting_Menu_Item_Id :: enum {
    Resolution,
    Fullscreen,
    Vsync,
}

@(rodata)
graphics_menu_options : [Graphics_Setting_Menu_Item_Id]Graphics_Setting_Menu_Item = {
    .Resolution = Menu_Item_Options(Resolution) {
        item_id       = "graphics_menu:resolution",
        item_term     =  .Resolution,
        options       = {
            .Res_800x480 = "800x480",
            .Res_800x600 = "800x600",
            .Res_960x540 = "960x540",
        }
    },
    .Fullscreen = Menu_Item_Options(ToggleState) {
        item_id       = "graphics_menu:fullscreen",
        item_term     =  .Fullscreen,
        options       = {
            .On   = .On,
            .Off  = .Off,
        }
    },
    .Vsync =  Menu_Item_Options(ToggleState) {
        item_id       = "graphics_menu:vsync",
        item_term     =  .Vsync,
        options       = {
            .On   = .On,
            .Off  = .Off,
        }
    },
}

graphics_menu_back_btn_id :: "graphics_menu:id"

GRAPHICS_MENU_CALLBACKS : Menu_Callbacks(^Graphics_Menu) : {
    update_ui = proc(menu : ^Graphics_Menu, ui : ^Ui) -> (res: Menu_Result) {
        defer {
            menu.switch_next = false
            menu.switch_prev = false
        }

        for focus_area in type_of(menu.focus_area) {
            switch focus_area {
                case .Menu:
                    item_height :: 32
                    widths      : [2]f32 : {200, 100}
                    spacing     :: 4
                    item_count  := cast(f32)len(Graphics_Setting_Menu_Item_Id)
                    
                    // option container
                    rect, _, _ := ui_push_rect(
                        ui, 
                        sizing = {
                            Fixed{ widths[0] + widths[1] },
                            Fixed{
                                item_height * item_count + (item_count - 1) * spacing,
                            }
                        },
                        anchor = { parent = {.5, .5}, element = {.5, .5} },
                    )
                    
                    current_item     := menu.current_menu_item
                    has_current_item := menu.focus_area == focus_area

                    ui_push_container(ui, rect)
                    {
                        defer ui_pop_container(ui)

                        item_anchor : Anchor

                        for menu_item, item_enum in graphics_menu_options {
                            switch item in menu_item {
                            case Menu_Item_Options(Resolution):
                                current_option := &menu.current_config.resolution
                                saved_option   := menu.saved_config.resolution

                                rect, _, is_clicked := ui_push_rect(
                                    ui,
                                    sizing = { Grow{}, Fixed{item_height} },
                                    anchor = item_anchor,
                                    interactive = {
                                        id            = item.item_id,
                                        hovered_color = hsv(140, 0.5, 1, 0.2),
                                        held_color    = hsv(140, 0.5, 0.5, 0.2),
                                    }
                                )
                                ui_push_container(ui, rect)
                                {
                                    defer ui_pop_container(ui)
                                    
                                    item_label := tr(item.item_term)

                                    ui_push_text(
                                        ui,
                                        text = item_label,
                                        anchor = { element = {0, .5}, parent = {0, .5}, offset = {8, 0} },
                                        color       = (
                                            has_current_item && item_enum == current_item ?
                                            hsv(140, 0.5, 1) :
                                            hsv(140, 1, 0.8)
                                        ),
                                    )
                                    
                                    opt_string := item.options.([Resolution]string)[current_option^]

                                    ui_push_text(
                                        ui,
                                        opt_string,
                                        anchor = {
                                            element = {1, .5},
                                            parent  = {1, .5},
                                            offset  = {-8, 0},
                                        },
                                        color       = (
                                            has_current_item && item_enum == current_item ?
                                            hsv(42, 0.7, 1) : hsv(42, 1, 0.8)
                                        ),
                                    )

                                    if is_clicked || (has_current_item && current_item == item_enum) {
                                        if menu.switch_next || is_clicked {
                                            current_option^ = cont_enum_next(current_option^)
                                        } else if menu.switch_prev {
                                            current_option^ = cont_enum_prev(current_option^)
                                        }
                                    }
                                }
                                
                            case Menu_Item_Options(ToggleState):
                                current_option : ^ToggleState
                                saved_option : ToggleState

                                #partial switch item_enum {
                                    case .Fullscreen: 
                                        current_option = &menu.current_config.fullscreen
                                        saved_option   = menu.saved_config.fullscreen
                                    case .Vsync: 
                                        current_option = &menu.current_config.vsync
                                        saved_option   = menu.saved_config.vsync
                                    case:
                                        panic("Unhandled toggle")
                                }

                                rect, _, is_clicked := ui_push_rect(
                                    ui,
                                    sizing = { Grow{}, Fixed{item_height} },
                                    anchor = item_anchor,
                                    interactive = {
                                        id            = item.item_id,
                                        hovered_color = hsv(140, 0.5, 1, 0.2),
                                        held_color    = hsv(140, 0.5, 0.5, 0.2),
                                    }
                                )
                                ui_push_container(ui, rect)
                                {
                                    defer ui_pop_container(ui)
                                
                                    item_label := tr(item.item_term)

                                    ui_push_text(
                                        ui,
                                        text = item_label,
                                        anchor = { element = {0, .5}, parent = {0, .5}, offset = {8, 0} },
                                        color       = (
                                            has_current_item && item_enum == current_item ?
                                            hsv(140, 0.5, 1) :
                                            hsv(140, 1, 0.8)
                                        ),
                                    )
                                    
                                    opt_string := tr(item.options.([ToggleState]Loc_Term)[current_option^])
                                    
                                    ui_push_text(
                                        ui,
                                        opt_string,
                                        anchor = {
                                            element = {1, .5},
                                            parent  = {1, .5},
                                            offset  = {-8, 0},
                                        },
                                        color       = (
                                            has_current_item && current_item == item_enum ?
                                            hsv(42, 0.7, 1) : hsv(42, 1, 0.8)
                                        ),
                                    )

                                    if is_clicked || (has_current_item && current_item == item_enum) {
                                        if menu.switch_next || is_clicked {
                                            current_option^ = cont_enum_next(current_option^)
                                        } else if menu.switch_prev {
                                            current_option^ = cont_enum_prev(current_option^)
                                        }
                                    }
                                }
                            }
                            
                            item_anchor.offset.y += item_height + spacing
                        }
                    }
                case .Footer:
                    has_current_item   := menu.focus_area == focus_area
                    current_item       := menu.current_footer_item
                    small_button_width :: 200
                    
                    items : [dynamic ; len(Graphics_Setting_Footer_Item_Id)]Graphics_Setting_Footer_Item_Id = {
                        .Back
                    }

                    has_changed_from_default := menu.current_config != graphics_setting_config_default 
                    has_changed_from_saved   := menu.saved_config   != menu.current_config
                    
                    if has_changed_from_default {
                        append(&items, .Defaults)
                    }
                    if has_changed_from_saved {
                        append(&items, .Apply)
                    }

                    // Clamp current option
                    {
                        item_exist := false
                        for it in items {
                            if current_item == it {
                                item_exist = true
                                break
                            }
                        }
                        
                        if !item_exist {
                            current_item = items[len(items) - 1]
                            menu.current_footer_item = current_item
                        }
                    }

                    for item, index in items {
                        sizing : [2]Sizing
                        sizing.y = Fixed{42}

                        anchor      : Anchor
                        text_anchor : Anchor

                        if len(items) == 1 {
                            sizing.x    = Grow{}
                            anchor      = { element = {0, 1}, parent = {0, 1} }
                            text_anchor = { element = {.5, .5}, parent = {.5, .5} }
                        } else if len(items) >= 2 {
                            small_button_button_count := f32(len(items) - 2) 
                            small_button_total_width  := small_button_button_count * small_button_width

                            // Two ends
                            if index == 0 {
                                sizing.x = PercentOffset{.5, -small_button_total_width * .5}
                                anchor      = { element = {0, 1},   parent = {0, 1} }
                                text_anchor = { element = {1, .5},  parent = {1, .5} }
                            } else if index == len(items) - 1 {
                                sizing.x = PercentOffset{.5, -small_button_total_width * .5}
                                anchor      = { element = {1, 1}, parent = {1, 1} }
                                text_anchor = { element = {0, .5},  parent = {0, .5} }
                            } else {
                                // Middle small buttons
                                small_button_index  := f32(index) - 1

                                sizing.x = Fixed{small_button_total_width}
                                anchor      = { element = {0, 1}, parent = {0.5, 1}, offset = {small_button_index * small_button_width - .5 * small_button_total_width, 0} }
                                text_anchor = { element = {.5, .5},  parent = {.5, .5} }
                            }
                        } 

                        switch item {
                            case .Back:
                                rect, _, is_clicked := ui_push_rect(
                                    ui,
                                    sizing = sizing,
                                    anchor = anchor,
                                    interactive = {
                                        id            = "graphics_menu:back",
                                        hovered_color = hsv(140, 0.5, 1, 0.2),
                                        held_color    = hsv(140, 0.5, 0.5, 0.2),
                                    }
                                )

                                is_clicked ||= menu.switch_next && has_current_item && current_item == item
                                res.close = is_clicked

                                 ui_push_container(ui, rect)
                                {
                                    defer ui_pop_container(ui)
                                    ui_push_text(
                                        ui,
                                        text   = tr(.Back),
                                        anchor = text_anchor,
                                        color  = (
                                            has_current_item && current_item == item ?
                                            hsv(140, 0.5, 1) :
                                            hsv(140, 1, 0.8)
                                        ),
                                        padding = 32,
                                    )
                                }
                            case .Defaults:
                                rect, _, is_clicked := ui_push_rect(
                                    ui,
                                    sizing = sizing,
                                    anchor = anchor,
                                    interactive = {
                                        id            = "graphics_menu:defaults",
                                        hovered_color = hsv(140, 0.5, 1, 0.2),
                                        held_color    = hsv(140, 0.5, 0.5, 0.2),
                                    }
                                )

                                is_clicked ||= menu.switch_next && has_current_item && current_item == item
                                if is_clicked {
                                    
                                }

                                ui_push_container(ui, rect)
                                {
                                    defer ui_pop_container(ui)
                                    ui_push_text(
                                        ui,
                                        text   = tr(.Defaults),
                                        anchor = text_anchor,
                                        color  = (
                                            has_current_item && current_item == item ?
                                            hsv(140, 0.5, 1) :
                                            hsv(140, 1, 0.8)
                                        ),
                                        padding = 32,
                                    )
                                }
                            case .Apply:
                                rect, _, is_clicked := ui_push_rect(
                                    ui,
                                    sizing = sizing,
                                    anchor = anchor,
                                    interactive = {
                                        id            = "graphics_menu:apply",
                                        hovered_color = hsv(140, 0.5, 1, 0.2),
                                        held_color    = hsv(140, 0.5, 0.5, 0.2),
                                    }
                                )

                                is_clicked ||= menu.switch_next && has_current_item && current_item == item
                                if is_clicked {

                                }

                                ui_push_container(ui, rect)
                                {
                                    defer ui_pop_container(ui)
                                    ui_push_text(
                                        ui,
                                        text   = tr(.Apply),
                                        anchor = text_anchor,
                                        color  = (
                                            has_current_item && current_item == item ?
                                            hsv(140, 0.5, 1) :
                                            hsv(140, 1, 0.8)
                                        ),
                                        padding = 32,
                                    )
                                }
                        }
                    }
            }
        }
        return
    },
    input_ui = proc(menu : ^Graphics_Menu, ui : ^Ui, ev : sapp.Event) -> (res : Menu_Result) {
        ui_capture_input(ui)

        requested_to_close := false

        if ev.type == .KEY_DOWN {
            if ev.key_code == .ESCAPE {
                requested_to_close = true
            } else if ev.key_code == .TAB {
                if (ev.modifiers & sapp.MODIFIER_SHIFT) != 0 {
                    menu.focus_area   = cont_enum_prev(menu.focus_area)
                } else {
                    menu.focus_area = cont_enum_next(menu.focus_area)
                }
                
            } else {
                switch menu.focus_area {
                    case .Menu:
                        current_item := &menu.current_menu_item

                        #partial switch ev.key_code {
                            case .DOWN:
                                current_item^ = cont_enum_next(current_item^)
                            case .UP:
                                current_item^ = cont_enum_prev(current_item^)
                            case .SPACE, .ENTER, .RIGHT:
                                menu.switch_next = true
                            case .LEFT:
                                menu.switch_prev = true         
                            case .ESCAPE:
                                requested_to_close = true
                        }
                    case .Footer:
                        current_item := &menu.current_footer_item

                        #partial switch ev.key_code {
                            case .DOWN, .RIGHT:
                                current_item^ = cont_enum_next(current_item^)
                            case .UP, .LEFT:
                                current_item^ = cont_enum_prev(current_item^)
                            case .SPACE, .ENTER:
                                menu.switch_next = true         
                            case .ESCAPE:
                                requested_to_close = true
                        }
                }

            }
        }

        res.close = requested_to_close

        return
    },
}