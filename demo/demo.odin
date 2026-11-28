package demo

import "core:fmt"
import "core:slice"


main :: proc() {
	arr : [dynamic]int
	append(&arr, 1)
	append(&arr, 2)
	append(&arr, 4)
	append(&arr, 6)

	target := 2
	for &val, i in arr {
		if val == target {
			unordered_remove(&arr, i) 
			fmt.println(val)
		}
	}
}