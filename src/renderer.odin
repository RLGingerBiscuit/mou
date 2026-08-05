package mou

import "base:intrinsics"
import gl "vendor:OpenGL"

Renderer_Flag :: enum {
	Indexed,
	Owns_VBO,
	Owns_EBO,
}
Renderer_Flags :: bit_set[Renderer_Flag]

Renderer :: struct {
	vao:    Vertex_Array,
	vbo:    Vertex_Buffer,
	ebo:    Index_Buffer,
	shader: Shader,
	stride: i32,
	flags:  Renderer_Flags,
}

make_renderer :: proc(
	shader: Shader,
	usage: Buffer_Usage,
	flags: Renderer_Flags = {},
	loc := #caller_location,
) -> (
	r: Renderer,
) {
	assert(
		.Owns_EBO not_in flags || .Indexed in flags,
		#procedure + "renderer flag .Owns_EBO requires .Indexed",
		loc = loc,
	)

	r.vao = make_vertex_array()
	if .Owns_VBO in flags {
		r.vbo = make_vertex_buffer(usage)
	}
	if .Owns_EBO in flags {
		r.ebo = make_index_buffer(usage)
		vertex_array_index_buffer(r.vao, r.ebo)
	}
	r.shader = shader
	r.flags = flags
	return
}

destroy_renderer :: proc(r: ^Renderer) {
	if .Owns_EBO in r.flags {
		destroy_index_buffer(&r.ebo)
	}
	if .Owns_VBO in r.flags {
		destroy_vertex_buffer(&r.vbo)
	}
	destroy_vertex_array(&r.vao)
	r^ = {}
}

bind_renderer :: proc(r: Renderer) {
	bind_vertex_array(r.vao)
	use_shader(r.shader)
}

unbind_renderer :: proc() {
	unbind_vertex_array()
}

renderer_vertices :: proc(r: ^Renderer, verts: $S/[]$T, loc := #caller_location) {
	vertex_buffer_data(r.vbo, verts, loc = loc)
}

renderer_indices :: proc(r: ^Renderer, indices: $S/[]$T, loc := #caller_location) {
	assert(
		.Indexed in r.flags && .Owns_EBO in r.flags,
		#procedure + " called on un-indexed renderer",
	)
	index_buffer_data(r.ebo, indices, loc = loc)
}

renderer_sub_vertices :: proc(r: ^Renderer, offset: int, verts: $S/[]$T, loc := #caller_location) {
	vertex_buffer_sub_data(r.vbo, offset, verts, loc = loc)
}

renderer_sub_indices :: proc(
	r: ^Renderer,
	offset: int,
	indices: $S/[]$T,
	loc := #caller_location,
) {
	assert(
		.Indexed in r.flags && .Owns_EBO in r.flags,
		#procedure + " called on un-indexed renderer",
	)
	index_buffer_sub_data(r.ebo, offset, indices, loc = loc)
}

renderer_vertex_layout :: proc(
	r: ^Renderer,
	$T: typeid,
	loc := #caller_location,
) where intrinsics.type_is_struct(T) {
	vertex_attrib_vert(r.vao, r.vbo, T, loc = loc)
	r.stride = size_of(T)
}

renderer_bind_vertices :: proc(r: ^Renderer, vbo: Vertex_Buffer) {
	vertex_array_vertex_buffer(r.vao, 0, vbo, 0, r.stride)
}

renderer_bind_indices :: proc(r: ^Renderer, ebo: Index_Buffer) {
	vertex_array_index_buffer(r.vao, ebo)
}

renderer_draw_indexed :: proc(
	r: Renderer,
	index_count: int,
	type: u32 = gl.UNSIGNED_INT,
	mode: u32 = gl.TRIANGLES,
) {
	assert(.Indexed in r.flags)
	gl.DrawElements(mode, i32(index_count), type, nil)
}

renderer_draw :: proc(r: Renderer, vertex_count: int, mode: u32 = gl.TRIANGLES) {
	gl.DrawArrays(mode, 0, i32(vertex_count))
}
