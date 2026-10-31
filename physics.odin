package main

import b3 "vendor:box3d"
import linalg "core:math/linalg" 

PHYSICS_TICK_RATE     :: 50.0
PHYSICS_DT            :: 1.0 / PHYSICS_TICK_RATE
PHYSICS_MAX_ACC_TICKS :: 8
PHYSICS_GRAVITY       :: -10

Physics_Layer :: enum u64 {
	Static_World,
	Player_Physics,
	Enemy_Physics,
	Player_Hitbox,
	Enemy_Hitbox,
}

Physics_Mask :: bit_set[Physics_Layer; u64]

ALL_PHYSICS_LAYERS :: ~Physics_Mask{}

physics_query_filter_create :: proc(
	collision_layer: Physics_Mask = ALL_PHYSICS_LAYERS,
	collision_mask: Physics_Mask = ALL_PHYSICS_LAYERS,
) -> b3.QueryFilter {
	return {
		categoryBits = transmute(u64)collision_layer,
		maskBits     = transmute(u64)collision_mask,
	}
}

physics_filter_create :: proc(
	collision_layer: Physics_Mask = ALL_PHYSICS_LAYERS,
	collision_mask: Physics_Mask = ALL_PHYSICS_LAYERS,
	group_index: i32 = 0,
) -> b3.Filter {
	return {
		categoryBits = transmute(u64)collision_layer,
		maskBits     = transmute(u64)collision_mask,
		groupIndex   = group_index,
	}
}

Physics :: struct {
	world           : b3.WorldId,
	accumulator     : f32,
	interpolatables : [dynamic]Physics_Interpolatable, 
}

physics_init :: proc(physics: ^Physics, allocator := context.allocator) {
	world_def              := b3.DefaultWorldDef()
	world_def.gravity       = {0, PHYSICS_GRAVITY, 0}
	physics.world           = b3.CreateWorld(world_def)
	physics.accumulator     = 0
	physics.interpolatables = make(
		[dynamic]Physics_Interpolatable,
		len = 0,
		cap = 10,
		allocator = allocator
	) 
}

physics_add_interpolatable_body :: proc(physics : ^Physics, body : b3.BodyId) -> (interpolatable_index : int) {
	append(
		&physics.interpolatables,
		{
			body_id           = body,
			previous_position = b3.Body_GetPosition(body), 
			previous_rotation = b3.Body_GetRotation(body), 
		}
	)
	return len(physics.interpolatables) - 1
}

// For teleportion or transform after created
physics_force_update_interpolatable_body :: proc(physics : ^Physics, interpolatable_index : int) {
	interpolatable := &physics.interpolatables[interpolatable_index]
	interpolatable.previous_position = b3.Body_GetPosition(interpolatable.body_id)
	interpolatable.previous_rotation = b3.Body_GetRotation(interpolatable.body_id)
}

physics_destroy :: proc(physics: ^Physics) {
	b3.DestroyWorld(physics.world)
	delete(physics.interpolatables)
}

Physics_Interpolatable :: struct {
	body_id           : b3.BodyId,
	previous_rotation : quaternion128,
	previous_position : [3]f32,
}

physics_update_3d :: proc(physics: ^Physics, dt: f32) {
	physics.accumulator += dt
    // Prevent spiral of death where a lag spike causes a huge dt
    // which in turn causes a bunch of physics ticks to simulate
    // which cause more lag
    physics.accumulator  = min(physics.accumulator, PHYSICS_MAX_ACC_TICKS * PHYSICS_DT)

    // Simulate passed ticks
	for physics.accumulator - PHYSICS_DT >= PHYSICS_DT {
		b3.World_Step(
            physics.world,
            timeStep     = PHYSICS_DT,
            subStepCount = 4,
        )
		physics.accumulator -= PHYSICS_DT
	}
	if physics.accumulator >= PHYSICS_DT {
		for &interpolatable in physics.interpolatables {
			interpolatable.previous_position = b3.Body_GetPosition(interpolatable.body_id) 
			interpolatable.previous_rotation = b3.Body_GetRotation(interpolatable.body_id) 
		}

		b3.World_Step(
            physics.world,
            timeStep     = PHYSICS_DT,
            subStepCount = 4,
        )
		physics.accumulator -= PHYSICS_DT
	}
}

physics_get_interpolated_transform :: proc(
	physics: ^Physics,
	interpolation_index : int
) -> (
	position : [3]f32,
	rotation : quaternion128,
) {
	// the left over after a physic update
	alpha := physics.accumulator / PHYSICS_DT

	interpolatable := physics.interpolatables[interpolation_index]
	position = linalg.lerp(
		interpolatable.previous_position,
		b3.Body_GetPosition(interpolatable.body_id),
		alpha,
	)
	rotation = linalg.quaternion_nlerp(
		interpolatable.previous_rotation,
		b3.Body_GetRotation(interpolatable.body_id),
		alpha,
	)
	return
}
