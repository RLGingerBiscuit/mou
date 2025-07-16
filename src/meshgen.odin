package mou

import "core:log"
import "core:mem"
import vmem "core:mem/virtual"
import "core:sync/chan"
import "core:thread"

import "prof"

MESHGEN_CHAN_CAP :: 16

Meshgen_Msg_Remesh :: struct {
	pos: Chunk_Pos,
}
Meshgen_Msg_Demesh :: struct {
	pos: Chunk_Pos,
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
	prof.init_thread()

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
			chunk, exists := &world.chunks[v.pos]
			ensure(exists, "Chunk sent for meshing doesn't exist")
			if !chunk_marked_remesh(chunk) || chunk_marked_demesh(chunk) {
				continue
			}

			// Make a new mesh here to avoid flashes as meshes are updated
			mesh := len(mg.tombstones) > 0 ? pop(&mg.tombstones) : new_chunk_mesh(mg, world)
			assert(mesh != nil)

			if prof.event("chunk mesh generation") {
				mesh_chunk(world, chunk, mesh)
			}

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
	mesh := new(Chunk_Mesh)

	// From some *very* basic tests these numbers seem to be alright for now
	mesh.opaque = make([dynamic]Mesh_Face, 0, CHUNK_BLOCK_COUNT / 24)
	mesh.opaque_indices = make([dynamic]Mesh_Face_Indexes, 0, CHUNK_BLOCK_COUNT / 24)
	mesh.transparent = make([dynamic]Mesh_Face)
	mesh.transparent_indices = make([dynamic]Mesh_Face_Indexes)
	mesh.water = make([dynamic]Mesh_Face)
	mesh.water_indices = make([dynamic]Mesh_Face_Indexes)

	return mesh
}

mesh_chunk :: proc(world: ^World, chunk: ^Chunk, mesh: ^Chunk_Mesh) {
	clear(&mesh.opaque)
	clear(&mesh.transparent)
	clear(&mesh.water)
	clear(&mesh.opaque_indices)
	clear(&mesh.transparent_indices)
	clear(&mesh.water_indices)

	WATER_TOP_OFFSET :: (f32(1) / 16)

	chunk_block_pos := chunk_pos_to_block_pos(chunk.pos)

	for y in i32(0) ..< CHUNK_HEIGHT {
		for z in i32(0) ..< CHUNK_DEPTH {
			for x in i32(0) ..< CHUNK_WIDTH {
				block := chunk.blocks[local_coords_to_block_index(x, y, z)]
				if block.id == .Air {
					continue
				}

				bnx, bnxok := get_world_block(world^, chunk_block_pos + {x - 1, y, z})
				bpx, bpxok := get_world_block(world^, chunk_block_pos + {x + 1, y, z})
				bny, bnyok := get_world_block(world^, chunk_block_pos + {x, y - 1, z})
				bpy, bpyok := get_world_block(world^, chunk_block_pos + {x, y + 1, z})
				bnz, bnzok := get_world_block(world^, chunk_block_pos + {x, y, z - 1})
				bpz, bpzok := get_world_block(world^, chunk_block_pos + {x, y, z + 1})

				bnnn, bnnnok := get_world_block(world^, chunk_block_pos + {x - 1, y - 1, z - 1})
				bnnz, bnnzok := get_world_block(world^, chunk_block_pos + {x - 1, y - 1, z + 0})
				bnnp, bnnpok := get_world_block(world^, chunk_block_pos + {x - 1, y - 1, z + 1})
				bnzn, bnznok := get_world_block(world^, chunk_block_pos + {x - 1, y + 0, z - 1})
				bnzp, bnzpok := get_world_block(world^, chunk_block_pos + {x - 1, y + 0, z + 1})
				bnpn, bnpnok := get_world_block(world^, chunk_block_pos + {x - 1, y + 1, z - 1})
				bnpz, bnpzok := get_world_block(world^, chunk_block_pos + {x - 1, y + 1, z + 0})
				bnpp, bnppok := get_world_block(world^, chunk_block_pos + {x - 1, y + 1, z + 1})
				bznn, bznnok := get_world_block(world^, chunk_block_pos + {x + 0, y - 1, z - 1})
				bznp, bznpok := get_world_block(world^, chunk_block_pos + {x + 0, y - 1, z + 1})
				bzpn, bzpnok := get_world_block(world^, chunk_block_pos + {x + 0, y + 1, z - 1})
				bzpp, bzppok := get_world_block(world^, chunk_block_pos + {x + 0, y + 1, z + 1})
				bpnn, bpnnok := get_world_block(world^, chunk_block_pos + {x + 1, y - 1, z - 1})
				bpnz, bpnzok := get_world_block(world^, chunk_block_pos + {x + 1, y - 1, z + 0})
				bpnp, bpnpok := get_world_block(world^, chunk_block_pos + {x + 1, y - 1, z + 1})
				bpzn, bpznok := get_world_block(world^, chunk_block_pos + {x + 1, y + 0, z - 1})
				bpzp, bpzpok := get_world_block(world^, chunk_block_pos + {x + 1, y + 0, z + 1})
				bppn, bppnok := get_world_block(world^, chunk_block_pos + {x + 1, y + 1, z - 1})
				bppz, bppzok := get_world_block(world^, chunk_block_pos + {x + 1, y + 1, z + 0})
				bppp, bpppok := get_world_block(world^, chunk_block_pos + {x + 1, y + 1, z + 1})

				// Which directions SHOULD faces be placed
				mask: Block_Face_Mask
				ao_mask: Block_Diag_Mask

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

				ao_mask |= bnnnok && bnnn.id != .Air && block_is_opaque(bnnn) ? {.NNN} : {}
				ao_mask |= bnnzok && bnnz.id != .Air && block_is_opaque(bnnz) ? {.NNZ} : {}
				ao_mask |= bnnpok && bnnp.id != .Air && block_is_opaque(bnnp) ? {.NNP} : {}
				ao_mask |= bnznok && bnzn.id != .Air && block_is_opaque(bnzn) ? {.NZN} : {}
				ao_mask |= bnzpok && bnzp.id != .Air && block_is_opaque(bnzp) ? {.NZP} : {}
				ao_mask |= bnpnok && bnpn.id != .Air && block_is_opaque(bnpn) ? {.NPN} : {}
				ao_mask |= bnpzok && bnpz.id != .Air && block_is_opaque(bnpz) ? {.NPZ} : {}
				ao_mask |= bnppok && bnpp.id != .Air && block_is_opaque(bnpp) ? {.NPP} : {}
				ao_mask |= bznnok && bznn.id != .Air && block_is_opaque(bznn) ? {.ZNN} : {}
				ao_mask |= bznpok && bznp.id != .Air && block_is_opaque(bznp) ? {.ZNP} : {}
				ao_mask |= bzpnok && bzpn.id != .Air && block_is_opaque(bzpn) ? {.ZPN} : {}
				ao_mask |= bzppok && bzpp.id != .Air && block_is_opaque(bzpp) ? {.ZPP} : {}
				ao_mask |= bpnnok && bpnn.id != .Air && block_is_opaque(bpnn) ? {.PNN} : {}
				ao_mask |= bpnzok && bpnz.id != .Air && block_is_opaque(bpnz) ? {.PNZ} : {}
				ao_mask |= bpnpok && bpnp.id != .Air && block_is_opaque(bpnp) ? {.PNP} : {}
				ao_mask |= bpznok && bpzn.id != .Air && block_is_opaque(bpzn) ? {.PZN} : {}
				ao_mask |= bpzpok && bpzp.id != .Air && block_is_opaque(bpzp) ? {.PZP} : {}
				ao_mask |= bppnok && bppn.id != .Air && block_is_opaque(bppn) ? {.PPN} : {}
				ao_mask |= bppzok && bppz.id != .Air && block_is_opaque(bppz) ? {.PPZ} : {}
				ao_mask |= bpppok && bppp.id != .Air && block_is_opaque(bppp) ? {.PPP} : {}

				if mask == {} {
					continue
				}

				vertices :=
					block_is_opaque(block) ? &mesh.opaque : block.id == .Water ? &mesh.water : &mesh.transparent
				indices :=
					block_is_opaque(block) ? &mesh.opaque_indices : block.id == .Water ? &mesh.water_indices : &mesh.transparent_indices
				block_pos := chunk_block_pos + Block_Pos{x, y, z}
				face_verts: Mesh_Face
				face_indices: Mesh_Face_Indexes

				if .Neg_Y in mask {
					face_verts, face_indices = position_face(
						.Neg_Y,
						ao_mask,
						block_pos,
						block,
						world.atlas,
					)
					if block.id == .Water {
						append(vertices, face_verts)
						face_indices += cast(u32)len(indices) * FACE_VERT_COUNT
						append(indices, face_indices)
						face_verts, face_indices = position_face(
							.Pos_Y,
							ao_mask,
							block_pos + {0, -1, 0},
							block,
							world.atlas,
						)
					}
					append(vertices, face_verts)
					face_indices += cast(u32)len(indices) * FACE_VERT_COUNT
					append(indices, face_indices)
				}
				if .Pos_Y in mask {
					face_verts, face_indices = position_face(
						.Pos_Y,
						ao_mask,
						block_pos,
						block,
						world.atlas,
					)
					if block.id == .Water {
						if bpyok && bpy.id != .Water {
							face_verts[0].pos.y -= WATER_TOP_OFFSET
							face_verts[1].pos.y -= WATER_TOP_OFFSET
							face_verts[2].pos.y -= WATER_TOP_OFFSET
							face_verts[3].pos.y -= WATER_TOP_OFFSET
						}
						append(vertices, face_verts)
						face_indices += cast(u32)len(indices) * FACE_VERT_COUNT
						append(indices, face_indices)
						face_verts, face_indices = position_face(
							.Neg_Y,
							ao_mask,
							block_pos + {0, 1, 0},
							block,
							world.atlas,
						)
						if bpyok && bpy.id != .Water {
							face_verts[0].pos.y -= WATER_TOP_OFFSET
							face_verts[1].pos.y -= WATER_TOP_OFFSET
							face_verts[2].pos.y -= WATER_TOP_OFFSET
							face_verts[3].pos.y -= WATER_TOP_OFFSET
						}
					}
					append(vertices, face_verts)
					face_indices += cast(u32)len(indices) * FACE_VERT_COUNT
					append(indices, face_indices)
				}
				if .Neg_Z in mask {
					face_verts, face_indices = position_face(
						.Neg_Z,
						ao_mask,
						block_pos,
						block,
						world.atlas,
					)
					if block.id == .Water {
						if bpyok && bpy.id != .Water {
							face_verts[0].pos.y -= WATER_TOP_OFFSET
						}
						append(vertices, face_verts)
						face_indices += cast(u32)len(indices) * FACE_VERT_COUNT
						append(indices, face_indices)
						face_verts, face_indices = position_face(
							.Pos_Z,
							ao_mask,
							block_pos + {0, 0, -1},
							block,
							world.atlas,
						)
						if bpyok && bpy.id != .Water {
							face_verts[0].pos.y -= WATER_TOP_OFFSET
						}
					}
					append(vertices, face_verts)
					face_indices += cast(u32)len(indices) * FACE_VERT_COUNT
					append(indices, face_indices)
				}
				if .Pos_Z in mask {
					face_verts, face_indices = position_face(
						.Pos_Z,
						ao_mask,
						block_pos,
						block,
						world.atlas,
					)
					if block.id == .Water {
						if bpyok && bpy.id != .Water {
							face_verts[0].pos.y -= WATER_TOP_OFFSET
						}
						append(vertices, face_verts)
						face_indices += cast(u32)len(indices) * FACE_VERT_COUNT
						append(indices, face_indices)
						face_verts, face_indices = position_face(
							.Neg_Z,
							ao_mask,
							block_pos + {0, 0, 1},
							block,
							world.atlas,
						)
						if bpyok && bpy.id != .Water {
							face_verts[0].pos.y -= WATER_TOP_OFFSET
						}
					}
					append(vertices, face_verts)
					face_indices += cast(u32)len(indices) * FACE_VERT_COUNT
					append(indices, face_indices)
				}
				if .Neg_X in mask {
					face_verts, face_indices = position_face(
						.Neg_X,
						ao_mask,
						block_pos,
						block,
						world.atlas,
					)
					if block.id == .Water {
						if bpyok && bpy.id != .Water {
							face_verts[0].pos.y -= WATER_TOP_OFFSET
						}
						append(vertices, face_verts)
						face_indices += cast(u32)len(indices) * FACE_VERT_COUNT
						append(indices, face_indices)
						face_verts, face_indices = position_face(
							.Pos_X,
							ao_mask,
							block_pos + {-1, 0, 0},
							block,
							world.atlas,
						)
						if bpyok && bpy.id != .Water {
							face_verts[0].pos.y -= WATER_TOP_OFFSET
						}
					}
					append(vertices, face_verts)
					face_indices += cast(u32)len(indices) * FACE_VERT_COUNT
					append(indices, face_indices)
				}
				if .Pos_X in mask {
					face_verts, face_indices = position_face(
						.Pos_X,
						ao_mask,
						block_pos,
						block,
						world.atlas,
					)
					if block.id == .Water {
						if bpyok && bpy.id != .Water {
							face_verts[0].pos.y -= WATER_TOP_OFFSET
						}
						append(vertices, face_verts)
						face_indices += cast(u32)len(indices) * FACE_VERT_COUNT
						append(indices, face_indices)
						face_verts, face_indices = position_face(
							.Neg_X,
							ao_mask,
							block_pos + {1, 0, 0},
							block,
							world.atlas,
						)
						if bpyok && bpy.id != .Water {
							face_verts[0].pos.y -= WATER_TOP_OFFSET
						}
					}
					append(vertices, face_verts)
					face_indices += cast(u32)len(indices) * FACE_VERT_COUNT
					append(indices, face_indices)
				}
			}
		}
	}
}

@(private = "file")
position_face :: #force_inline proc(
	$face: Block_Face_Bit,
	ao_mask: Block_Diag_Mask,
	block_pos: Block_Pos,
	block: Block,
	atlas: ^Atlas,
) -> (
	Mesh_Face,
	Mesh_Face_Indexes,
) {
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

	side_ao :: #force_inline proc(mask: Block_Diag_Mask, n: [8]Block_Diag_Bit) -> [4]u8 {
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

		face_data[0].ao = AO_DATA[ao[0]] // tl

		face_data[1].ao = AO_DATA[ao[1]] // bl

		face_data[2].ao = AO_DATA[ao[2]] // br

		face_data[3].ao = AO_DATA[ao[3]] // tr

		// flip face to get rid if nasty anisotropy
		if ao[1] + ao[3] < ao[0] + ao[2] {
			// face_data[0] = face_data[1] // 0=1
			// face_data[1] = face_data[2] // 1=2
			// face_data[2] = face_data[4] // 2=4
			// face_data[3] = face_data[4] // 3=4
			// face_data[4] = face_data[5] // 4=5
			// face_data[5] = face_data[0] // 5=1
		}
	}

	world_pos := block_pos_to_world_pos(block_pos)
	uvs := atlas.uvs[block_asset_name(block, face)]

	face_data[0].pos += world_pos
	face_data[0].tex_coord = {
		uvs[int(face_data[0].tex_coord.x)].x,
		uvs[int(face_data[0].tex_coord.y)].y,
	}

	face_data[1].pos += world_pos
	face_data[1].tex_coord = {
		uvs[int(face_data[1].tex_coord.x)].x,
		uvs[int(face_data[1].tex_coord.y)].y,
	}

	face_data[2].pos += world_pos
	face_data[2].tex_coord = {
		uvs[int(face_data[2].tex_coord.x)].x,
		uvs[int(face_data[2].tex_coord.y)].y,
	}

	face_data[3].pos += world_pos
	face_data[3].tex_coord = {
		uvs[int(face_data[3].tex_coord.x)].x,
		uvs[int(face_data[3].tex_coord.y)].y,
	}

	// FIXME: a nicer place to put this (atlas generates per block face data?)
	if block.id == .Water {
		when face == .Neg_Y || face == .Pos_Y {
			a: u8 = 0xc0
		} else {
			a: u8 = 0xff
		}

		colour := RGBA{0x3f, 0x76, 0xe4, a}

		face_data[0].colour = colour
		face_data[1].colour = colour
		face_data[2].colour = colour
		face_data[3].colour = colour
	}

	return face_data, {0, 1, 2, 2, 3, 0}
}

// odinfmt:disable
@(private = "file")
VERTEX_INPUT_COUNT :: size_of(Mesh_Face)
@(rodata, private = "file")
AO_DATA := [?]f32{0, 0.25, 0.5, 0.75}
@( private = "file")
FACE_NEIGHBOURS :: [Block_Face_Bit][8]Block_Diag_Bit {
	.Neg_X={.NZP, .NNP, .NNZ, .NNN, .NZN, .NPN, .NPZ, .NPP},
	.Pos_X={.PZN, .PNN, .PNZ, .PNP, .PZP, .PPP, .PPZ, .PPN},
	.Neg_Y={.NNZ, .NNP, .ZNP, .PNP, .PNZ, .PNN, .ZNN, .NNN},
	.Pos_Y={.ZPP, .NPP, .NPZ, .NPN, .ZPN, .PPN, .PPZ, .PPP},
	.Neg_Z={.NZN, .NNN, .ZNN, .PNN, .PZN, .PPN, .ZPN, .NPN},
	.Pos_Z={.PZP, .PNP, .ZNP, .NNP, .NZP, .NPP, .ZPP, .PPP},
}
@(private = "file")
FACE_PLANES :: [Block_Face_Bit]Mesh_Face {
	.Neg_X={// Left
	{{-0.5,  0.5, -0.5},  {0, 0},  {255, 255, 255, 255}, 0},
	{{-0.5, -0.5, -0.5},  {0, 1},  {255, 255, 255, 255}, 0},
	{{-0.5, -0.5,  0.5},  {1, 1},  {255, 255, 255, 255}, 0},
	{{-0.5,  0.5,  0.5},  {1, 0},  {255, 255, 255, 255}, 0},
},
	.Pos_X={// Right
	{{ 0.5,  0.5,  0.5},  {0, 0},  {255, 255, 255, 255}, 0},
	{{ 0.5, -0.5,  0.5},  {0, 1},  {255, 255, 255, 255}, 0},
	{{ 0.5, -0.5, -0.5},  {1, 1},  {255, 255, 255, 255}, 0},
	{{ 0.5,  0.5, -0.5},  {1, 0},  {255, 255, 255, 255}, 0},
},
	.Neg_Y={// Bottom
	{{ 0.5, -0.5, -0.5},  {0, 0},  {255, 255, 255, 255}, 0},
	{{ 0.5, -0.5,  0.5},  {0, 1},  {255, 255, 255, 255}, 0},
	{{-0.5, -0.5,  0.5},  {1, 1},  {255, 255, 255, 255}, 0},
	{{-0.5, -0.5, -0.5},  {1, 0},  {255, 255, 255, 255}, 0},
},
	.Pos_Y={// Top
	{{ 0.5,  0.5, -0.5},  {0, 1},  {255, 255, 255, 255}, 0},
	{{-0.5,  0.5, -0.5},  {1, 1},  {255, 255, 255, 255}, 0},
	{{-0.5,  0.5,  0.5},  {1, 0},  {255, 255, 255, 255}, 0},
	{{ 0.5,  0.5,  0.5},  {0, 0},  {255, 255, 255, 255}, 0},
},
	.Pos_Z={// Front
	{{-0.5,  0.5,  0.5},  {0, 0},  {255, 255, 255, 255}, 0},
	{{-0.5, -0.5,  0.5},  {0, 1},  {255, 255, 255, 255}, 0},
	{{ 0.5, -0.5,  0.5},  {1, 1},  {255, 255, 255, 255}, 0},
	{{ 0.5,  0.5,  0.5},  {1, 0},  {255, 255, 255, 255}, 0},
},
	.Neg_Z={// Back
	{{ 0.5,  0.5, -0.5},  {1, 0},  {255, 255, 255, 255}, 0},
	{{ 0.5, -0.5, -0.5},  {1, 1},  {255, 255, 255, 255}, 0},
	{{-0.5, -0.5, -0.5},  {0, 1},  {255, 255, 255, 255}, 0},
	{{-0.5,  0.5, -0.5},  {0, 0},  {255, 255, 255, 255}, 0},
},
}
// odinfmt:enable
