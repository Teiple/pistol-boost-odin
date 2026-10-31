package main

import "core:strings"
import "core:math"
import "core:math/linalg"
import "base:runtime"
import "core:image/png"
import "core:slice"
import gltf "glTF2"
import sg "sokol-odin/sokol/gfx"

Model_Vertex :: struct {
	position : [3]f32,
	color    : [4]f32,
	uv       : [2]f32,
	joints   : [4]f32,
	weights  : [4]f32,
}

Model_Bone :: struct {
	model_matrix   : matrix[4,4]f32,
	local_rotation : quaternion128,
	local_position : [3]f32, 
	parent         : int,
}

Model_Animation_Channel :: union {
	Model_Animation_Position_Channel,
	Model_Animation_Rotation_Channel,
}

Model_Animation_Position_Channel :: struct {
	positions  : [dynamic][3]f32,
	timestamps : [dynamic]f32,
	bone_index : int,
}

Model_Animation_Rotation_Channel :: struct {
	rotations  : [dynamic]quaternion128,
	timestamps : [dynamic]f32,
	bone_index : int,
}

Model_Animation :: struct {
	channels   : [dynamic]Model_Animation_Channel,
	name       : string,
	duration   : f32,
}

Animation_Loop_Mode :: enum {
	Once,
	Loop
}

Model :: struct {
	bones                : [dynamic]Model_Bone,
	model_to_bone_matrix : [dynamic]matrix[4,4]f32, 
	animations           : [dynamic]Model_Animation,
	bindings             : sg.Bindings,
	texture_image        : sg.Image,
	index_count          : i32,
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
			assert(len(joints)  == vert_count)
			
			indices := gltf.buffer_slice(dat, prim.indices.?).([]u16)
			
			base_vertex := u16(len(model_vertices))

			for i in 0..<vert_count {
				vertex := Model_Vertex{
					position = position[i],
					uv       = uv[i],
					color    = {expand_values(color[i]), 1},
					joints   = cast([4]f32)joints[i],
					weights  = weights[i],
				}
				
				append(&model_vertices, vertex)
			}

			for idx in indices {
				append(&model_indices, base_vertex + idx)
			}
		}
	}

	// Fetch animations
	model.animations = make([dynamic]Model_Animation, len(dat.animations), allocator = allocator)

	for &anim, i in dat.animations {
		model.animations[i] = {
			name     = strings.clone(anim.name.?, allocator = allocator),
			channels = make(
				[dynamic]Model_Animation_Channel,
				allocator = allocator
			)
		}

		duration : f32 = 0 

		for channel_index in 0..<len(anim.channels) {
			channel := anim.channels[channel_index]
			node, is_animating_node := channel.target.node.?
			if !is_animating_node do continue
			bone_index, is_animating_bone := node_to_bone_lookup[node]
			if !is_animating_bone do continue
			
			sampler := anim.samplers[channel.sampler]
			
			raw_timestamps := gltf.buffer_slice(dat, sampler.input).([]f32)

			if len(raw_timestamps) > 0 {
				duration = max(raw_timestamps[len(raw_timestamps) - 1], duration)
			}
			
			#partial switch channel.target.path {
				case .Translation:
					append(&model.animations[i].channels, {
						bone_index = bone_index,
						timestamps = slice.clone_to_dynamic(raw_timestamps, allocator = allocator),
						positions  = slice.clone_to_dynamic(gltf.buffer_slice(dat, sampler.output).([][3]f32), allocator = allocator),
					})
				case .Rotation:
					clone_to_quaternions :: proc(rotation_slice : [][4]f32, allocator : runtime.Allocator) -> [dynamic]quaternion128 {
						quats := make([dynamic]quaternion128, len(rotation_slice), allocator = allocator)
						for rot, i in rotation_slice {
							quats[i] = quaternion(w = rot.w, x = rot.x, y = rot.y, z = rot.z)
						}
						return quats
					}

					append(&model.animations[i].channels, {
						bone_index = bone_index,
						timestamps = slice.clone_to_dynamic(raw_timestamps, allocator = allocator),
						rotations  = clone_to_quaternions(gltf.buffer_slice(dat, sampler.output).([][4]f32), allocator = allocator),
					})
			}
		}

		model.animations[i].duration = duration
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
		assert(img_err == nil)
		
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

	// default to rest pose
	model_calculate_hierachy(model)
}

model_destroy :: proc(model : ^Model) {
	sg.destroy_buffer(model.bindings.index_buffer)
	sg.destroy_buffer(model.bindings.vertex_buffers[0])
	sg.destroy_view(model.bindings.views[0])
	sg.destroy_sampler(model.bindings.samplers[0])
	sg.destroy_image(model.texture_image)

	delete(model.model_to_bone_matrix)
	delete(model.bones)

	for &anim in model.animations {
		for &channel in anim.channels {
			switch c in channel {
				case Model_Animation_Position_Channel:
					delete(c.timestamps)
					delete(c.positions)
				case Model_Animation_Rotation_Channel:
					delete(c.timestamps)
					delete(c.rotations)
			}
		}
		delete(anim.channels)
		delete(anim.name)
	}
	delete(model.animations)
}

model_sample_bone_animation :: proc(model: ^Model, animation_index: int, at_timestamp : f32) {
	anim := model.animations[animation_index]
	for &channel in anim.channels {
		timestamps : []f32
		switch &c in channel {
			case Model_Animation_Position_Channel:
				timestamps = c.timestamps[:]
			case Model_Animation_Rotation_Channel:
				timestamps = c.timestamps[:]
		}

		assert(len(timestamps) > 0)

		current_index := len(timestamps) - 1
		for i in 0..<len(timestamps) {
			if timestamps[i] >= at_timestamp {
				current_index = i
				break
			}
		}

		from_index :=  max(current_index - 1, 0)
		to_index   := current_index
		
		progress   := math.clamp(
			(
				from_index != to_index ?
				(at_timestamp - timestamps[from_index]) /
				(timestamps[to_index] - timestamps[from_index]) : 0
			),
			0, 1
		)

		switch &c in channel {
			case Model_Animation_Position_Channel:
				model.bones[c.bone_index].local_position =
					linalg.lerp(c.positions[from_index], c.positions[to_index], progress);
			case Model_Animation_Rotation_Channel:
				model.bones[c.bone_index].local_rotation =
					linalg.quaternion_nlerp(c.rotations[from_index], c.rotations[to_index], progress);
		}
	}

	model_calculate_hierachy(model)
}

model_calculate_hierachy :: proc(model: ^Model) {
	for &bone in model.bones {
		local_matrix := (
			linalg.matrix4_translate(bone.local_position) *
			linalg.matrix4_from_quaternion(bone.local_rotation)
		)

		if bone.parent == -1 {
			bone.model_matrix = local_matrix
		} else {
			bone.model_matrix = model.bones[bone.parent].model_matrix * local_matrix
		}
	}
}


Model_Animation_Play :: struct {
	current_time    : f32,
	animation_index : int,
	loop_mode       : Animation_Loop_Mode,
	is_active       : bool,
}

model_update_animation_play :: proc(model: ^Model, play : ^Model_Animation_Play, dt: f32) {
	if !play.is_active {
		return
	}

	model_sample_bone_animation(model, play.animation_index, play.current_time)
	play.current_time += dt	
	anim := &model.animations[play.animation_index]
	
	switch play.loop_mode {
		case .Once:
			play.current_time = math.min(play.current_time, anim.duration)
		case .Loop:
			play.current_time = math.mod(play.current_time, anim.duration)
	}
}

model_play_animation :: proc(model : ^Model, play : ^Model_Animation_Play, animation_name : string, loop_mode : Animation_Loop_Mode) {
	for &anim, index in model.animations {
		if anim.name == animation_name {
			play^ = {
				animation_index = index,
				current_time    = 0,
				is_active       = true,
				loop_mode       = loop_mode,
			}
			return
		}
	}
	panic("Cannot found animation!")
}