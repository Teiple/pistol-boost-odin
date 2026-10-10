package main

import "core:slice"
import sg "sokol-odin/sokol/gfx"

Vertex :: struct {
	position : [3]f32,
	color    : [4]f32,
	uv       : [2]f32,
}

Mesh :: struct {
	bindings : sg.Bindings,
	index_count   : i32,
}

// create a checkerboard image and texture view (from sokol examples)
CHECKER_BOARD_PATTERN :: []u32 {
    0xFFFFFFFF, 0xFF000000, 0xFFFFFFFF, 0xFF000000,
    0xFF000000, 0xFFFFFFFF, 0xFF000000, 0xFFFFFFFF,
    0xFFFFFFFF, 0xFF000000, 0xFFFFFFFF, 0xFF000000,
    0xFF000000, 0xFFFFFFFF, 0xFF000000, 0xFFFFFFFF,
}

WHITE_PIXEL :: []u32 { 0xFFFFFFFF }

mesh_init_from_data :: proc(mesh : ^Mesh, vertices : []Vertex, indices : []u16) {
	mesh.bindings.vertex_buffers[0] = sg.make_buffer({
		data = { ptr = raw_data(vertices), size = cast(uint)slice.size(vertices)}
	})
	mesh.bindings.index_buffer = sg.make_buffer({
        usage = { index_buffer = true }, 
		data  = { ptr = raw_data(indices), size = cast(uint)slice.size(indices)}
	})
	mesh.index_count = cast(i32)len(indices)

    // default views and sample bindings
    mesh.bindings.views[0] = sg.make_view({
        texture = {
            image = sg.make_image({
                width = 1,
                height = 1,
                data = {
                    mip_levels = {
                        0 = {
                            ptr = raw_data(WHITE_PIXEL),
                            size = cast(uint)slice.size(WHITE_PIXEL)
                        }
                    }
                }
            })
        }
    })
    mesh.bindings.samplers[0] = sg.make_sampler({})
}

mesh_init_box :: proc(mesh : ^Mesh, half_size : [3]f32) {
	// cube vertex buffer
    vertices : []Vertex = {
        {{-1.0, -1.0, -1.0}, 1, { 0, 0 }},  
        {{ 1.0, -1.0, -1.0}, 1, { 1, 0 }},  
        {{ 1.0,  1.0, -1.0}, 1, { 1, 1 }},  
        {{-1.0,  1.0, -1.0}, 1, { 0, 1 }},  
        {{-1.0, -1.0,  1.0}, 1, { 0, 0 }},  
        {{ 1.0, -1.0,  1.0}, 1, { 1, 0 }},  
        {{ 1.0,  1.0,  1.0}, 1, { 1, 1 }},  
        {{-1.0,  1.0,  1.0}, 1, { 0, 1 }},  
        {{-1.0, -1.0, -1.0}, 1, { 0, 0 }},  
        {{-1.0,  1.0, -1.0}, 1, { 1, 0 }},  
        {{-1.0,  1.0,  1.0}, 1, { 1, 1 }},  
        {{-1.0, -1.0,  1.0}, 1, { 0, 1 }},  
        {{ 1.0, -1.0, -1.0}, 1, { 0, 0 }},  
        {{ 1.0,  1.0, -1.0}, 1, { 1, 0 }},  
        {{ 1.0,  1.0,  1.0}, 1, { 1, 1 }},  
        {{ 1.0, -1.0,  1.0}, 1, { 0, 1 }},  
        {{-1.0, -1.0, -1.0}, 1, { 0, 0 }},  
        {{-1.0, -1.0,  1.0}, 1, { 1, 0 }},  
        {{ 1.0, -1.0,  1.0}, 1, { 1, 1 }},  
        {{ 1.0, -1.0, -1.0}, 1, { 0, 1 }},  
        {{-1.0,  1.0, -1.0}, 1, { 0, 0 }},  
        {{-1.0,  1.0,  1.0}, 1, { 1, 0 }},  
        {{ 1.0,  1.0,  1.0}, 1, { 1, 1 }},  
        {{ 1.0,  1.0, -1.0}, 1, { 0, 1 }},  
    }
    // create an index buffer for the cube
    indices := []u16 {
         0,  1,  2,   0,  2,  3,
         6,  5,  4,   7,  6,  4,
         8,  9, 10,   8, 10, 11,
        14, 13, 12,  15, 14, 12,
        16, 17, 18,  16, 18, 19,
        22, 21, 20,  23, 22, 20,
    }

    for &v in vertices {
    	v.color     = {v.position.x, v.position.y, v.position.z, 1}
    	v.color.rgb = v.color.xyz * 0.5 + 0.5
    	v.position  *= half_size
    }

    mesh_init_from_data(mesh, vertices, indices)
}