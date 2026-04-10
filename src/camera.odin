package mou

import glm "core:math/linalg/glsl"
import gl "vendor:OpenGL"

FAST_MODIFIER :: 2.5

Camera :: struct {
	yaw, pitch:        f32,
	pos:               glm.vec3,
	speed:             f32,
	sensitivity_mult:  f32,
	fovx:              f32,
	view_matrix:       glm.mat4,
	projection_matrix: glm.mat4,
	global_up:         glm.vec3,
	front, right, up:  glm.vec3,
	flags:             bit_set[enum u8 {
		Fast,
		Wireframe,
	};u8],
}

init_camera :: proc(
	state: ^State,
	pos: glm.vec3,
	yaw, pitch, speed, sensitivity_mult, fovx: f32,
	up := glm.vec3{0, 1, 0},
) {
	cam := &state.camera
	cam.pos = pos
	cam.yaw = yaw
	cam.pitch = pitch
	cam.speed = speed
	cam.sensitivity_mult = sensitivity_mult
	cam.fovx = fovx
	cam.global_up = up
	cam.up = up

	_update_camera_axes(state)
}

_update_camera_axes :: proc(state: ^State) {
	cam := &state.camera

	yaw := glm.radians(cam.yaw)
	pitch := glm.radians(cam.pitch)

	cam.front = glm.normalize(
		glm.vec3{glm.sin(pitch) * glm.cos(yaw), glm.cos(pitch), glm.sin(pitch) * glm.sin(yaw)},
	)
	cam.right = glm.normalize(glm.cross(cam.front, cam.global_up))
	cam.up = glm.normalize(glm.cross(cam.right, cam.front))

	aspect := window_aspect_ratio(state.window)
	fovy := 2 * glm.atan(glm.tan(glm.radians(cam.fovx) / 2) / aspect)

	cam.view_matrix = glm.mat4LookAt(cam.pos, cam.pos + cam.front, cam.up)
	cam.projection_matrix = glm.mat4Perspective(
		fovy,
		aspect,
		NEAR_PLANE,
		state.far_plane ? f32(state.render_distance + 1) * CHUNK_SIZE : 1_000,
	)
}

update_camera :: proc(state: ^State, dt: f64) {
	cam := &state.camera
	wnd := &state.window

	if .UI in wnd.flags {
		_update_camera_axes(state)
		return
	}

	window_size := get_window_size(state.window)
	centre := glm.dvec2{cast(f64)window_size.x / 2, cast(f64)window_size.y / 2}

	x := wnd.cursor.x
	y := wnd.cursor.y
	x = centre.x - x
	y = centre.y - y
	window_center_cursor(wnd)

	sensitivity := state.camera.fovx * state.camera.sensitivity_mult

	x *= cast(f64)sensitivity
	y *= cast(f64)sensitivity

	cam.yaw -= cast(f32)x
	cam.pitch = clamp(cam.pitch - cast(f32)y, 0.01, 179.99)

	_update_camera_axes(state)

	old_pos := cam.pos

	if window_is_key_down(wnd^, KEY_SPRINT) {
		cam.flags |= {.Fast}
	}

	if window_is_key_pressed(wnd^, KEY_WIREFRAME) {
		cam.flags ~= {.Wireframe}
		if .Wireframe in cam.flags {
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
		} else {
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
		}
	}

	velocity := f32(cast(f64)cam.speed * dt)
	if .Fast in cam.flags {
		velocity *= FAST_MODIFIER
	}

	yaw := glm.radians(cam.yaw)
	front := glm.normalize(glm.vec3{glm.cos(yaw), 0, glm.sin(yaw)})
	right := glm.normalize(glm.cross(front, cam.global_up))

	if window_is_key_down(wnd^, KEY_FORWARD) {
		cam.pos += front * velocity
	}
	if window_is_key_down(wnd^, KEY_BACKWARD) {
		cam.pos -= front * velocity
	}
	if window_is_key_down(wnd^, KEY_LEFT) {
		cam.pos -= right * velocity
	}
	if window_is_key_down(wnd^, KEY_RIGHT) {
		cam.pos += right * velocity
	}
	if window_is_key_down(wnd^, KEY_UP) {
		cam.pos += cam.global_up * velocity
	}
	if window_is_key_down(wnd^, KEY_DOWN) {
		cam.pos -= cam.global_up * velocity
	}

	if window_is_key_down(wnd^, KEY_PAN_UP) {
		cam.pitch -= sensitivity * 5
	}
	if window_is_key_down(wnd^, KEY_PAN_DOWN) {
		cam.pitch += sensitivity * 5
	}
	if window_is_key_down(wnd^, KEY_PAN_LEFT) {
		cam.yaw -= sensitivity * 5
	}
	if window_is_key_down(wnd^, KEY_PAN_RIGHT) {
		cam.yaw += sensitivity * 5
	}

	if cam.pos == old_pos && window_is_key_up(wnd^, KEY_SPRINT) {
		cam.flags &~= {.Fast}
	}
}
