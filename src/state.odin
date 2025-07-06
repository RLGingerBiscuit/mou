package mou

import glm "core:math/linalg/glsl"

// Global state
State :: struct {
	// Rendering state
	window:          Window,
	camera:          Camera,
	fbo:             Framebuffer,
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
	// NOTE: Pointers are fine here because world is always locked
	chunks_to_demesh:   [dynamic]^Chunk,
	opaque_chunks:      [dynamic]^Chunk,
	transparent_chunks: [dynamic]^Chunk,
	water_chunks:       [dynamic]^Chunk,
	memory_usage:       [dynamic][7]int,
	line_vertices:      [dynamic]Line_Vert,
}

init_state :: proc(state: ^State) {
	state.frame.chunks_to_demesh = make([dynamic]^Chunk, 0, MAX_RENDER_DISTANCE * 16)
	state.frame.opaque_chunks = make([dynamic]^Chunk, 0, MAX_RENDER_DISTANCE * 16)
	state.frame.transparent_chunks = make([dynamic]^Chunk, 0, MAX_RENDER_DISTANCE * 16)
	state.frame.water_chunks = make([dynamic]^Chunk, 0, MAX_RENDER_DISTANCE * 16)
	state.frame.memory_usage = make([dynamic][7]int, 0, MAX_RENDER_DISTANCE * 16)
	state.frame.line_vertices = make([dynamic]Line_Vert, 0, MAX_RENDER_DISTANCE * 16)
}

destroy_state :: proc(state: ^State) {
	delete(state.frame.chunks_to_demesh)
	delete(state.frame.opaque_chunks)
	delete(state.frame.transparent_chunks)
	delete(state.frame.water_chunks)
	delete(state.frame.memory_usage)
	delete(state.frame.line_vertices)
}
