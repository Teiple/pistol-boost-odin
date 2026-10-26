package main
import sapp "sokol-odin/sokol/app"
import "core:fmt"
import ins "base:intrinsics"

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
            case .Controls:
                res.next_menu = Controls_Menu{}
            case .Audio:
                res.next_menu = Audio_Menu{}
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

Settings_Footer_Item :: enum {
    Back,
    Defaults,
}

Settings_Menu_Focus_Area :: enum {
    Menu,
    Footer,
}

Settings_Sub_Menu :: struct($T : typeid) where ins.type_is_enum(T) {
    current_menu_item   : T,
    current_footer_item : Settings_Footer_Item,
    focus_area          : Settings_Menu_Focus_Area,
    switch_next         : bool,
    switch_prev         : bool,
}

Graphics_Menu_Item_Id :: enum {
    Resolution,
    Fullscreen,
    Gamma,
}

Graphics_Menu :: Settings_Sub_Menu(Graphics_Menu_Item_Id)

GRAPHICS_MENU_CALLBACKS : Menu_Callbacks(^Graphics_Menu) : {
    update_ui = proc(menu : ^Graphics_Menu, ui : ^Ui) -> (res: Menu_Result) {
        defer {
            menu.switch_next = false
            menu.switch_prev = false
        }

        settings := &game_get_settings().graphics

        for focus_area in type_of(menu.focus_area) {
            switch focus_area {
                case .Menu:
                    item_height :: 32
                    spacing     :: 4
                    item_count  := cast(f32)len(Graphics_Menu_Item_Id)
                    
                    // option container
                    rect, _, _ := ui_push_rect(
                        ui, 
                        sizing = {
                            Fixed{ 300 },
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
                        
                        for item in Graphics_Menu_Item_Id {
                            is_active := has_current_item && current_item == item
                            defer item_anchor.offset.y += item_height + spacing
                            switch item {
                                case .Resolution:
                                    new_value, changed := menu_helper_item_options(
                                        ui,
                                        item          = Menu_Item_Options(Resolution) {
                                            item_id   = "graphics_menu:resolution",
                                            item_term = .Resolution,
                                            options = {
                                                .Resolution_480x270  = "480x270",
                                                .Resolution_640x360  = "640x360",
                                                .Resolution_960x540  = "960x540",
                                                .Resolution_1280x720 = "1280x720",
                                            } 
                                        },
                                        current_value = settings.resolution,
                                        is_active     = is_active,
                                        anchor        = item_anchor,
                                        switch_next   = menu.switch_next,
                                        switch_prev   = menu.switch_prev,
                                        item_height   = item_height,
                                    )
                                    if changed {
                                        settings.resolution = new_value
                                        settings_apply(settings^)
                                    }
                                case .Fullscreen:
                                    new_value, changed := menu_helper_item_toggle(
                                        ui,
                                        item_id   = "graphics_menu:fullscreen",
                                        item_term = .Fullscreen,
                                        on_term   = .On,
                                        off_term  = .Off,
                                        current_value = settings.fullscreen,
                                        is_active     = is_active,
                                        anchor        = item_anchor,
                                        switch_next   = menu.switch_next,
                                        switch_prev   = menu.switch_prev,
                                        item_height   = item_height,
                                    )
                                    if changed {
                                        settings.fullscreen = new_value
                                        settings_apply(settings^)
                                    }
                                case .Gamma:
                                    new_value, changed := menu_helper_item_spinner(
                                        ui,
                                        item_id       = "graphics_menu:gamma", 
                                        item_term     = .Gamma, 
                                        current_value = settings.gamma,
                                        min           = .5,
                                        max           = 1.5,
                                        step          = .1,
                                        format        = "%.1f",
                                        is_active     = is_active,
                                        anchor        = item_anchor,
                                        switch_next   = menu.switch_next,
                                        switch_prev   = menu.switch_prev,
                                        item_height   = item_height,
                                    )
                                    if changed {
                                        settings.gamma = new_value
                                        settings_apply(settings^)
                                    }
                            }
                        }
                    }
                case .Footer:
                    res.close = menu_helper_settings_footer(
                        ui,
                        menu,
                        is_focused       = menu.focus_area == focus_area,
                        settings         = settings,
                        settings_default = GRAPHICS_SETTINGS_DEFAULT,
                        back_id          = "graphics_menu:back",
                        defaults_id      = "graphics_menu:defaults",
                    )
            }
        }
        return
    },
    input_ui = proc(menu : ^Graphics_Menu, ui : ^Ui, ev : sapp.Event) -> (res : Menu_Result) {
        return menu_helper_settings_input(menu, ui, ev)
    },
}

Controls_Menu :: Settings_Sub_Menu(Controls_Menu_Item_Id)

Controls_Menu_Item_Id :: enum {
    Mouse_Invert_Y,
    Mouse_Horizontal_Sensitivity,
    Mouse_Vertical_Sensitivity,
}


CONTROLS_MENU_CALLBACKS : Menu_Callbacks(^Controls_Menu) : {
    update_ui = proc(menu : ^Controls_Menu, ui : ^Ui) -> (res: Menu_Result) {
        defer {
            menu.switch_next = false
            menu.switch_prev = false
        }

        settings := &game_get_settings().controls

        for focus_area in type_of(menu.focus_area) {
            switch focus_area {
                case .Menu:
                    item_height :: 32
                    
                    spacing     :: 4
                    item_count  := cast(f32)len(Controls_Menu_Item_Id)
                    
                    // option container
                    rect, _, _ := ui_push_rect(
                        ui, 
                        sizing = {
                            Fixed{ 400 },
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
                        
                        for item in Controls_Menu_Item_Id {
                            is_active := has_current_item && current_item == item
                            defer item_anchor.offset.y += item_height + spacing
                            switch item {
                                case .Mouse_Invert_Y:
                                    new_value, changed := menu_helper_item_toggle(
                                        ui,
                                        item_id   = "controls_menu:invert_y",
                                        item_term = .Mouse_Invert_Y,
                                        on_term   = .On,
                                        off_term  = .Off,
                                        current_value = settings.invert_y,
                                        is_active     = is_active,
                                        anchor        = item_anchor,
                                        switch_next   = menu.switch_next,
                                        switch_prev   = menu.switch_prev,
                                        item_height   = item_height,
                                    )
                                    if changed {
                                        settings.invert_y = new_value
                                        settings_apply(settings^)
                                    }
                                case .Mouse_Horizontal_Sensitivity:
                                    new_value, changed := menu_helper_item_spinner(
                                        ui,
                                        item_id       = "controls_menu:mouse_horizontal_sensitivity", 
                                        item_term     = .Mouse_Horizontal_Sensitivity, 
                                        current_value = settings.horizontal_sensitivity,
                                        min           = 1,
                                        max           = 10,
                                        step          = 1,
                                        format        = "%d",
                                        is_active     = is_active,
                                        anchor        = item_anchor,
                                        switch_next   = menu.switch_next,
                                        switch_prev   = menu.switch_prev,
                                        item_height   = item_height,
                                    )
                                    if changed {
                                        settings.horizontal_sensitivity = new_value
                                        settings_apply(settings^)
                                    }
                                case .Mouse_Vertical_Sensitivity:
                                    new_value, changed := menu_helper_item_spinner(
                                        ui,
                                        item_id       = "controls_menu:mouse_vertical_sensitivity", 
                                        item_term     = .Mouse_Vertical_Sensitivity, 
                                        current_value = settings.vertical_sensitivity,
                                        min           = 1,
                                        max           = 10,
                                        step          = 1,
                                        format        = "%d",
                                        is_active     = is_active,
                                        anchor        = item_anchor,
                                        switch_next   = menu.switch_next,
                                        switch_prev   = menu.switch_prev,
                                        item_height   = item_height,
                                    )
                                    if changed {
                                        settings.vertical_sensitivity = new_value
                                        settings_apply(settings^)
                                    }
                            }
                        }
                    }
                case .Footer:
                    res.close = menu_helper_settings_footer(
                        ui,
                        menu,
                        is_focused       = menu.focus_area == focus_area,
                        settings         = settings,
                        settings_default = CONTROLS_SETTINGS_DEFAULT,
                        back_id          = "controls_menu:back",
                        defaults_id      = "controls_menu:defaults",
                    )
            }
        }
        return
    },
    input_ui = proc(menu : ^Controls_Menu, ui : ^Ui, ev : sapp.Event) -> (res : Menu_Result) {
        return menu_helper_settings_input(menu, ui, ev)
    },
}


Audio_Menu :: Settings_Sub_Menu(Audio_Menu_Item_Id)

Audio_Menu_Item_Id :: enum {
    Master_Volume,
    Sound_Volume,
    Music_Volume,
}

AUDIO_MENU_CALLBACKS : Menu_Callbacks(^Audio_Menu) : {
    update_ui = proc(menu : ^Audio_Menu, ui : ^Ui) -> (res: Menu_Result) {
        defer {
            menu.switch_next = false
            menu.switch_prev = false
        }

        settings := &game_get_settings().audio

        for focus_area in type_of(menu.focus_area) {
            switch focus_area {
                case .Menu:
                    item_height :: 32
                    
                    spacing     :: 4
                    item_count  := cast(f32)len(Audio_Menu_Item_Id)
                    
                    // option container
                    rect, _, _ := ui_push_rect(
                        ui, 
                        sizing = {
                            Fixed{ 450 },
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
                        
                        for item in Audio_Menu_Item_Id {
                            is_active := has_current_item && current_item == item
                            defer item_anchor.offset.y += item_height + spacing
                            switch item {
                                case .Master_Volume:
                                    new_value, changed := menu_helper_item_progress_bar(
                                        ui,
                                        item_id          = "audio_menu:master_volume",
                                        item_term        = .Master_Volume, 
                                        current_value    = settings.master_volume,
                                        min              = 0.0,
                                        max              = 1.0,
                                        step             = 0.1,
                                        total_bar_width  = 200,
                                        left_control_id  = "audio_menu:master_volume:left_control",
                                        right_control_id = "audio_menu:master_volume:right_control",
                                        bar_id           = "audio_menu:master_volume:bar",
                                        format           = "%d",
                                        is_active        = is_active,
                                        anchor           = item_anchor,
                                        switch_next      = menu.switch_next,
                                        switch_prev      = menu.switch_prev,
                                        item_height      = item_height,
                                    )
                                    if changed {
                                        settings.master_volume = new_value
                                        settings_apply(settings^)
                                    }
                                case .Sound_Volume:
                                    new_value, changed := menu_helper_item_progress_bar(
                                        ui,
                                        item_id          = "audio_menu:sound_volume",
                                        item_term        = .Sound_Volume, 
                                        current_value    = settings.sound_volume,
                                        min              = 0.0,
                                        max              = 1.0,
                                        step             = 0.1,
                                        total_bar_width  = 200,
                                        left_control_id  = "audio_menu:sound_volume:left_control",
                                        right_control_id = "audio_menu:sound_volume:right_control",
                                        bar_id           = "audio_menu:sound_volume:bar",
                                        format           = "%d",
                                        is_active        = is_active,
                                        anchor           = item_anchor,
                                        switch_next      = menu.switch_next,
                                        switch_prev      = menu.switch_prev,
                                        item_height      = item_height,
                                    )
                                    if changed {
                                        settings.sound_volume = new_value
                                        settings_apply(settings^)
                                    }
                                case .Music_Volume:
                                    new_value, changed := menu_helper_item_progress_bar(
                                        ui,
                                        item_id          = "audio_menu:music_volume",
                                        item_term        = .Music_Volume, 
                                        current_value    = settings.music_volume,
                                        min              = 0.0,
                                        max              = 1.0,
                                        step             = 0.1,
                                        total_bar_width  = 200,
                                        left_control_id  = "audio_menu:music_volume:left_control",
                                        right_control_id = "audio_menu:music_volume:right_control",
                                        bar_id           = "audio_menu:music_volume:bar",
                                        format           = "%d",
                                        is_active        = is_active,
                                        anchor           = item_anchor,
                                        switch_next      = menu.switch_next,
                                        switch_prev      = menu.switch_prev,
                                        item_height      = item_height,
                                    )
                                    if changed {
                                        settings.music_volume = new_value
                                        settings_apply(settings^)
                                    }
                            }
                        }
                    }
                case .Footer:
                    res.close = menu_helper_settings_footer(
                        ui,
                        menu,
                        is_focused       = menu.focus_area == focus_area,
                        settings         = settings,
                        settings_default = AUDIO_SETTINGS_DEFAULT,
                        back_id          = "audio_menu:back",
                        defaults_id      = "audio_menu:defaults",
                    )
            }
        }
        return
    },
    input_ui = proc(menu : ^Audio_Menu, ui : ^Ui, ev : sapp.Event) -> (res : Menu_Result) {
        return menu_helper_settings_input(menu, ui, ev)
    },
}