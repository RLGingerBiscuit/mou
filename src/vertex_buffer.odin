package mou

import gl "vendor:OpenGL"

Vertex_Buffer :: struct {
	handle: u32,
	usage:  Buffer_Usage,
}

make_vertex_buffer :: proc(
	usage: Buffer_Usage,
	loc := #caller_location,
) -> (
	buffer: Vertex_Buffer,
) {
	when ODIN_DEBUG {
		gl.CreateBuffers(1, &buffer.handle, loc = loc)
	} else {
		gl.CreateBuffers(1, &buffer.handle)
	}
	buffer.usage = usage
	return
}

destroy_vertex_buffer :: proc(buffer: ^Vertex_Buffer, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.DeleteBuffers(1, &buffer.handle, loc = loc)
	} else {
		gl.DeleteBuffers(1, &buffer.handle)
	}
	buffer^ = {}
}

vertex_buffer_data :: proc(buffer: Vertex_Buffer, data: $S/[]$T, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.NamedBufferData(
			buffer.handle,
			len(data) * size_of(T),
			raw_data(data),
			cast(u32)buffer.usage,
			loc = loc,
		)
	} else {
		gl.NamedBufferData(
			buffer.handle,
			len(data) * size_of(T),
			raw_data(data),
			cast(u32)buffer.usage,
		)
	}
}

vertex_buffer_sub_data :: proc(
	buffer: Vertex_Buffer,
	offset: int,
	data: $S/[]$T,
	loc := #caller_location,
) {
	when ODIN_DEBUG {
		gl.NamedBufferSubData(
			buffer.handle,
			offset,
			len(data) * size_of(T),
			raw_data(data),
			loc = loc,
		)
	} else {
		gl.NamedBufferSubData(buffer.handle, offset, len(data) * size_of(T), raw_data(data))
	}
}
