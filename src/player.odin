package mou

import glm "core:math/linalg/glsl"

PLAYER_WIDTH :: 1
PLAYER_HEIGHT :: 2
PLAYER_EYE_OFFSET :: glm.vec3{0, 1.8, 0}
PLAYER_GRAVITY :: -24 // blocks/s^2
PLAYER_JUMP_SPEED :: 9 // blocks/s^2
PLAYER_TERMINAL_VELOCITY :: -78
PLAYER_SPRINT_MODIFIER :: 1.5

Player :: struct {
	cam:       Camera,
	pos:       glm.vec3,
	speed:     f32,
	vel:       glm.vec3,
	sprinting: bool,
	noclip:    bool,
	on_ground: bool,
}

player_box :: proc(p: Player) -> AABB {
	return aabb_from_base(p.pos, PLAYER_WIDTH, PLAYER_HEIGHT)
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

update_player :: proc(p: ^Player, wnd: ^Window, #by_ptr world: World, render_distance: i32, dt: f64) {
	update_camera(&p.cam, wnd, render_distance, dt)
	if .UI in wnd.flags {
		return
	}

	if window_is_key_down(wnd^, KEY_SPRINT) {
		p.sprinting = true
	}

	if window_is_key_pressed(wnd^, KEY_FLY) {
		p.noclip = !p.noclip
		p.vel = {}
	}

	speed := p.speed
	if p.sprinting {
		speed *= PLAYER_SPRINT_MODIFIER
	}

	cam := &p.cam

	yaw := glm.radians(cam.yaw)
	front := glm.normalize(glm.vec3{glm.cos(yaw), 0, glm.sin(yaw)})
	right := glm.normalize(glm.cross(front, cam.global_up))

	move: glm.vec3
	if window_is_key_down(wnd^, KEY_FORWARD) {
		move += front
	}
	if window_is_key_down(wnd^, KEY_BACKWARD) {
		move -= front
	}
	if window_is_key_down(wnd^, KEY_LEFT) {
		move -= right
	}
	if window_is_key_down(wnd^, KEY_RIGHT) {
		move += right
	}

	if p.noclip {
		if window_is_key_down(wnd^, KEY_UP) {
			move += cam.global_up
		}
		if window_is_key_down(wnd^, KEY_DOWN) {
			move -= cam.global_up
		}
	}

	moving := move != glm.vec3{}
	if moving {
		move = glm.normalize(move)
	}

	dt := cast(f32)dt
	delta := move * speed * dt

	if p.noclip {
		p.pos += delta
	} else {
		if p.on_ground && window_is_key_down(wnd^, KEY_UP) {
			p.vel.y = PLAYER_JUMP_SPEED
			p.on_ground = false
		}

		delta.y += p.vel.y * dt + 0.5 * PLAYER_GRAVITY * dt * dt
		p.vel.y = max(p.vel.y + PLAYER_GRAVITY * dt, PLAYER_TERMINAL_VELOCITY)

		moved, hit := aabb_move(world, player_box(p^), delta)
		p.pos += moved

		p.on_ground = .Y in hit && delta.y <= 0
		if .Y in hit {
			p.vel.y = 0
		}
	}

	// Don't need to hold sprint while moving
	if !moving && window_is_key_up(wnd^, KEY_SPRINT) {
		p.sprinting = false
	}

	p.cam.pos = p.pos + PLAYER_EYE_OFFSET
}
