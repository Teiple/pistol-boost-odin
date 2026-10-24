package main

import ins "base:intrinsics"

enum_next :: proc(current : $T) -> T where ins.type_is_enum(T) && ins.type_enum_is_contiguous(T) {
    return cast(T)((int(current) + 1) % len(T))
}

enum_prev :: proc(current : $T) -> T where ins.type_is_enum(T) && ins.type_enum_is_contiguous(T) {
    prev := int(current) - 1
    if prev < 0 {
        return cast(T)(prev + len(T))
    } else {
        return cast(T)(prev % len(T))
    }
}
