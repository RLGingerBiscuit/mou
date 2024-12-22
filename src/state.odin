package mou

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
	// Other state
	world:           World,
}
