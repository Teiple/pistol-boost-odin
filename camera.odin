package main

import sapp   "sokol-odin/sokol/app"
import math   "core:math"
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
    proj := linalg.matrix4_perspective(
        fovy   = math.to_radians(camera.fovy_degrees),
        aspect = viewport_get_aspect(vp),
        near   = camera.near,
        far    = camera.far,
    )

    view := linalg.matrix4_look_at(
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
    if !follow_cam.enabled {
        return
    }

    follow_cam.target = linalg.lerp(
        follow_cam.target,
        target_pos,
        follow_cam.smoothness * dt,
    )
    
    camera.target   = follow_cam.target
    camera.position = follow_cam.target + follow_cam.offset
    camera.up       = {0, 1, 0}
}

Free_Camera :: struct {
    move_direction : [3]f32,
    move_speed     : f32,
    look_speed     : f32,
    pitch          : f32,
    yaw            : f32,
    enabled        : bool,
}

free_camera_input :: proc(free_cam: ^Free_Camera, camera: ^Camera, ev : sapp.Event) {
    if !free_cam.enabled {
        return
    }

    
    #partial switch ev.type {
        case .KEY_DOWN: if (ev.modifiers & sapp.MODIFIER_RMB) != 0 { 
                #partial switch ev.key_code {
                    case .W: free_cam.move_direction.z =  1
                    case .S: free_cam.move_direction.z = -1
                    case .A: free_cam.move_direction.x = -1
                    case .D: free_cam.move_direction.x =  1
                    case .Q: free_cam.move_direction.y = -1
                    case .E: free_cam.move_direction.y =  1
                }
            }
        case .KEY_UP:
            #partial switch ev.key_code {
                case .W: free_cam.move_direction.z = 0
                case .S: free_cam.move_direction.z = 0
                case .A: free_cam.move_direction.x = 0
                case .D: free_cam.move_direction.x = 0
                case .Q: free_cam.move_direction.y = 0
                case .E: free_cam.move_direction.y = 0
            }
    }
} 

free_camera_update_3d :: proc(free_cam: ^Free_Camera, camera: ^Camera, mouse : ^Mouse_Input, dt : f32) {
    if !free_cam.enabled {
        return
    }

    if mouse.state[.Right] == .Pressed || mouse.state[.Right] == .Down {
        free_cam.yaw   -= mouse.delta.x * free_cam.look_speed
        free_cam.pitch  = clamp(
            free_cam.pitch - mouse.delta.y * free_cam.look_speed,
            math.to_radians_f32(-89.9),
            math.to_radians_f32( 89.9),
        )
    }

    // math stuff I copied from llms (again)
    forward := [3]f32{
        math.sin(free_cam.yaw),
        0,
        math.cos(free_cam.yaw),
    }
    right := linalg.cross(forward, {0, 1, 0})

    camera.position += (
        right * free_cam.move_direction.x + 
        {0, 1, 0} * free_cam.move_direction.y + 
        forward * free_cam.move_direction.z
    ) * free_cam.move_speed * dt
    
    camera.target    = camera.position +
    {
        math.cos(free_cam.pitch) * math.sin(free_cam.yaw), // x
        math.sin(free_cam.pitch),                          // y
        math.cos(free_cam.pitch) * math.cos(free_cam.yaw), // z
    }
} 