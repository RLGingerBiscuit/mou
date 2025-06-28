package mou

import glm "core:math/linalg/glsl"
import gl "vendor:OpenGL"
import "vendor:glfw"

FAST_MODIFIER :: 2.5

Camera :: struct {
	yaw, pitch:        f32,
	pos:               glm.vec3,
	speed:             f32,
	sensitivity:       f32,
	fov:               f32,
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
	yaw, pitch, speed, sensitivity, fov: f32,
	up := glm.vec3{0, 1, 0},
) {
	cam := &state.camera
	cam.pos = pos
	cam.yaw = yaw
	cam.pitch = pitch
	cam.speed = speed
	cam.sensitivity = sensitivity
	cam.fov = fov
	cam.global_up = up
	cam.up = up

	_update_camera_axes(state)
}

_update_camera_axes :: proc(state: ^State) {
	cam := &state.camera

	yaw := glm.radians(cam.yaw)
	pitch := glm.radians(cam.pitch)

	cam.front = glm.normalize(
		glm.vec3{glm.cos(yaw) * glm.cos(pitch), glm.sin(pitch), glm.sin(yaw) * glm.cos(pitch)},
	)
	cam.right = glm.normalize(glm.cross(cam.front, cam.global_up))
	cam.up = glm.normalize(glm.cross(cam.right, cam.front))

	cam.view_matrix = glm.mat4LookAt(cam.pos, cam.pos + cam.front, cam.up)
	cam.projection_matrix = glm.mat4Perspective(
		cam.fov,
		cast(f32)state.window.size.x / cast(f32)state.window.size.y,
		NEAR_PLANE,
		state.far_plane ? f32(state.render_distance + 2) * CHUNK_WIDTH : 10_000,
	)
	cam.front = glm.normalize(glm.vec3{glm.cos(yaw), 0, glm.sin(yaw)})
	cam.right = glm.normalize(glm.cross(cam.front, cam.global_up))
}

update_camera :: proc(state: ^State, dt: f64) {
	cam := &state.camera
	wnd := &state.window

	if .UI in wnd.flags {
		_update_camera_axes(state)
		return
	}

	centre := glm.dvec2{cast(f64)wnd.size.x / 2, cast(f64)wnd.size.y / 2}

	x := wnd.cursor.x
	y := wnd.cursor.y
	x = centre.x - x
	y = centre.y - y
	glfw.SetCursorPos(wnd.handle, centre.x, centre.y)
	wnd.cursor = centre

	x *= cast(f64)cam.sensitivity
	y *= cast(f64)cam.sensitivity

	cam.yaw -= cast(f32)x
	cam.pitch = clamp(cam.pitch + cast(f32)y, -89.99, 89.99)

	_update_camera_axes(state)

	old_pos := cam.pos

	if window_get_key(wnd^, .Left_Control) == .Press {
		cam.flags |= {.Fast}
	}

	if window_get_key(wnd^, .X) == .Press && window_get_prev_key(wnd^, .X) != .Press {
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

	if window_get_key(wnd^, .W) == .Press {
		cam.pos += cam.front * velocity
	}
	if window_get_key(wnd^, .A) == .Press {
		cam.pos -= cam.right * velocity
	}
	if window_get_key(wnd^, .S) == .Press {
		cam.pos -= cam.front * velocity
	}
	if window_get_key(wnd^, .D) == .Press {
		cam.pos += cam.right * velocity
	}
	if window_get_key(wnd^, .Space) == .Press {
		cam.pos += cam.global_up * velocity
	}
	if window_get_key(wnd^, .Left_Shift) == .Press {
		cam.pos -= cam.global_up * velocity
	}

	if window_get_key(wnd^, .Left) == .Press {
		cam.yaw -= cam.sensitivity * 10
	}
	if window_get_key(wnd^, .Right) == .Press {
		cam.yaw += cam.sensitivity * 10
	}
	if window_get_key(wnd^, .Up) == .Press {
		cam.pitch += cam.sensitivity * 10
	}
	if window_get_key(wnd^, .Down) == .Press {
		cam.pitch -= cam.sensitivity * 10
	}

	if cam.pos == old_pos && window_get_key(wnd^, .Left_Control) == .Release {
		cam.flags &~= {.Fast}
	}
}
