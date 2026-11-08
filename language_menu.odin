package main

import sapp "sokol-odin/sokol/app"

Language_Menu :: struct {
    current_item     : Language,
    show             : bool,
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
    update_ui = proc(menu : ^Language_Menu, ctx : Game_Context) -> (res: Menu_Result) {
        defer menu.selected_current = false

        selected_opt, selected := menu_helper_label_menu(
            menu             = menu,
            ctx              = ctx,
            selected_current = menu.selected_current,
            current_item     = menu.current_item,
            items            = language_menu_items,
        )

        if selected {
            ctx.settings.language = selected_opt
        }

        res.close = menu_helper_back_button(
            ui    = ctx.ui,
            label = .Back,
            id    = language_menu_back_btn_id,
        )

        return
    },
    input_ui = proc(menu : ^Language_Menu, ctx : Game_Context, ev : sapp.Event) -> (res : Menu_Result) {
        res.close = menu_helper_label_menu_input(
            ui               = ctx.ui,
            ev               = ev,
            selected_current = &menu.selected_current,
            current_item     = &menu.current_item,
        )
        return
    },
    open = proc(menu : ^Language_Menu, ctx : Game_Context) {
        menu.show = true
        menu.current_item = ctx.settings.language
    },
    close = proc(menu : ^Language_Menu, ctx : Game_Context) {
        menu.show = false
    },
}