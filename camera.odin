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
    ortho_size   : f32,
}

camera_init_default :: proc(camera : ^Camera, position : [3]f32, target : [3]f32) {
    camera.fovy_degrees = 60
    camera.near         = 0.1
    camera.far          = 100
    camera.up           = {0, 1, 0}
    camera.position     = position
    camera.target       = target
    camera.ortho_size   = 0
}

camera_destroy :: proc(camera : ^Camera) {
    // nothing for now
}

camera_basis :: proc(camera: ^Camera, vp: ^Viewport) -> (right, up, forward: [3]f32) {
    // Camera basis vectors
    forward = linalg.normalize(camera.target - camera.position)
    right   = linalg.normalize(linalg.cross(forward, camera.up))
    up      = linalg.cross(right, forward)
    return
}

camera_view_projection_matrix :: proc(camera: ^Camera, vp: ^Viewport) -> matrix[4, 4]f32 {
    proj, view : matrix[4,4]f32

    if camera.ortho_size == 0 {
        proj = linalg.matrix4_perspective(
            fovy   = math.to_radians(camera.fovy_degrees),
            aspect = viewport_get_aspect(vp),
            near   = camera.near,
            far    = camera.far,
        )
        view = linalg.matrix4_look_at(
            eye    = camera.position,
            centre = camera.target,
            up     = camera.up,
        )
    } else {
        // deepseek helped me with this
        aspect := viewport_get_aspect(vp)
       
        half_height := camera.ortho_size
        half_width  := half_height * aspect

        proj = linalg.matrix_ortho3d(
            left   = -half_width,
            right  =  half_width,
            bottom = -half_height,
            top    =  half_height,
            near   = camera.near,
            far    = camera.far,
        )
        view = linalg.matrix4_look_at(
            eye    = camera.position,
            centre = camera.target,
            up     = camera.up,
        )
    }

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
    mode_perspective : Free_Camera_Perspective,
    mode_orthogonal  : Free_Camera_Orthogonal,
    move_direction   : [3]f32,
    camera           : ^Camera,
    move_speed       : f32,
    mode             : Free_Camera_Mode,
}

Free_Camera_Mode :: enum u8 {
    Perspective,
    Orthogonal,
}

Free_Camera_Perspective :: struct {
    position   : [3]f32,
    pitch      : f32,
    yaw        : f32,
    look_speed : f32,
}

Free_Camera_Orthogonal :: struct {
    size      : f32,
    direction : [3]f32,
    position  : [3]f32,
}

free_camera_init_default :: proc(free_cam: ^Free_Camera, camera: ^Camera, viewport : ^Viewport) {
    free_cam^  = {
        camera           = camera,
        mode_perspective = {
            yaw      = math.PI,
            pitch    = 0,
            position = { 0, 2, 10 },
            look_speed = .005,
        },
        mode_orthogonal  = {
            size      = 8,
            direction = { 0, 0, -1 }, 
            position  = { 0, 2, 10 },
        },
        move_speed = 5,
    }
}

free_camera_input :: proc(free_cam: ^Free_Camera, ev : sapp.Event) {
    if ev.modifiers & sapp.MODIFIER_CTRL != 0 {
        return
    }
    #partial switch ev.type {
        case .KEY_DOWN:
            #partial switch ev.key_code {
                case .W: free_cam.move_direction.z =  1
                case .S: free_cam.move_direction.z = -1
                case .A: free_cam.move_direction.x = -1
                case .D: free_cam.move_direction.x =  1
                case .Q: free_cam.move_direction.y = -1
                case .E: free_cam.move_direction.y =  1
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

free_camera_update_3d :: proc(free_cam: ^Free_Camera, ctx: Game_Context, dt: f32) {
    if free_cam.mode == .Perspective {
        if (ctx.mouse.state[.Right] == .Pressed || ctx.mouse.state[.Right] == .Down) {
            free_cam.mode_perspective.yaw   -= ctx.mouse.delta.x * free_cam.mode_perspective.look_speed
            free_cam.mode_perspective.pitch  = clamp(
                free_cam.mode_perspective.pitch - ctx.mouse.delta.y * free_cam.mode_perspective.look_speed,
                math.to_radians_f32(-89.99),
                math.to_radians_f32( 89.99),
            )
        }

        forward := [3]f32{
            math.sin(free_cam.mode_perspective.yaw),
            0,
            math.cos(free_cam.mode_perspective.yaw),
        }
        right := linalg.cross(forward, {0, 1, 0})
        
        free_cam.mode_perspective.position += (
            right * free_cam.move_direction.x + 
            {0, 1, 0} * free_cam.move_direction.y + 
            forward * free_cam.move_direction.z
        ) * free_cam.move_speed * dt
        
        free_cam.camera.position   = free_cam.mode_perspective.position 
        free_cam.camera.ortho_size = 0
        free_cam.camera.target     = free_cam.camera.position +
        {
            math.cos(free_cam.mode_perspective.pitch) * math.sin(free_cam.mode_perspective.yaw), // x
            math.sin(free_cam.mode_perspective.pitch),                                           // y
            math.cos(free_cam.mode_perspective.pitch) * math.cos(free_cam.mode_perspective.yaw),  // z
        }
    } else {
        camera_right, camera_up, camera_foward := camera_basis(free_cam.camera, ctx.viewport)
        
        free_cam.mode_orthogonal.position += (
            camera_right * free_cam.move_direction.x + 
            camera_up    * free_cam.move_direction.z
        ) * free_cam.move_speed * dt

        free_cam.mode_orthogonal.size -= ctx.mouse.scroll.y * 2
        free_cam.camera.position       = free_cam.mode_orthogonal.position
        free_cam.camera.ortho_size     = free_cam.mode_orthogonal.size
        free_cam.camera.target         = free_cam.camera.position + free_cam.mode_orthogonal.direction
    }    
}
