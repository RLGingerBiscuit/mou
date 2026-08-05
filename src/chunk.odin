package mou

import glm "core:math/linalg/glsl"
import "core:slice"
import "core:sync"

CHUNK_SIZE :: 16
CHUNK_BLOCK_COUNT :: CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE

Chunk_Mesh :: struct {
	opaque_vbo:              Vertex_Buffer,
	opaque_index_count:      int,
	transparent_vbo:         Vertex_Buffer,
	transparent_index_count: int,
	water_vbo:               Vertex_Buffer,
	water_index_count:       int,
	// For sorting...
	transparent_verts:       []Mesh_Face,
	water_verts:             []Mesh_Face,
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
	chunk.mesh = Chunk_Mesh {
		opaque_vbo      = make_vertex_buffer(.Dynamic),
		transparent_vbo = make_vertex_buffer(.Dynamic),
		water_vbo       = make_vertex_buffer(.Dynamic),
	}
	mesh := &chunk.mesh.(Chunk_Mesh)
	return mesh
}

chunk_update_mesh :: proc(chunk: ^Chunk, generated: ^Generated_Chunk_Mesh) -> ^Chunk_Mesh {
	mesh := chunk_ensure_mesh(chunk)
	mesh.opaque_index_count = len(generated.opaque_verts) * FACE_INDEX_COUNT
	mesh.transparent_index_count = len(generated.transparent_verts) * FACE_INDEX_COUNT
	mesh.water_index_count = len(generated.water_verts) * FACE_INDEX_COUNT

	delete(mesh.water_verts)
	delete(mesh.transparent_verts)
	mesh.water_verts = slice.clone(generated.water_verts[:])
	mesh.transparent_verts = slice.clone(generated.transparent_verts[:])

	buffer_data(mesh.opaque_vbo, generated.opaque_verts[:])
	buffer_data(mesh.transparent_vbo, generated.transparent_verts[:])
	buffer_data(mesh.water_vbo, generated.water_verts[:])
	return mesh
}

chunk_destroy_mesh :: proc(chunk: ^Chunk) {
	if mesh, ok := &chunk.mesh.?; ok {
		delete(mesh.water_verts)
		delete(mesh.transparent_verts)
		destroy_vertex_buffer(&mesh.opaque_vbo)
		destroy_vertex_buffer(&mesh.transparent_vbo)
		destroy_vertex_buffer(&mesh.water_vbo)
	}
	chunk.mesh = nil
}

chunk_update_block :: proc(
	world: ^World,
	chunk: ^Chunk,
	local_pos: Local_Pos,
	block: Block,
	mark := true,
) {
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
	end := local_coords_to_block_index(15, y, 15) + 1
	return chunk.blocks[start:end]
}

get_chunk_layers :: proc(chunk: ^Chunk, start_y, end_y: i32) -> []Block {
	start := local_coords_to_block_index(0, start_y, 0)
	end := local_coords_to_block_index(15, end_y, 15) + 1
	return chunk.blocks[start:end]
}

get_chunk_centre :: proc(chunk: ^Chunk) -> glm.vec3 {
	return chunk_pos_centre(chunk.pos)
}

chunk_pos_centre :: proc(chunk_pos: Chunk_Pos) -> glm.vec3 {
	centre := chunk_pos_to_block_pos(chunk_pos) + Block_Pos(CHUNK_SIZE / 2)
	return {f32(centre.x), f32(centre.y), f32(centre.z)}
}

chunk_pos_to_world_pos :: proc(chunk_pos: Chunk_Pos) -> World_Pos {
	return {f32(chunk_pos.x << 4), f32(chunk_pos.y << 4), f32(chunk_pos.z << 4)}
}

chunk_pos_to_block_pos :: proc(chunk_pos: Chunk_Pos) -> Block_Pos {
	return {chunk_pos.x << 4, chunk_pos.y << 4, chunk_pos.z << 4}
}

local_coords_to_block_index :: proc(x, y, z: i32) -> i32 {
	return (y * CHUNK_SIZE * CHUNK_SIZE) + (z * CHUNK_SIZE) + x
}
