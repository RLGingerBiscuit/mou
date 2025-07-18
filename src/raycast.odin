package mou

import "core:log"
import "core:math"
import glm "core:math/linalg/glsl"

_ :: log

cast_ray_to_block :: proc(
	world: World,
	origin: World_Pos,
	direction: glm.vec3,
	dist: int,
) -> (
	block_pos: Block_Pos,
	hit: bool,
) {
	// Based on:
	// "A Fast Voxel Traversal Algorithm for Ray Tracing"
	// John Amanatides, Andrew Woo
	// http://www.cse.yorku.ca/~amana/research/grid.pdf
	// http://www.devmaster.net/articles/raytracing_series/A%20faster%20voxel%20traversal%20algorithm%20for%20ray%20tracing.pdf
	// https://web.archive.org/web/20121024081332/www.xnawiki.com/index.php?title=Voxel_traversal

	direction := direction
	direction = glm.normalize(direction)

	start := world_pos_to_block_pos(origin)
	pos := start

	step := glm.sign(direction)
	boundary := glm.floor(origin) + {
				step.x > 0 ? 1 : 0,
				step.y > 0 ? 1 : 0,
				step.z > 0 ? 1 : 0, //
			}

	t_max := (boundary - origin) / direction
	if math.is_nan(t_max.x) {t_max.x = math.inf_f32(1)}
	if math.is_nan(t_max.y) {t_max.y = math.inf_f32(1)}
	if math.is_nan(t_max.z) {t_max.z = math.inf_f32(1)}

	t_delta := step / direction
	if math.is_nan(t_delta.x) {t_delta.x = math.inf_f32(1)}
	if math.is_nan(t_delta.y) {t_delta.y = math.inf_f32(1)}
	if math.is_nan(t_delta.z) {t_delta.z = math.inf_f32(1)}

	for {
		if glm.length(block_pos_to_world_pos(pos) - origin) > f32(dist) {
			break
		}

		block, block_ok := get_world_block(world, pos)
		if block_ok && block.id != .Air {
			return pos, true
		}

		if t_max.x < t_max.y && t_max.x < t_max.z {
			pos.x += i32(step.x)
			t_max.x += t_delta.x
		} else if t_max.y < t_max.z {
			pos.y += i32(step.y)
			t_max.y += t_delta.y
		} else {
			pos.z += i32(step.z)
			t_max.z += t_delta.z
		}
	}

	return {}, false
}
