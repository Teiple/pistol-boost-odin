package main
import b3 "vendor:box3d"
import "core:math"
import linalg "core:math/linalg"

Player :: struct {
    model : Model,
    visual_offset : struct {
        position : [3]f32,
        rotation : quaternion128,
    },
    recoil_pivot   : [3]f32,
    body           : b3.BodyId,
	animation_play : Model_Animation_Play,
}

player_init :: proc(
	player: ^Player,
	world: b3.WorldId,
	position: [3]f32,
	allocator := context.allocator
) {
	model_init_from_gltf(&player.model, #load("assets/models/pistol.glb"), allocator = allocator)
	
	player.visual_offset.position = {0.030, -0.039, 0}
	player.visual_offset.rotation = euler_degrees_to_quat({0, 90, 0})
	player.recoil_pivot           = {-0.023, 0.001, 0}

	body_def                     := b3.DefaultBodyDef()
	body_def.type                = .dynamicBody
	body_def.position            = position
	body_def.rotation            = linalg.QUATERNIONF32_IDENTITY
	body_def.motionLocks.linearZ = true
	body_def.gravityScale        = 0

	player.body = b3.CreateBody(world, body_def)

	box_colliders := [?]struct {
		size:     [3]f32,
		position: [3]f32,
		rotation: quaternion128,
	} {
		{
			size     = {0.191, 0.060, 0.034},
			position = {0.033, 0.001, 0},
			rotation = euler_degrees_to_quat({0, 0, 0}),
		},
		{
			size     = {0.065, 0.106, 0.032},
			position = {-0.024, -0.070, 0},
			rotation = euler_degrees_to_quat({0, 0, -12.086}),
		},
	}

	for box in box_colliders {
		half_size := box.size * 0.5
		box_hull := b3.MakeBoxHull(half_size.x, half_size.y, half_size.z)
		shape_def := b3.DefaultShapeDef()
		shape_def.baseMaterial.friction = 0.5
		shape_def.density = 1100
		shape_def.filter = physics_filter_create(
			{.Player_Physics},
			{.Static_World, .Enemy_Physics},
		)

		_ = b3.CreateTransformedHullShape(
			player.body,
			shape_def,
			&box_hull.base,
			{p = box.position, q = box.rotation},
			{1, 1, 1},
		)
	}

	hitboxes := [?]struct {
		size:     [3]f32,
		position: [3]f32,
		rotation: quaternion128,
	} {
		{
			size = {0.191, 0.060, 0.034} * 0.98,
			position = {0.033, 0.001, 0} * 0.98,
			rotation = euler_degrees_to_quat({0, 0, 0}),
		},
		{
			size = {0.065, 0.106, 0.032} * 0.98,
			position = {-0.024, -0.070, 0} * 0.98,
			rotation = euler_degrees_to_quat({0, 0, -12.086}),
		},
	}

	for box in hitboxes {
		half_size := box.size * 0.5
		box_hull := b3.MakeBoxHull(half_size.x, half_size.y, half_size.z)
		shape_def := b3.DefaultShapeDef()
		shape_def.isSensor = true
		shape_def.density = 0
		shape_def.filter = physics_filter_create({.Player_Hitbox})

		_ = b3.CreateTransformedHullShape(
			player.body,
			shape_def,
			&box_hull.base,
			{p = box.position, q = box.rotation},
			{1, 1, 1},
		)
	}
}

player_destroy :: proc(player: ^Player) {
	model_destroy(&player.model)
}

player_update_3d :: proc(
	player   : ^Player,
	camera   : ^Camera,
	viewport : ^Viewport,
	mouse    : ^Mouse_Input,
	audio    : ^Audio,
	dt       : f32,
) {
	model_update_animation_play(&player.model, &player.animation_play, dt)

	target_pos := viewport_get_mouse_world_position_on_zplane(viewport, camera, 0)
	player_update_aim(player, target_pos)

	if mouse.state[.Left] == .Pressed {
		recoil_point := b3.Body_GetWorldPoint(player.body, player.recoil_pivot)
		recoil_dir := b3.Body_GetWorldVector(player.body, {-1, 0, 0})
		b3.Body_ApplyLinearImpulse(player.body, recoil_dir * 2.0, recoil_point, true)

		audio_play_sound(audio, .Fire_Primary)
		model_play_animation(&player.model, &player.animation_play, "fire", .Once) 
	} else if mouse.state[.Right] == .Pressed {
		recoil_point := b3.Body_GetWorldPoint(player.body, player.recoil_pivot)
		recoil_dir := b3.Body_GetWorldVector(player.body, {-1, 0, 0})
		b3.Body_ApplyLinearImpulse(player.body, recoil_dir * 4.0, recoil_point, true)

		audio_play_sound(audio, .Fire_Secondary)
		model_play_animation(&player.model, &player.animation_play, "fire", .Once) 
	}
}

player_update_aim :: proc(
	player         : ^Player,
	target_pos     : [3]f32,
	max_turn_speed : f32 = 25.0,
	turn_multiplier      : f32 = 1.0,
) {
	player_pos := b3.Body_GetPosition(player.body)
	look_vec   := target_pos - player_pos
	look_vec.z  = 0

	if linalg.length2(look_vec) < 1e-4 {
		return
	}

	z_axis := [3]f32{0, 0, look_vec.x < 0 ? -1 : 1}
	x_axis := linalg.normalize(look_vec)
	y_axis := linalg.normalize(linalg.cross(z_axis, x_axis))
	
	basis  := matrix[3, 3]f32{
		x_axis.x, y_axis.x, z_axis.x,
		x_axis.y, y_axis.y, z_axis.y,
		x_axis.z, y_axis.z, z_axis.z,
	}

	target_quat  := linalg.quaternion_from_matrix3(basis)
	current_quat := b3.Body_GetRotation(player.body)

	diff_quat    := target_quat * linalg.quaternion_inverse(current_quat)
	angle, axis  := linalg.angle_axis_from_quaternion(diff_quat)

	if angle > math.PI {
		angle -= math.TAU
	}

	target_angular_velocity   := axis * angle * max_turn_speed
	target_angular_velocity.z *= turn_multiplier

	b3.Body_SetAngularVelocity(player.body, target_angular_velocity)
}

player_draw_3d :: proc(player: ^Player, renderer : ^Renderer) {
	pos := b3.Body_GetPosition(player.body)
	rot := b3.Body_GetRotation(player.body)

	body_mat   := linalg.matrix4_translate_f32(pos) * linalg.matrix4_from_quaternion(rot)
	visual_mat := linalg.matrix4_translate_f32(player.visual_offset.position) * linalg.matrix4_from_quaternion(player.visual_offset.rotation)
	final_mat  := body_mat * visual_mat

    renderer_draw_model(renderer, player.model, final_mat)
}

player_get_position :: proc(player: ^Player) -> [3]f32 {
	return b3.Body_GetPosition(player.body)
}
