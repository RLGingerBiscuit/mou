package mou

import "core:log"
_ :: log

import "core:math"
import glm "core:math/linalg/glsl"
import vmem "core:mem/virtual"
import "core:slice"
import "core:sync"
import "core:sync/chan"
import "noise"

World :: struct {
	chunks:         map[glm.ivec3]Chunk,
	meshgen_thread: Meshgen_Thread,
	meshgen_tx:     chan.Chan(Meshgen_Msg, chan.Direction.Send),
	lock:           sync.RW_Mutex,
	atlas:          ^Atlas, // FIXME: This doesn't belong here
	arena:          vmem.Arena,
}

init_world :: proc(world: ^World, atlas: ^Atlas) {
	world.atlas = atlas
	world.meshgen_tx = init_meshgen_thread(&world.meshgen_thread, world)

	ensure(vmem.arena_init_growing(&world.arena) == nil)

	context.allocator = vmem.arena_allocator(&world.arena)
	world.chunks = make(map[glm.ivec3]Chunk)
}

destroy_world :: proc(world: ^World) {
	destroy_meshgen_thread(&world.meshgen_thread)

	// God I love arenas
	vmem.arena_destroy(&world.arena)

	world^ = {}
}

// Generates a chunk if it is not already generated.
//
// Returns true if a chunk was generated, false if it was already generated.
//
// NOTE: Caller needs to have the lock on the world.
//
// NOTE: Chunks need to manaully be sent for remesh if send_for_mesh is false.
world_generate_chunk :: proc(world: ^World, chunk_pos: glm.ivec3, send_for_mesh := true) -> bool {
	context.allocator = vmem.arena_allocator(&world.arena)

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

	if send_for_mesh {
		world_remesh_surrounding_chunks(world, chunk_pos)
	}

	return true
}

// NOTE: caller needs to have the lock on the world
world_fill_chunk :: proc(world: ^World, chunk_pos: glm.ivec3, block: Block) {
	context.allocator = vmem.arena_allocator(&world.arena)

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
world_mark_chunk_remesh :: proc(world: ^World, chunk: ^Chunk) {
	if queued := sync.atomic_compare_exchange_strong(&chunk.needs_remeshing, false, true);
	   !queued {
		chan.send(world.meshgen_tx, Meshgen_Msg_Remesh{chunk.pos})
	}
}

// Marks a chunk as in need of demeshing and signals to the meshgen thread to do so.
world_mark_chunk_demesh :: proc(world: ^World, chunk: ^Chunk) {
	sync.atomic_store(&chunk.needs_remeshing, false)
	chan.send(world.meshgen_tx, Meshgen_Msg_Demesh{chunk.pos})
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
