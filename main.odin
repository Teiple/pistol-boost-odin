package main

import "base:runtime"
import "core:fmt"
import sapp "sokol-odin/sokol/app"
import "core:mem"

WINDOW_INITIAL_WIDTH  :: 1024
WINDOW_INITIAL_HEIGHT :: 768

odin_ctx := runtime.default_context()

main :: proc() {
	track : mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, odin_ctx.allocator)
	odin_ctx.allocator = mem.tracking_allocator(&track)
	
	context = odin_ctx

	sapp.run({
		window_title     = "Pistol Boost",
		width            = WINDOW_INITIAL_WIDTH,
		height           = WINDOW_INITIAL_HEIGHT,
		// disable_vsync    = true,
		init_cb    = proc "c" () {
			context = odin_ctx
			game_init()
		},
		frame_cb   = proc "c" () {
			context = odin_ctx
			dt : = cast(f32)sapp.frame_duration_unfiltered()
			game_update(dt)
		},
		event_cb   = proc "c" (ev : ^sapp.Event) {
			context = odin_ctx
			game_input(ev)
		},
		cleanup_cb = proc "c" () {
			context = odin_ctx
			game_destroy()
		}
	})

	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintfln("=== %d allocations not freed ===", len(track.allocation_map))
			for ptr, entry in track.allocation_map {
				fmt.eprintfln("{0} -> {1} bytes not freed", entry.location, entry.size)
			}
		}
		if len(track.bad_free_array) > 0 {
			fmt.eprintfln("=== Bad frees ===")
			for entry in track.bad_free_array {
				fmt.eprintfln("{0} -> bad free", entry.location)
			}
		}

		mem.tracking_allocator_destroy(&track)
	}
}