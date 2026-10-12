package main

import ins "base:intrinsics"
import "core:fmt"

Union :: struct {
    
}

main :: proc() {
    a : Gen_Struct(^int)
    fmt.println(a)   
}