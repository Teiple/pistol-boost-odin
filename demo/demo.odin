package main

import "core:fmt"


main :: proc() {
    a : [dynamic]f32
    append(&a, 12)
    append(&a, -15)
    append(&a, 7)
    append(&a, 24)
    append(&a, 10)

    fmt.println(a[5:5])

    for i in a[5:6] {
        fmt.println(i)
    }
}