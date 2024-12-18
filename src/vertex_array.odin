package mou

import gl "vendor:OpenGL"

Vertex_Array :: struct {
	handle: u32,
}

make_vertex_array :: proc() -> (vao: Vertex_Array) {
	gl.GenVertexArrays(1, &vao.handle)
	return
}

destroy_vertex_array :: proc(vao: ^Vertex_Array) {
	gl.DeleteVertexArrays(1, &vao.handle)
	vao^ = {}
}

bind_vertex_array :: proc(vao: Vertex_Array) {
	gl.BindVertexArray(vao.handle)
}

unbind_vertex_array :: proc() {
	gl.BindVertexArray(0)
}

vertex_attrib_pointer :: proc(
	index: u32,
	size: i32,
	type: Data_Type,
	normalized: bool,
	stride: i32,
	pointer: uintptr,
) {
	gl.VertexAttribPointer(index, size, cast(u32)type, normalized, stride, pointer)
	gl.EnableVertexAttribArray(index)
}

vertex_attrib_i_pointer :: proc(
	index: u32,
	size: i32,
	type: Data_Type,
	stride: i32,
	pointer: uintptr,
) {
	gl.VertexAttribIPointer(index, size, cast(u32)type, stride, pointer)
	gl.EnableVertexAttribArray(index)
}
