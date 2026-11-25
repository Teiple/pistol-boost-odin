package demo

import "core:fmt"

main :: proc() {
	arr : [dynamic]i32
	append(&arr, 5)
	append(&arr, 2)
	append(&arr, 4)
	append(&arr, 8)

	for _, index in arr {
		ordered_remove(&arr, index)
	}

	fmt.println(arr)
}