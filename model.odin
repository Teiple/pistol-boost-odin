package main

import gltf "glTF2"

Model :: struct {
	gltf_data : ^gltf.Data
}

Model_Attribute :: enum {
	Position,
	UV,
	Joints,
	Weights,
}

MODEL_ATTRIBUTES :: [Model_Attribute]string {
	.Position = "POSITION",
	.UV       = "TEXCOORD_0",
	.Joints   = "JOINTS_0",
	.Weights  = "WEIGHTS_0",
}

model_init_from_gltf :: proc(model : ^Model, file_data : []byte) {
	dat, err := gltf.parse(file_data, { is_glb = true })
	assert(err == nil)

	for &m in dat.meshes {
		for prim in m.primitives {
			// pos := gltf.buffer_slice(dat, prim.attributes[MODEL_ATTRIBUTES[.Position]]).([][3]f32)
			
		} 
	}

	model.gltf_data = dat
}

mesh_destroy :: proc(model : ^Model) {
	gltf.unload(model.gltf_data)
}