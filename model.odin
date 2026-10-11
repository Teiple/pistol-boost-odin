package main

import gltf "glTF2"

Model :: struct {
	gltf_data : ^gltf.Data,
	meshes    : [dynamic]Mesh
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

model_init_from_gltf :: proc(model : ^Model, file_data : []byte) {
	dat, err := gltf.parse(file_data, { is_glb = true })
	assert(err == nil)

	model.meshes = make([dynamic]Mesh)

	for &m in dat.meshes {
		for prim in m.primitives {
			position := gltf.buffer_slice(dat, prim.attributes[MODEL_ATTRIBUTES[.Position]]).([][3]f32)
			color    := gltf.buffer_slice(dat, prim.attributes[MODEL_ATTRIBUTES[.Color]]).([][4]f32)
			uv       := gltf.buffer_slice(dat, prim.attributes[MODEL_ATTRIBUTES[.Position]]).([][2]f32)
			
			vert_count := len(position) 
			assert(len(color) == vert_count)
			assert(len(uv) == vert_count)
			
			indices  := gltf.buffer_slice(dat, prim.indices.?).([]u16)
			
			vertices := make([]Vertex, vert_count)
		    // vertices will be copied over
			defer delete(vertices)

			for &v,i in vertices {
				v.position = position[i]
				v.uv       = uv[i]
			}

			append(&model.meshes, mesh_create_from_data({vertices, indices}))			
		}
	}

	model.gltf_data = dat
}

model_destroy :: proc(model : ^Model) {
	gltf.unload(model.gltf_data)

	for &m in model.meshes {
		mesh_destroy(&m)
	}
}