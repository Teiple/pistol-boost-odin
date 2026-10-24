package main

import "core:flags"
import sapp "sokol-odin/sokol/app"

Language_Menu :: struct {
    show             : bool,
    current_item     : Language,
    selected_current : bool,
}

@(rodata)
language_menu_items := [Language]Menu_Item{
    .English           = { id = "lang_menu:en", term = { LANGUAGE_SELECTIONS[.English],           .English }},
    .Vietnamese        = { id = "lang_menu:vi", term = { LANGUAGE_SELECTIONS[.Vietnamese],        .Vietnamese }},
    .Simplified_Chinese = { id = "lang_menu:sc", term = { LANGUAGE_SELECTIONS[.Simplified_Chinese], .Simplified_Chinese }},
    .Japanese          = { id = "lang_menu:jp", term = { LANGUAGE_SELECTIONS[.Japanese],          .Japanese }},
}

language_menu_back_btn_id :: "lang_menu:back"

LANGUAGE_MENU_CALLBACKS : Menu_Callbacks(^Language_Menu) : {
    update_ui = proc(menu : ^Language_Menu, ui : ^Ui) -> (res: Menu_Result) {
        defer menu.selected_current = false

        selected_opt, selected := menu_helper_label_menu(
            menu             = menu,
            ui               = ui,
            selected_current = menu.selected_current,
            current_item     = menu.current_item,
            items            = language_menu_items,
        )

        if selected {
            game_switch_lang(selected_opt)
        }

        res.close = menu_helper_back_button(
            ui    = ui,
            label = .Back,
            id    = language_menu_back_btn_id,
        )

        return
    },
    input_ui = proc(menu : ^Language_Menu, ui : ^Ui, ev : sapp.Event) -> (res : Menu_Result) {
        res.close = menu_helper_label_menu_input(
            ui               = ui,
            ev               = ev,
            selected_current = &menu.selected_current,
            current_item     = &menu.current_item,
        )
        return
    },
    open = proc(menu : ^Language_Menu) {
        menu.show = true
        menu.current_item = cast(Language)game_lang()
    },
    close = proc(menu : ^Language_Menu) {
        menu.show = false
    },
}