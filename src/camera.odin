package mou

import glm "core:math/linalg/glsl"
import gl "vendor:OpenGL"

Camera :: struct {
	yaw, pitch:        f32,
	pos:               glm.vec3,
	sensitivity_mult:  f32,
	fovx:              f32,
	view_matrix:       glm.mat4,
	projection_matrix: glm.mat4,
	global_up:         glm.vec3,
	front, right, up:  glm.vec3,
	wireframe:         bool,
}

init_camera :: proc(
	cam: ^Camera,
	wnd: ^Window,
	pos: glm.vec3,
	yaw, pitch, sensitivity_mult, fovx: f32,
	render_distance: i32,
	up := glm.vec3{0, 1, 0},
) {
	cam.pos = pos
	cam.yaw = yaw
	cam.pitch = pitch
	cam.sensitivity_mult = sensitivity_mult
	cam.fovx = fovx
	cam.global_up = up
	cam.up = up

	_update_camera_axes(cam, wnd, render_distance)
}

_update_camera_axes :: proc(cam: ^Camera, wnd: ^Window, render_distance: i32) {
	yaw := glm.radians(cam.yaw)
	pitch := glm.radians(cam.pitch)

	cam.front = glm.normalize(glm.vec3{glm.sin(pitch) * glm.cos(yaw), glm.cos(pitch), glm.sin(pitch) * glm.sin(yaw)})
	cam.right = glm.normalize(glm.cross(cam.front, cam.global_up))
	cam.up = glm.normalize(glm.cross(cam.right, cam.front))

	aspect := window_aspect_ratio(wnd^)
	fovy := 2 * glm.atan(glm.tan(glm.radians(cam.fovx) / 2) / aspect)

	cam.view_matrix = glm.mat4LookAt(cam.pos, cam.pos + cam.front, cam.up)
	cam.projection_matrix = glm.mat4Perspective(fovy, aspect, NEAR_PLANE, f32(render_distance + 1) * CHUNK_SIZE)
}

update_camera :: proc(cam: ^Camera, wnd: ^Window, render_distance: i32, dt: f64) {
	if .UI in wnd.flags {
		return
	}

	defer _update_camera_axes(cam, wnd, render_distance)

	window_size := get_window_size(wnd^)
	centre := glm.dvec2{cast(f64)window_size.x / 2, cast(f64)window_size.y / 2}

	x := wnd.cursor.x
	y := wnd.cursor.y
	x = centre.x - x
	y = centre.y - y
	window_center_cursor(wnd)

	sensitivity := cam.fovx * cam.sensitivity_mult

	x *= cast(f64)sensitivity
	y *= cast(f64)sensitivity

	cam.yaw -= cast(f32)x
	cam.pitch = clamp(cam.pitch - cast(f32)y, 0.01, 179.99)

	if window_is_key_pressed(wnd^, KEY_WIREFRAME) {
		cam.wireframe = !cam.wireframe
		if cam.wireframe {
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
		} else {
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
		}
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
}
