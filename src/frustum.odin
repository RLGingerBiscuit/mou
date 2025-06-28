package mou

import sa "core:container/small_array"
import glm "core:math/linalg/glsl"

// FIXME: this doesn't belong here
Line_Vert :: struct #packed {
	pos:    glm.vec3,
	colour: RGBA,
}

Frustum_Plane :: distinct glm.vec4

Frustum :: struct {
	left, right: Frustum_Plane,
	bottom, top: Frustum_Plane,
	near, far:   Frustum_Plane,
}

create_frustum :: proc(mat: glm.mat4) -> (f: Frustum) {
	mat := mat
	mat = glm.transpose(mat)

	norm :: #force_inline proc(x: glm.vec4) -> Frustum_Plane {
		x := x
		len := glm.length(x.xyz)
		ensure(len > 0)
		x /= len
		return Frustum_Plane(x)
	}

	// left/right swapped due to inverted coords (mc-style)
	f.left = norm(mat[3] - mat[0])
	f.right = norm(mat[3] + mat[0])

	f.bottom = norm(mat[3] + mat[1])
	f.top = norm(mat[3] - mat[1])

	f.near = norm(mat[3] + mat[2])
	f.far = norm(mat[3] - mat[2])

	return
}

FRUSTUM_COLOUR :: RGBA{0xff, 0xff, 0xff, 0xff}
FRUSTUM_VERT_COUNT :: 4 * 6

get_frustum_vertices :: proc(f: Frustum) -> [FRUSTUM_VERT_COUNT]Line_Vert {
	verts: sa.Small_Array(FRUSTUM_VERT_COUNT, Line_Vert)

	intersect :: #force_inline proc(p0, p1, p2: Frustum_Plane) -> glm.vec3 {
		a := glm.cross(p2.xyz, p0.xyz)
		b := glm.cross(p0.xyz, p1.xyz)
		c := glm.cross(p1.xyz, p2.xyz)
		d := glm.dot(p1.xyz, a)

		x := (-p1.w * a.x - p2.w * b.x - p0.w * c.x) / d
		y := (-p1.w * a.y - p2.w * b.y - p0.w * c.y) / d
		z := (-p1.w * a.z - p2.w * b.z - p0.w * c.z) / d

		return {x, y, z}
	}

	nlb := intersect(f.near, f.left, f.bottom)
	nrb := intersect(f.near, f.right, f.bottom)
	nrt := intersect(f.near, f.right, f.top)
	nlt := intersect(f.near, f.left, f.top)

	flb := intersect(f.far, f.left, f.bottom)
	frb := intersect(f.far, f.right, f.bottom)
	frt := intersect(f.far, f.right, f.top)
	flt := intersect(f.far, f.left, f.top)

	// Near face
	assert(sa.append(&verts, Line_Vert{nlb, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{nrb, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{nrb, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{nrt, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{nrt, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{nlt, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{nlt, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{nlb, FRUSTUM_COLOUR}))

	// Far face
	assert(sa.append(&verts, Line_Vert{flb, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{frb, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{frb, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{frt, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{frt, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{flt, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{flt, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{flb, FRUSTUM_COLOUR}))

	// Left face
	assert(sa.append(&verts, Line_Vert{nlb, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{flb, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{nlt, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{flt, FRUSTUM_COLOUR}))

	// Right face
	assert(sa.append(&verts, Line_Vert{nrb, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{frb, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{nrt, FRUSTUM_COLOUR}))
	assert(sa.append(&verts, Line_Vert{frt, FRUSTUM_COLOUR}))

	assert(sa.space(verts) == 0)

	return verts.data
}

frustum_contains_chunk :: proc(f: Frustum, ipos: glm.ivec3) -> bool {
	pos := glm.vec3 {
		f32(ipos.x) * CHUNK_WIDTH,
		f32(ipos.y) * CHUNK_HEIGHT,
		f32(ipos.z) * CHUNK_DEPTH,
	}

	check :: #force_inline proc(p: Frustum_Plane, pos: glm.vec3) -> bool {
		vert := pos
		if p.x >= 0 {
			vert.x += CHUNK_WIDTH
		}
		if p.y >= 0 {
			vert.y += CHUNK_HEIGHT
		}
		if p.z >= 0 {
			vert.z += CHUNK_DEPTH
		}
		return glm.dot(p.xyz, vert) + p.w >= 0
	}

	return(
		check(f.left, pos) &&
		check(f.right, pos) &&
		check(f.far, pos) &&
		check(f.near, pos) &&
		check(f.top, pos) &&
		check(f.bottom, pos) \
	)
}

get_frustum_indices :: proc() -> []u32 {
	@(static, rodata)
	FRUSTUM_LINE_INDICES := []u32 {
		0,
		1,
		1,
		2,
		2,
		3,
		3,
		0,
		4,
		5,
		5,
		6,
		6,
		7,
		7,
		4,
		0,
		4,
		1,
		5,
		2,
		6,
		3,
		7,
	}
	return FRUSTUM_LINE_INDICES
}
