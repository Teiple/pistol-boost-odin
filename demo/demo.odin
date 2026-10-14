package main

import "core:fmt"


main :: proc() {
    a : [dynamic]f32
    append(&a, 12)
    append(&a, 24)
}