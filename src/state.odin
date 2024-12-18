package mou

// Global state
State :: struct {
	// Rendering state
	window:          Window,
	camera:          Camera,
	// UI state
	ui_tex:          Texture,
	ui_vao:          Vertex_Array,
	ui_vbo:          Buffer,
	ui_ebo:          Buffer,
	ui_shader:       Shader,
	// Settings
	render_distance: i32,
	fog_enabled:     bool,
	far_plane:       bool,
	// Other state
	world:           World,
}
