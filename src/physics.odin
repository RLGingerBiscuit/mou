package mou

import "core:math"
import glm "core:math/linalg/glsl"

COLLISION_SKIN :: 0.02
COLLISION_GAP :: 0.001

Axis :: enum {
	X,
	Y,
	Z,
}
Collision :: bit_set[Axis]

AABB :: struct {
	min, max: glm.vec3,
}

aabb_from_base :: proc(pos: glm.vec3, width, height: f32) -> AABB {
	half := width / 2
	return {min = pos - {half, 0, half}, max = pos + {half, height, half}}
}

aabb_translate :: proc(box: AABB, by: glm.vec3) -> AABB {
	return {min = box.min + by, max = box.max + by}
}

aabb_extend :: proc(box: AABB, by: glm.vec3) -> AABB {
	box := box
	for i in 0 ..< len(by) {
		if by[i] > 0 {
			box.max[i] += by[i]
		} else {
			box.min[i] += by[i]
		}
	}
	return box
}

aabb_move :: proc(#by_ptr world: World, box: AABB, delta: glm.vec3) -> (moved: glm.vec3, hit: Collision) {
	box := box

	ORDER :: [3]Axis{.X, .Y, .Z}

	for axis, i in ORDER {
		d, blocked := _aabb_move_axis(world, box, axis, delta[i])
		if blocked {
			hit += {axis}
		}
		moved[i] = d

		step: glm.vec3
		step[i] = d
		box = aabb_translate(box, step)
	}

	return
}

_aabb_move_axis :: proc(#by_ptr world: World, box: AABB, axis: Axis, d: f32) -> (moved: f32, blocked: bool) {
	moved = d
	if moved == 0 {
		return
	}

	// Go slightly further so we notice the collision before it actually happens
	reach: glm.vec3
	reach[int(axis)] = d + (d > 0 ? COLLISION_SKIN : -COLLISION_SKIN)
	probe := aabb_extend(box, reach)

	inset := glm.vec3(COLLISION_GAP)
	inset[int(axis)] = 0

	lo := world_pos_to_block_pos(probe.min + inset)
	hi := world_pos_to_block_pos(probe.max - inset)

	nearest := math.inf_f32(d > 0 ? 1 : -1)

	for y in lo.y ..= hi.y {
		for z in lo.z ..= hi.z {
			for x in lo.x ..= hi.x {
				block, ok := get_world_block(world, {x, y, z})
				if !ok || !block_is_solid(block) {
					continue
				}

				cell := Block_Pos{x, y, z}
				if d > 0 {
					limit := f32(cell[int(axis)]) - box.max[int(axis)]
					if limit < -COLLISION_GAP {
						continue // Already inside this block
					}
					nearest = min(nearest, limit)
				} else {
					limit := f32(cell[int(axis)] + 1) - box.min[int(axis)]
					if limit > COLLISION_GAP {
						continue // Already inside this block
					}
					nearest = max(nearest, limit)
				}
				blocked = true
			}
		}
	}

	if blocked {
		if d > 0 {
			moved = clamp(nearest - COLLISION_GAP, 0, d)
		} else {
			moved = clamp(nearest + COLLISION_GAP, d, 0)
		}
	}

	return
}
