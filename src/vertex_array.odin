package mou

import "base:intrinsics"
import "core:fmt"
import "core:reflect"
import "core:strings"
import gl "vendor:OpenGL"

Vertex_Array :: struct {
	handle: u32,
}

make_vertex_array :: proc(loc := #caller_location) -> (vao: Vertex_Array) {
	when ODIN_DEBUG {
		gl.CreateVertexArrays(1, &vao.handle, loc = loc)
	} else {
		gl.CreateVertexArrays(1, &vao.handle)
	}
	return
}

destroy_vertex_array :: proc(vao: ^Vertex_Array, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.DeleteVertexArrays(1, &vao.handle, loc = loc)
	} else {
		gl.DeleteVertexArrays(1, &vao.handle)
	}
	vao^ = {}
}

bind_vertex_array :: proc(vao: Vertex_Array, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.BindVertexArray(vao.handle, loc = loc)
	} else {
		gl.BindVertexArray(vao.handle)
	}
}

unbind_vertex_array :: proc(loc := #caller_location) {
	when ODIN_DEBUG {
		gl.BindVertexArray(0, loc = loc)
	} else {
		gl.BindVertexArray(0)
	}
}

vertex_array_vertex_buffer :: proc(
	vao: Vertex_Array,
	binding_index: u32,
	buffer: Vertex_Buffer,
	offset: int,
	stride: i32,
	loc := #caller_location,
) {
	when ODIN_DEBUG {
		gl.VertexArrayVertexBuffer(
			vao.handle,
			binding_index,
			buffer.handle,
			offset,
			stride,
			loc = loc,
		)
	} else {
		gl.VertexArrayVertexBuffer(vao.handle, binding_index, buffer.handle, offset, stride)
	}
}

vertex_array_index_buffer :: proc(
	vao: Vertex_Array,
	buffer: Index_Buffer,
	loc := #caller_location,
) {
	when ODIN_DEBUG {
		gl.VertexArrayElementBuffer(vao.handle, buffer.handle, loc = loc)
	} else {
		gl.VertexArrayElementBuffer(vao.handle, buffer.handle)
	}
}

vertex_array_attrib_pointer :: proc(
	vao: Vertex_Array,
	binding_index: u32,
	index: u32,
	size: i32,
	type: Data_Type,
	normalized: bool,
	relative_offset: u32,
	loc := #caller_location,
) {
	when ODIN_DEBUG {
		gl.VertexArrayAttribFormat(
			vao.handle,
			index,
			size,
			cast(u32)type,
			normalized,
			relative_offset,
			loc = loc,
		)
		gl.VertexArrayAttribBinding(vao.handle, index, binding_index, loc = loc)
		gl.EnableVertexArrayAttrib(vao.handle, index, loc = loc)
	} else {
		gl.VertexArrayAttribFormat(
			vao.handle,
			index,
			size,
			cast(u32)type,
			normalized,
			relative_offset,
		)
		gl.VertexArrayAttribBinding(vao.handle, index, binding_index)
		gl.EnableVertexArrayAttrib(vao.handle, index)
	}
}

vertex_array_attrib_i_pointer :: proc(
	vao: Vertex_Array,
	binding_index: u32,
	index: u32,
	size: i32,
	type: Data_Type,
	relative_offset: u32,
	loc := #caller_location,
) {
	when ODIN_DEBUG {
		gl.VertexArrayAttribIFormat(
			vao.handle,
			index,
			size,
			cast(u32)type,
			relative_offset,
			loc = loc,
		)
		gl.VertexArrayAttribBinding(vao.handle, index, binding_index, loc = loc)
		gl.EnableVertexArrayAttrib(vao.handle, index, loc = loc)
	} else {
		gl.VertexArrayAttribIFormat(vao.handle, index, size, cast(u32)type, relative_offset)
		gl.VertexArrayAttribBinding(vao.handle, index, binding_index)
		gl.EnableVertexArrayAttrib(vao.handle, index)
	}
}

vertex_attrib_vert :: proc(
	vao: Vertex_Array,
	buffer: Vertex_Buffer,
	$T: typeid,
	binding_index := u32(0),
	loc := #caller_location,
) where intrinsics.type_is_struct(T) {
	fields := reflect.struct_fields_zipped(T)
	ti := type_info_of(T)
	tin := ti.variant.(reflect.Type_Info_Named)
	tib := reflect.type_info_base(ti)
	tis := tib.variant.(reflect.Type_Info_Struct)

	if .packed not_in tis.flags {
		panic(fmt.tprintf(#procedure + ": {} is not packed!", typeid_of(T)))
	}

	vertex_array_vertex_buffer(vao, binding_index, buffer, 0, size_of(T), loc = loc)

	type: Data_Type

	for field, i in fields {
		tag := reflect.struct_tag_get(field.tag, "vert")

		#partial switch v in reflect.type_info_base(field.type).variant {
		case reflect.Type_Info_Integer:
			switch field.type.size {
			case 4:
				type = v.signed ? .Int : .Unsigned_Int
			case:
				unimplemented(
					fmt.tprintf(
						"{}.{} : Unimplemented type {}",
						tin.name,
						field.name,
						field.type.id,
					),
				)
			}

			vertex_array_attrib_i_pointer(
				vao,
				binding_index,
				u32(i),
				1,
				type,
				cast(u32)field.offset,
				loc = loc,
			)

		case reflect.Type_Info_Float:
			switch field.type.size {
			case 4:
				type = .Float
			case:
				unimplemented(
					fmt.tprintf(
						"{}.{} : Unimplemented type {}",
						tin.name,
						field.name,
						field.type.id,
					),
				)
			}

			vertex_array_attrib_pointer(
				vao,
				binding_index,
				u32(i),
				1,
				type,
				false,
				cast(u32)field.offset,
				loc = loc,
			)

		case reflect.Type_Info_Array:
			if v.count > 4 {
				unimplemented(
					fmt.tprintf(
						"{}.{} : Unimplemented type {}",
						tin.name,
						field.name,
						field.type.id,
					),
				)
			}

			// NOTE: Special case for RGBA colour
			if v.count == 4 && v.elem.id == u8 && !strings.equal_fold(tag, "raw") {
				vertex_array_attrib_i_pointer(
					vao,
					binding_index,
					u32(i),
					1,
					.Unsigned_Int,
					cast(u32)field.offset,
					loc = loc,
				)
				continue
			}

			#partial switch ev in reflect.type_info_base(v.elem).variant {
			case reflect.Type_Info_Integer:
				switch v.elem.size {
				case 4:
					type = ev.signed ? .Int : .Unsigned_Int
				case:
					unimplemented(
						fmt.tprintf(
							"{}.{} : Unimplemented type {}",
							tin.name,
							field.name,
							field.type.id,
						),
					)
				}

				vertex_array_attrib_i_pointer(
					vao,
					binding_index,
					u32(i),
					i32(v.count),
					type,
					cast(u32)field.offset,
					loc = loc,
				)

			case reflect.Type_Info_Float:
				switch v.elem.size {
				case 4:
					type = .Float
				case:
					unimplemented(
						fmt.tprintf(
							"{}.{} : Unimplemented type {}",
							tin.name,
							field.name,
							field.type.id,
						),
					)
				}

				vertex_array_attrib_pointer(
					vao,
					binding_index,
					u32(i),
					i32(v.count),
					type,
					false,
					cast(u32)field.offset,
					loc = loc,
				)

			case:
				unimplemented(
					fmt.tprintf(
						"{}.{} : Unimplemented type {}",
						tin.name,
						field.name,
						field.type.id,
					),
				)
			}

		case:
			unimplemented(
				fmt.tprintf("{}.{} : Unimplemented type {}", tin.name, field.name, field.type.id),
			)
		}


	}
}
