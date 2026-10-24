package main 

import "core:os"
import "core:fmt"
import "core:encoding/json"

SAVE_DIR :: "."
SAVE_FILE :: "config.json"
SAVE_FILE_PATH := SAVE_DIR + "/" + SAVE_FILE

Game_Settings :: struct {
    graphics : Graphics_Settings,
    language : Language, 
}

GAME_SETTINGS_DEFAULT :: Game_Settings {
    graphics = GRAPHICS_SETTINGS_DEFAULT,
    language = LANGUAGE_DEFAULT,
}

LANGUAGE_DEFAULT :: Language.English

Graphics_Settings :: struct {
    resolution : Resolution,
    fullscreen : bool,
    gamma      : f32,
}

Resolution :: enum u8 {
    Resolution_480x270,
    Resolution_640x360,
    Resolution_960x540,
    Resolution_1280x720,
}

GRAPHICS_SETTINGS_DEFAULT : Graphics_Settings : {
    resolution = .Resolution_960x540,
    fullscreen = true,
    gamma      = 1,
}

@(rodata)
resolution_map : [Resolution][2]f32 = {
    .Resolution_480x270  = {480, 270},
    .Resolution_640x360  = {640, 360},
    .Resolution_960x540  = {960, 540},
    .Resolution_1280x720 = {1280, 720},
}

Audio_Settings :: struct {
    master     : f32,
    music      : f32,
    sfx        : f32,
}

Control_Settings :: struct {
    horizontal_sensitivity : f32,
    vertical_sensitivity   : f32,
    invert_y               : bool,
}

settings_save :: proc(settings : Game_Settings, allocator := context.temp_allocator) {
    if !os.exists(SAVE_DIR) {
        err := os.make_directory_all(SAVE_DIR)
        if err != nil {
            fmt.eprintfln("Cannot create directory %v for save file", SAVE_DIR)
            return
        }   
    }

    config_data, marshal_err := json.marshal(
        settings,
        {
            use_enum_names = true,
            pretty         = true,
        },
        allocator = allocator,
    )
    defer delete(config_data, allocator)

    if marshal_err != nil {
        fmt.eprintfln("Error marshalling graphics setting: %v", marshal_err)
    } else {
        save_err := os.write_entire_file(SAVE_FILE_PATH, config_data)
        if save_err != nil {
            fmt.eprintfln("Error saving graphics setting: %v", save_err)
        }
    }
}

settings_load :: proc(allocator := context.allocator) -> (settings : Game_Settings) {
    if !os.exists(SAVE_FILE_PATH) {
        return GAME_SETTINGS_DEFAULT
    }
    
    config_data, load_err := os.read_entire_file(SAVE_FILE_PATH, allocator = allocator)
    defer delete(config_data, allocator)

    if load_err != nil {
        fmt.eprintfln("Error loading graphics setting: %v", load_err)
        return
    }

    unmarshal_err := json.unmarshal(config_data, &settings, allocator = allocator)

    if unmarshal_err != nil {
        fmt.eprintfln("Error unmarshalling graphics setting: %v", unmarshal_err)
        return
    }

    return settings
}

settings_apply :: proc {
    settings_apply_all,
    settings_apply_graphics,
    settings_apply_language,
}

settings_apply_all :: proc(settings : Game_Settings){
    settings_apply(settings.graphics)
    settings_apply(settings.language)
}

settings_apply_graphics :: proc(config : Graphics_Settings) {
    game_set_fullscreen(config.fullscreen)
    game_request_size(resolution_map[config.resolution])
    game_set_gamma(config.gamma)
}

settings_apply_language :: proc(lang : Language) {
    game_switch_lang(lang)
}
