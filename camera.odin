package main

import math "core:math"
import linalg "core:math/linalg"

Camera :: struct {
	up           : [3]f32,
	target       : [3]f32,
	position     : [3]f32,
	fovy_degrees : f32,
	near         : f32,
	far          : f32,
}

camera_init_default :: proc(camera : ^Camera, position : [3]f32, target : [3]f32) {
	camera.fovy_degrees = 60
	camera.near         = 0.1
	camera.far          = 100
	camera.up           = {0, 1, 0}
	camera.position     = position
	camera.target       = target
}

camera_view_projection_matrix :: proc(camera: ^Camera, vp: ^Viewport) -> matrix[4, 4]f32 {
	proj := linalg.matrix4_perspective_f32(
		fovy   = math.to_radians_f32(camera.fovy_degrees),
		aspect = viewport_get_aspect(vp),
		near   = camera.near,
		far    = camera.far,
	)

	view := linalg.matrix4_look_at_f32(
		eye    = camera.position,
		centre = camera.target,
		up     = camera.up,
	)

	return proj * view
}