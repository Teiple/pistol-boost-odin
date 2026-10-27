package main

import b3 "vendor:box3d"


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
	world:       b3.WorldId,
	accumulator: f32,
}

physics_init :: proc(physics: ^Physics) {
	world_def           := b3.DefaultWorldDef()
	world_def.gravity    = {0, PHYSICS_GRAVITY, 0}
	physics.world        = b3.CreateWorld(world_def)
	physics.accumulator  = 0
}

physics_destroy :: proc(physics: ^Physics) {
	b3.DestroyWorld(physics.world)
}

physics_update_3d :: proc(physics: ^Physics, dt: f32) {
	physics.accumulator += dt
    // Prevent spiral of death where a lag spike causes a huge dt
    // which in turn causes a bunch of physics ticks to simulate
    // which cause more lag
    physics.accumulator  = min(physics.accumulator, PHYSICS_MAX_ACC_TICKS * PHYSICS_DT)

    // Simulate passed ticks
	for physics.accumulator >= PHYSICS_DT {
		b3.World_Step(
            physics.world,
            timeStep     = PHYSICS_DT,
            subStepCount = 4,
        )
		physics.accumulator -= PHYSICS_DT
	}
}
