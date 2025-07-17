package mou

import "core:log"
import glm "core:math/linalg/glsl"
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

get_uniform_location :: proc(shader: Shader, name: cstring) -> i32 {
	return gl.GetUniformLocation(shader.handle, name)
}

set_uniform_mat2 :: proc(shader: Shader, name: cstring, val: glm.mat2) {
	val := val
	gl.UniformMatrix2fv(get_uniform_location(shader, name), 1, false, &val[0, 0])
}

set_uniform_mat3 :: proc(shader: Shader, name: cstring, val: glm.mat3) {
	val := val
	gl.UniformMatrix3fv(get_uniform_location(shader, name), 1, false, &val[0, 0])
}

set_uniform_mat4 :: proc(shader: Shader, name: cstring, val: glm.mat4) {
	val := val
	gl.UniformMatrix4fv(get_uniform_location(shader, name), 1, false, &val[0, 0])
}

set_uniform_f32 :: proc(shader: Shader, name: cstring, val: f32) {
	gl.Uniform1f(get_uniform_location(shader, name), val)
}

set_uniform_i32 :: proc(shader: Shader, name: cstring, val: i32) {
	gl.Uniform1i(get_uniform_location(shader, name), val)
}

set_uniform_u32 :: proc(shader: Shader, name: cstring, val: u32) {
	gl.Uniform1ui(get_uniform_location(shader, name), val)
}

set_uniform_vec2 :: proc(shader: Shader, name: cstring, val: glm.vec2) {
	gl.Uniform2f(get_uniform_location(shader, name), val.x, val.y)
}

set_uniform_vec3 :: proc(shader: Shader, name: cstring, val: glm.vec3) {
	gl.Uniform3f(get_uniform_location(shader, name), val.x, val.y, val.z)
}

set_uniform_vec4 :: proc(shader: Shader, name: cstring, val: glm.vec4) {
	gl.Uniform4f(get_uniform_location(shader, name), val.x, val.y, val.z, val.w)
}

set_uniform_ivec2 :: proc(shader: Shader, name: cstring, val: glm.ivec2) {
	gl.Uniform2i(get_uniform_location(shader, name), val.x, val.y)
}

set_uniform_ivec3 :: proc(shader: Shader, name: cstring, val: glm.ivec3) {
	gl.Uniform3i(get_uniform_location(shader, name), val.x, val.y, val.z)
}

set_uniform_ivec4 :: proc(shader: Shader, name: cstring, val: glm.ivec4) {
	gl.Uniform4i(get_uniform_location(shader, name), val.x, val.y, val.z, val.w)
}

set_uniform_uvec2 :: proc(shader: Shader, name: cstring, val: glm.uvec2) {
	gl.Uniform2ui(get_uniform_location(shader, name), val.x, val.y)
}

set_uniform_uvec3 :: proc(shader: Shader, name: cstring, val: glm.uvec3) {
	gl.Uniform3ui(get_uniform_location(shader, name), val.x, val.y, val.z)
}

set_uniform_uvec4 :: proc(shader: Shader, name: cstring, val: glm.uvec4) {
	gl.Uniform4ui(get_uniform_location(shader, name), val.x, val.y, val.z, val.w)
}

set_uniform_rgba :: proc(shader: Shader, name: cstring, val: RGBA) {
	set_uniform(shader, name, transmute(u32)val)
}

set_uniform_rgba32 :: proc(shader: Shader, name: cstring, val: RGBA32) {
	set_uniform(shader, name, cast(glm.vec4)val)
}

set_uniform :: proc {
	set_uniform_mat2,
	set_uniform_mat3,
	set_uniform_mat4,
	set_uniform_f32,
	set_uniform_i32,
	set_uniform_u32,
	set_uniform_vec2,
	set_uniform_vec3,
	set_uniform_vec4,
	set_uniform_ivec2,
	set_uniform_ivec3,
	set_uniform_ivec4,
	set_uniform_uvec2,
	set_uniform_uvec3,
	set_uniform_uvec4,
	set_uniform_rgba,
	set_uniform_rgba32,
}
