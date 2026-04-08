package mou

import "core:fmt"
import "core:log"
import "core:strings"
import gl "vendor:OpenGL"

Debug_Source :: enum u32 {
	API             = gl.DEBUG_SOURCE_API,
	Window_System   = gl.DEBUG_SOURCE_WINDOW_SYSTEM,
	Shader_Compiler = gl.DEBUG_SOURCE_SHADER_COMPILER,
	Third_Party     = gl.DEBUG_SOURCE_THIRD_PARTY,
	Application     = gl.DEBUG_SOURCE_APPLICATION,
	Other           = gl.DEBUG_SOURCE_OTHER,
}

Debug_Type :: enum u32 {
	Error               = gl.DEBUG_TYPE_ERROR,
	Deprecated_Behavior = gl.DEBUG_TYPE_DEPRECATED_BEHAVIOR,
	Undefined_Behavior  = gl.DEBUG_TYPE_UNDEFINED_BEHAVIOR,
	Portability         = gl.DEBUG_TYPE_PORTABILITY,
	Performance         = gl.DEBUG_TYPE_PERFORMANCE,
	Other               = gl.DEBUG_TYPE_OTHER,
	Marker              = gl.DEBUG_TYPE_MARKER,
	Push_Group          = gl.DEBUG_TYPE_PUSH_GROUP,
	Pop_Group           = gl.DEBUG_TYPE_POP_GROUP,
}

Debug_Severity :: enum u32 {
	High         = gl.DEBUG_SEVERITY_HIGH,
	Medium       = gl.DEBUG_SEVERITY_MEDIUM,
	Low          = gl.DEBUG_SEVERITY_LOW,
	Notification = gl.DEBUG_SEVERITY_NOTIFICATION,
}


@(disabled = !ODIN_DEBUG)
setup_opengl_debug :: proc() {
	gl.Enable(gl.DEBUG_OUTPUT)
	gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
	gl.DebugMessageCallback(
		proc "c" (
			source_: u32,
			type_: u32,
			id: u32,
			severity_: u32,
			length: i32,
			message: cstring,
			user_data: rawptr,
		) {
			context = default_context()

			source := cast(Debug_Source)source_
			type := cast(Debug_Source)type_
			severity := cast(Debug_Severity)severity_
			msg := strings.string_from_ptr(cast([^]u8)message, cast(int)length)
			
					// odinfmt:disable
			level: log.Level
			switch severity {
			case .Notification: level = .Debug
			case .Low:          level = .Info
			case .Medium:       level = .Warning
			case .High:         level = .Error
			}
			// odinfmt:enable

			log.log(level, fmt.tprintf("[OPENGL] {}, {}, {}: {}", source, type, id, msg))
		},
		nil,
	)
}

@(disabled = !ODIN_DEBUG)
push_debug_group :: proc(message: string, loc := #caller_location) {
	gl.PushDebugGroup(
		gl.DEBUG_SOURCE_APPLICATION,
		0,
		cast(i32)len(message),
		strings.unsafe_string_to_cstring(message),
		loc = loc,
	)

}

@(disabled = !ODIN_DEBUG)
pop_debug_group :: proc(loc := #caller_location) {
	gl.PopDebugGroup(loc = loc)
}

@(disabled = !ODIN_DEBUG, deferred_in = debug_group_end)
debug_group :: proc(message: string, loc := #caller_location) {
	push_debug_group(message, loc = loc)
}

@(disabled = !ODIN_DEBUG)
debug_group_end :: proc(_: string, loc := #caller_location) {
	pop_debug_group(loc = loc)
}
