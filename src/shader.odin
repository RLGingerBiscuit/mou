package mou

import "core:log"
import "core:os"
import path "core:path/filepath"
import "core:strings"
import gl "vendor:OpenGL"

Shader :: struct {
	handle: u32,
}

make_shader :: proc(vert_path, frag_path: string) -> (shader: Shader) {
	load_shader :: proc(src_path: string, allocator := context.allocator) -> string {
		context.allocator = allocator

		src, ok := os.read_entire_file(src_path, context.temp_allocator)
		assert(ok)
		defer delete(src, context.temp_allocator)

		src_str := string(src)

		b := strings.builder_make(0, int(cast(f32)len(src_str) * 1.2))
		// defer resize(&b.buf, len(b.buf))

		for line in strings.split_lines_iterator(&src_str) {
			if !strings.starts_with(line, "#include ") {
				strings.write_string(&b, line)
				strings.write_byte(&b, '\n')
				continue
			}

			starts :: #force_inline proc(s: string, b: u8) -> bool {
				return s[0] == b
			}
			ends :: #force_inline proc(s: string, b: u8) -> bool {
				return s[len(s) - 1] == b
			}

			split := strings.split_after_n(line, "#include ", 2, context.temp_allocator)
			defer delete(split, context.temp_allocator)

			inc_path := split[1]
			if starts(inc_path, '"') || starts(inc_path, '\'') || starts(inc_path, '<') {
				inc_path = inc_path[1:]
			}
			if ends(inc_path, '"') || ends(inc_path, '\'') || ends(inc_path, '>') {
				inc_path = inc_path[:len(inc_path) - 1]
			}

			// TODO: implement proper relative paths and absolute paths
			inc_path = path.join({"assets/shaders/", inc_path}, context.temp_allocator)
			defer delete(inc_path, context.temp_allocator)

			if !os.exists(inc_path) {
				log.errorf("Could not find '{}' (included from '{}')", inc_path, src_path)
				os.exit(1)
			}

			inc_src := load_shader(inc_path, context.temp_allocator)
			defer delete(inc_src, context.temp_allocator)

			strings.write_string(&b, inc_src)
			strings.write_byte(&b, '\n')
		}

		return strings.to_string(b)
	}

	vert := load_shader(vert_path)
	defer delete(vert)
	frag := load_shader(frag_path)
	defer delete(frag)

	ok: bool
	shader.handle, ok = gl.load_shaders_source(vert, frag)
	if !ok {
		msg, type := gl.get_last_error_message()
		#partial switch type {
		case .VERTEX_SHADER:
			log.error(vert_path, type, msg)
		case .FRAGMENT_SHADER:
			log.error(frag_path, type, msg)
		case:
			log.error(type, msg)
		}
	}
	assert(ok)

	return
}

destroy_shader :: proc(shader: ^Shader) {
	gl.DeleteProgram(shader.handle)
	shader^ = {}
}

use_shader :: proc(shader: Shader) {
	gl.UseProgram(shader.handle)
}
