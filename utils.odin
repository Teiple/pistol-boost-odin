package main

import "core:math"
import ins "base:intrinsics"
import "core:math/linalg"

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

euler_degrees_to_quat :: proc(angles: [3]f32) -> quaternion128 {
	r := linalg.matrix4_from_euler_angles_xyz_f32(
		math.to_radians_f32(angles.x),
		math.to_radians_f32(angles.y),
		math.to_radians_f32(angles.z),
	)
	return linalg.quaternion_from_matrix4(r)
}