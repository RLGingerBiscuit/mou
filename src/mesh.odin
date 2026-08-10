package mou

import glm "core:math/linalg/glsl"

RGBA :: distinct [4]u8
#assert(size_of(RGBA) == size_of(u32))
RGBA32 :: distinct glm.vec4

Mesh_Vert :: struct #packed {
	pos:       glm.vec3,
	tex_coord: glm.vec2,
	colour:    RGBA,
	ao:        bit_field u32 {
		ao:    u32 | 2,
		layer: u32 | 8,
	},
}

FACE_VERT_COUNT :: 4
FACE_INDEX_COUNT :: 6
Mesh_Face :: [FACE_VERT_COUNT]Mesh_Vert
Mesh_Face_Indexes :: [FACE_INDEX_COUNT]u32
