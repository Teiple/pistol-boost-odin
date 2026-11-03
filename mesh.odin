package main

import "core:slice"
import sg "sokol-odin/sokol/gfx"

Vertex :: struct {
	position : [3]f32,
	color    : [4]f32,
	uv       : [2]f32,
}

Mesh_Data :: struct {
    vertices     : []Vertex,
    indices      : []u16,
}

Mesh :: struct {
	bindings    : sg.Bindings,
	index_count : i32,
}

mesh_create_from_data :: proc(data : Mesh_Data) -> (mesh : Mesh)  {
    vertices := data.vertices
    indices  := data.indices
    
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
            image = sg_placeholder_image,
        }
    })
    mesh.bindings.samplers[0] = sg.make_sampler({})

    return mesh
}

mesh_create_box :: proc(half_size : [3]f32) -> Mesh {
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

    return mesh_create_from_data({vertices, indices})
}

// convert any triangle indices to line indices that can be used for wire drawing
// used dynamic here since it keeps the allocator so we don't need to keep track of it
// also llm wrote this
mesh_create_line_indices :: proc(tri_indices: []u16, allocator := context.allocator) -> [dynamic]u16 {
	tri_count    := len(tri_indices) / 3
	line_indices := make([dynamic]u16, tri_count * 6)

	for i in 0 ..< tri_count {
		i0 := tri_indices[i * 3 + 0]
		i1 := tri_indices[i * 3 + 1]
		i2 := tri_indices[i * 3 + 2]

		line_indices[i * 6 + 0] = i0
		line_indices[i * 6 + 1] = i1
		line_indices[i * 6 + 2] = i1
		line_indices[i * 6 + 3] = i2
		line_indices[i * 6 + 4] = i2
		line_indices[i * 6 + 5] = i0
	}

	return line_indices
}

mesh_destroy :: proc(mesh : ^Mesh) {
    sg.destroy_buffer(mesh.bindings.vertex_buffers[0])
    sg.destroy_buffer(mesh.bindings.index_buffer)
    sg.destroy_view(mesh.bindings.views[0])
}