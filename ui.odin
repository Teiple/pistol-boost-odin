package main

import "core:fmt"
import "core:math"
import "core:strings"
import "core:strconv"
import "base:runtime"
import "core:image/png"
import "core:math/linalg"
import "core:slice"
import "core:text/edit"
import "core:unicode/utf8"

import sg "sokol-odin/sokol/gfx"
import tt "vendor:stb/truetype"
import shaders "shaders"
import sapp "sokol-odin/sokol/app"

UI_MAX_SCISSOR_STACK :: 4

Anchor :: struct {
    element   : [2]f32,
    parent    : [2]f32,
    offset    : [2]f32,
}

Sizing :: union {Fixed, Percent, PercentOffset}

Fixed :: f32

Ui_Id :: union #no_nil {
    int,
    string,
}

Percent :: struct {
    value : f32,
}

PercentOffset :: struct {
    value  : f32,
    offset : f32,
}

Font_Id :: enum u8 {
    Normal
}

Ui_Icon :: enum u8 {
    Cursor,
    Left_Arrow,
    Right_Arrow,
    Plus,
    Minus,
    Up_Arrow,
    Down_Arrow,
}

Font :: struct {
    packed_chars  : [dynamic]tt.packedchar,
    atlas_size    : [2]i32,
    base_size     : f32,
    font_spacing  : f32,
    line_spacing  : f32,
    ascent        : f32,
    font_img      : sg.Image,
    font_view     : sg.View,
    non_ascii_map : map[rune]i32, 
}

// A stateful data container for current frame (mostly)
Ui_Builder :: struct {
    container_stack : [dynamic][4]f32,
    scissor_stack   : [dynamic; UI_MAX_SCISSOR_STACK][4]f32,
    commands        : [dynamic]Ui_Cmd,
    hold            : struct {
        held_id     : Maybe(Ui_Id),
        start_time  : f32,
        mouse_delta : [2]f32
    },
    text_edit    : struct {
        state            : edit.State,
        focus            : struct {
            pending_action : Pending_Action(Ui_Id),
            focused_id     : Maybe(Ui_Id),
            is_new         : bool,
        },
        builder          : strings.Builder,
        scroll_x         : f32,
        submit_requested : bool,
    },
    mouse           : ^Mouse_Input,
    keyboard_input  : bit_set[Ui_Keys],
    input_captured  : bool,
}

@(rodata)
ui_icon_files : [Ui_Icon][]byte = {
    .Cursor      = #load("assets/images/cursor.png"),
    .Left_Arrow  = #load("assets/images/left_arrow.png"),
    .Right_Arrow = #load("assets/images/right_arrow.png"),
    .Up_Arrow    = #load("assets/images/up_arrow.png"),
    .Down_Arrow  = #load("assets/images/down_arrow.png"),
    .Plus        = #load("assets/images/plus.png"),
    .Minus       = #load("assets/images/minus.png"),
}

Ui_Keys :: enum u8 {
    Left, Right, Up, Down,
    Space, Enter, Escape, Tab
}

Ui :: struct {
    pipeline    : sg.Pipeline,
    shader      : sg.Shader,
    bindings    : sg.Bindings,
    
    // for drawing rects
    rect_image  : sg.Image,
    rect_view   : sg.View,

    // for drawing icons
    icon_images : [Ui_Icon]sg.Image,
    icon_views   : [Ui_Icon]sg.View,

    lang_fonts : [Language][Font_Id]Font,
    language   : Language,

    // These can be used to impl growing buf but for 
    // now they are just for validation
    cur_vbuf_cap : uint ,
    cur_ibuf_cap : uint,

    vertices : [dynamic]Vertex,
    indices  : [dynamic]u16,

    // Per-frame data struct
    builder  : Ui_Builder,

    get_time : proc() -> f32,
}

Ui_Cmd :: union {
    Ui_Paint_Cmd,
    Ui_Scissor_Push_Cmd,
    Ui_Scissor_Pop_Cmd,    
}

Ui_Paint_Cmd :: struct {
    start_index : int,
    num_indices : int,
    view        : sg.View,
}

Ui_Scissor_Push_Cmd :: struct {
    rect : [4]f32
}

Ui_Scissor_Pop_Cmd :: struct {
}

Lang_Font_Config :: struct {
    language        : Language,
    non_ascii_runes : []rune,
    ttf_data        : []byte,
    atlas_width     : i32,
    atlas_height    : i32,
    base_size       : f32,
}

ui_init :: proc(
    ui : ^Ui,
    lang_font_cfgs : []Lang_Font_Config,
    get_time : proc() -> f32,
    allocator := context.allocator
) {
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
            pixel_format  = .DEPTH,
            write_enabled = false,
            compare       = .ALWAYS
        },
        colors      = {
            0 = {
                pixel_format = .RGBA8, // must specify since Windows and stuff
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
    
    for font_cfg, id in lang_font_cfgs {
        ui_init_lang_font(&ui.lang_fonts[font_cfg.language][.Normal], font_cfg)
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
    
    ui.rect_image = sg.make_image({
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
        texture = { image = ui.rect_image }
    })

    ui.builder.commands        = make([dynamic]Ui_Cmd, 0, 8)
    ui.builder.container_stack = make([dynamic][4]f32, 0, 8)

    // Loading icons 
    for _, icon in ui.icon_images {
        img, err := png.load(ui_icon_files[icon], {.alpha_add_if_missing}, allocator = allocator)
        assert(err == nil)
        defer png.destroy(img)

        ui.icon_images[icon] = sg.make_image({
            width  = cast(i32)img.width,
            height = cast(i32)img.height,
            data   = {
                mip_levels = {
                    0 = {
                        ptr  = raw_data(img.pixels[:]),
                        size = cast(uint)slice.size(img.pixels[:]),
                    }
                }
            }
        })
        ui.icon_views[icon] = sg.make_view({
            texture = {
                image = ui.icon_images[icon]
            }
        }) 
    }

    // Text edit
    ui_text_edit_init(ui, allocator = allocator)
    
    ui.get_time = get_time
}

ui_destroy :: proc(ui : ^Ui) {
	strings.builder_destroy(
        &ui.builder.text_edit.builder
    )
	edit.destroy(&ui.builder.text_edit.state)

    for &lf in ui.lang_fonts {
        for &f in lf {
            ui_destroy_font(&f)
        }
    }

    for _, icon in ui.icon_images {
        sg.destroy_image(ui.icon_images[icon])
        sg.destroy_view(ui.icon_views[icon])
    }

    sg.destroy_image(ui.rect_image)
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

ui_init_lang_font :: proc(font: ^Font, font_cfg : Lang_Font_Config, allocator := context.allocator) {
    font^ = {
        base_size    = font_cfg.base_size,
        atlas_size   = {font_cfg.atlas_width, font_cfg.atlas_height},
    }

    // Fetch vmetrics
    {
        descent, line_gap: f32
        tt.GetScaledFontVMetrics(
            raw_data(font_cfg.ttf_data),
            index    = 0,
            size     = font.base_size,
            ascent   = &font.ascent,
            // don't need these really 
            descent  = &descent,
            lineGap  = &line_gap, 
        )
    }

    // Prepare buffers
    atlas := make([]byte, font.atlas_size.x * font.atlas_size.y, allocator = allocator)
    defer delete(atlas, allocator)    
    
    font.packed_chars = make([dynamic]tt.packedchar, len = 95 + len(font_cfg.non_ascii_runes), allocator = allocator)

    ascii_chars          := font.packed_chars[:95]
    used_non_ascii_chars := font.packed_chars[95:]

    // A custom map to map non ascii char (e.g. Chinese char -> the spot in packed_chars)
    font.non_ascii_map = make(map[rune]i32)

    for r, idx in font_cfg.non_ascii_runes {
        font.non_ascii_map[r] = 95 + i32(idx)
    }
    
    // Define the ranges
    ranges : [dynamic; 2]tt.pack_range
    {
        append(&ranges, {
            font_size                        = font.base_size,
            first_unicode_codepoint_in_range = 32,
            num_chars                        = 95,
            chardata_for_range               = raw_data(ascii_chars),
        })
        if len(used_non_ascii_chars) > 0 {
            append(&ranges, {
                font_size                   = font.base_size,
                array_of_unicode_codepoints = raw_data(font_cfg.non_ascii_runes),
                num_chars                   = i32(len(font_cfg.non_ascii_runes)),
                chardata_for_range          = raw_data(used_non_ascii_chars),
            })
        }
    }

    // Run the packing
    pack_ctx: tt.pack_context
    tt.PackBegin(
        &pack_ctx,
        pixels          = raw_data(atlas),
        width           = font.atlas_size.x,
        height          = font.atlas_size.y,
        stride_in_bytes = 0,
        padding         = 1,
        alloc_context   = nil)
    {
        defer tt.PackEnd(&pack_ctx)

        tt.PackSetOversampling(
            &pack_ctx,
            h_oversample = 1,
            v_oversample = 1,
        )

        ok := tt.PackFontRanges(
            &pack_ctx,
            fontdata   = raw_data(font_cfg.ttf_data),
            font_index = 0,
            ranges     = raw_data(ranges[:]),
            num_ranges = i32(len(ranges)),
        )

        assert(
            bool(ok),
            "Error packing font. Atlas might be too small, try increasing atlas size or reducing base font size"
        )
    }

    // Create texture image and texture view for ui to sample
    atlas_rgba8 := make([]byte, font.atlas_size.x * font.atlas_size.y * 4)
    {
        defer delete(atlas_rgba8)
    
        for p, i in atlas {
            atlas_rgba8[i * 4]     = 255
            atlas_rgba8[i * 4 + 1] = 255
            atlas_rgba8[i * 4 + 2] = 255
            atlas_rgba8[i * 4 + 3] = p
        }
    
        font.font_img = sg.make_image({
            pixel_format = .RGBA8, 
            width  = font.atlas_size.x,
            height = font.atlas_size.y,
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
    }

    return
}

ui_destroy_font :: proc(font : ^Font) {
    sg.destroy_image(font.font_img)
    sg.destroy_view(font.font_view)

    delete(font.non_ascii_map)
    delete(font.packed_chars)
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
    ui          : ^Ui,
    sizing      : [2]Sizing      = {},
    anchor      : Anchor         = {},
    color       : [4]f32         = 0,
    icon        : Maybe(Ui_Icon) = nil,
    interactive : Maybe(struct {
        id              : Ui_Id,
        hovered_color   : Maybe([4]f32),
        held_color      : Maybe([4]f32),
        skip_drag_click : bool, // ignore a click if there was a mouse movement
    }) = nil,
) -> (ele_rect : [4]f32, is_clicked : bool) {
    container := ui_top_container(ui)
    
    switch size in sizing.x {
        case Fixed:
            ele_rect.z = size
        case Percent:
            ele_rect.z = container.z * size.value
        case PercentOffset:
            ele_rect.z = container.z * size.value + size.offset
    }

    switch size in sizing.y {
        case Fixed:
            ele_rect.w = size
        case Percent:
            ele_rect.w = container.w * size.value
        case PercentOffset:
            ele_rect.w = container.w * size.value + size.offset 
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
            i.id != 0,
            "Empty id on interactive element is not allowed!"
        )

        mouse := ui.builder.mouse
        is_inside := mouse_is_inside_rect(mouse, ele_rect)

        if is_inside {
            if mouse.state[.Left] == .Pressed {
                ui_set_held_id(ui, i.id)
            }
            
            if i.hovered_color != nil
            {
                color = i.hovered_color.?
            }

            if ui.builder.hold.held_id == i.id {
                if i.held_color != nil {
                    color = i.held_color.?
                }

                if mouse.state[.Left] == .Released {
                    is_clicked = i.skip_drag_click ? ui.builder.hold.mouse_delta == 0 : true
                    ui_clear_held_id(ui)
                }
            }
        }        
    }

    v,i := ui_get_quad(ele_rect.xy, base_index, ele_rect.zw, color = color)

    append(&ui.vertices, ..v[:])
    append(&ui.indices,  ..i[:])

    append(&ui.builder.commands, Ui_Paint_Cmd {
        view        = icon == nil ? ui.rect_view : ui.icon_views[icon.?],
        start_index = start_index,
        num_indices = len(ui.indices) - start_index,
    })

    return ele_rect, is_clicked
}

ui_set_held_id :: proc(ui :^Ui, id :Ui_Id) {
    ui.builder.hold.start_time = ui.get_time()
    ui.builder.hold.held_id    = id
}

ui_clear_held_id :: proc(ui :^Ui) {
    ui.builder.hold.start_time  = 0
    ui.builder.hold.mouse_delta = 0
    ui.builder.hold.held_id     = nil
}

ui_push_text :: proc(
    ui             : ^Ui,
    text           : string,
    font_id        : Font_Id = .Normal,
    font_size      : f32     = 32,
    color          : [4]f32  = 1,
    anchor         : Anchor  = {},
    text_alignment : f32     = .5,
    padding        : [4]f32  = 0,
    wrap_enabled   : bool    = true,
) -> (ele_rect : [4]f32) {
    // use address here since font struct is quite big
    font := &ui.lang_fonts[ui.language][font_id]

    if len(text) == 0 do return

    scale        := font_size / font.base_size
    line_height  := font.ascent * scale
    pen          := [2]f32{0, line_height}
    line_spacing :: 4

    ele_rect.w  = font_size

    // capture the index range to update their vertex position later
    start_index := len(ui.indices)
    start_vert  := len(ui.vertices)
    
    base_index  := u16(start_vert)

    wrapped_lines := ui_wrap_text(
        font, text, font_size,
        max_width = wrap_enabled ? ui_top_container(ui).z : math.INF_F32
    )

    widest_line_width := wrapped_lines[0].width
    for i in 1..<len(wrapped_lines) {
        if wrapped_lines[i].width > widest_line_width {
            widest_line_width = wrapped_lines[i].width
        }
    }

    for wrapped_line, index in wrapped_lines {
        // Move the pen down each line and reset horizontal offset
        // (except the last line)
        defer if index < len(wrapped_lines) - 1 {
            pen.x      = 0
            delta_y    := line_height + line_spacing
            pen.y      += delta_y
            ele_rect.w += delta_y
        }
        {
            line_width := wrapped_line.width
            pad_x      := (widest_line_width - line_width) * text_alignment
            
            pen.x      += pad_x
            ele_rect.x  = min(ele_rect.x, pen.x)
            ele_rect.z  = max(ele_rect.z, line_width)
        }

        for r in wrapped_line.line {
            char := i32(r)
            
            pchar : ^tt.packedchar // use pointer as it's also a big struct

            if char >= 32 && char <= 126 {
                // ascii text can sample the packed chars directly by index
                ascii_idx := char - 32
                pchar = &font.packed_chars[ascii_idx]
            } else {
                // non-ascii char need lookup table
                non_ascii_idx := font.non_ascii_map[r]
                pchar = &font.packed_chars[non_ascii_idx]
            }

            // rect is easier to reason about imo
            rect:= [4]f32{
                f32(pchar.x0),
                f32(pchar.y0),
                f32(pchar.x1 - pchar.x0),
                f32(pchar.y1 - pchar.y0),
            }

            uv_rect := rect
            uv_rect.xz /= f32(font.atlas_size.x)
            uv_rect.yw /= f32(font.atlas_size.y)

            v,i := ui_get_quad(
                position     = pen + {pchar.xoff, pchar.yoff} * scale,
                index_offset = base_index,
                size         = rect.zw * scale,
                uv_rect      = uv_rect,
            )

            base_index  += len(v)

            append(&ui.vertices, ..v[:])
            append(&ui.indices,  ..i[:])

            delta_x := pchar.xadvance * scale
            pen.x   += delta_x
        }
    }

    container := ui_top_container(ui)

    // apply padding + anchor
    ele_rect.zw += padding.xy + padding.zw
    
    anchor_offset : [2]f32
    anchor_offset  = container.xy
    anchor_offset += anchor.parent  * container.zw
    anchor_offset -= anchor.element * ele_rect.zw
    anchor_offset += anchor.offset

    ele_rect.xy = anchor_offset
    
    text_offset := anchor_offset + padding.xy
    
    for vi in start_vert..<len(ui.vertices) {
        v := &ui.vertices[vi]
        v.position.xy += text_offset
        v.color = color
    }

    append(&ui.builder.commands, Ui_Paint_Cmd {
        view        = font.font_view,
        start_index = start_index,
        num_indices = len(ui.indices) - start_index,
    })

    return ele_rect
}

Wrapped_Line :: struct  {
    line  : string,
    width : f32,
}

@(require_results)
ui_wrap_text :: proc(
    font: ^Font,
    text: string,
    font_size: f32,
    max_width: f32,
    allocator := context.temp_allocator,
) -> []Wrapped_Line {
    assert(len(text) > 0)

    wrapped_lines := make([dynamic]Wrapped_Line, allocator)
    scale := font_size / font.base_size

    glyph_advance :: proc(font: ^Font, r: rune, scale: f32) -> f32 {
        if r >= 32 && r <= 126 {
            return font.packed_chars[r - 32].xadvance * scale
        }
        if idx, ok := font.non_ascii_map[r]; ok {
            return font.packed_chars[idx].xadvance * scale
        }
        return 0
    }

    line_start := 0 // in byte index
    last_break := 0 // in byte index
    
    line_width: f32 = 0
    word_width: f32 = 0

    for r, cur_index in text {
        if r == '\n' {
            append(&wrapped_lines, {text[line_start:cur_index], line_width + word_width})
            
            // new line starts next index
            line_start = cur_index + 1
            last_break = cur_index + 1

            line_width = 0
            word_width = 0
            continue
        }

        xadvance := glyph_advance(font, r, scale)

        if r == ' ' || r == '\t' {
            line_width += word_width + xadvance
            word_width = 0
            last_break = cur_index + 1
            continue
        }

        // next witdth as the result of appending this character/rune
        next_width := line_width + word_width + xadvance
        
        // if lang is cjk, characters are seperatable
        if game_lang_is_cjk() {
            // TODO: incase the first advance exceed max_width
            // it will pushs an empty string
            if next_width > max_width {
                // stop before current index
                append(&wrapped_lines, {text[line_start:cur_index], line_width + word_width})
                
                // new line starts from current index
                // so next line already has a character/rune
                line_start = cur_index
                line_width = 0
                word_width = 0
            }
            
            word_width += xadvance
            last_break = cur_index
            
            continue
        } else if next_width > max_width && last_break > line_start {
            append(&wrapped_lines, {text[line_start:last_break - 1], line_width})
            
            line_start = last_break
            line_width = 0
        }

        word_width += xadvance
    }

    // The rest
    if line_start < len(text) {
        append(&wrapped_lines, {text[line_start:], line_width + word_width})
    }

    return wrapped_lines[:]
}

ui_push_cursor :: proc(
    ui        : ^Ui,
    position  : [2]f32,
    size      : [2]f32 = 32,
    tint      : [4]f32 = 1,
    alignment : [2]f32 = {0, 0}
) {
    start_index := len(ui.indices)
    start_vert  := len(ui.vertices)
    base_index  := u16(start_vert)

    v,i := ui_get_quad(position - size * alignment, base_index, size, color = tint)

    append(&ui.vertices, ..v[:])
    append(&ui.indices,  ..i[:])

    append(&ui.builder.commands, Ui_Paint_Cmd {
        view        = ui.icon_views[.Cursor],
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
    mvp : shaders.Unlit_Vs_Params = {
        mvp = linalg.matrix_ortho3d(
            left   = 0,
            right  = viewport.base_size.x,
            top    = 0,
            bottom = viewport.base_size.y,
            near   = -1,
            far    = 1,
        )
    }
    sg.apply_uniforms(0, { ptr = &mvp, size = size_of(mvp) })

    clear(&ui.builder.scissor_stack)
    append(&ui.builder.scissor_stack, {0, 0, viewport.base_size.x, viewport.base_size.y})

    for command in ui.builder.commands {
        switch cmd in command {
            case Ui_Paint_Cmd:
                ui.bindings.views[0] = cmd.view
                sg.apply_bindings(ui.bindings)
                sg.draw(cmd.start_index, cmd.num_indices, 1)
            case Ui_Scissor_Push_Cmd:
                append(&ui.builder.scissor_stack, cmd.rect)
                sg.apply_scissor_rectf(expand_values(cmd.rect), origin_top_left = true)
            case Ui_Scissor_Pop_Cmd:
                pop(&ui.builder.scissor_stack)
                sg.apply_scissor_rectf(
                    expand_values(ui_current_scissor_rect(ui)),
                    origin_top_left = true,
                )
        } 
    }

    clear(&ui.indices)
    clear(&ui.vertices)
    clear(&ui.builder.commands)
    clear(&ui.builder.container_stack)
}

ui_begin :: proc(ui : ^Ui, viewport : ^Viewport, mouse : ^Mouse_Input, lang : Language) {
    ui_push_container(ui, {0, 0, viewport.base_size.x, viewport.base_size.y})
    ui.builder.mouse = mouse
    ui.language      = lang
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
        ui_clear_held_id(ui)
    }
    // Update hold mouse delta
    if ui.builder.hold.held_id != nil {
        ui.builder.hold.mouse_delta += ui.builder.mouse.delta
    }

    // These record focused elements through frames
    ui.builder.text_edit.focus.is_new = pending_resolve(
        &ui.builder.text_edit.focus.pending_action,
        &ui.builder.text_edit.focus.focused_id,
    ) && ui.builder.text_edit.focus.focused_id != nil

    ui.builder.text_edit.submit_requested = false
    clear(&ui.builder.scissor_stack)

    ui.builder.input_captured = false
    ui.builder.keyboard_input = {}
}

ui_input :: proc(ui : ^Ui , ev : sapp.Event) {
    if ev.type == .KEY_DOWN {
        #partial switch ev.key_code {
            case .UP:
                ui.builder.keyboard_input += {.Up}
            case .DOWN:
                ui.builder.keyboard_input += {.Down}
            case .LEFT:
                ui.builder.keyboard_input += {.Left}
            case .RIGHT:
                ui.builder.keyboard_input += {.Right}
            case .ESCAPE:
                ui.builder.keyboard_input += {.Escape}
            case .SPACE:
                ui.builder.keyboard_input += {.Space}
            case .ENTER:
                ui.builder.keyboard_input += {.Enter}
            case .TAB:
                ui.builder.keyboard_input += {.Tab}
        }
    }
}

ui_capture_input :: proc(ui: ^Ui) {
    ui.builder.input_captured = true
}

ui_input_captured :: proc(ui : ^Ui) -> bool {
    return ui.builder.input_captured
}

ui_set_lang :: proc(ui : ^Ui, lang : Language) {
    ui.language = lang
}

ui_get_local_mouse_position :: proc(ui : ^Ui, rect : [4]f32) -> (local_position : [2]f32, inside: bool) {
    if (
        ui.builder.mouse.position.x >= rect.x &&
        ui.builder.mouse.position.x <= rect.x + rect.z &&
        ui.builder.mouse.position.y >= rect.y &&
        ui.builder.mouse.position.y <= rect.y + rect.w
    ) {
        return ui.builder.mouse.position - rect.xy, true
    }

    return
}

ui_mouse_is_inside_rect :: proc(ui : ^Ui, rect : [4]f32) -> bool {
    return mouse_is_inside_rect(ui.builder.mouse, rect)
}

Ui_Text_Edit_Key_Binding :: struct {
	key:   sapp.Keycode,
	ctrl:  bool,
	shift: bool,
	cmd:   edit.Command,
}

// `core:text/edit` has no opinion on which key does what, so the example picks
// the usual bindings. The modifiers have to match exactly, which is what keeps
// <Ctrl+Left> from also triggering the plain <Left> binding.
UI_TEXT_EDIT_KEY_BINDINGS :: []Ui_Text_Edit_Key_Binding{
	{.LEFT,      false, false, .Left},
	{.LEFT,      false, true,  .Select_Left},
	{.LEFT,      true,  false, .Word_Left},
	{.LEFT,      true,  true,  .Select_Word_Left},
	{.RIGHT,     false, false, .Right},
	{.RIGHT,     false, true,  .Select_Right},
	{.RIGHT,     true,  false, .Word_Right},
	{.RIGHT,     true,  true,  .Select_Word_Right},
	{.HOME,      false, false, .Start},
	{.HOME,      false, true,  .Select_Start},
	{.END,       false, false, .End},
	{.END,       false, true,  .Select_End},
	{.BACKSPACE, false, false, .Backspace},
	{.BACKSPACE, true,  false, .Delete_Word_Left},
	{.DELETE,    false, false, .Delete},
	{.DELETE,    true,  false, .Delete_Word_Right},
	{.A,         true,  false, .Select_All},
	{.C,         true,  false, .Copy},
	{.X,         true,  false, .Cut},
	{.V,         true,  false, .Paste},
	{.Z,         true,  false, .Undo},
	{.Y,         true,  false, .Redo},
}

ui_text_edit_init :: proc(ui : ^Ui, allocator : runtime.Allocator) {
	edit.init(
        &ui.builder.text_edit.state,
        undo_text_allocator  = allocator,
        undo_state_allocator = allocator
    )
	ui.builder.text_edit.builder = strings.builder_make(allocator = allocator)

	ui.builder.text_edit.state.translate_by_grapheme = true

	ui.builder.text_edit.state.set_clipboard = proc(_: rawptr, text: string) -> bool {
		// sokol, like raylib, copies the content of the text, so we only need the temp allocator here
        sapp.set_clipboard_string(strings.clone_to_cstring(text, allocator = context.temp_allocator))
        return true
	}

	ui.builder.text_edit.state.get_clipboard = proc(_: rawptr) -> (text: string, ok: bool) {
		cstr := sapp.get_clipboard_string()
		return string(cstr), cstr != nil
	}
}

ui_text_edit_input :: proc(
    ui : ^Ui,
    ev : sapp.Event,
) {
    if ui.builder.text_edit.focus.focused_id == nil {
        return
    }
    // Text edit always capture input
    ui_capture_input(ui)

	edit.update_time(&ui.builder.text_edit.state)

	ctrl  := ev.modifiers & sapp.MODIFIER_CTRL  != 0
	shift := ev.modifiers & sapp.MODIFIER_SHIFT != 0

    if ev.type == .KEY_DOWN {
        for binding in UI_TEXT_EDIT_KEY_BINDINGS {
            pressed := ev.key_code == binding.key
            if pressed && binding.ctrl == ctrl && binding.shift == shift {
                edit.perform_command(&ui.builder.text_edit.state, binding.cmd)
            }
        }
        if ev.key_code == .ENTER {
            ui.builder.text_edit.submit_requested = true
        }
    }
    
    // ignore unprintable ascii and the Enter
    // to prevent clashing with the commands
    // we need to ignore the char type when pressing ctrl
    if !ctrl && ev.type == .CHAR {
        edit.input_rune(&ui.builder.text_edit.state, rune(ev.char_code))
    }
}

ui_is_key_pressed :: proc(ui : ^Ui, key: Ui_Keys) -> bool {
    return key in ui.builder.keyboard_input
}

ui_is_accept_pressed :: proc(ui : ^Ui) -> bool {
    return .Space in ui.builder.keyboard_input || .Enter in ui.builder.keyboard_input 
}
ui_is_cancel_pressed :: proc(ui : ^Ui) -> bool {
    return .Escape in ui.builder.keyboard_input 
}

ui_push_spinner :: proc(
    ui              : ^Ui,
    id              : Ui_Id,
    up_control_id   : Ui_Id,
    down_control_id : Ui_Id,
    value           : f32,
    label           : string,
    step            : f32,
    min_val         : Maybe(f32) = nil,
    max_val         : Maybe(f32) = nil,
    width           : [3]f32     = { 100, 50, 20 },
    height          : f32        = 42,
    label_color     : [4]f32     = 1, 
    anchor          : Anchor     = {},
    mouse_drag_sensitivity : f32 = .1,
) -> (new_value : f32, changed: bool) {
    rect, _ := ui_push_rect(
        ui,
        anchor = anchor,
        sizing = { width.x + width.y + width.z, height}, 
        color  = hsv(0, 0, 0, .4),
    )

    ui_push_container(ui, rect)
    {
        defer ui_pop_container(ui)

        // Content rect
        label_rect, _ := ui_push_rect(                
            ui,
            sizing = { width.x, height},
            anchor = {
                element = {0, .5},
                parent  = {0, .5},
            },
        )
        
        ui_push_container(ui, label_rect)
        {
            defer ui_pop_container(ui)
            
            ui_push_text(
                ui,
                text           = label,
                text_alignment = 0,
                anchor = {
                    element = {0, .5},
                    parent  = {0, .5},
                },
                padding = {4, 0, 0, 0},
                color   = label_color,
            )
        }

        text := fmt.tprintf("%.4g", value)

        new_text, submitted := ui_push_text_edit(
            ui, 
            id     = id,
            text   = text,
            sizing = { width.y, height },
            anchor = {
                element = {0, .5},
                parent  = {0, .5},
                offset  = {width.x, 0},
            },
            padding_x = 4,
        )

        // 2 controls, up and down, to step through the value when text input is not focused
        up_control_rect, up_clicked := ui_push_rect(
            ui,
            sizing      = { width.z, height * .5 },
            anchor      = {
                element = {1, 0},
                parent  = {1, 0},
            },
            interactive = {
                id         = up_control_id,
                held_color = hsv(0, 0, .4),
            },
            color  = hsv(0, 0, .55),
        )
        ui_push_container(ui, up_control_rect)
        {
            defer ui_pop_container(ui)
            ui_push_rect(
                ui,
                sizing = 16,
                anchor = {
                    element = {.5, .5},
                    parent  = {.5, .5},
                },
                icon  = .Up_Arrow,
                color  = 1,
            )
        }
       
        down_control_rect, down_clicked := ui_push_rect(
            ui,
            sizing = { width.z, height * .5 },
            anchor = {
                element = {1, 1},
                parent  = {1, 1},
            },
            interactive = {
                id = down_control_id,
                held_color = hsv(0, 0, .6),
            },
            color  = hsv(0, 0, .7),
        )
        ui_push_container(ui, down_control_rect)
        {
            defer ui_pop_container(ui)
            ui_push_rect(
                ui,
                sizing = 16,
                anchor = {
                    element = {.5, .5},
                    parent  = {.5, .5},
                },
                icon   = .Down_Arrow,
                color  = 1,
            )
        }

        if submitted {
            parsed, is_valid := strconv.parse_f32(new_text)
            if is_valid {
                new_value = parsed

                if min_val != nil do new_value = max(new_value, min_val.?)
                if max_val != nil do new_value = min(new_value, max_val.?)
                
                changed   = new_value != value
            }
        } else {
            multiplier : f32 =
                (up_clicked   ? 0 :  1) +
                (down_clicked ? 0 : -1) +
                (
                    ui.builder.text_edit.focus.focused_id != id &&
                    ui.builder.hold.held_id     == id &&
                    abs(ui.builder.mouse.delta.x) > 0 ?
                    ui.builder.mouse.delta.x * mouse_drag_sensitivity : 0
                )
            
            if multiplier != 0 {
                submitted = true
                new_value = value + multiplier

                if min_val != nil do new_value = max(new_value, min_val.?)
                if max_val != nil do new_value = min(new_value, max_val.?)

                changed   = new_value != value
            }
        }
    }

    return
}

ui_get_intersect_rect :: proc(rect_a : [4]f32, rect_b : [4]f32) -> ([4]f32, bool) {
    left   := max(rect_a.x, rect_b.x)
	top    := max(rect_a.y, rect_b.y)
	right  := min(rect_a.x + rect_a.z, rect_b.x + rect_b.z)
	bottom := min(rect_a.y + rect_a.w, rect_b.y + rect_b.w)

	width  := right - left
	height := bottom - top

	return {left, top, max(width, 0),  max(height, 0)}, width > 0 && height > 0
}

ui_get_mouse_button_state :: proc(ui: ^Ui) -> Mouse_Button_State {
    return ui.builder.mouse.state[.Left]
}


ui_push_text_edit :: proc(
    ui         : ^Ui,
    text       : string,
    id         : Ui_Id,
    font_id    : Font_Id = .Normal,
    font_size  : f32 = 32,
    padding_x  : f32 = 4,
    sizing     : [2]Sizing = { 200, 42 },
    anchor     : Anchor    = {},
) -> (current_text: string, submitted : bool) {
	font        := &ui.lang_fonts[ui.language][font_id]
        
    rect, is_clicked := ui_push_rect(
        ui,
        sizing      = sizing,
        anchor      = anchor,
        color       = hsv(0, 0, .2),
        interactive = {
            id              = id,
            skip_drag_click = true,
        }
    )

    if is_clicked {
        fmt.println("clicked", id)
        ui_focus_set(ui, id)
    }
    
    is_focused    := ui.builder.text_edit.focus.focused_id == id
    newly_focused := is_focused && ui.builder.text_edit.focus.is_new

    // When just focused
    if newly_focused {
        // Setup text edit
        edit.clear_all(&ui.builder.text_edit.state)
        strings.write_string(&ui.builder.text_edit.builder, text)
        edit.setup_once(&ui.builder.text_edit.state, &ui.builder.text_edit.builder)

        // Reset scroll
        ui.builder.text_edit.scroll_x = 0
    }

    text_x := padding_x + (is_focused ? ui.builder.text_edit.scroll_x : 0)

    // When click on the rect when already focused, reposition of caret
    if is_focused && is_clicked {
        // Caret positioning
        local_mouse_pos, is_inside := ui_get_local_mouse_position(ui, rect)
        
        // Allow clicking onto padding to snap caret to start or end
        local_text_x := max(local_mouse_pos.x - text_x, 0)
        caret := ui_text_edit_set_caret(
            font          = &ui.lang_fonts[ui.language][font_id],
            font_size     = font_size,
            text          = strings.to_string(ui.builder.text_edit.state.builder^),
            local_mouse_x = local_text_x,
        )

        ui.builder.text_edit.state.selection = {caret, caret}
    }

    // On focus loss (clicked outside)
    if is_focused &&
        ui_get_mouse_button_state(ui) == .Pressed &&
        !ui_mouse_is_inside_rect(ui, rect)
    {
        ui_focus_clear(ui)
        submitted ||= true
    }
    
    // text edit sb shouldn't be altered from this point anyway,
    // we can just return this text as current text
    current_text = is_focused ? strings.to_string(ui.builder.text_edit.builder) : text 
    submitted    ||= is_focused && ui.builder.text_edit.submit_requested

    caret_width :: 2

    ui_push_container(ui, rect);
    {
        defer ui_pop_container(ui);
        
        scissor_rect := [4]f32{
            rect.x + padding_x,
            rect.y,
            rect.z - 2 * padding_x,
            rect.w,
        }
        ui_push_scissor(ui, scissor_rect)
        defer ui_pop_scissor(ui);
        
        if is_focused {
            // Draw text selection
            if lo, hi := edit.sorted_selection(&ui.builder.text_edit.state); lo != hi {
                lo_x := ui_text_width(font, current_text[:lo], font_size)
                hi_x := ui_text_width(font, current_text[:hi], font_size)

                ui_push_rect(
                    ui,
                    sizing = { hi_x - lo_x, font_size },
                    color  = hsv(215),
                    anchor = {
                        parent = {0, .5},
                        element= {0, .5},
                        offset = {text_x + lo_x, 0} 
                    }
                )
            }
        }

        ui_push_text(
            ui,
            text           = current_text,
            font_id        = font_id,
            font_size      = font_size,
            color          = hsv(0, 0, 1),
            text_alignment = .0,
            wrap_enabled   = false,
            anchor         = {
                parent = {0, .5},
                element= {0, .5},
                offset = {text_x, 0} 
            }
        )

        // Caret
        if is_focused {
            caret_x := text_x + ui_text_width(
                font      = font,
                text      = current_text[:ui.builder.text_edit.state.selection[0]],
                font_size = font_size
            )

            caret_blink_rate :: .25
            if int(ui.get_time() / caret_blink_rate) % 2 == 0 {
                ui_push_rect(
                    ui,
                    sizing = { 2, font_size },
                    anchor = { 
                        parent  = { 0, .5 },
                        element = { 0, .5 },
                        offset  = { caret_x, 0 },
                    },
                    color = hsv(0, 0, 1),
                )
            }
            
            right_edge := rect.z - padding_x
            
            if caret_x < padding_x {
                ui.builder.text_edit.scroll_x += padding_x - caret_x
            } else if caret_x > right_edge - caret_width {
                ui.builder.text_edit.scroll_x -= caret_x - (right_edge - caret_width)
            }
        }
    }

    if submitted {
        ui_focus_clear(ui)
    }

    return
}

ui_focus_set :: proc(ui: ^Ui, id : Ui_Id) {
    // Don't override existing action unless it's a clear action
    // Also don't set unless it's a different focus id
    if ui.builder.text_edit.focus.focused_id == id {
        return
    }

    if _, set := ui.builder.text_edit.focus.pending_action.(Pending_Action_Set(Ui_Id)); !set {
        ui.builder.text_edit.focus.pending_action = {id}
    }
}

ui_focus_clear :: proc(ui: ^Ui) {
    // Don't clear existing set action (e.g. some elements in the same frame may require focuses)
    if _, none := ui.builder.text_edit.focus.pending_action.(Pending_Action_Keep); none {
        ui.builder.text_edit.focus.pending_action = Pending_Action_Clear{}
    }
}

ui_text_width :: proc(font: ^Font, text: string, font_size: f32) -> f32 {
    size  := font_size > 0 ? font_size : font.base_size
    scale := size / font.base_size
    width : f32 = 0
    for r in text {
        if r >= 32 && r <= 126 {
            width += font.packed_chars[r - 32].xadvance * scale
        } else if idx, ok := font.non_ascii_map[r]; ok {
            width += font.packed_chars[idx].xadvance * scale
        }
    }
    return width
}

ui_text_edit_set_caret :: proc(font: ^Font, font_size : f32,  text: string, local_mouse_x: f32) -> (caret: int) {
    best := abs(local_mouse_x)

	it := utf8.decode_grapheme_iterator_make(text)
	for _, grapheme in utf8.decode_grapheme_iterate(&it) {
		end := grapheme.byte_index + len(grapheme.text)
		if distance := abs(ui_text_width(font, text[:end], font_size) - local_mouse_x); distance < best {
			caret, best = end, distance
		}
	}
	return
}

ui_push_scissor :: proc(ui: ^Ui, rect : [4]f32) {
    append(&ui.builder.commands, Ui_Scissor_Push_Cmd { rect })
    append(&ui.builder.scissor_stack, rect)
}

ui_pop_scissor :: proc(ui: ^Ui) {
    append(&ui.builder.commands, Ui_Scissor_Pop_Cmd{})
    pop(&ui.builder.scissor_stack)
}

ui_current_scissor_rect :: #force_inline proc(ui: ^Ui) -> [4]f32 {
    return ui.builder.scissor_stack[len(ui.builder.scissor_stack) - 1]
}