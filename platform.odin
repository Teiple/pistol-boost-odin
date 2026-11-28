package main

import "core:math/linalg"
import "base:intrinsics"

MIN_PLATFORM_SIZE    :: [3]f32{ .1, .1, .1}

Platform :: struct {
    origin  : [3]f32,
    size    : [3]f32,    
    variant : Platform_Variant
}

Platform_Type :: enum u8 {
    Box,
    Slope,
}

Platform_Variant :: union {
    Platform_Box,
    Platform_Slope,
}

Platform_Box :: struct{
}

Slope_Corner :: enum u8 {
    Bottom_Left,
    Bottom_Right,
    Top_Left,
    Top_Right,
}

Platform_Slope :: struct {
    corner : Slope_Corner,
}

Platform_Instance :: struct($T: typeid)
    where intrinsics.type_is_variant_of(Platform_Variant, T)
{
    using base : ^Platform,
    using var  : ^T,
}

platform_instance :: proc(platform: ^Platform, variant : ^$T) -> Platform_Instance(T) {
    return { base = platform, var = variant }
}

// Platform ultility data lookup 

Box_Face :: enum u8 {
    Negative_X,
    Positive_X,
    Negative_Y,
    Positive_Y,
    Negative_Z,
    Positive_Z,
}

box_unit_face_quads := [Box_Face][4][3]f32 {
    .Negative_X = { {0, 0, 0}, {0, 0, 1}, {0, 1, 1}, {0, 1, 0} },
    .Positive_X = { {1, 0, 0}, {1, 1, 0}, {1, 1, 1}, {1, 0, 1} },
    .Negative_Y = { {0, 0, 0}, {1, 0, 0}, {1, 0, 1}, {0, 0, 1} },
    .Positive_Y = { {0, 1, 0}, {0, 1, 1}, {1, 1, 1}, {1, 1, 0} },
    .Negative_Z = { {0, 0, 0}, {0, 1, 0}, {1, 1, 0}, {1, 0, 0} },
    .Positive_Z = { {0, 0, 1}, {1, 0, 1}, {1, 1, 1}, {0, 1, 1} },
}

box_face_normals := [Box_Face][3]f32 {
    .Negative_X = { -1,  0,  0},
    .Positive_X = {  1,  0,  0},
    .Negative_Y = {  0, -1,  0},
    .Positive_Y = {  0,  1,  0},
    .Negative_Z = {  0,  0, -1},
    .Positive_Z = {  0,  0,  1},
}

box_face_normal_indices := [Box_Face]int {
    .Negative_X = 0,
    .Positive_X = 0,
    .Negative_Y = 1,
    .Positive_Y = 1,
    .Negative_Z = 2,
    .Positive_Z = 2,
}

Box_Unit_Edge :: struct {
    p0 : [3]f32,
    p1 : [3]f32,
    f0 : Box_Face,
    f1 : Box_Face,
}

box_unit_edges := [12]Box_Unit_Edge {
    { {0, 0, 0}, {1, 0, 0}, .Negative_Y, .Negative_Z },
    { {0, 0, 1}, {1, 0, 1}, .Negative_Y, .Positive_Z },
    { {0, 1, 0}, {1, 1, 0}, .Positive_Y, .Negative_Z },
    { {0, 1, 1}, {1, 1, 1}, .Positive_Y, .Positive_Z },

    { {0, 0, 0}, {0, 1, 0}, .Negative_X, .Negative_Z },
    { {0, 0, 1}, {0, 1, 1}, .Negative_X, .Positive_Z },
    { {1, 0, 0}, {1, 1, 0}, .Positive_X, .Negative_Z },
    { {1, 0, 1}, {1, 1, 1}, .Positive_X, .Positive_Z },

    { {0, 0, 0}, {0, 0, 1}, .Negative_X, .Negative_Y },
    { {0, 1, 0}, {0, 1, 1}, .Negative_X, .Positive_Y },
    { {1, 0, 0}, {1, 0, 1}, .Positive_X, .Negative_Y },
    { {1, 1, 0}, {1, 1, 1}, .Positive_X, .Positive_Y },
}

// Platform ultilies

ray_to_line :: proc(
    ray_origin     : [3]f32,
    ray_direction  : [3]f32,
    line_point     : [3]f32,
    line_direction : [3]f32,
) -> (dist_along_line : f32, ok : bool) {
    w0 := ray_origin - line_point
    a  := linalg.dot(ray_direction,  ray_direction)
    b  := linalg.dot(ray_direction,  line_direction)
    c  := linalg.dot(line_direction, line_direction)
    d  := linalg.dot(ray_direction,  w0)
    e  := linalg.dot(line_direction, w0)
    denom := a * c - b * b

    if abs(denom) < 1e-4 do return
    return (a * e - b * d) / denom, true
}

ray_slope_interesect :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    slope_origin  : [3]f32,
    slope_size    : [3]f32,
    slope_corner  : Slope_Corner,
) -> (dist : f32, hit: bool) {
    min_box := slope_origin
    max_box := slope_origin + slope_size

    t_min := (min_box - ray_origin) / ray_direction
    t_max := (max_box - ray_origin) / ray_direction

    t1 := linalg.min(t_min, t_max)
    t2 := linalg.max(t_min, t_max)

    t_near := max(t1.x, t1.y, t1.z)
    t_far  := min(t2.x, t2.y, t2.z)

    if t_far < t_near || t_near < 0 do return 0, false

    // The diagonal plane
    nx, ny, plane_val : f32
    sx := slope_size.x
    sy := slope_size.y
    ox := slope_origin.x
    oy := slope_origin.y

    switch slope_corner {
    case .Bottom_Left:
        nx = sy
        ny = sx
        plane_val = sy * ox + sx * oy + sx * sy
    case .Bottom_Right:
        nx = -sy
        ny = sx
        plane_val = -sy * ox + sx * oy
    case .Top_Left:
        nx = sy
        ny = -sx
        plane_val = sy * ox - sx * oy
    case .Top_Right:
        nx = -sy
        ny = -sx
        plane_val = -sy * ox - sx * oy - sx * sy
    }

    denom := nx * ray_direction.x + ny * ray_direction.y
    numer := plane_val - (nx * ray_origin.x + ny * ray_origin.y)

    if denom < 0 {
        t_near = max(t_near, numer / denom)
    } else if denom > 0 {
        t_far  = min(t_far , numer / denom)
    } else if numer < 0 {
        return 0, false
    }

    return t_near, t_far > t_near && t_near > 0
}

ray_box_intersect :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    box_origin    : [3]f32,
    box_size      : [3]f32,
) -> (dist: f32, face: Box_Face, hit: bool) {
    min_box := box_origin
    max_box := box_origin + box_size

    t_min := (min_box - ray_origin) / ray_direction
    t_max := (max_box - ray_origin) / ray_direction

    t1 := linalg.min(t_min, t_max)
    t2 := linalg.max(t_min, t_max)

    t_near := max(t1.x, t1.y, t1.z)
    t_far  := min(t2.x, t2.y, t2.z)

    if t_far < t_near || t_near < 0 do return

    hit_face: Box_Face
    if t_near == t1.x {
        hit_face = .Negative_X if ray_direction.x > 0 else .Positive_X
    } else if t_near == t1.y {
        hit_face = .Negative_Y if ray_direction.y > 0 else .Positive_Y
    } else {
        hit_face = .Negative_Z if ray_direction.z > 0 else .Positive_Z
    }

    return t_near, hit_face, true
}

ray_segment_distance_sqr :: proc(ro, rd, p0, p1: [3]f32) -> f32 {
    u := p1 - p0
    v := rd
    w := p0 - ro

    a := linalg.dot(u, u)
    b := linalg.dot(u, v)
    c := linalg.dot(v, v)
    d := linalg.dot(u, w)
    e := linalg.dot(v, w)

    denom := a * c - b * b
    s: f32 = 0
    t: f32 = 0

    if abs(denom) < 1e-5 {
        s = 0
        t = e / c if c > 1e-5 else 0
    } else {
        s = (b * e - c * d) / denom
        t = (a * e - b * d) / denom
    }

    s = clamp(s, 0, 1)
    t = max(t, 0)

    closest_seg := p0 + s * u
    closest_ray := ro + t * v
    diff := closest_seg - closest_ray
    return linalg.dot(diff, diff)
}

Box_Edge :: struct {
    p0: [3]f32,
    p1: [3]f32,
    f0: Box_Face,
    f1: Box_Face,
}

pick_box_face :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    box_origin    : [3]f32,
    box_size      : [3]f32,
) -> Box_Face {
    if dist, face, hit := ray_box_intersect(
        ray_origin    = ray_origin,
        ray_direction = ray_direction,
        box_origin    = box_origin,
        box_size      = box_size,
    ); hit {
        return face
    } 

    edges     := get_box_edges(box_origin, box_size)
    best_dist := max(f32)
    best_face := Box_Face.Negative_X

    for edge in edges {
        n0 := box_face_normals[edge.f0]
        n1 := box_face_normals[edge.f1]

        dot0 := linalg.dot(n0, ray_direction)
        dot1 := linalg.dot(n1, ray_direction)
        // dot < 0 meaning facing towards the ray
        if (dot0 < 0) == (dot1 < 0) do continue

        dist := ray_segment_distance_sqr(ray_origin, ray_direction, edge.p0, edge.p1)
        if dist < best_dist {
            best_dist = dist
            best_face = edge.f0 if dot0 > dot1 else edge.f1
        }
    }

    return best_face
}

pick_box_face_multi :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    platforms     : []Platform,
    indices       : []i32,
) -> (pick_index : i32, pick_face: Box_Face) {
    pick_index = -1

    // Check direct hit first
    best_dist := max(f32)
    for index in indices {
        if dist, face, hit := ray_box_intersect(
            ray_origin    = ray_origin,
            ray_direction = ray_direction,
            box_origin    = platforms[index].origin,
            box_size      = platforms[index].size,
        ); hit && dist < best_dist {
            dist       = best_dist
            pick_index = index
            pick_face  = face
        }
    }

    if pick_index >= 0 do return

    best_dist = max(f32)
    
    for index in indices {
        edges := get_box_edges(platforms[index].origin, platforms[index].size)
        for edge in edges {
            n0 := box_face_normals[edge.f0]
            n1 := box_face_normals[edge.f1]

            dot0 := linalg.dot(n0, ray_direction)
            dot1 := linalg.dot(n1, ray_direction)
            // dot < 0 meaning facing towards the ray
            if (dot0 < 0) == (dot1 < 0) do continue

            dist := ray_segment_distance_sqr(ray_origin, ray_direction, edge.p0, edge.p1)
            if dist < best_dist {
                best_dist  = dist
                pick_index = index
                pick_face  = edge.f0 if dot0 > dot1 else edge.f1
            }
        }
    }

    return
}

// Find all the coplanar faces
pick_face_extend_targets :: proc(
    lead_index : i32,
    lead_face  : Box_Face,
    platforms  : []Platform,
    indices    : []i32,
    targets    : ^[dynamic]Face_Extend_Target,
) {
    lead_normal       := box_face_normals       [lead_face]
    lead_normal_index := box_face_normal_indices[lead_face]
    lead_center       := platforms[lead_index].origin + platforms[lead_index].size * .5
    lead_face_pos     := lead_center + lead_normal * platforms[lead_index].size * .5

    for index in indices {
        center        := platforms[index].origin + platforms[index].size * .5
        face_position := center + lead_normal * platforms[index].size * .5
        if abs(face_position[lead_normal_index] - lead_face_pos[lead_normal_index]) < 1e-8 {
            append(targets, {
                index          = index,
                initial_origin = platforms[index].origin,
                initial_size   = platforms[index].size,
            })
        }
    }
}

get_box_quad_by_face :: proc(
    box_origin : [3]f32,
    box_size   : [3]f32,
    face       : Box_Face,
    offset     : f32 = 0,
) -> [4][3]f32 {
    unit_quad := box_unit_face_quads[face]
    quad: [4][3]f32
    for i in 0..<4 {
        quad[i] = box_origin + unit_quad[i] * box_size +
            box_face_normals[face] * offset
    }
    return quad
}

get_box_edges :: proc(box_origin, box_size: [3]f32) -> (edges: [12]Box_Edge) {
    for e, i in box_unit_edges {
        edges[i] = {
            p0 = box_origin + e.p0 * box_size,
            p1 = box_origin + e.p1 * box_size,
            f0 = e.f0,
            f1 = e.f1,
        }
    }
    return
}

ray_plane_intersect :: proc(
    ray_origin    : [3]f32,
    ray_direction : [3]f32,
    plane_normal  : [3]f32,
    plane_point   : [3]f32,
) -> (point : [3]f32, hit: bool){
    if abs(linalg.dot(ray_direction, plane_normal)) < 1e-4 {
        return
    }
    t := linalg.dot(plane_point - ray_origin, plane_normal) / linalg.dot(ray_direction, plane_normal)
    if t < 0 do return
    return ray_origin + t * ray_direction, true
}

snap_platform_to_grid :: proc(platform : ^Platform, grid_unit : f32) {
    platform.origin = linalg.round(platform.origin / grid_unit) * grid_unit
    platform.size   = linalg.round(platform.size / grid_unit) * grid_unit
    platform.size   = linalg.max(platform.size, MIN_PLATFORM_SIZE)
}

get_centroid_of_platforms :: proc(platforms : []Platform, indices : []i32) -> (centroid : [3]f32) {
    if len(indices) == 0 do return

    for index in indices {
        centroid += platforms[index].origin + platforms[index].size * .5 
    }
    centroid /= cast(f32)len(indices) 
    return
}