package mou

import "core:math"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:thread"
import "noise"

World :: struct {
	chunks:          map[glm.ivec3]Chunk,
	remesh_queue:    [dynamic]glm.ivec3,
	meshgen_thread:  ^thread.Thread,
	meshgen_sema:    sync.Sema,
	lock:            sync.RW_Mutex,
	atlas:           ^Atlas,
	allocator:       mem.Allocator,
}

init_world :: proc(world: ^World, atlas: ^Atlas, allocator := context.allocator) {
	context.allocator = allocator
	world.allocator = allocator
	world.chunks = make(map[glm.ivec3]Chunk)
	world.atlas = atlas
	world.meshgen_thread = thread.create_and_start_with_data(world, _meshgen_thread_proc)
}

_meshgen_thread_proc :: proc(ptr: rawptr) {
	world := cast(^World)ptr

	for {
		sync.wait(&world.meshgen_sema)
		if sync.guard(&world.lock) {
			chunk_pos, ok := pop_front_safe(&world.remesh_queue)
			if !ok {break} 	// HACK: for stopping thread

			// Should:tm: never happen, but you never know
			chunk, exists := &world.chunks[chunk_pos]
			assert(exists, "Chunk sent for meshing doesn't exist")
			mesh_chunk(world, chunk)
		}
	}
}

destroy_world :: proc(world: ^World) {
	context.allocator = world.allocator

	if sync.guard(&world.lock) {
		clear(&world.remesh_queue)
		sync.post(&world.meshgen_sema)
	}
	thread.destroy(world.meshgen_thread)

	for _, &chunk in world.chunks {
		destroy_chunk(&chunk)
	}
	delete(world.chunks)
	delete(world.remesh_queue)

	world^ = {}
}

// Generates a chunk if it is not already generated.
//
// Returns true if a chunk was generated, false if it was already generated.
// 
// NOTE: caller needs to have the lock on the world
world_generate_chunk :: proc(world: ^World, chunk_pos: glm.ivec3) -> bool {
	context.allocator = world.allocator

	if _, found := world.chunks[chunk_pos]; found {
		return false
	}

	world.chunks[chunk_pos] = generate_chunk(chunk_pos)
	chunk := &world.chunks[chunk_pos]

	chunk_noise: [CHUNK_WIDTH * CHUNK_DEPTH]i32

	for z in i32(0) ..< CHUNK_DEPTH {
		for x in i32(0) ..< CHUNK_WIDTH {
			OCTAVES :: 4
			PERSISTENCE :: 0.5

			xf := f32(chunk_pos.x * CHUNK_WIDTH + x)
			zf := f32(chunk_pos.z * CHUNK_DEPTH + z)

			frequency := f32(1) / f32(64)
			amplitude := f32(1)
			amplitude_total: f32
			n: f32
			#unroll for _ in 0 ..< OCTAVES {
				n += noise.perlin2d(xf * frequency, zf * frequency) * amplitude
				amplitude_total += amplitude
				amplitude *= PERSISTENCE
				frequency *= 2
			}
			n /= amplitude_total
			n *= 0.5
			n += 0.5
			n *= CHUNK_HEIGHT * 2

			height := cast(i32)math.round(n)
			chunk_noise[z * CHUNK_DEPTH + x] = height
		}
	}

	for y in i32(0) ..< CHUNK_HEIGHT {
		for z in i32(0) ..< CHUNK_DEPTH {
			for x in i32(0) ..< CHUNK_WIDTH {
				height := chunk_noise[z * CHUNK_DEPTH + x]

				cy := y + chunk_pos.y * CHUNK_HEIGHT
				switch {
				case cy == height:
					chunk.blocks[local_coords_to_block_index(x, y, z)] = Block{.Grass}
				case cy + 3 < height:
					chunk.blocks[local_coords_to_block_index(x, y, z)] = Block{.Stone}
				case cy < height:
					chunk.blocks[local_coords_to_block_index(x, y, z)] = Block{.Dirt}
				case:
				// Air
				}
			}
		}
	}

	world_mark_chunk_remesh(world, chunk)
	world_remesh_surrounding_chunks(world, chunk_pos)

	return true
}

// NOTE: caller needs to have the lock on the world
world_fill_chunk :: proc(world: ^World, chunk_pos: glm.ivec3, block: Block) {
	context.allocator = world.allocator

	chunk: ^Chunk
	found: bool
	if chunk, found = &world.chunks[chunk_pos]; !found {
		world.chunks[chunk_pos] = generate_chunk(chunk_pos)
		chunk = &world.chunks[chunk_pos]
	}
	slice.fill(chunk.blocks, block)

	world_remesh_surrounding_chunks(world, chunk_pos)
}

world_remesh_surrounding_chunks :: proc(world: ^World, chunk_pos: glm.ivec3) {
	for z in i32(-1) ..= 1 {
		for y in i32(-1) ..= 1 {
			for x in i32(-1) ..= 1 {
				if chunk, ok := &world.chunks[chunk_pos + {x, y, z}]; ok {
					world_mark_chunk_remesh(world, chunk)
				}
			}
		}
	}
}

// Marks a chunk as in need of remeshing and signals to the meshgen thread to do so.
// 
// NOTE: caller needs to have the lock on the world
world_mark_chunk_remesh :: proc(world: ^World, chunk: ^Chunk) {
	sync.atomic_store(&chunk.needs_remeshing, true)
	// FIXME: Don't append chunks already marked for remesh
	append(&world.remesh_queue, chunk.pos)
	sync.post(&world.meshgen_sema)
}

global_pos_to_chunk_pos :: proc(global_pos: glm.ivec3) -> glm.ivec3 {
	return {global_pos.x >> 4, global_pos.y >> 4, global_pos.z >> 4}
}

global_pos_to_local_pos :: proc(global_pos: glm.ivec3) -> glm.ivec3 {
	return global_pos - global_pos_to_chunk_pos(global_pos) * 16
}

get_world_chunk :: proc(world: World, chunk_pos: glm.ivec3) -> (c: Chunk, ok: bool) {
	return world.chunks[chunk_pos]
}

get_world_block :: proc(world: World, global_pos: glm.ivec3) -> (b: Block, ok: bool) {
	chunk_pos := global_pos_to_chunk_pos(global_pos)
	local_pos := global_pos - chunk_pos * CHUNK_MULTIPLIER
	chunk := get_world_chunk(world, chunk_pos) or_return
	return get_chunk_block(chunk, local_pos)
}
