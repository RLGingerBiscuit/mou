package mou

import glm "core:math/linalg/glsl"

Mesh_Vert :: struct #packed {
	pos:       glm.vec3,
	tex_coord: glm.vec2,
}

Chunk_Mesh :: struct {
	opaque:      [dynamic]Mesh_Vert `fmt:"-"`,
	transparent: [dynamic]Mesh_Vert `fmt:"-"`,
}
