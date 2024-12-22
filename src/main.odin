package mou

import "base:runtime"
import sa "core:container/small_array"
import "core:log"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import "core:sync"
import gl "vendor:OpenGL"
import "vendor:glfw"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_SIZE :: [2]i32{WINDOW_WIDTH, WINDOW_HEIGHT}
WINDOW_TITLE :: "Goofin Minecraft Clone"

DEFAULT_RENDER_DISTANCE :: 4
MAX_RENDER_DISTANCE :: 8
DEFAULT_FOV :: 45
NEAR_PLANE :: 0.1

when ODIN_DEBUG {
	tracking_allocator: mem.Tracking_Allocator
}

_ :: mem

when ODIN_DEBUG {
	MIN_LOG_LEVEL :: log.Level.Debug
} else {
	MIN_LOG_LEVEL :: log.Level.Warning
}

logger: log.Logger
init_logger :: proc() -> log.Logger {
	logger = log.create_console_logger(
		MIN_LOG_LEVEL,
		ident = "logl",
		opt = log.Default_Console_Logger_Opts ~ {.Terminal_Color},
	)
	return logger
}

default_context :: proc() -> runtime.Context {
	ctx := runtime.default_context()
	when ODIN_DEBUG {
		assert(tracking_allocator.backing.procedure != nil)
		assert(logger.data != nil)
		ctx.allocator = mem.tracking_allocator(&tracking_allocator)
		ctx.logger = logger
	}
	return ctx
}

main :: proc() {
	context.logger = init_logger()
	defer log.destroy_console_logger(logger)

	when ODIN_DEBUG {
		log.debug("Initialising tracking allocator")
		mem.tracking_allocator_init(&tracking_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		defer {
			total_leaked := 0
			for _, alloc in tracking_allocator.allocation_map {
				log.debugf("{}: Leaked {} bytes", alloc.location, alloc.size)
				total_leaked += alloc.size
			}
			if total_leaked > 0 {
				log.debugf("In total leaked {} bytes", total_leaked)
			}
		}
	}

	log.info("Hellope!")

	log.debug("Initialising GLFW")
	if !glfw.Init() {
		desc, code := glfw.GetError()
		log.fatal("Error initialising GLFW ({}): {}", code, desc)
		os.exit(1)
	}
	defer {
		log.debug("Terminating GLFW")
		glfw.Terminate()
	}

	state: State
	state.render_distance = DEFAULT_RENDER_DISTANCE
	state.fog_enabled = true
	state.far_plane = true

	init_camera(
		&state.camera,
		pos = {0, 17, 0},
		yaw = 90,
		pitch = 0,
		speed = 5,
		sensitivity = 0.1,
		fov = DEFAULT_FOV,
	)

	window_ok := init_window(&state, WINDOW_TITLE, WINDOW_SIZE, vsync = false, visible = false)
	if !window_ok {
		os.exit(1)
	}
	defer destroy_window(&state.window)

	glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)

	gl.Enable(gl.DEPTH_TEST)
	gl.Enable(gl.CULL_FACE)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	shader := make_shader("assets/shaders/basic.vert", "assets/shaders/basic.frag")
	defer destroy_shader(&shader)

	atlas := make_atlas("assets/textures/")
	defer destroy_atlas(&atlas)

	init_world(&state.world, &atlas)
	defer destroy_world(&state.world)

	if sync.guard(&state.world.lock) {
		N := state.render_distance
		for y in i32(-N) ..= N {
			for z in i32(-N) ..= N {
				for x in i32(-N) ..= N {
					world_generate_chunk(&state.world, {x, y, z})
				}
			}
		}
	}

	vao := make_vertex_array()
	vbo := make_buffer(.Array, .Dynamic)
	transparent_vbo := make_buffer(.Array, .Dynamic)

	{
		MAX_VERTEX_SIZE :: (CHUNK_SIZE * 6 * 6) * 5
		temp := make([]f32, MAX_VERTEX_SIZE, context.temp_allocator)
		defer delete(temp, context.temp_allocator)

		bind_vertex_array(vao)

		bind_buffer(vbo)
		buffer_data(vbo, temp)

		bind_buffer(transparent_vbo)
		buffer_data(transparent_vbo, temp)

		unbind_buffer(.Array)
		unbind_vertex_array()
	}

	mu_init_ui(&state)
	defer mu_destroy_ui(&state)

	show_window(&state.window)

	window_center_cursor(&state.window)

	gl.LineWidth(4)

	previous_time := glfw.GetTime()
	for !window_should_close(state.window) {
		current_time := glfw.GetTime()
		delta_time := current_time - previous_time
		previous_time = current_time

		{ 	// Update
			if window_get_key(state.window, .Escape) == .Press {
				log.debugf("Escape pressed, closing window")
				set_window_should_close(state.window, true)
			}

			mu_update_ui(&state, delta_time)

			update_camera(&state.camera, &state.window, delta_time)
			update_window(&state.window)

			// TODO: Don't forget to turn this back on nerd
			if false {
				// if sync.guard(&state.world.lock) {
				N := i32(1.2 * f32(state.render_distance))

				global_pos := glm.ivec3 {
					i32(state.camera.pos.x),
					i32(state.camera.pos.y),
					i32(state.camera.pos.z),
				}
				cam_chunk_pos := global_pos_to_chunk_pos(global_pos)
				cam_chunk_pos.y = 0
				for y in i32(-N) ..< N {
					for z in i32(-N) ..< N {
						for x in i32(-N) ..< N {
							chunk_pos := cam_chunk_pos + {x, y, z}
							if !world_generate_chunk(&state.world, chunk_pos) {
								chunk := &state.world.chunks[chunk_pos]
								if len(chunk.opaque_mesh) == 0 {
									world_mark_chunk_remesh(&state.world, chunk)
								}
							}
						}
					}
				}

				@(static) chunks_to_demesh: sa.Small_Array(MAX_RENDER_DISTANCE * 16, glm.ivec3)

				for chunk_pos in state.world.chunks {
					if len(state.world.chunks[chunk_pos].opaque_mesh) > 0 &&
						   glm.abs(cam_chunk_pos.x - chunk_pos.x) > N ||
					   glm.abs(cam_chunk_pos.z - chunk_pos.z) > N {
						sa.append_elem(&chunks_to_demesh, chunk_pos)
					}
				}

				for chunk_pos in sa.slice(&chunks_to_demesh) {
					chunk := &state.world.chunks[chunk_pos]
					// TODO: separate chunks from mesh so mesh can be fully deleted
					// TODO: ensure chunks are also removed from remesh queue if they're in there for some reason
					clear(&chunk.opaque_mesh)
					clear(&chunk.transparent_mesh)
				}
				sa.clear(&chunks_to_demesh)
			}
		}

		{ 	// Draw
			SKY_COLOUR := glm.vec4{0.3, 0.6, 0.8, 1}

			gl.ClearColor(SKY_COLOUR[0], SKY_COLOUR[1], SKY_COLOUR[2], SKY_COLOUR[3])
			gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

			projection_matrix := get_projection_matrix(state)
			view_matrix := state.camera.view_matrix

			bind_vertex_array(vao)

			use_shader(shader)
			bind_texture(atlas.texture)
			u_mvp := projection_matrix * view_matrix
			gl.UniformMatrix4fv(
				gl.GetUniformLocation(shader.handle, "u_mvp"),
				1,
				false,
				&u_mvp[0, 0],
			)
			gl.Uniform3fv(
				gl.GetUniformLocation(shader.handle, "u_campos"),
				1,
				&state.camera.pos[0],
			)

			if state.fog_enabled {
				gl.Uniform1f(
					gl.GetUniformLocation(shader.handle, "fog_start"),
					f32(state.render_distance - 1) * CHUNK_WIDTH,
				)
				gl.Uniform1f(
					gl.GetUniformLocation(shader.handle, "fog_end"),
					f32(state.render_distance) * CHUNK_WIDTH,
				)
				gl.Uniform4fv(
					gl.GetUniformLocation(shader.handle, "fog_colour"),
					1,
					&SKY_COLOUR[0],
				)
			} else {
				gl.Uniform1f(gl.GetUniformLocation(shader.handle, "fog_start"), max(f32))
				gl.Uniform1f(gl.GetUniformLocation(shader.handle, "fog_end"), max(f32))
			}

			sync.shared_guard(&state.world.lock)

			bind_buffer(vbo)
			gl.Enable(gl.CULL_FACE)
			vertex_attrib_pointer(0, 3, .Float, false, 5 * size_of(f32), 0)
			vertex_attrib_pointer(1, 2, .Float, false, 5 * size_of(f32), 3 * size_of(f32))
			for _, &chunk in state.world.chunks {
				if len(chunk.opaque_mesh) > 0 {
					buffer_sub_data(vbo, 0, chunk.opaque_mesh[:])
					gl.DrawArrays(gl.TRIANGLES, 0, cast(i32)len(chunk.opaque_mesh) / 3)
				}
			}

			bind_buffer(transparent_vbo)
			gl.Disable(gl.CULL_FACE)
			vertex_attrib_pointer(0, 3, .Float, false, 5 * size_of(f32), 0)
			vertex_attrib_pointer(1, 2, .Float, false, 5 * size_of(f32), 3 * size_of(f32))
			for _, &chunk in state.world.chunks {
				if len(chunk.transparent_mesh) > 0 {
					buffer_sub_data(vbo, 0, chunk.transparent_mesh[:])
					gl.DrawArrays(gl.TRIANGLES, 0, cast(i32)len(chunk.transparent_mesh) / 3)
				}
			}

			unbind_buffer(.Array)
			unbind_vertex_array()

			mu_render_ui(&state)
		}

		window_swap_buffers(state.window)
		glfw.PollEvents()

		when ODIN_DEBUG {
			for bad_free in tracking_allocator.bad_free_array {
				log.errorf("Bad free {} at {}\n", bad_free.memory, bad_free.location)
			}
			if len(tracking_allocator.bad_free_array) > 0 {
				os.exit(1)
			}
			clear(&tracking_allocator.bad_free_array)
		}
		free_all(context.temp_allocator)
	}
}
