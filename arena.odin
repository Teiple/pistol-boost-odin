package main

import b3 "vendor:box3d"
import linalg "core:math/linalg"

Arena_Geometry :: struct {
    position : [3]f32,
    mesh     : Mesh,
}

Arena :: struct {
	body       : b3.BodyId,
    geometries : [dynamic]Arena_Geometry
}

arena_init :: proc(arena: ^Arena, physics: ^Physics, platforms: []Platform, allocator := context.allocator) {
    arena.geometries = make([dynamic]Arena_Geometry, allocator = allocator)

	body_def := b3.DefaultBodyDef()
	body_def.type = .staticBody
	body_def.position = {0, 0, 0}
	arena.body = b3.CreateBody(physics.world, body_def)

	for &p in platforms {
		half      := p.size * 0.5
		box_hull  := b3.MakeBoxHull(half.x, half.y, half.z)
		shape_def := b3.DefaultShapeDef()
		shape_def.baseMaterial.friction = 0.6
		shape_def.baseMaterial.restitution = 0.2
		shape_def.filter = physics_filter_create(
            {.Static_World},
            {.Player_Physics, .Enemy_Physics}
        )

        platform_position := p.origin + p.size * .5

		_ = b3.CreateTransformedHullShape(
            arena.body,
			shape_def,
			&box_hull.base,
			{p = platform_position, q = 1},
			{1, 1, 1},
		)

        append(&arena.geometries, {
            position = platform_position,
            mesh     = mesh_create_box(p.size * .5)
        })
	}
}

arena_destroy :: proc(arena: ^Arena) {
    for &geometry in arena.geometries {
        mesh_destroy(&geometry.mesh)
    }
    delete(arena.geometries)
    b3.DestroyBody(arena.body)
}

arena_draw_3d :: proc(arena: ^Arena, renderer : ^Renderer) {
    for &geometry in arena.geometries {
        renderer_draw_mesh(renderer, &geometry.mesh, geometry.position, 1)
    }
}