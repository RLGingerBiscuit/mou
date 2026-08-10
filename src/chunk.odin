package mou

import glm "core:math/linalg/glsl"
import "core:sync"

// 4 == 16, 5 == 32, etc.
CHUNK_SIZE_SHIFT :: 4
CHUNK_SIZE :: 1 << CHUNK_SIZE_SHIFT
CHUNK_SIZE_MASK :: CHUNK_SIZE - 1
CHUNK_BLOCK_COUNT :: CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE

Chunk_Mesh :: struct {
	opaque_vbo:              Vertex_Buffer,
	opaque_index_count:      int,
	transparent_vbo:         Vertex_Buffer,
	transparent_index_count: int,
	water_vbo:               Vertex_Buffer,
	water_index_count:       int,
	gen_time:                f32,
}

Chunk :: struct {
	pos:         Chunk_Pos,
	blocks:      []Block `fmt:"-"`,
	mesh:        Maybe(Chunk_Mesh),
	mark_remesh: bool,
	mark_demesh: bool,
}

make_chunk :: proc(pos: Chunk_Pos) -> Chunk {
	chunk: Chunk
	chunk.pos = pos
	chunk.blocks = make([]Block, CHUNK_BLOCK_COUNT)

	return chunk
}

destroy_chunk :: proc(chunk: ^Chunk) {
	delete(chunk.blocks)
	chunk_destroy_mesh(chunk)
	chunk^ = {}
}

chunk_marked_remesh :: proc(chunk: ^Chunk) -> bool {
	return sync.atomic_load(&chunk.mark_remesh)
}

chunk_marked_demesh :: proc(chunk: ^Chunk) -> bool {
	return sync.atomic_load(&chunk.mark_demesh)
}

chunk_ensure_mesh :: proc(chunk: ^Chunk) -> ^Chunk_Mesh {
	if mesh, ok := &chunk.mesh.?; ok {
		return mesh
	}
	chunk.mesh = Chunk_Mesh{}
	mesh := &chunk.mesh.(Chunk_Mesh)
	return mesh
}

chunk_update_mesh :: proc(chunk: ^Chunk, generated: ^Generated_Chunk_Mesh) -> ^Chunk_Mesh {
	mesh := chunk_ensure_mesh(chunk)
	mesh.opaque_index_count = len(generated.opaque_verts) * FACE_INDEX_COUNT
	if mesh.opaque_index_count > 0 {
		if mesh.opaque_vbo.handle == 0 {
			mesh.opaque_vbo = make_vertex_buffer(.Dynamic)
		}
		buffer_data(mesh.opaque_vbo, generated.opaque_verts[:])
	} else if mesh.opaque_vbo.handle != 0 {
		destroy_vertex_buffer(&mesh.opaque_vbo)
		mesh.opaque_vbo = {}
	}
	mesh.transparent_index_count = len(generated.transparent_verts) * FACE_INDEX_COUNT
	if mesh.transparent_index_count > 0 {
		if mesh.transparent_vbo.handle == 0 {
			mesh.transparent_vbo = make_vertex_buffer(.Dynamic)
		}
		buffer_data(mesh.transparent_vbo, generated.transparent_verts[:])
	} else if mesh.transparent_vbo.handle != 0 {
		destroy_vertex_buffer(&mesh.transparent_vbo)
		mesh.transparent_vbo = {}
	}
	mesh.water_index_count = len(generated.water_verts) * FACE_INDEX_COUNT
	if mesh.water_index_count > 0 {
		if mesh.water_vbo.handle == 0 {
			mesh.water_vbo = make_vertex_buffer(.Dynamic)
		}
		buffer_data(mesh.water_vbo, generated.water_verts[:])
	} else if mesh.water_vbo.handle != 0 {
		destroy_vertex_buffer(&mesh.water_vbo)
		mesh.water_vbo = {}
	}

	return mesh
}

chunk_destroy_mesh :: proc(chunk: ^Chunk) {
	if mesh, ok := &chunk.mesh.?; ok {
		destroy_vertex_buffer(&mesh.opaque_vbo)
		destroy_vertex_buffer(&mesh.transparent_vbo)
		destroy_vertex_buffer(&mesh.water_vbo)
	}
	chunk.mesh = nil
}

chunk_update_block :: proc(world: ^World, chunk: ^Chunk, local_pos: Local_Pos, block: Block, mark := true) {
	idx := local_coords_to_block_index(local_pos.x, local_pos.y, local_pos.z)
	chunk.blocks[idx] = block
	if mark {
		world_mark_chunk_remesh_priority(world, chunk)
	}
}

get_chunk_block :: proc(chunk: Chunk, local_pos: Local_Pos) -> (Block, bool) {
	x := local_pos.x
	y := local_pos.y
	z := local_pos.z
	if x < 0 || y < 0 || z < 0 || x >= CHUNK_SIZE || y >= CHUNK_SIZE || z >= CHUNK_SIZE {
		return {}, false
	}
	index := local_coords_to_block_index(x, y, z)
	return chunk.blocks[index], true
}

get_chunk_layer :: proc(chunk: ^Chunk, y: i32) -> []Block {
	start := local_coords_to_block_index(0, y, 0)
	end := local_coords_to_block_index(CHUNK_SIZE - 1, y, CHUNK_SIZE - 1) + 1
	return chunk.blocks[start:end]
}

get_chunk_layers :: proc(chunk: ^Chunk, start_y, end_y: i32) -> []Block {
	start := local_coords_to_block_index(0, start_y, 0)
	end := local_coords_to_block_index(CHUNK_SIZE - 1, end_y, CHUNK_SIZE - 1) + 1
	return chunk.blocks[start:end]
}

get_chunk_centre :: proc(chunk: ^Chunk) -> glm.vec3 {
	return chunk_pos_centre(chunk.pos)
}

chunk_pos_centre :: proc(chunk_pos: Chunk_Pos) -> glm.vec3 {
	centre := chunk_pos_to_block_pos(chunk_pos) + Block_Pos(CHUNK_SIZE / 2)
	return cast(glm.vec3)centre
}

chunk_pos_to_world_pos :: proc(chunk_pos: Chunk_Pos) -> World_Pos {
	return cast(World_Pos)chunk_pos * CHUNK_SIZE
}

chunk_pos_to_block_pos :: proc(chunk_pos: Chunk_Pos) -> Block_Pos {
	return chunk_pos * CHUNK_SIZE
}

local_coords_to_block_index :: proc(x, y, z: i32) -> i32 {
	return (y * CHUNK_SIZE * CHUNK_SIZE) + (z * CHUNK_SIZE) + x
}
