package main

import "core:math"

hsv :: proc(h: f32, s: f32 = 1.0, v : f32 = 1.0, a : f32 = 1.0) -> [4]f32 {
    h := math.mod(h, 360)
    if h < 0 do h += 360
    
    c := v * s
    x := c * (1 - math.abs(math.mod(h / 60, 2) - 1))
    m := v - c
    
    rgb_prime : [3]f32

    switch h {
        case 0  ..<60  : rgb_prime = {c, x, 0}
        case 60 ..<120 : rgb_prime = {x, c, 0}
        case 120..<180 : rgb_prime = {0, c, x}
        case 180..<240 : rgb_prime = {0, x, c}
        case 240..<300 : rgb_prime = {x, 0, c}
        case           : rgb_prime = {c, 0, x}
    }

    rgb_prime += m
    rgba : [4]f32 = {rgb_prime.r, rgb_prime.g, rgb_prime.b, a}
    
    return rgba
}