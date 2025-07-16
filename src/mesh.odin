package mou

import glm "core:math/linalg/glsl"

RGBA :: distinct [4]u8
#assert(size_of(RGBA) == size_of(u32))
RGBA32 :: distinct glm.vec4

Mesh_Vert :: struct #packed {
	pos:       glm.vec3,
	tex_coord: glm.vec2,
	colour:    RGBA,
	ao:        f32,
}

FACE_VERT_COUNT :: 4
FACE_INDEX_COUNT :: 6
Mesh_Face :: [FACE_VERT_COUNT]Mesh_Vert
Mesh_Face_Indexes :: [FACE_INDEX_COUNT]u32

Chunk_Mesh :: struct {
	opaque:              [dynamic]Mesh_Face `fmt:"-"`,
	opaque_indices:      [dynamic]Mesh_Face_Indexes `fmt:"-"`,
	transparent:         [dynamic]Mesh_Face `fmt:"-"`,
	transparent_indices: [dynamic]Mesh_Face_Indexes `fmt:"-"`,
	water:               [dynamic]Mesh_Face `fmt:"-"`,
	water_indices:       [dynamic]Mesh_Face_Indexes `fmt:"-"`,
}
