package main

import "base:runtime"
import "core:fmt"
import sapp "sokol-odin/sokol/app"
import "core:mem"

odin_ctx := runtime.default_context()

main :: proc() {
	track : mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, odin_ctx.allocator)
	odin_ctx.allocator = mem.tracking_allocator(&track)
	
	context = odin_ctx

	sapp.run({
		window_title     = "Pistol Boost",
		width            = 960,
		height           = 540,
		disable_vsync    = true,
		enable_clipboard = true,
		clipboard_size   = 1024,
		init_cb    = proc "c" () {

		},
		frame_cb   = proc "c" () {

		},
		cleanup_cb = proc "c" () {

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