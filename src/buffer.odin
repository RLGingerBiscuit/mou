package mou

import gl "vendor:OpenGL"

Buffer_Target :: enum u32 {
	Array         = gl.ARRAY_BUFFER,
	Element_Array = gl.ELEMENT_ARRAY_BUFFER,
}

Buffer_Usage :: enum u32 {
	Static  = gl.STATIC_DRAW,
	Dynamic = gl.DYNAMIC_DRAW,
	Stream  = gl.STREAM_DRAW,
}

Buffer :: struct {
	handle: u32,
	target: Buffer_Target,
	usage:  Buffer_Usage,
}

make_buffer :: proc(
	target: Buffer_Target,
	usage: Buffer_Usage,
	loc := #caller_location,
) -> (
	buffer: Buffer,
) {
	when ODIN_DEBUG {
		gl.GenBuffers(1, &buffer.handle, loc = loc)
	} else {
		gl.GenBuffers(1, &buffer.handle)
	}
	buffer.target = target
	buffer.usage = usage
	return
}

destroy_buffer :: proc(buffer: ^Buffer, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.DeleteBuffers(1, &buffer.handle, loc = loc)
	} else {
		gl.DeleteBuffers(1, &buffer.handle)
	}
	buffer^ = {}
}

bind_buffer :: proc(buffer: Buffer, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.BindBuffer(cast(u32)buffer.target, buffer.handle, loc = loc)
	} else {
		gl.BindBuffer(cast(u32)buffer.target, buffer.handle)
	}
}

unbind_buffer :: proc(target: Buffer_Target, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.BindBuffer(cast(u32)target, 0, loc = loc)
	} else {
		gl.BindBuffer(cast(u32)target, 0)
	}
}

buffer_data :: proc(buffer: Buffer, data: $S/[]$T, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.BufferData(
			cast(u32)buffer.target,
			len(data) * size_of(T),
			raw_data(data),
			cast(u32)buffer.usage,
			loc = loc,
		)
	} else {
		gl.BufferData(
			cast(u32)buffer.target,
			len(data) * size_of(T),
			raw_data(data),
			cast(u32)buffer.usage,
		)
	}
}

buffer_sub_data :: proc(buffer: Buffer, offset: int, data: $S/[]$T, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.BufferSubData(
			cast(u32)buffer.target,
			offset,
			len(data) * size_of(T),
			raw_data(data),
			loc = loc,
		)
	} else {
		gl.BufferSubData(cast(u32)buffer.target, offset, len(data) * size_of(T), raw_data(data))
	}
}
