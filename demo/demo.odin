package demo

import "core:fmt"

Struct1 :: struct {
	position : [3]f32,
	origin   : [3]f32,
	type     : u8,
}

Struct2 :: struct #packed {
	position : [3]f32,
	origin   : [3]f32,
	type     : u8,
}

Struct3 :: struct #packed {
	using _ : Struct1
}

main :: proc() {
	fmt.println(size_of(Struct1), size_of(Struct2), size_of(Struct3))
}