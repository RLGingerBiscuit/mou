package mou

import "base:intrinsics"
import "core:fmt"
import "core:reflect"
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

vertex_attrib_vert :: proc($T: typeid) where intrinsics.type_is_struct(T) {
	fields := reflect.struct_fields_zipped(T)
	ti := type_info_of(T)
	tin := ti.variant.(reflect.Type_Info_Named)
	tib := reflect.type_info_base(ti)
	tis := tib.variant.(reflect.Type_Info_Struct)

	if .packed not_in tis.flags {
		panic(fmt.tprintf(#procedure + ": {} is not packed!", typeid_of(T)))
	}

	type: Data_Type

	for field, i in fields {
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

			vertex_attrib_i_pointer(u32(i), 1, type, size_of(T), field.offset)

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

			vertex_attrib_pointer(u32(i), 1, type, false, size_of(T), field.offset)

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
			if v.count == 4 && v.elem.id == u8 {
				vertex_attrib_i_pointer(u32(i), 1, .Unsigned_Int, size_of(T), field.offset)
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

				vertex_attrib_i_pointer(u32(i), i32(v.count), type, size_of(T), field.offset)

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

				vertex_attrib_pointer(u32(i), i32(v.count), type, false, size_of(T), field.offset)

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
