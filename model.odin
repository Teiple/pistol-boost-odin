package main

import "core:image/png"
import "core:slice"
import gltf "glTF2"
import sg "sokol-odin/sokol/gfx"

Model_Vertex :: struct {
	position : [3]f32,
	color    : [4]f32,
	uv       : [2]f32,
	joints   : [4]u8,
	weights  : [4]f32,
}

Model_Bone :: struct {
	parent         : int,
	local_position : [3]f32, 
	local_rotation : quaternion128,
	model_matrix   : matrix[4,4]f32,
}

Model :: struct {
	index_count          : i32,
	bindings             : sg.Bindings,
	bones                : [dynamic]Model_Bone,
	model_to_bone_matrix : [dynamic]matrix[4,4]f32, 
	texture_image        : sg.Image,
}

Model_Attribute :: enum {
	Position,
	Color,
	UV,
	Joints,
	Weights,
}

MODEL_ATTRIBUTES :: [Model_Attribute]string {
	.Position = "POSITION",
	.Color    = "COLOR_0",
	.UV       = "TEXCOORD_0",
	.Joints   = "JOINTS_0",
	.Weights  = "WEIGHTS_0",
}

model_init_from_gltf :: proc(model : ^Model, file_data : []byte, allocator := context.allocator) {
	dat, err := gltf.parse(file_data, { is_glb = true })
	assert(err == nil)
	
	defer gltf.unload(dat)

	skin := dat.skins[0]
	model_to_bone_matrices := gltf.buffer_slice(dat, skin.inverse_bind_matrices.?).([]matrix[4,4]f32)
	bone_count := len(model_to_bone_matrices)

	model.bones = make([dynamic]Model_Bone, len = bone_count, allocator = allocator)
	model.model_to_bone_matrix = slice.clone_to_dynamic(model_to_bone_matrices, allocator = allocator)
	
	node_to_bone_lookup := make(map[u32]int, allocator = allocator)
	defer delete(node_to_bone_lookup) 

	// Save transform at rest, assumming parent bones first
	for i in 0..<bone_count {
		node_index := skin.joints[i]
		node       := dat.nodes[node_index]
		node_to_bone_lookup[node_index] = i
		model.bones[i] = {
			local_position = node.translation,
			local_rotation = node.rotation,
			parent         = -1,
		}
	}

	// Fill in the parent info for each bone
	for bone_index in 0..<len(model.bones) {
		node_index := skin.joints[bone_index]
		for child_node in dat.nodes[node_index].children {
			// in some cases a bone can hold things that other than bones, e.g. some helper objects
			if child_bone_index, ok := node_to_bone_lookup[child_node]; ok {
				model.bones[child_bone_index].parent = bone_index
			}
		}
	}
	
	model_vertices := make([dynamic]Model_Vertex, allocator = allocator)
	model_indices  := make([dynamic]u16, allocator = allocator)

	defer delete(model_indices)
	defer delete(model_vertices)

	for &m in dat.meshes {
		for prim in m.primitives {
			position := gltf.buffer_slice(dat, prim.attributes[MODEL_ATTRIBUTES[.Position]]).([][3]f32)
			color    := gltf.buffer_slice(dat, prim.attributes[MODEL_ATTRIBUTES[.Color]]).([][3]f32)
			uv       := gltf.buffer_slice(dat, prim.attributes[MODEL_ATTRIBUTES[.UV]]).([][2]f32)
			joints   := gltf.buffer_slice(dat, prim.attributes[MODEL_ATTRIBUTES[.Joints]]).([][4]u8)
			weights  := gltf.buffer_slice(dat, prim.attributes[MODEL_ATTRIBUTES[.Weights]]).([][4]f32)
			
			vert_count := len(position)

			assert(len(color)   == vert_count)
			assert(len(uv)      == vert_count)
			assert(len(weights) == vert_count)
			assert(len(joints) == vert_count)
			
			indices := gltf.buffer_slice(dat, prim.indices.?).([]u16)
			
			base_vertex := u16(len(model_vertices))

			for i in 0..<vert_count {
				vertex := Model_Vertex{
					position = position[i],
					uv       = uv[i],
					color    = {expand_values(color[i]), 1},
					joints   = joints[i],
					weights  = weights[i],
				}
				
				append(&model_vertices, vertex)
			}

			for idx in indices {
				append(&model_indices, base_vertex + idx)
			}
		}
	}

	model.index_count = i32(len(model_indices))

	model.bindings.index_buffer = sg.make_buffer({
		usage = { index_buffer = true },
		data = {
			ptr = raw_data(model_indices), size = cast(uint)slice.size(model_indices[:])
		}
	})

	model.bindings.vertex_buffers[0] = sg.make_buffer({
		usage = { vertex_buffer = true },
		data = {
			ptr = raw_data(model_vertices), size = cast(uint)slice.size(model_vertices[:])
		}
	})

	// Load texture image
	if len(dat.images) > 0 {
		model_image := dat.images[0]
		buffer_view := dat.buffer_views[model_image.buffer_view.?]
		raw_buffer  := dat.buffers[buffer_view.buffer].uri.([]byte)
		png_bytes   := raw_buffer[buffer_view.byte_offset:][:buffer_view.byte_length]
		
		img, img_err := png.load_from_bytes(png_bytes, {.alpha_add_if_missing}, allocator = allocator)
		assert(img_err != nil)
		
		defer png.destroy(img)
	
		img_bytes := img.pixels.buf
		model.texture_image = sg.make_image({
			width  = i32(img.width), 
			height = i32(img.height), 
			data   = {
				mip_levels = {
					0 = {
						ptr  = raw_data(img_bytes),
						size = cast(uint)slice.size(img_bytes[:])
					}
				}
			}
		})
	} else {
		white_pixel : []u32 = {0xFFFFFF}
		model.texture_image = sg.make_image({
			width  = 1, 
			height = 1, 
			data   = {
				mip_levels = {
					0 = {
						ptr  = raw_data(white_pixel),
						size = cast(uint)slice.size(white_pixel)
					}
				}
			}
		})
	}

	model.bindings.views[0] = sg.make_view({
		texture = {
			image = model.texture_image 
		}
	})

	model.bindings.samplers[0] = sg.make_sampler({})
}

model_destroy :: proc(model : ^Model) {
	sg.destroy_buffer(model.bindings.index_buffer)
	sg.destroy_buffer(model.bindings.vertex_buffers[0])
	sg.destroy_view(model.bindings.views[0])
	sg.destroy_sampler(model.bindings.samplers[0])
	sg.destroy_image(model.texture_image)

	delete(model.model_to_bone_matrix)
	delete(model.bones)
}