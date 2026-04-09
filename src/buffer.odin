package mou

import gl "vendor:OpenGL"

Buffer_Usage :: enum u32 {
	Static  = gl.STATIC_DRAW,
	Dynamic = gl.DYNAMIC_DRAW,
	Stream  = gl.STREAM_DRAW,
}

destroy_buffer :: proc {
	destroy_vertex_buffer,
	destroy_index_buffer,
}

buffer_data :: proc {
	vertex_buffer_data,
	index_buffer_data,
}

buffer_sub_data :: proc {
	vertex_buffer_sub_data,
	index_buffer_sub_data,
}
