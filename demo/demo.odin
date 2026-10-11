package main

import "core:fmt"

get_arr :: proc() -> []f32 {
    @(static, rodata)
    arr := []f32 {
        0, 1, 2, 4
    }
    arr[0] = 2
    return arr
}

main :: proc() {
    a := get_arr()
    fmt.println(a)   
}