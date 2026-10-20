package main

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

Graphics_Menu :: struct {
    current_item     : Graphics_Menu_Item_Id,
    selected_current : bool,
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
    type_item_options_of(Resolution),
    type_item_options_of(ToggleState),
}

Graphics_Menu_Item_Id :: enum {
    Resolution,
    Vsync,
}

@(rodata)
graphics_menu_options : [Graphics_Menu_Item_Id]Graphics_Setting_Menu_Item = {
    .Resolution = type_item_options_of(Resolution) {
        item_id       = "graphics_menu:resolution",
        item_term     =  .Resolution,
        option_box_id = "graphics_menu:resolution:value",
        options       = {
            labels    = {
                .Res_800x480 = "800x480",
                .Res_800x600 = "800x600",
                .Res_960x540 = "960x540",
            },
        }
    },
    .Vsync =  type_item_options_of(ToggleState) {
        item_id       = "graphics_menu:vsync",
        item_term     =  .Vsync,
        option_box_id = "graphics_menu:vsync:value",
        options       = {
            .On   = .On,
            .Off  = .Off,
        }
    },
}

graphics_menu_back_btn_id :: "graphics_menu:id"

GRAPHICS_MENU_CALLBACKS : Menu_Callbacks(^Graphics_Menu) : {

    update_ui = proc(menu : ^Graphics_Menu, ui : ^Ui) -> (res: Menu_Result) {
        item_height :: 32
        widths : [2]f32 : {100, 100}
        spacing   :: 4
        item_count := cast(f32)len(Graphics_Menu_Item_Id)
        
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

        ui_push_container(ui, rect)
        {
            defer ui_pop_container(ui)

            item_anchor : Anchor

            for menu_item, id in graphics_menu_options {
                switch item in menu_item {
                case type_item_options_of(Resolution):
                    ui_push_text(ui, tr(item.item_term), anchor = item_anchor)
                case type_item_options_of(ToggleState):
                    ui_push_text(ui, tr(item.item_term), anchor = item_anchor)
                }
                 
                item_anchor.offset.y += item_height + spacing
            }
        }

        res.close = menu_helper_back_button(ui, "graphics_menu:back", .Back)
        
        return
    },
    input_ui = proc(menu : ^Graphics_Menu, ui : ^Ui, ev : sapp.Event) -> (res : Menu_Result) {
        // res.close = menu_helper_label_menu_input(
        //     ui               = ui,
        //     ev               = ev,
        //     selected_current = &menu.selected_current,
        //     current_item     = &menu.current_item,
        // )
        return
    },
}