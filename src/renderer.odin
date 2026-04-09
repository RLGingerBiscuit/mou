package mou

import "base:intrinsics"

Renderer :: struct {
	vao:      Vertex_Array,
	vbo:      Vertex_Buffer,
	ebo:      Index_Buffer,
	shader:   Shader,
	_indexed: bool,
}

make_renderer :: proc(indexed: bool, shader: Shader, usage: Buffer_Usage) -> (r: Renderer) {
	r.vao = make_vertex_array()
	r.vbo = make_vertex_buffer(usage)
	if indexed {
		r.ebo = make_index_buffer(usage)
		vertex_array_index_buffer(r.vao, r.ebo)
	}
	r.shader = shader
	r._indexed = indexed
	return
}

destroy_renderer :: proc(r: ^Renderer) {
	if r._indexed {
		destroy_index_buffer(&r.ebo)
	}
	destroy_vertex_buffer(&r.vbo)
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

renderer_vertices :: proc(r: Renderer, verts: $S/[]$T, loc := #caller_location) {
	vertex_buffer_data(r.vbo, verts, loc = loc)
}

renderer_indices :: proc(r: Renderer, indices: $S/[]$T, loc := #caller_location) {
	assert(r._indexed, #procedure + " called on un-indexed renderer")
	index_buffer_data(r.ebo, indices, loc = loc)
}

renderer_sub_vertices :: proc(r: Renderer, offset: int, verts: $S/[]$T, loc := #caller_location) {
	vertex_buffer_sub_data(r.vbo, offset, verts, loc = loc)
}

renderer_sub_indices :: proc(r: Renderer, offset: int, indices: $S/[]$T, loc := #caller_location) {
	assert(r._indexed, #procedure + " called on un-indexed renderer")
	index_buffer_sub_data(r.ebo, offset, indices, loc = loc)
}

renderer_vertex_layout :: proc(
	r: Renderer,
	$T: typeid,
	loc := #caller_location,
) where intrinsics.type_is_struct(T) {
	vertex_attrib_vert(r.vao, r.vbo, T, loc = loc)
}
