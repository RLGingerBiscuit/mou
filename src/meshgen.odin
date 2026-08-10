package mou

import "core:log"
import glm "core:math/linalg/glsl"
import "core:mem"
import vmem "core:mem/virtual"
import "core:sync"
import "core:sync/chan"
import "core:thread"

import "prof"

MESHGEN_CHAN_CAP :: 32

MESHGEN_CHUNK_SIZE :: CHUNK_SIZE + 2
Meshgen_Chunk :: [MESHGEN_CHUNK_SIZE * MESHGEN_CHUNK_SIZE * MESHGEN_CHUNK_SIZE]Block

Generated_Chunk_Mesh :: struct {
	opaque_verts:      [dynamic]Mesh_Face `fmt:"-"`,
	transparent_verts: [dynamic]Mesh_Face `fmt:"-"`,
	water_verts:       [dynamic]Mesh_Face `fmt:"-"`,
	gen_time:          f32,
}

Meshgen_Msg_Remesh :: struct {
	pos: Chunk_Pos,
}
Meshgen_Msg_Demesh :: struct {
	pos: Chunk_Pos,
}
Meshgen_Msg_Tombstone :: struct {
	mesh: ^Generated_Chunk_Mesh,
}

Meshgen_Msg :: union {
	Meshgen_Msg_Remesh,
	Meshgen_Msg_Demesh,
	Meshgen_Msg_Tombstone,
}

Meshgen_Thread :: struct {
	world:       ^World,
	th:          ^thread.Thread,
	rx:          chan.Chan(Meshgen_Msg, chan.Direction.Recv),
	world_tx:    chan.Chan(World_Msg, chan.Direction.Send),
	_mg_chan:    chan.Chan(Meshgen_Msg),
	_world_chan: chan.Chan(World_Msg),
	tombstones:  [dynamic]^Generated_Chunk_Mesh,
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
	mg._mg_chan, chan_err = chan.create(type_of(mg._mg_chan), MESHGEN_CHAN_CAP, allocator)
	ensure(chan_err == nil)
	rx := chan.as_recv(mg._mg_chan)
	tx := chan.as_send(mg._mg_chan)

	mg._world_chan, chan_err = chan.create(type_of(mg._world_chan), MESHGEN_CHAN_CAP, allocator)
	ensure(chan_err == nil)
	world_rx := chan.as_recv(mg._world_chan)
	world_tx := chan.as_send(mg._world_chan)

	ensure(vmem.arena_init_growing(&mg.arena) == nil)

	mg.rx = rx
	mg.world_tx = world_tx
	mg.world = world
	mg.th = thread.create_and_start_with_poly_data(mg, _meshgen_thread_proc)
	ensure(mg.th != nil)

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

	prof.init_thread("Meshgen-Thread")

	context.logger = log.create_console_logger(
		LOG_LEVEL,
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
			should_mesh := false
			mg_chunk: Meshgen_Chunk
			{
				sync.shared_guard(&world.lock)
				chunk, exists := &world.chunks[v.pos]
				ensure(exists, "Chunk sent for meshing doesn't exist")
				should_mesh = chunk_marked_remesh(chunk) && !chunk_marked_demesh(chunk)
				if should_mesh {
					sync.atomic_store(&chunk.mark_remesh, false)
					chunk_block_pos := chunk_pos_to_block_pos(chunk.pos)
					for py in i32(-1) ..< MESHGEN_CHUNK_SIZE - 1 {
						for pz in i32(-1) ..< MESHGEN_CHUNK_SIZE - 1 {
							for px in i32(-1) ..< MESHGEN_CHUNK_SIZE - 1 {
								block_pos := Block_Pos{px, py, pz}
								world_pos := chunk_block_pos + block_pos
								if b, ok := get_world_block(world^, world_pos); ok {
									mg_chunk[meshgen_index(block_pos)] = b
								}
							}
						}
					}
				}
			}

			if !should_mesh {
				continue
			}

			// Make a new mesh here to avoid flashes as meshes are updated
			mesh := len(mg.tombstones) > 0 ? pop(&mg.tombstones) : new_chunk_mesh(mg, world)
			assert(mesh != nil)

			if prof.event("chunk mesh generation") {
				mesh_chunk(world, v.pos, &mg_chunk, mesh)
			}

			chan.send(mg.world_tx, World_Msg_Meshed{v.pos, mesh})

		case Meshgen_Msg_Demesh:
			chan.send(mg.world_tx, World_Msg_Demeshed{v.pos})

		case Meshgen_Msg_Tombstone:
			append(&mg.tombstones, v.mesh)
		}
	}
}

new_chunk_mesh :: proc(mg: ^Meshgen_Thread, world: ^World) -> ^Generated_Chunk_Mesh {
	mesh := new(Generated_Chunk_Mesh)

	mesh.opaque_verts = make([dynamic]Mesh_Face)
	mesh.transparent_verts = make([dynamic]Mesh_Face)
	mesh.water_verts = make([dynamic]Mesh_Face)

	return mesh
}

mesh_chunk :: proc(world: ^World, chunk_pos: Chunk_Pos, mg_chunk: ^Meshgen_Chunk, mesh: ^Generated_Chunk_Mesh) {
	clear(&mesh.opaque_verts)
	clear(&mesh.transparent_verts)
	clear(&mesh.water_verts)

	WATER_TOP_OFFSET :: (f32(1) / CHUNK_SIZE)


	for y in i32(0) ..< CHUNK_SIZE {
		for z in i32(0) ..< CHUNK_SIZE {
			for x in i32(0) ..< CHUNK_SIZE {
				block := meshgen_get(mg_chunk, {x, y, z})
				if block.id == .Air {
					continue
				}

				bnx := meshgen_get(mg_chunk, {x - 1, y, z})
				bpx := meshgen_get(mg_chunk, {x + 1, y, z})
				bny := meshgen_get(mg_chunk, {x, y - 1, z})
				bpy := meshgen_get(mg_chunk, {x, y + 1, z})
				bnz := meshgen_get(mg_chunk, {x, y, z - 1})
				bpz := meshgen_get(mg_chunk, {x, y, z + 1})


				mask: Block_Face_Mask
				mask |=
					bnx.id != .Air && (block_is_opaque(bnx) || (bnx.id == block.id && block_culls_self(bnx))) ? {} : {.Neg_X}
				mask |=
					bpx.id != .Air && (block_is_opaque(bpx) || (bpx.id == block.id && block_culls_self(bpx))) ? {} : {.Pos_X}
				mask |=
					bny.id != .Air && (block_is_opaque(bny) || (bny.id == block.id && block_culls_self(bny))) ? {} : {.Neg_Y}
				mask |=
					bpy.id != .Air && (block_is_opaque(bpy) || (bpy.id == block.id && block_culls_self(bpy))) ? {} : {.Pos_Y}
				mask |=
					bnz.id != .Air && (block_is_opaque(bnz) || (bnz.id == block.id && block_culls_self(bnz))) ? {} : {.Neg_Z}
				mask |=
					bpz.id != .Air && (block_is_opaque(bpz) || (bpz.id == block.id && block_culls_self(bpz))) ? {} : {.Pos_Z}

				if mask == {} {
					continue
				}

				// Which directions SHOULD faces be placed
				ao_mask: Block_Diag_Mask

				if block.id != .Water {
					bnnn := meshgen_get(mg_chunk, {x - 1, y - 1, z - 1})
					bnnz := meshgen_get(mg_chunk, {x - 1, y - 1, z + 0})
					bnnp := meshgen_get(mg_chunk, {x - 1, y - 1, z + 1})
					bnzn := meshgen_get(mg_chunk, {x - 1, y + 0, z - 1})
					bnzp := meshgen_get(mg_chunk, {x - 1, y + 0, z + 1})
					bnpn := meshgen_get(mg_chunk, {x - 1, y + 1, z - 1})
					bnpz := meshgen_get(mg_chunk, {x - 1, y + 1, z + 0})
					bnpp := meshgen_get(mg_chunk, {x - 1, y + 1, z + 1})
					bznn := meshgen_get(mg_chunk, {x + 0, y - 1, z - 1})
					bznp := meshgen_get(mg_chunk, {x + 0, y - 1, z + 1})
					bzpn := meshgen_get(mg_chunk, {x + 0, y + 1, z - 1})
					bzpp := meshgen_get(mg_chunk, {x + 0, y + 1, z + 1})
					bpnn := meshgen_get(mg_chunk, {x + 1, y - 1, z - 1})
					bpnz := meshgen_get(mg_chunk, {x + 1, y - 1, z + 0})
					bpnp := meshgen_get(mg_chunk, {x + 1, y - 1, z + 1})
					bpzn := meshgen_get(mg_chunk, {x + 1, y + 0, z - 1})
					bpzp := meshgen_get(mg_chunk, {x + 1, y + 0, z + 1})
					bppn := meshgen_get(mg_chunk, {x + 1, y + 1, z - 1})
					bppz := meshgen_get(mg_chunk, {x + 1, y + 1, z + 0})
					bppp := meshgen_get(mg_chunk, {x + 1, y + 1, z + 1})

					ao_mask |= bnnn.id != .Air && block_is_opaque(bnnn) ? {.NNN} : {}
					ao_mask |= bnnz.id != .Air && block_is_opaque(bnnz) ? {.NNZ} : {}
					ao_mask |= bnnp.id != .Air && block_is_opaque(bnnp) ? {.NNP} : {}
					ao_mask |= bnzn.id != .Air && block_is_opaque(bnzn) ? {.NZN} : {}
					ao_mask |= bnzp.id != .Air && block_is_opaque(bnzp) ? {.NZP} : {}
					ao_mask |= bnpn.id != .Air && block_is_opaque(bnpn) ? {.NPN} : {}
					ao_mask |= bnpz.id != .Air && block_is_opaque(bnpz) ? {.NPZ} : {}
					ao_mask |= bnpp.id != .Air && block_is_opaque(bnpp) ? {.NPP} : {}
					ao_mask |= bznn.id != .Air && block_is_opaque(bznn) ? {.ZNN} : {}
					ao_mask |= bznp.id != .Air && block_is_opaque(bznp) ? {.ZNP} : {}
					ao_mask |= bzpn.id != .Air && block_is_opaque(bzpn) ? {.ZPN} : {}
					ao_mask |= bzpp.id != .Air && block_is_opaque(bzpp) ? {.ZPP} : {}
					ao_mask |= bpnn.id != .Air && block_is_opaque(bpnn) ? {.PNN} : {}
					ao_mask |= bpnz.id != .Air && block_is_opaque(bpnz) ? {.PNZ} : {}
					ao_mask |= bpnp.id != .Air && block_is_opaque(bpnp) ? {.PNP} : {}
					ao_mask |= bpzn.id != .Air && block_is_opaque(bpzn) ? {.PZN} : {}
					ao_mask |= bpzp.id != .Air && block_is_opaque(bpzp) ? {.PZP} : {}
					ao_mask |= bppn.id != .Air && block_is_opaque(bppn) ? {.PPN} : {}
					ao_mask |= bppz.id != .Air && block_is_opaque(bppz) ? {.PPZ} : {}
					ao_mask |= bppp.id != .Air && block_is_opaque(bppp) ? {.PPP} : {}
				}

				local_pos := Local_Pos{x, y, z}

				vertices :=
					block_is_opaque(block) ? &mesh.opaque_verts : block.id == .Water ? &mesh.water_verts : &mesh.transparent_verts

				face_verts: Mesh_Face

				if .Neg_Y in mask {
					face_verts = position_face(.Neg_Y, ao_mask, local_pos, block)
					append(vertices, face_verts)
				}
				if .Pos_Y in mask {
					face_verts = position_face(.Pos_Y, ao_mask, local_pos, block)
					if block.id == .Water && bpy.id != .Water {
						face_verts[0].pos.y -= WATER_TOP_OFFSET
						face_verts[1].pos.y -= WATER_TOP_OFFSET
						face_verts[2].pos.y -= WATER_TOP_OFFSET
						face_verts[3].pos.y -= WATER_TOP_OFFSET
					}
					append(vertices, face_verts)
				}
				if .Neg_Z in mask {
					face_verts = position_face(.Neg_Z, ao_mask, local_pos, block)
					if block.id == .Water && bpy.id != .Water {
						face_verts[0].pos.y -= WATER_TOP_OFFSET
						face_verts[3].pos.y -= WATER_TOP_OFFSET
					}
					append(vertices, face_verts)
				}
				if .Pos_Z in mask {
					face_verts = position_face(.Pos_Z, ao_mask, local_pos, block)
					if block.id == .Water && bpy.id != .Water {
						face_verts[0].pos.y -= WATER_TOP_OFFSET
						face_verts[3].pos.y -= WATER_TOP_OFFSET
					}
					append(vertices, face_verts)
				}
				if .Neg_X in mask {
					face_verts = position_face(.Neg_X, ao_mask, local_pos, block)
					if block.id == .Water && bpy.id != .Water {
						face_verts[0].pos.y -= WATER_TOP_OFFSET
						face_verts[3].pos.y -= WATER_TOP_OFFSET
					}
					append(vertices, face_verts)
				}
				if .Pos_X in mask {
					face_verts = position_face(.Pos_X, ao_mask, local_pos, block)
					if block.id == .Water && bpy.id != .Water {
						face_verts[0].pos.y -= WATER_TOP_OFFSET
						face_verts[3].pos.y -= WATER_TOP_OFFSET
					}
					append(vertices, face_verts)
				}
			}
		}
	}
}

meshgen_index :: proc "contextless" (pos: glm.ivec3) -> i32 {
	return (pos.y + 1) * MESHGEN_CHUNK_SIZE * MESHGEN_CHUNK_SIZE + (pos.z + 1) * MESHGEN_CHUNK_SIZE + (pos.x + 1)
}
meshgen_get :: proc "contextless" (mg: ^Meshgen_Chunk, pos: glm.ivec3) -> Block {
	return mg[meshgen_index(pos)]
}

@(private = "file")
position_face :: #force_inline proc(
	$face: Block_Face,
	ao_mask: Block_Diag_Mask,
	local_pos: Local_Pos,
	block: Block,
) -> Mesh_Face {
	face_data := FACE_PLANES[face]

	ao_index :: #force_inline proc(s1, s2, c: bool) -> u8 {
		if s1 && s2 {
			return 3
		} else if (s1 || s2) && c {
			return 2
		} else if !s1 && !s2 && !c {
			return 0
		} else {
			return 1
		}
	}

	side_ao :: #force_inline proc(mask: Block_Diag_Mask, n: [8]Block_Diag) -> [4]u8 {
		ns: [8]bool
		for x, i in n {
			ns[i] = x in mask
		}
		return {
			ao_index(ns[4], ns[6], ns[5]),
			ao_index(ns[2], ns[4], ns[3]),
			ao_index(ns[0], ns[2], ns[1]),
			ao_index(ns[6], ns[0], ns[7]),
		}
	}

	if block.id != .Water {
		ao := side_ao(ao_mask, FACE_NEIGHBOURS[face])

		face_data[0].ao.ao = u32(ao[0]) // tl
		face_data[1].ao.ao = u32(ao[1]) // bl
		face_data[2].ao.ao = u32(ao[2]) // br
		face_data[3].ao.ao = u32(ao[3]) // tr

		// flip face to get rid if nasty anisotropy
		if ao[1] + ao[3] < ao[0] + ao[2] {
			tmp := face_data[0]
			face_data[0] = face_data[1] // 0=1
			face_data[1] = face_data[2] // 1=2
			face_data[2] = face_data[3] // 2=3
			face_data[3] = tmp // 3=0
		}
	} else {
		face_data[0].colour.a = 0xa0
		face_data[1].colour.a = 0xa0
		face_data[2].colour.a = 0xa0
		face_data[3].colour.a = 0xa0
	}

	// The tex coords in FACE_PLANES already span the whole layer
	layer := u32(block_texture(block, face))
	pos := glm.vec3{f32(local_pos.x), f32(local_pos.y), f32(local_pos.z)}

	face_data[0].pos += pos
	face_data[0].ao.layer = layer

	face_data[1].pos += pos
	face_data[1].ao.layer = layer

	face_data[2].pos += pos
	face_data[2].ao.layer = layer

	face_data[3].pos += pos
	face_data[3].ao.layer = layer

	return face_data
}

// odinfmt:disable
@(private = "file")
VERTEX_INPUT_COUNT :: size_of(Mesh_Face)
@( private = "file")
FACE_NEIGHBOURS :: [Block_Face][8]Block_Diag {
	.Neg_X={.NZP, .NNP, .NNZ, .NNN, .NZN, .NPN, .NPZ, .NPP},
	.Pos_X={.PZN, .PNN, .PNZ, .PNP, .PZP, .PPP, .PPZ, .PPN},
	.Neg_Y={.NNZ, .NNP, .ZNP, .PNP, .PNZ, .PNN, .ZNN, .NNN},
	.Pos_Y={.ZPP, .NPP, .NPZ, .NPN, .ZPN, .PPN, .PPZ, .PPP},
	.Neg_Z={.NZN, .NNN, .ZNN, .PNN, .PZN, .PPN, .ZPN, .NPN},
	.Pos_Z={.PZP, .PNP, .ZNP, .NNP, .NZP, .NPP, .ZPP, .PPP},
}
@(private = "file")
FACE_PLANES :: [Block_Face]Mesh_Face {
	.Neg_X={// Left
	{{0, 1, 0},  {0, 0},  {255, 255, 255, 255}, {}},
	{{0, 0, 0},  {0, 1},  {255, 255, 255, 255}, {}},
	{{0, 0, 1},  {1, 1},  {255, 255, 255, 255}, {}},
	{{0, 1, 1},  {1, 0},  {255, 255, 255, 255}, {}},
},
	.Pos_X={// Right
	{{1, 1, 1},  {0, 0},  {255, 255, 255, 255}, {}},
	{{1, 0, 1},  {0, 1},  {255, 255, 255, 255}, {}},
	{{1, 0, 0},  {1, 1},  {255, 255, 255, 255}, {}},
	{{1, 1, 0},  {1, 0},  {255, 255, 255, 255}, {}},
},
	.Neg_Y={// Bottom
	{{1, 0, 0},  {0, 0},  {255, 255, 255, 255}, {}},
	{{1, 0, 1},  {0, 1},  {255, 255, 255, 255}, {}},
	{{0, 0, 1},  {1, 1},  {255, 255, 255, 255}, {}},
	{{0, 0, 0},  {1, 0},  {255, 255, 255, 255}, {}},
},
	.Pos_Y={// Top
	{{1, 1, 0},  {0, 1},  {255, 255, 255, 255}, {}},
	{{0, 1, 0},  {1, 1},  {255, 255, 255, 255}, {}},
	{{0, 1, 1},  {1, 0},  {255, 255, 255, 255}, {}},
	{{1, 1, 1},  {0, 0},  {255, 255, 255, 255}, {}},
},
	.Pos_Z={// Front
	{{0, 1, 1},  {0, 0},  {255, 255, 255, 255}, {}},
	{{0, 0, 1},  {0, 1},  {255, 255, 255, 255}, {}},
	{{1, 0, 1},  {1, 1},  {255, 255, 255, 255}, {}},
	{{1, 1, 1},  {1, 0},  {255, 255, 255, 255}, {}},
},
	.Neg_Z={// Back
	{{1, 1, 0},  {1, 0},  {255, 255, 255, 255}, {}},
	{{1, 0, 0},  {1, 1},  {255, 255, 255, 255}, {}},
	{{0, 0, 0},  {0, 1},  {255, 255, 255, 255}, {}},
	{{0, 1, 0},  {0, 0},  {255, 255, 255, 255}, {}},
},
}
// odinfmt:enable
