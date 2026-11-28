package demo

import "core:fmt"
import "core:slice"

Box :: struct {
	origin : [3]f32,
	size   : [3]f32,
}

Platform :: struct {
	using _ : Box,
	variant : int,
}

main :: proc() {
	arr : [dynamic]Platform
	append(&arr, {origin = 0, size = 1, variant = 2})
	append(&arr, {origin = 0, size = 1, variant = 2})
	append(&arr, {origin = 0, size = 1, variant = 2})
	append(&arr, {origin = 0, size = 1, variant = 2})

	boxes := cast([]Box)arr[:]

	fmt.println(boxes)
}