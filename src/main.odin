package mou

import "base:runtime"
import "core:log"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:sync"
import gl "vendor:OpenGL"
import "vendor:glfw"

import rdoc "third:renderdoc"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_SIZE :: [2]i32{WINDOW_WIDTH, WINDOW_HEIGHT}
WINDOW_TITLE :: "Goofin Minecraft Clone"

DEFAULT_RENDER_DISTANCE :: 4
MAX_RENDER_DISTANCE :: 16
DEFAULT_FOV :: 45
NEAR_PLANE :: 0.001

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

	rdoc_lib, rdoc_api, rdoc_ok := rdoc.load_api()
	if rdoc_ok {
		log.debugf("loaded renderdoc {}", rdoc_api)
	}
	defer if rdoc_ok {
		rdoc.unload_api(rdoc_lib)
	}

	rdoc.SetCaptureFilePathTemplate(rdoc_api, "captures/cap")
	rdoc.SetCaptureKeys(rdoc_api, {})

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
	init_state(&state)
	defer destroy_state(&state)

	init_camera(
		&state,
		pos = {0, 17, 0},
		yaw = -90,
		pitch = 0,
		speed = 5,
		sensitivity = 0.1,
		fov = DEFAULT_FOV,
	)

	window_ok := init_window(&state, WINDOW_TITLE, WINDOW_SIZE, vsync = true, visible = false)
	if !window_ok {
		os.exit(1)
	}
	defer destroy_window(&state.window)

	glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)

	gl.Enable(gl.DEPTH_TEST)
	gl.Enable(gl.CULL_FACE)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	chunk_shader := make_shader("assets/shaders/chunk.vert", "assets/shaders/chunk.frag")
	defer destroy_shader(&chunk_shader)

	line_shader := make_shader("assets/shaders/line.vert", "assets/shaders/line.frag")
	defer destroy_shader(&line_shader)

	atlas := make_atlas("assets/textures/")
	defer destroy_atlas(&atlas)

	init_world(&state.world, &atlas)
	defer destroy_world(&state.world)

	{
		N := state.render_distance
		for y in i32(0) ..= 1 {
			for z in i32(-N) ..= N {
				for x in i32(-N) ..= N {
					sync.guard(&state.world.lock)
					world_generate_chunk(&state.world, {x, y, z})
				}
			}
		}
	}

	vao := make_vertex_array()
	defer destroy_vertex_array(&vao)
	vbo := make_buffer(.Array, .Dynamic)
	defer destroy_buffer(&vbo)
	transparent_vbo := make_buffer(.Array, .Dynamic)
	defer destroy_buffer(&transparent_vbo)
	water_vbo := make_buffer(.Array, .Dynamic)
	defer destroy_buffer(&water_vbo)

	{
		MAX_VERTEX_SIZE :: CHUNK_SIZE * size_of(Mesh_Face) * 3
		temp := make([]f32, MAX_VERTEX_SIZE, context.temp_allocator)
		defer delete(temp, context.temp_allocator)

		bind_vertex_array(vao)

		bind_buffer(vbo)
		buffer_data(vbo, temp)

		bind_buffer(transparent_vbo)
		buffer_data(transparent_vbo, temp)

		bind_buffer(water_vbo)
		buffer_data(water_vbo, temp)

		unbind_buffer(.Array)
		unbind_vertex_array()
	}

	line_vao := make_vertex_array()
	defer destroy_vertex_array(&line_vao)
	line_vbo := make_buffer(.Array, .Dynamic)
	defer destroy_buffer(&line_vbo)
	line_ebo := make_buffer(.Element_Array, .Static)
	defer destroy_buffer(&line_ebo)

	{
		@(static, rodata)
		VERTICES_TEMP := [8]glm.vec3{}

		bind_vertex_array(line_vao)

		bind_buffer(line_vbo)
		buffer_data(line_vbo, VERTICES_TEMP[:])

		bind_buffer(line_ebo)
		buffer_data(line_ebo, get_frustum_indices())

		vertex_attrib_pointer(0, 3, .Float, false, size_of(glm.vec3), 0)

		// unbind_buffer(.Array)
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

		capture_frame := false

		{ 	// Update
			if window_get_key(state.window, .Escape) == .Press {
				log.debugf("Escape pressed, closing window")
				set_window_should_close(state.window, true)
			}

			if rdoc_api != nil &&
			   window_get_key(state.window, .F1) == .Press &&
			   window_get_prev_key(state.window, .F1) != .Press {
				capture_frame = true
			}

			mu_update_ui(&state, delta_time)

			update_camera(&state, delta_time)
			update_window(&state.window)

			{
				N := i32(1.2 * f32(state.render_distance))
				global_pos := glm.ivec3 {
					i32(state.camera.pos.x),
					i32(state.camera.pos.y),
					i32(state.camera.pos.z),
				}
				cam_chunk_pos := global_pos_to_chunk_pos(global_pos)
				cam_chunk_pos.y = 0

				for y in i32(0) ..= 1 {
					for z in i32(-N) ..= N {
						for x in i32(-N) ..= N {
							chunk_pos := cam_chunk_pos + {x, y, z}
							sync.guard(&state.world.lock)
							if !world_generate_chunk(&state.world, chunk_pos) {
								chunk := &state.world.chunks[chunk_pos]
								// Chunk is generated, but needs to be sent for meshing
								if chunk.mesh == nil {
									world_mark_chunk_remesh(&state.world, chunk)
								}
							}
						}
					}
				}

				chunks_to_demesh := &state.frame.chunks_to_demesh
				defer clear(chunks_to_demesh)

				for _, &chunk in &state.world.chunks {
					if chunk.mesh != nil &&
					   (glm.abs(cam_chunk_pos.x - chunk.pos.x) > N ||
							   glm.abs(cam_chunk_pos.z - chunk.pos.z) > N) {
						append(chunks_to_demesh, &chunk)
					}
				}

				for chunk in chunks_to_demesh {
					world_mark_chunk_demesh(&state.world, chunk)
				}
			}

			world_update(&state.world, state.camera.pos)
		}

		{
			clear(&state.frame.memory_usage)
			for _, chunk in state.world.chunks {
				mesh := chunk.mesh
				if mesh == nil {continue}
				append(
					&state.frame.memory_usage,
					[7]int {
						len(mesh.opaque) * size_of(Mesh_Face),
						cap(mesh.opaque) * size_of(Mesh_Face),
						len(mesh.transparent) * size_of(Mesh_Face),
						cap(mesh.transparent) * size_of(Mesh_Face),
						len(chunk.blocks) * size_of(Block),
						len(mesh.water) * size_of(Mesh_Face),
						cap(mesh.water) * size_of(Mesh_Face),
					},
				)
			}
		}

		if capture_frame {
			log.debug("capturing frame")
			rdoc.StartFrameCapture(rdoc_api, nil, nil)
		}
		defer if capture_frame {
			ensure(rdoc_api != nil)
			log.debug("captured frame")
			rdoc.EndFrameCapture(rdoc_api, nil, nil)

			cap_idx := rdoc.GetNumCaptures(rdoc_api) - 1
			if cap_idx >= 0 {
				ts: u64
				fp := make([]u8, 512, context.temp_allocator)
				fp_len: u32

				if rdoc.GetCapture(rdoc_api, cap_idx, cast(cstring)raw_data(fp), &fp_len, &ts) !=
				   0 {
					ensure(int(fp_len) < len(fp))
					cwd := os.get_current_directory(context.temp_allocator)

					cap_path := filepath.join({cwd, string(fp[:fp_len])}, context.temp_allocator)

					log.infof("loading capture {}", cap_path)

					if rdoc.IsTargetControlConnected(rdoc_api) {
						rdoc.ShowReplayUI(rdoc_api)
					} else {
						pid := rdoc.LaunchReplayUI(rdoc_api, 1, cast(cstring)raw_data(cap_path))
						if pid != 0 {
							log.infof("launched RenderDoc (pid={})", pid)
						}
					}

				}

			}
		}

		{ 	// Draw
			SKY_COLOUR := glm.vec4{0.3, 0.6, 0.8, 1}

			gl.ClearColor(SKY_COLOUR[0], SKY_COLOUR[1], SKY_COLOUR[2], SKY_COLOUR[3])
			gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

			projection_matrix := state.camera.projection_matrix
			view_matrix := state.camera.view_matrix
			u_mvp := projection_matrix * view_matrix

			frustum_matrix := state.frozen_frustum.? or_else u_mvp
			frustum := create_frustum(frustum_matrix)

			bind_vertex_array(vao)
			defer unbind_vertex_array()

			use_shader(chunk_shader)
			bind_texture(atlas.texture)
			gl.UniformMatrix4fv(
				gl.GetUniformLocation(chunk_shader.handle, "u_mvp"),
				1,
				false,
				&u_mvp[0, 0],
			)
			gl.Uniform3fv(
				gl.GetUniformLocation(chunk_shader.handle, "u_campos"),
				1,
				&state.camera.pos[0],
			)

			if state.fog_enabled {
				gl.Uniform1f(
					gl.GetUniformLocation(chunk_shader.handle, "u_fog_start"),
					f32(state.render_distance) * CHUNK_WIDTH - CHUNK_WIDTH / 4,
				)
				gl.Uniform1f(
					gl.GetUniformLocation(chunk_shader.handle, "u_fog_end"),
					f32(state.render_distance) * CHUNK_WIDTH,
				)
				gl.Uniform4fv(
					gl.GetUniformLocation(chunk_shader.handle, "u_fog_colour"),
					1,
					&SKY_COLOUR[0],
				)
			} else {
				gl.Uniform1f(gl.GetUniformLocation(chunk_shader.handle, "u_fog_start"), max(f32))
				gl.Uniform1f(gl.GetUniformLocation(chunk_shader.handle, "u_fog_end"), max(f32))
			}

			sync.shared_guard(&state.world.lock)

			opaque_chunks := &state.frame.opaque_chunks
			transparent_chunks := &state.frame.transparent_chunks
			water_chunks := &state.frame.water_chunks
			clear(opaque_chunks)
			clear(transparent_chunks)
			clear(water_chunks)

			for _, &chunk in state.world.chunks {
				if chunk.mesh == nil {
					continue
				}

				// TODO: impl. regions & frustum cull them too
				if !frustum_contains_chunk(frustum, chunk.pos) {
					continue
				}

				if len(chunk.mesh.opaque) > 0 {
					append(opaque_chunks, &chunk)
				}
				if len(chunk.mesh.transparent) > 0 {
					append(transparent_chunks, &chunk)
				}
				if len(chunk.mesh.water) > 0 {
					append(water_chunks, &chunk)
				}
			}

			context.user_ptr = &state
			slice.sort_by(transparent_chunks[:], proc(i, j: ^Chunk) -> bool {
				state := cast(^State)context.user_ptr
				i_dist := glm.length(state.camera.pos - get_chunk_centre(i))
				j_dist := glm.length(state.camera.pos - get_chunk_centre(j))
				return i_dist > j_dist
			})

			slice.sort_by(water_chunks[:], proc(i, j: ^Chunk) -> bool {
				state := cast(^State)context.user_ptr
				i_dist := glm.length(state.camera.pos - get_chunk_centre(i))
				j_dist := glm.length(state.camera.pos - get_chunk_centre(j))
				return i_dist > j_dist
			})

			for chunk in water_chunks {
				mesh := chunk.mesh

				slice.sort_by(mesh.water[:], proc(i, j: Mesh_Face) -> bool {
					state := cast(^State)context.user_ptr

					get_face_centre :: proc(f: Mesh_Face) -> glm.vec3 {
						a := f[0].pos
						b := f[2].pos
						t := (a + b) / 2
						if a.x == b.x {
							return {a.x, t.y, t.z}
						} else if a.y == b.y {
							return {t.x, a.y, t.z}
						} else if a.z == b.z {
							return {t.x, t.y, a.z}
						}
						unreachable()
					}

					i_c := get_face_centre(i)
					j_c := get_face_centre(j)

					i_dist := glm.length(state.camera.pos - i_c)
					j_dist := glm.length(state.camera.pos - j_c)

					return i_dist > j_dist
				})
			}

			setup_vertex_attribs :: #force_inline proc() {
				vertex_attrib_pointer(
					0,
					3,
					.Float,
					false,
					size_of(Mesh_Vert),
					offset_of(Mesh_Vert, pos),
				)
				vertex_attrib_pointer(
					1,
					2,
					.Float,
					false,
					size_of(Mesh_Vert),
					offset_of(Mesh_Vert, tex_coord),
				)
				vertex_attrib_i_pointer(
					2,
					1,
					.Unsigned_Int,
					size_of(Mesh_Vert),
					offset_of(Mesh_Vert, colour),
				)
			}

			bind_buffer(vbo)
			setup_vertex_attribs()
			gl.Disable(gl.BLEND) // Disable blending for opaque meshes; slight performance boost
			for &chunk in opaque_chunks {
				buffer_sub_data(vbo, 0, chunk.mesh.opaque[:])
				gl.DrawArrays(gl.TRIANGLES, 0, FACE_VERT_COUNT * cast(i32)len(chunk.mesh.opaque))
			}

			gl.Enable(gl.BLEND)
			bind_buffer(transparent_vbo)
			setup_vertex_attribs()
			for chunk in transparent_chunks {
				buffer_sub_data(vbo, 0, chunk.mesh.transparent[:])
				gl.DrawArrays(
					gl.TRIANGLES,
					0,
					FACE_VERT_COUNT * cast(i32)len(chunk.mesh.transparent),
				)
			}

			bind_buffer(water_vbo)
			setup_vertex_attribs()
			for chunk in water_chunks {
				buffer_sub_data(vbo, 0, chunk.mesh.water[:])
				gl.DrawArrays(gl.TRIANGLES, 0, FACE_VERT_COUNT * cast(i32)len(chunk.mesh.water))
			}

			unbind_buffer(.Array)
			unbind_vertex_array()

			if state.render_frustum {
				frustum_vertices := get_frustum_vertices(frustum)

				old_far_plane := state.far_plane
				state.far_plane = false
				defer state.far_plane = old_far_plane
				_update_camera_axes(&state)
				projection_matrix = state.camera.projection_matrix
				view_matrix = state.camera.view_matrix
				u_mvp = projection_matrix * view_matrix

				gl.Disable(gl.DEPTH_TEST)
				defer gl.Enable(gl.DEPTH_TEST)

				LINE_COLOUR := glm.vec3{1, 1, 1}

				bind_vertex_array(line_vao)
				defer unbind_vertex_array()
				bind_buffer(line_vbo)

				use_shader(line_shader)
				gl.UniformMatrix4fv(
					gl.GetUniformLocation(line_shader.handle, "u_mvp"),
					1,
					false,
					&u_mvp[0, 0],
				)
				gl.Uniform3fv(
					gl.GetUniformLocation(line_shader.handle, "u_line_colour"),
					1,
					&LINE_COLOUR[0],
				)

				buffer_sub_data(line_vbo, 0, frustum_vertices[:])

				gl.DrawElements(
					gl.LINES,
					cast(i32)len(get_frustum_indices()),
					gl.UNSIGNED_INT,
					nil,
				)
			}

			{ 	// UI
				mu_render_ui(&state)
			}
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
