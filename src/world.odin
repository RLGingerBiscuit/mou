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
import "prof"

World_Pos :: glm.vec3 // Player pos in world
Block_Pos :: glm.ivec3 // Block pos in world
Chunk_Pos :: glm.ivec3 // Chunk in world
Local_Pos :: glm.ivec3 // Block pos in chunk

WATER_LEVEL :: 12

World_Msg_Meshed :: struct {
	chunk_pos: Chunk_Pos,
	mesh:      ^Chunk_Mesh,
}

World_Msg_Demeshed :: struct {
	chunk_pos: Chunk_Pos,
}

World_Msg :: union {
	World_Msg_Meshed,
	World_Msg_Demeshed,
}

World :: struct {
	chunks:          map[Chunk_Pos]Chunk,
	meshgen_thread:  Meshgen_Thread,
	meshgen_tx:      chan.Chan(Meshgen_Msg, chan.Direction.Send),
	rx:              chan.Chan(World_Msg, chan.Direction.Recv),
	lock:            sync.RW_Mutex,
	atlas:           ^Atlas, // FIXME: This doesn't belong here
	chunk_msg_stack: [dynamic]Meshgen_Msg,
	arena:           vmem.Arena,
}

init_world :: proc(world: ^World, atlas: ^Atlas) {
	world.atlas = atlas
	world.meshgen_tx, world.rx = init_meshgen_thread(&world.meshgen_thread, world)

	ensure(vmem.arena_init_growing(&world.arena) == nil)

	context.allocator = vmem.arena_allocator(&world.arena)
	world.chunks = make(map[Chunk_Pos]Chunk)
	world.chunk_msg_stack = make(
		[dynamic]Meshgen_Msg,
		0,
		MAX_RENDER_DISTANCE * MAX_RENDER_DISTANCE,
	)
}

destroy_world :: proc(world: ^World) {
	destroy_meshgen_thread(&world.meshgen_thread)

	// God I love arenas
	vmem.arena_destroy(&world.arena)

	world^ = {}
}

world_update :: proc(world: ^World, player_pos: glm.vec3) {
	if prof.event("world sort messages") {
		player_pos := player_pos
		context.user_ptr = &player_pos
		slice.sort_by(
			world.chunk_msg_stack[:],
			proc(i, j: Meshgen_Msg) -> bool {
				player_pos := cast(^glm.vec3)context.user_ptr
				i_dist, j_dist: f32
				j_pos: Chunk_Pos

				switch vi in i {
				// Give terminate/tombstone priority (send to top of stack)
				case Meshgen_Msg_Terminate, Meshgen_Msg_Tombstone:
					return false

				case Meshgen_Msg_Remesh:
					i_dist = glm.length(player_pos^ - chunk_pos_centre(vi.pos))
								// odinfmt:disable
				switch vj in j {
				case Meshgen_Msg_Terminate, Meshgen_Msg_Tombstone: return true
				case Meshgen_Msg_Remesh:                           j_pos = vj.pos
				case Meshgen_Msg_Demesh:                           j_pos = vj.pos
				}
				// odinfmt:enable
					j_dist = glm.length(player_pos^ - chunk_pos_centre(j_pos))
					return i_dist > j_dist

				case Meshgen_Msg_Demesh:
					i_dist = glm.length(player_pos^ - chunk_pos_centre(vi.pos))
								// odinfmt:disable
				switch vj in j {
				case Meshgen_Msg_Terminate, Meshgen_Msg_Tombstone: return true
				case Meshgen_Msg_Remesh:                           j_pos = vj.pos
				case Meshgen_Msg_Demesh:                           j_pos = vj.pos
				}
				// odinfmt:enable
					j_dist = glm.length(player_pos^ - chunk_pos_centre(j_pos))
					return i_dist > j_dist
				}
				unreachable()
			},
		)
	}

	if prof.event("world send events") {
		for msg in pop_safe(&world.chunk_msg_stack) {
			if !chan.try_send(world.meshgen_tx, msg) {
				append(&world.chunk_msg_stack, msg)
				break
			}
		}
	}

	if prof.event("world recieve events") {
		for msg in chan.try_recv(world.rx) {
			switch v in msg {
			case World_Msg_Meshed:
				sync.guard(&world.lock)
				chunk, exists := &world.chunks[v.chunk_pos]
				ensure(exists, "Meshed chunk doesn't exist")
				old_mesh := chunk.mesh
				chunk.mesh = v.mesh
				if old_mesh != nil {
					append(&world.chunk_msg_stack, Meshgen_Msg_Tombstone{old_mesh})
				}
				sync.atomic_store(&chunk.mark_remesh, false)

			case World_Msg_Demeshed:
				sync.guard(&world.lock)
				chunk, exists := &world.chunks[v.chunk_pos]
				ensure(exists, "Demeshed chunk doesn't exist")
				old_mesh := chunk.mesh
				if old_mesh != nil {
					append(&world.chunk_msg_stack, Meshgen_Msg_Tombstone{old_mesh})
				}
				chunk.mesh = nil
				sync.atomic_store(&chunk.mark_remesh, false)
			}
		}
	}
}

// Generates a chunk if it is not already generated.
//
// Returns true if a chunk was generated, false if it was already generated.
//
// NOTE: Caller needs to have the lock on the world.
world_generate_chunk :: proc(world: ^World, chunk_pos: Chunk_Pos) -> bool {
	context.allocator = vmem.arena_allocator(&world.arena)

	if _, found := world.chunks[chunk_pos]; found {
		return false
	}

	world.chunks[chunk_pos] = make_chunk(chunk_pos)
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
				case cy < height - 3:
					chunk.blocks[local_coords_to_block_index(x, y, z)] = Block{.Stone}
				case cy < height:
					chunk.blocks[local_coords_to_block_index(x, y, z)] = Block{.Dirt}
				case cy <= WATER_LEVEL:
					chunk.blocks[local_coords_to_block_index(x, y, z)] = Block{.Water}
				case:
				// Air
				}
			}
		}
	}

	world_remesh_surrounding_chunks(world, chunk_pos)

	return true
}

// NOTE: caller needs to have the lock on the world
world_fill_chunk :: proc(world: ^World, chunk_pos: Chunk_Pos, block: Block) {
	context.allocator = vmem.arena_allocator(&world.arena)

	chunk: ^Chunk
	found: bool
	if chunk, found = &world.chunks[chunk_pos]; !found {
		world.chunks[chunk_pos] = make_chunk(chunk_pos)
		chunk = &world.chunks[chunk_pos]
	}
	slice.fill(chunk.blocks, block)

	world_remesh_surrounding_chunks(world, chunk_pos)
}

world_remesh_surrounding_chunks :: proc(world: ^World, chunk_pos: Chunk_Pos) {
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

// Marks a chunk as in need of remeshing and adds it to the queue for dispatching to the meshgen thread.
world_mark_chunk_remesh :: proc(world: ^World, chunk: ^Chunk) {
	if queued := sync.atomic_compare_exchange_strong(&chunk.mark_remesh, false, true); !queued {
		sync.atomic_store(&chunk.mark_remesh, true)
		sync.atomic_store(&chunk.mark_demesh, false)
		append(&world.chunk_msg_stack, Meshgen_Msg_Remesh{chunk.pos})
	}
}

// Marks a chunk as in need of demeshing and adds it to the queue for dispatching to the meshgen thread.
world_mark_chunk_demesh :: proc(world: ^World, chunk: ^Chunk) {
	if queued := sync.atomic_compare_exchange_strong(&chunk.mark_demesh, false, true); !queued {
		sync.atomic_store(&chunk.mark_remesh, false)
		sync.atomic_store(&chunk.mark_demesh, true)
		append(&world.chunk_msg_stack, Meshgen_Msg_Demesh{chunk.pos})
	}
}

world_pos_to_chunk_pos :: proc(world_pos: World_Pos) -> Chunk_Pos {
	return {i32(world_pos.x) >> 4, i32(world_pos.y) >> 4, i32(world_pos.z) >> 4}
}

block_pos_to_world_pos :: proc(block_pos: Block_Pos) -> World_Pos {
	return {f32(block_pos.x), f32(block_pos.y), f32(block_pos.z)}
}

block_pos_to_chunk_pos :: proc(block_pos: Block_Pos) -> Chunk_Pos {
	return {block_pos.x >> 4, block_pos.y >> 4, block_pos.z >> 4}
}

block_pos_to_local_pos :: proc(block_pos: Block_Pos) -> Local_Pos {
	return block_pos - block_pos_to_chunk_pos(block_pos) * CHUNK_SIZE
}

get_world_chunk :: proc(world: World, chunk_pos: Chunk_Pos) -> (c: ^Chunk, ok: bool) {
	return &world.chunks[chunk_pos]
}

get_world_block :: proc(world: World, block_pos: Block_Pos) -> (b: Block, ok: bool) {
	chunk_pos := block_pos_to_chunk_pos(block_pos)
	local_pos := block_pos_to_local_pos(block_pos)
	chunk := get_world_chunk(world, chunk_pos) or_return
	return get_chunk_block(chunk^, local_pos)
}
