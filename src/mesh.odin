package mou

import glm "core:math/linalg/glsl"

RGBA :: distinct [4]u8
#assert(size_of(RGBA) == size_of(u32))

Mesh_Vert :: struct #packed {
	pos:       glm.vec3,
	tex_coord: glm.vec2,
	colour:    RGBA,
}

FACE_VERT_COUNT :: 6
Mesh_Face :: [FACE_VERT_COUNT]Mesh_Vert

Chunk_Mesh :: struct {
	opaque:      [dynamic]Mesh_Face `fmt:"-"`,
	transparent: [dynamic]Mesh_Face `fmt:"-"`,
	water:       [dynamic]Mesh_Face `fmt:"-"`,
}
