package main

import "core:math/linalg"
import "core:slice"
import sg "sokol-odin/sokol/gfx"

debug_draw : ^Debug_Draw

Debug_Draw_Mode :: enum u8{
    // Must order this way, solid then wire on top
    Triangle,
    Line,
}

Debug_Draw_Mode_Resource :: struct {
    pipeline : Pipeline_Type,
    bindings : sg.Bindings,
    // Doesn't grow, just for validation, but can be added later
    vbuffer  : sg.Buffer,
    ibuffer  : sg.Buffer,
    vertices : [dynamic]Vertex,
    indices  : [dynamic]u16,
    current_vbuf_cap : uint,
    current_ibuf_cap : uint,
}

Debug_Draw :: struct {
    modes          : [Debug_Draw_Mode]Debug_Draw_Mode_Resource,
    shared_view    : sg.View,
    shared_sampler : sg.Sampler,
    active         : bool,
}

debug_draw_init :: proc(draw : ^Debug_Draw, allocator := context.allocator) {
    draw.shared_view    = sg.make_view({
        texture = { image = sg_placeholder_image }
    })
    draw.shared_sampler = sg.make_sampler({})

    for &mode, mode_id in draw.modes {
        switch mode_id {
            case .Line:
                mode.pipeline = .Unlit_Lines

                mode.current_ibuf_cap = 1024
                mode.current_vbuf_cap = 1024
                
                mode.vertices  = make([dynamic]Vertex, len = 0, cap = mode.current_vbuf_cap, allocator = allocator)
                mode.indices   = make([dynamic]u16,    len = 0, cap = mode.current_ibuf_cap, allocator = allocator)

                mode.bindings.index_buffer = sg.make_buffer({
                    // write_transient allows us to update the buffer later 
                    usage = { index_buffer = true, write_transient = true },
                    size  =  size_of(u16) * mode.current_ibuf_cap,
                })

                mode.bindings.vertex_buffers[0] = sg.make_buffer({
                    // vertex buffer is the default btw, just to make it clearer
                    usage = { vertex_buffer = true, write_transient = true },
                    size  =  size_of(Vertex) * mode.current_vbuf_cap,
                })

                mode.bindings.views[0]   = draw.shared_view
                mode.bindings.samplers[0] = draw.shared_sampler
            case .Triangle:
                mode.pipeline = .Unlit_Triangles

                mode.current_ibuf_cap = 1024
                mode.current_vbuf_cap = 1024
                
                mode.vertices  = make([dynamic]Vertex, len = 0, cap = mode.current_vbuf_cap, allocator = allocator)
                mode.indices   = make([dynamic]u16,    len = 0, cap = mode.current_ibuf_cap, allocator = allocator)

                mode.bindings.index_buffer = sg.make_buffer({
                    // write_transient allows us to update the buffer later 
                    usage = { index_buffer = true, write_transient = true },
                    size  =  size_of(u16) * mode.current_ibuf_cap,
                })

                mode.bindings.vertex_buffers[0] = sg.make_buffer({
                    // vertex buffer is the default btw, just to make it clearer
                    usage = { vertex_buffer = true, write_transient = true },
                    size  =  size_of(Vertex) * mode.current_vbuf_cap,
                })
                
                mode.bindings.views[0]    = draw.shared_view
                mode.bindings.samplers[0] = draw.shared_sampler
        }
    }
    debug_draw = draw
}

debug_draw_destroy :: proc(draw : ^Debug_Draw) {
    for &mode in draw.modes {
        delete(mode.indices)  
        delete(mode.vertices)  
        
        // destroying shared resources multiple time is no-op
        sg.destroy_sampler(mode.bindings.samplers[0])
        sg.destroy_view(mode.bindings.views[0])
        sg.destroy_buffer(mode.bindings.vertex_buffers[0])
        sg.destroy_buffer(mode.bindings.index_buffer)

        // image is place holder hold by the renderer
    }
}

debug_draw_begin :: proc(draw : ^Debug_Draw) {
    draw.active = true
    
    for &mode in draw.modes {
        clear(&mode.indices)
        clear(&mode.vertices)
    }
}

debug_draw_3d :: proc(draw : ^Debug_Draw, renderer : ^Renderer) {
    assert(draw.active)
    defer draw.active = false
    
    for &mode in draw.modes {
        if uint(len(mode.indices)) > mode.current_ibuf_cap {
            panic("Exceed ibuf cap!")
        }
        if uint(len(mode.vertices)) > mode.current_vbuf_cap {
            panic("Exceed vbuf cap!")
        }

        sg.write_buffer_transient({
            dst = {
                buffer = mode.bindings.index_buffer, 
            },
            src = {
                data = { ptr = raw_data(mode.indices), size = cast(uint)slice.size(mode.indices[:])}
            }
        })
        sg.write_buffer_transient({
            dst = {
                buffer = mode.bindings.vertex_buffers[0], 
            },
            src = {
                data = { ptr = raw_data(mode.vertices), size = cast(uint)slice.size(mode.vertices[:])}
            }
        })

        renderer_draw_bindings(renderer, mode.bindings, len(mode.indices), mode.pipeline)
    }
}

debug_draw_box :: proc(
    draw      : ^Debug_Draw,
    half_size : [3]f32,
    color     : [4]f32,
    position  : [3]f32 = 0,
    rotation  : quaternion128 = 1,
) {
    assert(draw.active)

    // cube vertex buffer
    vertices := [?]Vertex {
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
    // 6 faces of the cube, 2 tris each face 
    indices := [?]u16 {
        // back -z, from 0
        0,  1,  2,   0,  2,  3,
        // front +z, from 6
        6,  5,  4,   7,  6,  4,
        // left -x, from 12
        8,  9, 10,   8, 10, 11,
        // right +x, from 18
        14, 13, 12,  15, 14, 12,
        // bottom -y, from 24
        16, 17, 18,  16, 18, 19,
        // top +y, from 30
        22, 21, 20,  23, 22, 20,
    }

    for &v in vertices {
    	v.color    = color
    	v.position = linalg.quaternion128_mul_vector3(
            rotation, v.position
        ) * half_size + position
    }

    cur_vbuf_len := len(draw.modes[.Triangle].vertices)
    vertex_count := len(vertices)

    cur_ibuf_len := len(draw.modes[.Triangle].indices)
    index_count  := len(indices)

    // offset other vertices that has been added
    indices += u16(cur_vbuf_len)
    
    assert(
        uint(cur_vbuf_len + vertex_count) <= draw.modes[.Triangle].current_vbuf_cap,
        "Exceed vbuf cap!",
    )

    assert(
        uint(cur_ibuf_len + index_count) <= draw.modes[.Triangle].current_ibuf_cap,
        "Exceed ibuf cap!",
    )

    append(&draw.modes[.Triangle].vertices, ..vertices[:])
    append(&draw.modes[.Triangle].indices,  ..indices[:])
}


debug_draw_wire_box :: proc(
    draw      : ^Debug_Draw,
    half_size : [3]f32,
    position  : [3]f32 = 0,
    rotation  : quaternion128 = 1,
    color     : [4]f32 = {1, 0, 0, 1},
) {
    assert(draw.active)

    vertices := [?]Vertex {
        {{-1.0, -1.0, -1.0}, 1, 0},
        {{ 1.0, -1.0, -1.0}, 1, 0},
        {{ 1.0,  1.0, -1.0}, 1, 0},
        {{-1.0,  1.0, -1.0}, 1, 0},
        {{-1.0, -1.0,  1.0}, 1, 0},
        {{ 1.0, -1.0,  1.0}, 1, 0},
        {{ 1.0,  1.0,  1.0}, 1, 0},
        {{-1.0,  1.0,  1.0}, 1, 0},
    }
    indices := [?]u16 {
        0, 1,  1, 2,  2, 3,  3, 0,
        4, 5,  5, 6,  6, 7,  7, 4,
        0, 4,  1, 5,  2, 6,  3, 7,
    }

    for &v in vertices {
    	v.color    = color
        v.position = linalg.quaternion128_mul_vector3(
            rotation, v.position
        ) * half_size + position
    }

    cur_vbuf_len := len(draw.modes[.Line].vertices)
    vertex_count := len(vertices)

    cur_ibuf_len := len(draw.modes[.Line].indices)
    index_count  := len(indices)

    // offset other vertices that has been added
    indices += u16(cur_vbuf_len)

    assert(
        uint(cur_vbuf_len + vertex_count) <= draw.modes[.Line].current_vbuf_cap,
        "Exceed vbuf cap!",
    )

    assert(
        uint(cur_ibuf_len + index_count) <= draw.modes[.Line].current_ibuf_cap,
        "Exceed ibuf cap!",
    )

    append(&draw.modes[.Line].vertices, ..vertices[:])
    append(&draw.modes[.Line].indices,  ..indices[:])
}