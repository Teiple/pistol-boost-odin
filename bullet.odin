package main

Bullet :: struct {
    position  : [3]f32,
    direction : [3]f32, 
}

bullets_update_3d :: proc(bullets : []Bullet, dt : f32) {
    for &bullet in bullets {
        bullet.position += bullet.direction * dt 
    }
}

bullets_draw_3d :: proc() {
    
}