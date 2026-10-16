package main

Time_Scale_Slot_Id :: enum {
    Base,
    Pause_Menu,
}

Game_Time :: struct {
    scaled_time      : f32,
    unscaled_time    : f32,
    time_scale       : f32,
    time_scale_stack : [Time_Scale_Slot_Id]f32
}

game_time_init :: proc(time : ^Game_Time) {
    game_time_reset_time_scale(time)
}

game_time_reset_time_scale :: proc(time : ^Game_Time) {
    for &slot in time.time_scale_stack {
        slot = 1
    }
}

@(require_results)
game_time_raw_update :: proc(time : ^Game_Time, unscaled_dt : f32) -> (scaled_dt : f32) {
    time.unscaled_time += unscaled_dt
    
    time.time_scale = 1
    for scale in time.time_scale_stack {
        time.time_scale *= scale
    }

    scaled_dt = time.time_scale * unscaled_dt
    
    time.scaled_time += scaled_dt

    return scaled_dt
}

game_time_set_time_scale :: proc(time : ^Game_Time, slot : Time_Scale_Slot_Id, value : f32) {
    time.time_scale_stack[slot] = value
}