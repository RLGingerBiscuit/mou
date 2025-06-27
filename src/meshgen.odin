package mou

import "core:log"
import glm "core:math/linalg/glsl"
import "core:mem"
import vmem "core:mem/virtual"
import "core:sync/chan"
import "core:thread"

MESHGEN_CHAN_CAP :: 16

Meshgen_Msg_Remesh :: struct {
	pos: glm.ivec3,
}
Meshgen_Msg_Demesh :: struct {
	pos: glm.ivec3,
}
Meshgen_Msg_Tombstone :: struct {
	mesh: ^Chunk_Mesh,
}
Meshgen_Msg_Terminate :: struct {}

Meshgen_Msg :: union {
	Meshgen_Msg_Remesh,
	Meshgen_Msg_Demesh,
	Meshgen_Msg_Tombstone,
	Meshgen_Msg_Terminate,
}

Meshgen_Thread :: struct {
	world:       ^World,
	th:          ^thread.Thread,
	rx:          chan.Chan(Meshgen_Msg, chan.Direction.Recv),
	world_tx:    chan.Chan(World_Msg, chan.Direction.Send),
	_mg_chan:    chan.Chan(Meshgen_Msg),
	_world_chan: chan.Chan(World_Msg),
	tombstones:  [dynamic]^Chunk_Mesh,
	arena:       vmem.Arena,
}

// Initialises the mesh generation thread.
//
// Returns the tx end of the meshgen channel, and rx end of the world channel.
init_meshgen_thread :: proc(
	mg: ^Meshgen_Thread,
	world: ^World,
	allocator := context.allocator,
) -> (
	chan.Chan(Meshgen_Msg, chan.Direction.Send),
	chan.Chan(World_Msg, chan.Direction.Recv),
) {
	chan_err: mem.Allocator_Error
	mg._mg_chan, chan_err = chan.create(type_of(mg._mg_chan), 16, allocator)
	rx := chan.as_recv(mg._mg_chan)
	tx := chan.as_send(mg._mg_chan)

	mg._world_chan, chan_err = chan.create(type_of(mg._world_chan), 16, allocator)
	ensure(chan_err == nil)
	world_rx := chan.as_recv(mg._world_chan)
	world_tx := chan.as_send(mg._world_chan)

	mg.rx = rx
	mg.world_tx = world_tx
	mg.th = thread.create_and_start_with_poly_data(mg, _meshgen_thread_proc)
	ensure(mg.th != nil)
	mg.world = world

	ensure(vmem.arena_init_growing(&mg.arena) == nil)

	return tx, world_rx
}

destroy_meshgen_thread :: proc(mg: ^Meshgen_Thread) {
	chan.close(mg._mg_chan)
	chan.close(mg._world_chan)

	thread.destroy(mg.th)

	chan.destroy(mg._mg_chan)
	chan.destroy(mg._world_chan)

	vmem.arena_destroy(&mg.arena)

	mg^ = {}
}

_meshgen_thread_proc :: proc(mg: ^Meshgen_Thread) {
	// Arena here means (1) stable pointers and (2) easy clean up
	context.allocator = vmem.arena_allocator(&mg.arena)

	context.logger = log.create_console_logger(
		MIN_LOG_LEVEL,
		ident = "logl-meshgen",
		opt = log.Default_Console_Logger_Opts ~ {.Terminal_Color},
	)

	world := mg.world

	for {
		msg, recieved := chan.recv(mg.rx)
		if !recieved {
			break
		}

		switch v in msg {
		case Meshgen_Msg_Remesh:
			// Make a new mesh here to avoid flashes as meshes are updated
			mesh := len(mg.tombstones) > 0 ? pop(&mg.tombstones) : new_chunk_mesh(mg, world)
			assert(mesh != nil)

			chunk, exists := &world.chunks[v.pos]
			ensure(exists, "Chunk sent for meshing doesn't exist")
			mesh_chunk(world, chunk, mesh)

			chan.send(mg.world_tx, World_Msg_Meshed{v.pos, mesh})

		case Meshgen_Msg_Demesh:
			chunk, exists := &world.chunks[v.pos]
			ensure(exists, "Chunk sent for demeshing doesn't exist")
			if chunk.mesh == nil {
				continue
			}
			chan.send(mg.world_tx, World_Msg_Demeshed{v.pos})

		case Meshgen_Msg_Tombstone:
			append(&mg.tombstones, v.mesh)

		case Meshgen_Msg_Terminate:
			return
		}
	}
}

new_chunk_mesh :: proc(mg: ^Meshgen_Thread, world: ^World) -> ^Chunk_Mesh {
	mesh, _ := new(Chunk_Mesh)

	// From some *very* basic tests these numbers seem to be alright for now
	mesh.opaque = make([dynamic]f32, 0, (CHUNK_SIZE / 2 * VERTEX_COUNT) / 4)
	mesh.transparent = make([dynamic]f32)

	return mesh
}

mesh_chunk :: proc(world: ^World, chunk: ^Chunk, mesh: ^Chunk_Mesh) {
	if !chunk_needs_remeshing(chunk) {
		return
	}

	clear(&mesh.opaque)
	clear(&mesh.transparent)

	for y in i32(0) ..< CHUNK_HEIGHT {
		for z in i32(0) ..< CHUNK_DEPTH {
			for x in i32(0) ..< CHUNK_WIDTH {
				block := chunk.blocks[local_coords_to_block_index(x, y, z)]
				if block.id == .Air {
					continue
				}

				bnx, bnxok := get_world_block(world^, chunk.pos * CHUNK_MULTIPLIER + {x - 1, y, z})
				bpx, bpxok := get_world_block(world^, chunk.pos * CHUNK_MULTIPLIER + {x + 1, y, z})
				bny, bnyok := get_world_block(world^, chunk.pos * CHUNK_MULTIPLIER + {x, y - 1, z})
				bpy, bpyok := get_world_block(world^, chunk.pos * CHUNK_MULTIPLIER + {x, y + 1, z})
				bnz, bnzok := get_world_block(world^, chunk.pos * CHUNK_MULTIPLIER + {x, y, z - 1})
				bpz, bpzok := get_world_block(world^, chunk.pos * CHUNK_MULTIPLIER + {x, y, z + 1})

				// Which directions SHOULD faces be placed
				mask: Block_Face_Mask

				mask |=
					bnxok && bnx.id != .Air && (block_is_opaque(bnx) || (bnx.id == block.id && block_culls_self(bnx))) ? {} : {.Neg_X}
				mask |=
					bpxok && bpx.id != .Air && (block_is_opaque(bpx) || (bpx.id == block.id && block_culls_self(bpx))) ? {} : {.Pos_X}
				mask |=
					bnyok && bny.id != .Air && (block_is_opaque(bny) || (bny.id == block.id && block_culls_self(bny))) ? {} : {.Neg_Y}
				mask |=
					bpyok && bpy.id != .Air && (block_is_opaque(bpy) || (bpy.id == block.id && block_culls_self(bpy))) ? {} : {.Pos_Y}
				mask |=
					bnzok && bnz.id != .Air && (block_is_opaque(bnz) || (bnz.id == block.id && block_culls_self(bnz))) ? {} : {.Neg_Z}
				mask |=
					bpzok && bpz.id != .Air && (block_is_opaque(bpz) || (bpz.id == block.id && block_culls_self(bpz))) ? {} : {.Pos_Z}

				if mask == {} {
					continue
				}

				mesh := block_is_opaque(block) ? &mesh.opaque : &mesh.transparent

				block_pos := glm.ivec3{x, y, z}

				if .Neg_X in mask {
					face := position_face(.Neg_X, block_pos, chunk.pos, block, world.atlas)
					append(mesh, ..face[:])
				}
				if .Pos_X in mask {
					face := position_face(.Pos_X, block_pos, chunk.pos, block, world.atlas)
					append(mesh, ..face[:])
				}
				if .Neg_Y in mask {
					face := position_face(.Neg_Y, block_pos, chunk.pos, block, world.atlas)
					append(mesh, ..face[:])
				}
				if .Pos_Y in mask {
					face := position_face(.Pos_Y, block_pos, chunk.pos, block, world.atlas)
					append(mesh, ..face[:])
				}
				if .Neg_Z in mask {
					face := position_face(.Neg_Z, block_pos, chunk.pos, block, world.atlas)
					append(mesh, ..face[:])
				}
				if .Pos_Z in mask {
					face := position_face(.Pos_Z, block_pos, chunk.pos, block, world.atlas)
					append(mesh, ..face[:])
				}
			}
		}
	}
}

@(private = "file")
position_face :: #force_inline proc(
	$face: Block_Face_Bit,
	block_pos: glm.ivec3,
	chunk_pos: glm.ivec3,
	block: Block,
	atlas: ^Atlas,
) -> [VERTEX_INPUT_COUNT]f32 {
	face_data := FACE_PLANES[face]

	x := f32(chunk_pos.x * CHUNK_WIDTH + block_pos.x)
	y := f32(chunk_pos.y * CHUNK_HEIGHT + block_pos.y)
	z := f32(chunk_pos.z * CHUNK_DEPTH + block_pos.z)

	face_data[0] += x
	face_data[5] += x
	face_data[10] += x
	face_data[15] += x
	face_data[20] += x
	face_data[25] += x

	face_data[1] += y
	face_data[6] += y
	face_data[11] += y
	face_data[16] += y
	face_data[21] += y
	face_data[26] += y

	face_data[2] += z
	face_data[7] += z
	face_data[12] += z
	face_data[17] += z
	face_data[22] += z
	face_data[27] += z

	// Setting UVs
	uvs := atlas.uvs[block_asset_name(block, face)]
	// tr
	face_data[3] = uvs[1].x
	face_data[4] = uvs[0].y

	// tl
	face_data[8] = uvs[0].x
	face_data[9] = uvs[0].y

	// bl
	face_data[13] = uvs[1].x
	face_data[14] = uvs[1].y

	// bl
	face_data[18] = uvs[0].x
	face_data[19] = uvs[1].y

	// br
	face_data[23] = uvs[1].x
	face_data[24] = uvs[1].y

	// tr
	face_data[28] = uvs[0].x
	face_data[29] = uvs[0].y

	return face_data
}

// odinfmt:disable
@(private = "file")
VERTEX_COUNT :: 6
@(private = "file")
COORD_COUNT :: VERTEX_COUNT * 3
@(private = "file")
TEX_COORD_COUNT :: VERTEX_COUNT * 2
@(private = "file")
VERTEX_INPUT_COUNT :: COORD_COUNT+TEX_COORD_COUNT
@(private = "file")
FACE_PLANES :: [Block_Face_Bit][VERTEX_INPUT_COUNT]f32{
	.Neg_X={// Left
	-0.5,  0.5, -0.5,  1, 0,
	-0.5,  0.5,  0.5,  0, 0,
	-0.5, -0.5, -0.5,  1, 1,
	-0.5, -0.5,  0.5,  0, 1,
	-0.5, -0.5, -0.5,  1, 1,
	-0.5,  0.5,  0.5,  0, 0,},
	.Pos_X={// Right
	 0.5,  0.5,  0.5,  1, 0,
	 0.5,  0.5, -0.5,  0, 0,
	 0.5, -0.5,  0.5,  1, 1,
	 0.5, -0.5, -0.5,  0, 1,
	 0.5, -0.5,  0.5,  1, 1,
	 0.5,  0.5, -0.5,  0, 0,},
	.Neg_Y={// Bottom
	 0.5, -0.5, -0.5,  1, 0,
	-0.5, -0.5, -0.5,  0, 0,
	 0.5, -0.5,  0.5,  1, 1,
	-0.5, -0.5,  0.5,  0, 1,
	 0.5, -0.5,  0.5,  1, 1,
	-0.5, -0.5, -0.5,  0, 0,},
	.Pos_Y={// Top
	 0.5,  0.5,  0.5,  1, 0,
	-0.5,  0.5,  0.5,  0, 0,
	 0.5,  0.5, -0.5,  1, 1,
	-0.5,  0.5, -0.5,  0, 1,
	 0.5,  0.5, -0.5,  1, 1,
	-0.5,  0.5,  0.5,  0, 0,},
	.Neg_Z={// Front
	 0.5,  0.5, -0.5,  1, 0,
	-0.5,  0.5, -0.5,  0, 0,
	 0.5, -0.5, -0.5,  1, 1,
	-0.5, -0.5, -0.5,  0, 1,
	 0.5, -0.5, -0.5,  1, 1,
	-0.5,  0.5, -0.5,  0, 0,},
	.Pos_Z={// Back
	-0.5,  0.5,  0.5,  1, 0,
	 0.5,  0.5,  0.5,  0, 0,
	-0.5, -0.5,  0.5,  1, 1,
	 0.5, -0.5,  0.5,  0, 1,
	-0.5, -0.5,  0.5,  1, 1,
	 0.5,  0.5,  0.5,  0, 0,},
}
// odinfmt:enable
