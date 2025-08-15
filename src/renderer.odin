package mou

Renderer :: struct {
	vao:      Vertex_Array,
	vbo:      Buffer,
	ebo:      Buffer,
	shader:   Shader,
	_indexed: bool,
}

make_renderer :: proc(indexed: bool, shader: Shader, usage: Buffer_Usage) -> (r: Renderer) {
	r.vao = make_vertex_array()
	r.vbo = make_buffer(.Array, usage)
	if indexed {
		r.ebo = make_buffer(.Element_Array, usage)
	}
	r.shader = shader
	r._indexed = indexed
	return
}

destroy_renderer :: proc(r: ^Renderer) {
	if r._indexed {
		destroy_buffer(&r.ebo)
	}
	destroy_buffer(&r.vbo)
	destroy_vertex_array(&r.vao)
	r^ = {}
}

bind_renderer :: proc(r: Renderer) {
	bind_vertex_array(r.vao)
	if r._indexed {
		bind_buffer(r.ebo)
	}
	bind_buffer(r.vbo)
	use_shader(r.shader)
}

unbind_renderer :: proc() {
	defer unbind_vertex_array()
	defer unbind_buffer(.Array)
}

renderer_vertices :: proc(r: Renderer, verts: $S/[]$T, loc := #caller_location) {
	buffer_data(r.vbo, verts, loc = loc)
}

renderer_indices :: proc(r: Renderer, indices: $S/[][$N]u32, loc := #caller_location) {
	assert(r._indexed, #procedure + " called on un-indexed renderer")
	buffer_data(r.ebo, indices, loc = loc)
}

renderer_sub_vertices :: proc(r: Renderer, offset: int, verts: $S/[]$T, loc := #caller_location) {
	buffer_sub_data(r.vbo, offset, verts, loc = loc)
}

renderer_sub_indices :: proc(
	r: Renderer,
	offset: int,
	indices: $S/[][$N]u32,
	loc := #caller_location,
) {
	assert(r._indexed, #procedure + " called on un-indexed renderer")
	buffer_sub_data(r.ebo, offset, indices, loc = loc)
}
