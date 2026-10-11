package main

import ins "base:intrinsics"
import "core:fmt"

Gen_Struct :: struct($T : typeid) where ins.type_is_pointer(T) {
    data : T
}
 
main :: proc() {
    a : Gen_Struct(^int)
    fmt.println(a)   
}