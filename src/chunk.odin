package mou

import glm "core:math/linalg/glsl"
import "core:sync"

CHUNK_WIDTH :: 16
CHUNK_HEIGHT :: 16
CHUNK_DEPTH :: 16
CHUNK_SIZE :: CHUNK_WIDTH * CHUNK_HEIGHT * CHUNK_DEPTH
CHUNK_MULTIPLIER :: glm.ivec3{CHUNK_WIDTH, CHUNK_HEIGHT, CHUNK_DEPTH}

Chunk :: struct {
	pos:              glm.ivec3,
	blocks:           []Block `fmt:"-"`,
	opaque_mesh:      [dynamic]f32 `fmt:"-"`,
	transparent_mesh: [dynamic]f32 `fmt:"-"`,
	needs_remeshing:  bool,
}

generate_chunk :: proc(pos: glm.ivec3, allocator := context.allocator) -> Chunk {
	context.allocator = allocator
	chunk: Chunk
	chunk.pos = pos
	chunk.blocks = make([]Block, CHUNK_SIZE)
	chunk.opaque_mesh = make([dynamic]f32, 0, (CHUNK_SIZE / 2 * VERTEX_COUNT) / 4)
	chunk.transparent_mesh = make([dynamic]f32, 0, (CHUNK_SIZE / 2 * VERTEX_COUNT) / 4)

	return chunk
}

destroy_chunk :: proc(chunk: ^Chunk, allocator := context.allocator) {
	context.allocator = allocator
	delete(chunk.blocks)
	delete(chunk.opaque_mesh)
	delete(chunk.transparent_mesh)
	chunk^ = {}
}

chunk_needs_remeshing :: proc(chunk: ^Chunk) -> bool {
	return sync.atomic_load(&chunk.needs_remeshing)
}

mesh_chunk :: proc(world: ^World, chunk: ^Chunk) {
	if !chunk_needs_remeshing(chunk) {
		return
	}

	clear(&chunk.opaque_mesh)
	clear(&chunk.transparent_mesh)

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

				mesh := block_is_opaque(block) ? &chunk.opaque_mesh : &chunk.transparent_mesh

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

	sync.atomic_store(&chunk.needs_remeshing, false)
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
	start := local_coords_to_block_index(0, end_y, 0)
	end := local_coords_to_block_index(15, start_y, 15) + 1
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

@(private)
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
@(private)
VERTEX_COUNT :: 6
@(private)
COORD_COUNT :: VERTEX_COUNT * 3
@(private)
TEX_COORD_COUNT :: VERTEX_COUNT * 2
@(private)
VERTEX_INPUT_COUNT :: COORD_COUNT+TEX_COORD_COUNT
@(private)
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
