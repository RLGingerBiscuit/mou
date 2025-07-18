package mou

import "core:fmt"
import "core:log"
import glm "core:math/linalg/glsl"
import "core:os"
import path "core:path/filepath"
import "core:strings"
import gl "vendor:OpenGL"

// Only in debug
_ :: fmt

Uniform :: struct {
	type:     Data_Type,
	size:     i32,
	location: i32,
}

Shader :: struct {
	handle:   u32,
	uniforms: map[string]Uniform,
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

	uniform_count: i32
	gl.GetProgramiv(shader.handle, gl.ACTIVE_UNIFORMS, &uniform_count)
	if uniform_count == 0 {
		return
	}

	shader.uniforms = make(map[string]Uniform, uniform_count)

	max_name_len: i32
	gl.GetProgramiv(shader.handle, gl.ACTIVE_UNIFORM_MAX_LENGTH, &max_name_len)

	name_buf := make([]u8, max_name_len, context.temp_allocator)
	defer delete(name_buf, context.temp_allocator)

	name_len, size: i32
	type: u32
	for i in 0 ..< uniform_count {
		gl.GetActiveUniform(
			shader.handle,
			u32(i),
			max_name_len,
			&name_len,
			&size,
			&type,
			raw_data(name_buf),
		)

		name, err := strings.clone_from_cstring_bounded(
			cast(cstring)raw_data(name_buf),
			cast(int)name_len,
		)
		assert(err == nil)

		shader.uniforms[name] = Uniform {
			type     = cast(Data_Type)type,
			size     = size,
			location = i,
		}
	}

	return
}

destroy_shader :: proc(shader: ^Shader) {
	for name, _ in shader.uniforms {
		delete(name)
	}
	delete(shader.uniforms)
	gl.DeleteProgram(shader.handle)
	shader^ = {}
}

use_shader :: proc(shader: Shader) {
	gl.UseProgram(shader.handle)
}

get_uniform :: proc(
	shader: Shader,
	name: string,
	loc := #caller_location,
) -> (
	uniform: Uniform,
	ok: bool,
) {
	uniform, ok = shader.uniforms[name]
	assert(ok, fmt.tprintf("Could not find uniform '{}'", name), loc = loc)
	return uniform, true
}

set_uniform_mat2 :: proc(
	shader: Shader,
	name: string,
	val: glm.mat2,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	val := val
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Float_Mat2,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Float_Mat2,
			uniform.type,
		),
		loc = loc,
	)
	gl.UniformMatrix2fv(uniform.location, 1, false, &val[0, 0])
	return true
}

set_uniform_mat3 :: proc(
	shader: Shader,
	name: string,
	val: glm.mat3,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	val := val
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Float_Mat3,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Float_Mat3,
			uniform.type,
		),
		loc = loc,
	)
	gl.UniformMatrix3fv(uniform.location, 1, false, &val[0, 0])
	return true
}

set_uniform_mat4 :: proc(
	shader: Shader,
	name: string,
	val: glm.mat4,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	val := val
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Float_Mat4,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Float_Mat4,
			uniform.type,
		),
		loc = loc,
	)
	gl.UniformMatrix4fv(uniform.location, 1, false, &val[0, 0])
	return true
}

set_uniform_f32 :: proc(
	shader: Shader,
	name: string,
	val: f32,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Float,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Float,
			uniform.type,
		),
		loc = loc,
	)
	gl.Uniform1f(uniform.location, val)
	return true
}

set_uniform_i32 :: proc(
	shader: Shader,
	name: string,
	val: i32,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Int,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Int,
			uniform.type,
		),
		loc = loc,
	)
	gl.Uniform1i(uniform.location, val)
	return true
}

set_uniform_u32 :: proc(
	shader: Shader,
	name: string,
	val: u32,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Unsigned_Int,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Unsigned_Int,
			uniform.type,
		),
		loc = loc,
	)
	gl.Uniform1ui(uniform.location, val)
	return true
}

set_uniform_vec2 :: proc(
	shader: Shader,
	name: string,
	val: glm.vec2,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Float_Vec2,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Float_Vec2,
			uniform.type,
		),
		loc = loc,
	)
	gl.Uniform2f(uniform.location, val.x, val.y)
	return true
}

set_uniform_vec3 :: proc(
	shader: Shader,
	name: string,
	val: glm.vec3,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Float_Vec3,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Float_Vec3,
			uniform.type,
		),
		loc = loc,
	)
	gl.Uniform3f(uniform.location, val.x, val.y, val.z)
	return true
}

set_uniform_vec4 :: proc(
	shader: Shader,
	name: string,
	val: glm.vec4,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Float_Vec4,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Float_Vec4,
			uniform.type,
		),
		loc = loc,
	)
	gl.Uniform4f(uniform.location, val.x, val.y, val.z, val.w)
	return true
}

set_uniform_ivec2 :: proc(
	shader: Shader,
	name: string,
	val: glm.ivec2,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Int_Vec2,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Int_Vec2,
			uniform.type,
		),
		loc = loc,
	)
	gl.Uniform2i(uniform.location, val.x, val.y)
	return true
}

set_uniform_ivec3 :: proc(
	shader: Shader,
	name: string,
	val: glm.ivec3,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Int_Vec3,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Int_Vec3,
			uniform.type,
		),
		loc = loc,
	)
	gl.Uniform3i(uniform.location, val.x, val.y, val.z)
	return true
}

set_uniform_ivec4 :: proc(
	shader: Shader,
	name: string,
	val: glm.ivec4,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Int_Vec4,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Int_Vec4,
			uniform.type,
		),
		loc = loc,
	)
	gl.Uniform4i(uniform.location, val.x, val.y, val.z, val.w)
	return true
}

set_uniform_uvec2 :: proc(
	shader: Shader,
	name: string,
	val: glm.uvec2,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Unsigned_Int_Vec2,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Unsigned_Int_Vec2,
			uniform.type,
		),
		loc = loc,
	)
	gl.Uniform2ui(uniform.location, val.x, val.y)
	return true
}

set_uniform_uvec3 :: proc(
	shader: Shader,
	name: string,
	val: glm.uvec3,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Unsigned_Int_Vec3,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Unsigned_Int_Vec3,
			uniform.type,
		),
		loc = loc,
	)
	gl.Uniform3ui(uniform.location, val.x, val.y, val.z)
	return true
}

set_uniform_uvec4 :: proc(
	shader: Shader,
	name: string,
	val: glm.uvec4,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	uniform := get_uniform(shader, name, loc = loc) or_return
	assert(
		uniform.type == .Unsigned_Int_Vec4,
		fmt.tprintf(
			#procedure + " uniform type mismatch: expected {}, found {}",
			Data_Type.Unsigned_Int_Vec4,
			uniform.type,
		),
		loc = loc,
	)
	gl.Uniform4ui(uniform.location, val.x, val.y, val.z, val.w)
	return true
}

set_uniform_rgba :: proc(
	shader: Shader,
	name: string,
	val: RGBA,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	return set_uniform(shader, name, transmute(u32)val, loc = loc)
}

set_uniform_rgba32 :: proc(
	shader: Shader,
	name: string,
	val: RGBA32,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	return set_uniform(shader, name, cast(glm.vec4)val, loc = loc)
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
