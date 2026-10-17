package main
// A very mininal anchor based ui system
import "core:fmt"
// It must do everything in one pass
// Mouse input only accounts for explicit ids
// There will be no implicit ids

import "core:math/linalg"
import "core:slice"
import sg "sokol-odin/sokol/gfx"
import tt "vendor:stb/truetype"
import shaders "shaders"


Anchor :: struct {
    element   : [2]f32,
    parent    : [2]f32,
    offset    : [2]f32,
}

Sizing :: union { Fixed, Grow, Percent }

Fixed :: struct {
    value : f32,
}

ID_NONE :: ""

Ui_Id :: union {
    string,
    int,
}

Grow :: struct {}

Percent :: struct {
    value : f32,
}

Font_Id :: enum {
    Normal,
    Mono
}

Font :: struct {
    atlas_size   : [2]f32,
    base_size    : f32,
    font_spacing : f32,
    line_spacing : f32,
    ascent       : f32,
    descent      : f32,
    baked_chars  : [96]tt.bakedchar,
    font_img     : sg.Image,
    font_view    : sg.View,
}

// A stateful data container for current frame
Ui_Builder :: struct {
    container_stack : [dynamic][4]f32,
    commands        : [dynamic]Ui_Cmd,
    held_id         : Ui_Id,
    mouse           : ^Mouse_Input,
    input_captured  : bool,
}

Ui :: struct {
    pipeline    : sg.Pipeline,
    shader      : sg.Shader,
    bindings    : sg.Bindings,
    
    // for drawing rects
    rect_img    : sg.Image,
    rect_view   : sg.View,

    fonts : [Font_Id]Font,

    // These can be used to impl growing buf but for 
    // now they are just for validation
    cur_vbuf_cap : uint ,
    cur_ibuf_cap : uint,

    vertices : [dynamic]Vertex,
    indices  : [dynamic]u16,

    builder  : Ui_Builder,
}

Ui_Cmd :: struct {
    start_index : int,
    num_indices : int,
    view        : sg.View,
}

ui_init_default :: proc(ui : ^Ui) {
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
    
    ui.fonts = {
        .Normal = ui_make_font(ui, #load("assets/fonts/NotoSans_SemiCondensed-SemiBold.ttf")),
        .Mono   = ui_make_font(ui, #load("assets/fonts/NotoSans_Mono.ttf")),
    }

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

    white_pixel : []u32 = {0xFFFFFFFF}
    
    ui.rect_img = sg.make_image({
        width = 1, height = 1,
        data = {
            mip_levels = {
                0 = {
                    // copy over
                    ptr  = raw_data(white_pixel),
                    size = cast(uint)slice.size(white_pixel)
                }
            }
        }
    })

    ui.rect_view = sg.make_view({
        texture = { image = ui.rect_img }
    })

    ui.builder.commands        = make([dynamic]Ui_Cmd, 0, 8)
    ui.builder.container_stack = make([dynamic][4]f32, 0, 8)
}

ui_destroy :: proc(ui : ^Ui) {
    for &f in ui.fonts {
        sg.destroy_image(f.font_img)
        sg.destroy_view(f.font_view)
    } 
    sg.destroy_image(ui.rect_img)
    sg.destroy_view(ui.rect_view)

    sg.destroy_sampler(ui.bindings.samplers[0])

    sg.destroy_buffer(ui.bindings.index_buffer)
    sg.destroy_buffer(ui.bindings.vertex_buffers[0])

    sg.destroy_shader(ui.shader)
    sg.destroy_pipeline(ui.pipeline)

    delete(ui.vertices)
    delete(ui.indices)
    
    delete(ui.builder.commands)
    delete(ui.builder.container_stack)

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

    font.font_img = sg.make_image({
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

    font.font_view = sg.make_view({
        texture = {image = font.font_img}
    })

    return font
}

ui_get_quad :: proc(
    position     : [2]f32,
    index_offset : u16,
    size         : [2]f32,
    uv_rect      : [4]f32 = {0 , 0, 1 ,1},
    color        : [4]f32 = 1,
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

ui_push_rect :: proc(
    ui    : ^Ui,
    color : [4]f32 = 0,
    interactive : Maybe(struct {
        id            : Ui_Id,
        hovered_color : Maybe([4]f32),
        held_color    : Maybe([4]f32),
    }) = nil,
    sizing : [2]Sizing    = {},
    anchor : Anchor       = {},
) -> (ele_rect : [4]f32, mouse_state : Mouse_Button_State, is_clicked : bool) {
    container := ui_top_container(ui)
    
    switch size in sizing.x {
        case Fixed:
            ele_rect.z = size.value
        case Grow:
            ele_rect.z = container.z
        case Percent:
            ele_rect.z = container.z * size.value 
    }

    switch size in sizing.y {
        case Fixed:
            ele_rect.w = size.value
        case Grow:
            ele_rect.w = container.w
        case Percent:
            ele_rect.w = container.w * size.value 
    }

    // apply anchor
    anchor_offset  : [2]f32
    anchor_offset  = container.xy
    anchor_offset += anchor.parent  * container.zw
    anchor_offset -= anchor.element * ele_rect.zw
    anchor_offset += anchor.offset

    ele_rect.xy += anchor_offset

    start_index := len(ui.indices)
    start_vert  := len(ui.vertices)
    
    base_index  := u16(start_vert)

    color := color
    if i, ok := interactive.?; ok {
        assert(
            i.id != ID_NONE,
            "Empty id on interactive element is not allowed!"
        )

        mouse := ui.builder.mouse
        is_inside := mouse_is_inside_rect(mouse, ele_rect)

        if is_inside {
            if mouse.state[.Left] == .Pressed {
                ui.builder.held_id = i.id
            }
            
            if i.hovered_color != nil
            {
                color = i.hovered_color.?
            }

            if ui.builder.held_id == i.id {
                // fmt.println("is pressing ", mouse.state[.Left])
                if i.held_color != nil {
                    color = i.held_color.?
                }

                if mouse.state[.Left] == .Released {
                    ui.builder.held_id = ID_NONE
                    is_clicked = true
                }
            } 
        } else {
            mouse_state = .None
        }
    }

    v,i := ui_get_quad(ele_rect.xy, base_index, ele_rect.zw, color = color)

    append(&ui.vertices, ..v[:])
    append(&ui.indices,  ..i[:])

    append(&ui.builder.commands, {
        view        = ui.rect_view,
        start_index = start_index,
        num_indices = len(ui.indices) - start_index,
    })

    return ele_rect, mouse_state, is_clicked
}

ui_push_text :: proc(
    ui        : ^Ui,
    font_id   : Font_Id,
    text      : string,
    font_size : f32 = 32,
    color     : [4]f32 = {0.2, 0.8, 0.2, 1},
    // interactive
    interactive : Maybe(struct {
        mouse         : ^Mouse_Input,
        hovered_color : Maybe([4]f32),
    }) = nil,
    anchor    : Anchor = {},
) -> (ele_rect : [4]f32) {
    // use address here since font struct is quite big
    font := &ui.fonts[font_id]

    if len(text) == 0 do return

    scale := font_size / font.base_size
    pen   := [2]f32{0, font.ascent * scale}

    ele_rect.w  = font_size

    // capture the index range to update their vertex position later
    start_index := len(ui.indices)
    start_vert  := len(ui.vertices)
    
    base_index  := u16(start_vert)

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
        )

        base_index  += len(v)

        append(&ui.vertices, ..v[:])
        append(&ui.indices,  ..i[:])

        pen.x      += bchar.xadvance * scale
        ele_rect.z += bchar.xadvance * scale
    }

    container := ui_top_container(ui)

    // apply anchor
    anchor_offset : [2]f32
    anchor_offset  = container.xy
    anchor_offset += anchor.parent  * container.zw
    anchor_offset -= anchor.element * ele_rect.zw
    anchor_offset += anchor.offset

    ele_rect.xy += anchor_offset

    color := color
    if i, ok := interactive.?; ok {
        if i.hovered_color != nil &&
            i.mouse.state[.Left] == .None &&
            mouse_is_inside_rect(i.mouse, ele_rect) {
            color = i.hovered_color.?
        }
    }
    
    for vi in start_vert..<len(ui.vertices) {
        v := &ui.vertices[vi]
        v.position.xy += anchor_offset
        v.color = color
    }

    append(&ui.builder.commands, {
        view        = font.font_view,
        start_index = start_index,
        num_indices = len(ui.indices) - start_index,
    })

    return ele_rect
}

ui_push_cursor :: proc(
    ui       : ^Ui,
    position : [2]f32,
    size     : [2]f32 = 16,
    tint     : [4]f32 = 1,
) {
    start_index := len(ui.indices)
    start_vert  := len(ui.vertices)
    base_index  := u16(start_vert)

    v,i := ui_get_quad(position - size * .5, base_index, size, color = tint)

    append(&ui.vertices, ..v[:])
    append(&ui.indices,  ..i[:])

    append(&ui.builder.commands, {
        view        = ui.rect_view,
        start_index = start_index,
        num_indices = len(ui.indices) - start_index,
    })
}

ui_draw :: proc(ui : ^Ui, viewport : ^Viewport) {
    assert(len(ui.indices)  <= int(ui.cur_ibuf_cap), "Exceeded ibuf cap!")
    assert(len(ui.vertices) <= int(ui.cur_vbuf_cap), "Exceeded vbuf cap!")

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
    
    // a projection to base size, can be cached but nahh
    mvp : Mvp_Vs_Param = {
        mvp = linalg.matrix_ortho3d(
            0, viewport.base_size.x,
            viewport.base_size.y, 0,
            0, -1,
        )
    }
    sg.apply_uniforms(0, { ptr = &mvp, size = size_of(mvp) })

    for cmd in ui.builder.commands {
        ui.bindings.views[0] = cmd.view
        sg.apply_bindings(ui.bindings)
        sg.draw(cmd.start_index, cmd.num_indices, 1)
    }

    clear(&ui.indices)
    clear(&ui.vertices)
    clear(&ui.builder.commands)
    clear(&ui.builder.container_stack)

    ui.builder.input_captured = false
}

ui_begin :: proc(ui : ^Ui, viewport : ^Viewport, mouse : ^Mouse_Input) {
    ui_push_container(ui, {0, 0, viewport.base_size.x, viewport.base_size.y})
    ui.builder.mouse = mouse
}

ui_push_container :: proc(ui : ^Ui, rect : [4]f32){
    append(&ui.builder.container_stack, rect)
}


ui_pop_container :: proc(ui : ^Ui){
    pop(&ui.builder.container_stack)
}

ui_top_container :: proc(ui : ^Ui) -> [4]f32 {
    return ui.builder.container_stack[len(ui.builder.container_stack) - 1]
}

ui_end :: proc(ui : ^Ui, viewport : ^Viewport) {
    if ui.builder.mouse.state[.Left] == .Released {
        ui.builder.held_id = ID_NONE
    }
}

// You should call this inside a input/event callback, not frame callback
ui_capture_input :: proc(ui: ^Ui) {
    ui.builder.input_captured = true
}

ui_is_capturing_input :: proc(ui : ^Ui) -> bool {
    return ui.builder.input_captured
}

