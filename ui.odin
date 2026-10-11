package main
// This is a very mininal anchor based ui system

import "core:fmt"
import "core:math/linalg"
import "core:slice"
import sg "sokol-odin/sokol/gfx"
import tt "vendor:stb/truetype"
import shaders "shaders"

Anchor :: struct {
    container : [4]f32,
    element   : [2]f32,
    parent    : [2]f32,
}

Font_Id :: enum {
    Normal,
    Mono
}

Font :: struct {
    atlas_size     : [2]f32,
    base_size      : f32,
    font_spacing   : f32,
    line_spacing   : f32,
    ascent         : f32,
    descent        : f32,
    baked_chars    : [96]tt.bakedchar,
}

Ui_Builder :: struct {
    current_container : [4]f32
}

Ui :: struct {
    font_img    : sg.Image,
    pipeline    : sg.Pipeline,
    shader      : sg.Shader,
    bindings    : sg.Bindings,
    
    fonts       : [Font_Id]Font,

    // These can be used to impl growing buf but for 
    // now they are just for validation
    cur_vbuf_cap : uint ,
    cur_ibuf_cap : uint,

    vertices : [dynamic]Vertex,
    indices  : [dynamic]u16,

    builder  : Ui_Builder,
}

ui_init_default :: proc(ui : ^Ui) {
    ui.fonts = {
        .Normal = ui_make_font(ui, #load("assets/fonts/NotoSans_SemiCondensed-SemiBold.ttf")),
        .Mono   = ui_make_font(ui, #load("assets/fonts/NotoSans_Mono.ttf")),
    }

    ui.shader   = sg.make_shader(shaders.unlit_shader_desc(sg.query_backend()))
	ui.pipeline = sg.make_pipeline({
		index_type  = .UINT16,
		shader      = ui.shader,
		layout      = {
			attrs   = {
				shaders.ATTR_unlit_pos       = { format = .FLOAT3 },
				shaders.ATTR_unlit_color0    = { format = .FLOAT4 },
				shaders.ATTR_unlit_texcoord0 = { format = .FLOAT2 },
			}
		},
		cull_mode   = .NONE,
		depth       = {
			write_enabled = false,
			compare       = .ALWAYS
		},
        colors      = {
            0 = {
                blend = {
                    enabled = true,
                    // standard color overlay i guess
                    src_factor_rgb   = .SRC_ALPHA,
                    dst_factor_rgb   = .ONE_MINUS_SRC_ALPHA,
                    src_factor_alpha = .ONE,
                    dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
                }
            }
        }
	})

    ui.cur_ibuf_cap = 1024
    ui.cur_vbuf_cap = 1024

    ui.vertices = make([dynamic]Vertex, 0, ui.cur_vbuf_cap)
    ui.indices  = make([dynamic]u16, 0, ui.cur_ibuf_cap)

    ui.bindings.index_buffer = sg.make_buffer({
        // write_transient allows us to update the buffer later 
        usage = { index_buffer = true, write_transient = true },
        size  =  size_of(u16) * ui.cur_ibuf_cap,
    })

    ui.bindings.vertex_buffers[0] = sg.make_buffer({
        // vertex buffer is the default btw, just to make it clearer
        usage = { vertex_buffer = true, write_transient = true },
        size  =  size_of(Vertex) * ui.cur_vbuf_cap,
    })

    ui.bindings.samplers[0] = sg.make_sampler({})
    ui.bindings.views[0]    = sg.make_view({
        texture = {
            image = ui.font_img,
        }
    })
}

ui_destroy :: proc(ui : ^Ui) {
    sg.destroy_image(ui.font_img)
    sg.destroy_view(ui.bindings.views[0])

    sg.destroy_sampler(ui.bindings.samplers[0])

    sg.destroy_buffer(ui.bindings.index_buffer)
    sg.destroy_buffer(ui.bindings.vertex_buffers[0])

    sg.destroy_shader(ui.shader)
    sg.destroy_pipeline(ui.pipeline)

    delete(ui.vertices)
    delete(ui.indices)
}

Glyph :: struct {
    offset   : [3]f32,
    xadvance : f32, 
}


ui_make_font :: proc(
    ui           : ^Ui,
    data         : []byte,
    base_size    : f32 = 32,
    spacing      : f32 = 0,
    line_spacing : f32 = 2,
    atlas_size   : [2]i32 = {256, 128},
    allocator    := context.allocator
) -> (font: Font) {
    font.base_size = base_size
    font.font_spacing   = spacing
    font.line_spacing   = line_spacing
    font.atlas_size     = cast([2]f32)atlas_size

    atlas := make([]byte, len = atlas_size.x * atlas_size.y, allocator = allocator)
    defer delete(atlas)

    // very annoying side quest to fetch the v metrics
    // since they wouldn't include them when using BakeFontBitmap()
    {
        font_info : tt.fontinfo
        tt.InitFont(&font_info, raw_data(data), 0)
        ascent, descent, line_gap : i32
        tt.GetFontVMetrics(&font_info, &ascent, &descent, &line_gap)

        scale := tt.ScaleForPixelHeight(&font_info, base_size)

        font.ascent  = f32(ascent)  * scale
        font.descent = f32(descent) * scale
    }

    row_used := tt.BakeFontBitmap(
        data         = raw_data(data),
        offset       = 0,
        pixel_height = base_size,
        pixels       = raw_data(atlas),
        pw           = atlas_size.x,
        ph           = atlas_size.y,
        // standard printable ASCII chars
        first_char   = 32,
        num_chars    = 92,
        chardata     = raw_data(font.baked_chars[:]),
    )

    assert(row_used > 0, "Atlas is overflowed! Try increase atlas_size or reduce base_size")

    atlas_rgba8 := make([]byte, len = atlas_size.x * atlas_size.y * 4, allocator = allocator)
    defer delete(atlas_rgba8)

    for p, i in atlas {
        atlas_rgba8[i * 4]     = 255
        atlas_rgba8[i * 4 + 1] = 255
        atlas_rgba8[i * 4 + 2] = 255
        atlas_rgba8[i * 4 + 3] = p
    }

    ui.font_img = sg.make_image({
        pixel_format = .RGBA8, 
        width  = atlas_size.x,
        height = atlas_size.y,
        data   = {
            mip_levels = {
                0 = {
                    ptr = raw_data(atlas_rgba8),
                    size = cast(uint)slice.size(atlas_rgba8)
                }
            }
        }
    })

    return font
}

ui_get_quad :: proc(
    position     : [2]f32,
    index_offset : u16,
    size         : [2]f32,
    uv_rect      : [4]f32,
    color        : [4]f32
) -> (v: [4]Vertex, i: [6]u16) {
    vertices : [4]Vertex = {
        {{ position.x,          position.y,          0 }, color, { uv_rect.x,             uv_rect.y }},
        {{ position.x,          position.y + size.y, 0 }, color, { uv_rect.x,             uv_rect.y + uv_rect.w }},
        {{ position.x + size.x, position.y + size.y, 0 }, color, { uv_rect.x + uv_rect.z, uv_rect.y + uv_rect.w }},
        {{ position.x + size.x, position.y,          0 }, color, { uv_rect.x + uv_rect.z, uv_rect.y }},
    }
    indices : [6]u16 = {
        0, 1, 2, 2, 3, 0
    } + index_offset

    return vertices, indices
}

ui_draw_text :: proc(
    ui        : ^Ui,
    font_id   : Font_Id,
    text      : string,
    font_size : f32 = 32,
    color     : [4]f32 = {0.2, 0.8, 0.2, 1},
    anchor    : Anchor = {},
) -> (ele_rect : [4]f32) {
    // use address here since font struct is quite big
    font := &ui.fonts[font_id]

    if len(text) == 0 do return

    scale := font_size / font.base_size
    pen   := [2]f32{0, font.ascent * scale}

    ele_rect.xy = pen
    ele_rect.w  = pen.y

    base_index       := u16(len(ui.indices))

    // capture the vertex range to update their position later
    start_vert_index := len(ui.vertices)
    end_vert_index   := start_vert_index

    for r in text {
        char := i32(r)
        assert(char >= 32 && char <= 32 + 92, "Only support ASCII text!")
        char  -= 32
        bchar := font.baked_chars[char]

        // rect is easier to reason about imo
        rect:= [4]f32{
            f32(bchar.x0),
            f32(bchar.y0),
            f32(bchar.x1 - bchar.x0),
            f32(bchar.y1 - bchar.y0),
        }

        uv_rect := rect
        uv_rect.xz /= font.atlas_size.x
        uv_rect.yw /= font.atlas_size.y

        v,i := ui_get_quad(
            position     = pen + {bchar.xoff, bchar.yoff} * scale,
            index_offset = base_index,
            size         = rect.zw * scale,
            uv_rect      = uv_rect,
            color        = color,
        )

        base_index     += len(v)
        end_vert_index += len(v)

        append(&ui.vertices, ..v[:])
        append(&ui.indices,  ..i[:])

        pen.x      += bchar.xadvance * scale
        ele_rect.z += bchar.xadvance * scale
    }

    assert(start_vert_index < end_vert_index)
    
    for i in start_vert_index..<end_vert_index {
        v := &ui.vertices[i]
        v.position.xy += anchor.container.xy
        v.position.xy += anchor.parent  * anchor.container.zw
        v.position.xy -= anchor.element * ele_rect.zw
    }

    return ele_rect
}

ui_draw :: proc(ui : ^Ui, viewport : ^Viewport) {
    assert(len(ui.indices)  <= int(ui.cur_ibuf_cap), "Exceed ibuf cap!")
    assert(len(ui.vertices) <= int(ui.cur_vbuf_cap), "Exceed vbuf cap!")

    sg.write_buffer_transient({
        dst = {
            buffer = ui.bindings.index_buffer, 
        },
        src = {
            data = { ptr = raw_data(ui.indices), size = cast(uint)slice.size(ui.indices[:])}
        }
    })
    sg.write_buffer_transient({
        dst = {
            buffer = ui.bindings.vertex_buffers[0], 
        },
        src = {
            data = { ptr = raw_data(ui.vertices), size = cast(uint)slice.size(ui.vertices[:])}
        }
    })

    sg.apply_pipeline(ui.pipeline)
    sg.apply_bindings(ui.bindings)
    
    // a projection to base size, can be cached but nahh
    mvp : Mvp_Vs_Param = {
        mvp = linalg.matrix_ortho3d(
            0, viewport.base_size.x,
            viewport.base_size.y, 0,
            0, -1,
        )
    }
    sg.apply_uniforms(0, { ptr = &mvp, size = size_of(mvp) })

    sg.draw(0, len(ui.indices), 1)

    clear(&ui.indices)
    clear(&ui.vertices)
}

ui_update :: proc(ui : ^Ui, viewport : ^Viewport) {
    ui.builder.current_container = {0, 0, viewport.base_size.x, viewport.base_size.y}
}

