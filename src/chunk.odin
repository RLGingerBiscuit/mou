package mou

import glm "core:math/linalg/glsl"
import "core:sync"

CHUNK_WIDTH :: 16
CHUNK_HEIGHT :: 16
CHUNK_DEPTH :: 16
CHUNK_SIZE :: CHUNK_WIDTH * CHUNK_HEIGHT * CHUNK_DEPTH
CHUNK_MULTIPLIER :: glm.ivec3{CHUNK_WIDTH, CHUNK_HEIGHT, CHUNK_DEPTH}

Chunk :: struct {
	pos:             glm.ivec3,
	blocks:          []Block `fmt:"-"`,
	mesh:            ^Chunk_Mesh,
	needs_remeshing: bool,
}

make_chunk :: proc(pos: glm.ivec3, allocator := context.allocator) -> Chunk {
	context.allocator = allocator
	chunk: Chunk
	chunk.pos = pos
	chunk.blocks = make([]Block, CHUNK_SIZE)

	return chunk
}

destroy_chunk :: proc(chunk: ^Chunk, allocator := context.allocator) {
	context.allocator = allocator
	delete(chunk.blocks)
	chunk^ = {}
}

chunk_needs_remeshing :: proc(chunk: ^Chunk) -> bool {
	return sync.atomic_load(&chunk.needs_remeshing)
}

get_chunk_block :: proc(chunk: Chunk, local_pos: glm.ivec3) -> (Block, bool) {
	x := local_pos.x
	y := local_pos.y
	z := local_pos.z
	if x < 0 || y < 0 || z < 0 || x >= CHUNK_WIDTH || y >= CHUNK_HEIGHT || z >= CHUNK_DEPTH {
		return {}, false
	}
	index := local_coords_to_block_index(x, y, z)
	return chunk.blocks[index], true
}

get_chunk_layer :: proc(chunk: ^Chunk, y: i32) -> []Block {
	start := local_coords_to_block_index(0, y, 0)
	end := local_coords_to_block_index(15, y, 15) + 1
	return chunk.blocks[start:end]
}

get_chunk_layers :: proc(chunk: ^Chunk, start_y, end_y: i32) -> []Block {
	start := local_coords_to_block_index(0, start_y, 0)
	end := local_coords_to_block_index(15, end_y, 15) + 1
	return chunk.blocks[start:end]
}

get_chunk_centre :: proc(chunk: ^Chunk) -> glm.vec3 {
	return chunk_pos_to_global_pos(chunk.pos) + ({CHUNK_WIDTH, CHUNK_HEIGHT, CHUNK_DEPTH} / 2)
}

chunk_pos_to_global_pos :: proc(chunk_pos: glm.ivec3) -> glm.vec3 {
	return {f32(chunk_pos.x << 4), f32(chunk_pos.y << 4), f32(chunk_pos.z << 4)}
}

local_coords_to_block_index :: proc(x, y, z: i32) -> i32 {
	return (y * CHUNK_DEPTH * CHUNK_WIDTH) + (z * CHUNK_WIDTH) + x
}
