package mou

import glm "core:math/linalg/glsl"

PLAYER_EYE_OFFSET :: glm.vec3{0, 2, 0}
SPRINT_MODIFIER :: 2.5

Player :: struct {
	cam:       Camera,
	pos:       glm.vec3,
	speed:     f32,
	sprinting: bool,
}

init_player :: proc(
	p: ^Player,
	wnd: ^Window,
	pos: glm.vec3,
	yaw, pitch, speed, sensitivity_mult, fovx: f32,
	render_distance: i32,
) {
	init_camera(&p.cam, wnd, pos + PLAYER_EYE_OFFSET, yaw, pitch, sensitivity_mult, fovx, render_distance)
	p.pos = pos
	p.speed = speed
}

update_player :: proc(p: ^Player, wnd: ^Window, render_distance: i32, dt: f64) {
	update_camera(&p.cam, wnd, render_distance, dt)
	if .UI in wnd.flags {
		return
	}

	if window_is_key_down(wnd^, KEY_SPRINT) {
		p.sprinting = true
	}

	old_pos := p.pos

	velocity := f32(cast(f64)p.speed * dt)
	if p.sprinting {
		velocity *= SPRINT_MODIFIER
	}

	cam := &p.cam

	yaw := glm.radians(cam.yaw)
	front := glm.normalize(glm.vec3{glm.cos(yaw), 0, glm.sin(yaw)})
	right := glm.normalize(glm.cross(front, cam.global_up))

	if window_is_key_down(wnd^, KEY_FORWARD) {
		p.pos += front * velocity
	}
	if window_is_key_down(wnd^, KEY_BACKWARD) {
		p.pos -= front * velocity
	}
	if window_is_key_down(wnd^, KEY_LEFT) {
		p.pos -= right * velocity
	}
	if window_is_key_down(wnd^, KEY_RIGHT) {
		p.pos += right * velocity
	}
	if window_is_key_down(wnd^, KEY_UP) {
		p.pos += cam.global_up * velocity
	}
	if window_is_key_down(wnd^, KEY_DOWN) {
		p.pos -= cam.global_up * velocity
	}

	// Don't need to hold sprint while moving
	if p.pos == old_pos && window_is_key_up(wnd^, KEY_SPRINT) {
		p.sprinting = false
	}

	p.cam.pos = p.pos + PLAYER_EYE_OFFSET
}
