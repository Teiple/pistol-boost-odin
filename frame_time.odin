package main

// in seconds
FPS_COUNT_INTERVAL :: 1

Frame_Time :: struct {
	time:                 f32,
	// Fps counter
	interval_fps_sum:     f32,
	interval_frame_count: f32,
	interval_fps_time:    f32,
	average_fps:          f32,
}

frame_time_update :: proc(frame_time : ^Frame_Time, dt: f32) {
	frame_time.time += dt

	// Fps counter
	fps := 1.0 / dt
	frame_time.interval_fps_time += dt
	frame_time.interval_fps_sum += fps
	frame_time.interval_frame_count += 1

	if frame_time.interval_fps_time >= FPS_COUNT_INTERVAL {
		if frame_time.interval_frame_count > 0 {
			frame_time.average_fps =
				frame_time.interval_fps_sum / frame_time.interval_frame_count
		} else {
			frame_time.average_fps = 0
		}

		frame_time.interval_fps_time = 0
		frame_time.interval_fps_sum = 0
		frame_time.interval_frame_count = 0
	}
}