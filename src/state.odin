package mou

import glm "core:math/linalg/glsl"

// Global state
State :: struct {
	// Rendering state
	window:          Window,
	camera:          Camera,
	// UI state
	ui:              UI_State,
	// Settings
	render_distance: i32,
	fog_enabled:     bool,
	far_plane:       bool,
	render_frustum:  bool,
	frozen_frustum:  Maybe(glm.mat4), // view projection matrix of frustum
	// Other state
	frame:           Frame_State,
	world:           World,
}

Frame_State :: struct {
	// Frame state
	// NOTE: Pointers are fine here because they are always locked
	chunks_to_demesh:   [dynamic]^Chunk,
	opaque_chunks:      [dynamic]^Chunk,
	transparent_chunks: [dynamic]^Chunk,
}

init_state :: proc(state: ^State) {
	state.frame.chunks_to_demesh = make([dynamic]^Chunk, 0, MAX_RENDER_DISTANCE * 16)
	state.frame.opaque_chunks = make([dynamic]^Chunk, 0, MAX_RENDER_DISTANCE * 16)
	state.frame.transparent_chunks = make([dynamic]^Chunk, 0, MAX_RENDER_DISTANCE * 16)
}

destroy_state :: proc(state: ^State) {
	delete(state.frame.chunks_to_demesh)
	delete(state.frame.opaque_chunks)
	delete(state.frame.transparent_chunks)
}
