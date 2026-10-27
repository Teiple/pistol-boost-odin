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

camera_destroy :: proc(camera : ^Camera) {
	// nothing for now
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

Follow_Camera :: struct {
	enabled    : bool,
	target     : [3]f32,
	offset     : [3]f32,
	smoothness : f32,
}

follow_camera_init :: proc(follow_cam: ^Follow_Camera, offset: [3]f32 = {0, 0, 3.0}, smoothness: f32 = 12.0) {
	follow_cam^ = {
		enabled    = true,
		offset     = offset,
		smoothness = smoothness,
	}
}

follow_camera_update_3d :: proc(follow_cam: ^Follow_Camera, camera: ^Camera, target_pos: [3]f32, dt: f32) {
	if !follow_cam.enabled do return

	follow_cam.target = linalg.lerp(
		follow_cam.target,
		target_pos,
		clamp(follow_cam.smoothness * dt, 0, 1),
	)

	camera.target   = follow_cam.target
	camera.position = follow_cam.target + follow_cam.offset
	camera.up       = {0, 1, 0}
}
