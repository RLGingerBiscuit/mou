package mou

import "base:runtime"
import sa "core:container/small_array"
import "core:fmt"
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

import "prof"

_ :: mem

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_SIZE :: [2]i32{WINDOW_WIDTH, WINDOW_HEIGHT}
WINDOW_TITLE :: "Goofin Minecraft Clone"

DEFAULT_RENDER_DISTANCE :: 8
MAX_RENDER_DISTANCE :: 32
DEFAULT_FOV :: 90
DEFAULT_SENSITIVITY_MULT :: f32(1) / 700
NEAR_PLANE :: 0.1
HIT_DISTANCE :: 6

when ODIN_DEBUG {
	tracking_allocator: mem.Tracking_Allocator
}

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

	prof.init()
	defer prof.deinit()

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
	state.render_ui = true
	state.ao = true
	init_state(&state)
	defer destroy_state(&state)

	init_camera(
		&state,
		pos = {0, 24, 0},
		yaw = 240,
		pitch = 90,
		speed = 5,
		sensitivity_mult = DEFAULT_SENSITIVITY_MULT,
		fovx = DEFAULT_FOV,
	)

	window_ok := init_window(&state, WINDOW_TITLE, WINDOW_SIZE, vsync = true, visible = false)
	if !window_ok {
		os.exit(1)
	}
	defer destroy_window(&state.window)

	glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)

	gl.Enable(gl.CULL_FACE)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	chunk_shader := make_shader("assets/shaders/chunk.vert", "assets/shaders/chunk.frag")
	defer destroy_shader(&chunk_shader)

	water_shader := make_shader("assets/shaders/water.vert", "assets/shaders/water.frag")
	defer destroy_shader(&water_shader)

	fullscreen_shader := make_shader(
		"assets/shaders/fullscreen.vert",
		"assets/shaders/fullscreen.frag",
	)
	defer destroy_shader(&fullscreen_shader)

	line_shader := make_shader("assets/shaders/line.vert", "assets/shaders/line.frag")
	defer destroy_shader(&line_shader)

	block_atlas := make_atlas("assets/textures/blocks/")
	defer destroy_atlas(&block_atlas)

	ui_atlas := make_atlas("assets/textures/ui/", false)
	defer destroy_atlas(&ui_atlas)

	init_world(&state.world, &block_atlas)
	defer destroy_world(&state.world)

	opaque_renderer := make_renderer(true, chunk_shader, .Dynamic)
	defer destroy_renderer(&opaque_renderer)
	transparent_renderer := make_renderer(true, chunk_shader, .Dynamic)
	defer destroy_renderer(&transparent_renderer)
	water_renderer := make_renderer(true, water_shader, .Dynamic)
	defer destroy_renderer(&water_renderer)
	line_renderer := make_renderer(false, line_shader, .Dynamic)
	defer destroy_renderer(&line_renderer)
	fullscreen_renderer := make_renderer(true, fullscreen_shader, .Static)
	defer destroy_renderer(&fullscreen_renderer)

	{ 	// Renderer setup
		MAX_VERTEX_SIZE :: CHUNK_BLOCK_COUNT * 3
		MAX_INDEX_SIZE :: CHUNK_BLOCK_COUNT * 3
		temp_verts := make([]Mesh_Face, MAX_VERTEX_SIZE, context.temp_allocator)
		defer delete(temp_verts, context.temp_allocator)
		temp_indices := make([]Mesh_Face_Indexes, MAX_INDEX_SIZE, context.temp_allocator)
		defer delete(temp_indices, context.temp_allocator)

		{ 	// Opaque setup
			bind_renderer(opaque_renderer)
			defer unbind_renderer()
			renderer_vertices(opaque_renderer, temp_verts)
			renderer_indices(opaque_renderer, temp_indices)
			vertex_attrib_vert(Mesh_Vert)
		}
		{ 	// Transparent setup
			bind_renderer(transparent_renderer)
			defer unbind_renderer()
			renderer_vertices(transparent_renderer, temp_verts)
			renderer_indices(transparent_renderer, temp_indices)
			vertex_attrib_vert(Mesh_Vert)
		}
		{ 	// Water setup
			bind_renderer(water_renderer)
			defer unbind_renderer()
			renderer_vertices(water_renderer, temp_verts)
			renderer_indices(water_renderer, temp_indices)
			vertex_attrib_vert(Mesh_Vert)
		}
		{ 	// Line setup
			bind_renderer(line_renderer)
			defer unbind_renderer()
			vertex_attrib_vert(Line_Vert)
		}
		{ 	// Fullscreen setup
			Fullscreen_Vert :: struct #packed {
				pos:       glm.vec2,
				tex_coord: glm.vec2,
			}
			bind_renderer(fullscreen_renderer)
			defer unbind_renderer()
			@(static, rodata)
			verts := []Fullscreen_Vert {
				{{-1, 1}, {0, 1}},
				{{-1, -1}, {0, 0}},
				{{1, -1}, {1, 0}},
				{{1, 1}, {1, 1}},
			}
			@(static, rodata)
			indices := []u32{0, 1, 2, 2, 3, 0}
			renderer_vertices(fullscreen_renderer, verts)
			renderer_indices(fullscreen_renderer, transmute([][1]u32)indices)
			vertex_attrib_vert(Fullscreen_Vert)
		}
	}

	fbo_colour_tex := make_texture(
		"::/fbo_colour",
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		.RGB,
		mipmap = false,
	)
	defer destroy_texture(&fbo_colour_tex)
	fbo_depth_tex := make_texture(
		"::/fbo_depth",
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		.Depth,
		mipmap = false,
	)
	defer destroy_texture(&fbo_depth_tex)

	state.fbo = make_framebuffer({{.Colour0, &fbo_colour_tex}, {.Depth, &fbo_depth_tex}})
	defer destroy_framebuffer(&state.fbo)

	if prof.event("initial chunk generation") {
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

	mu_init_ui(&state)
	defer mu_destroy_ui(&state)

	show_window(&state.window)
	window_center_cursor(&state.window)

	gl.LineWidth(4)

	prev_delta_times: sa.Small_Array(120, f64)
	previous_time := glfw.GetTime()
	for !window_should_close(state.window) {
		current_time := glfw.GetTime()
		delta_time := current_time - previous_time
		previous_time = current_time

		capture_frame := false

		if prof.event("frame") {
			if prof.event("update iteration") {
				{
					if sa.space(prev_delta_times) == 0 {
						sa.ordered_remove(&prev_delta_times, 0)
					}
					sa.append(&prev_delta_times, delta_time)
					avg_dt: f64
					for dt in sa.slice(&prev_delta_times) {
						avg_dt += dt
					}
					avg_dt /= f64(sa.len(prev_delta_times))
					set_window_title(
						state.window,
						fmt.ctprintf(WINDOW_TITLE + " ({:.0f} fps)", 1 / avg_dt),
					)
				}

				if window_get_key(state.window, .Left_Alt) == .Press ||
				   window_get_key(state.window, .Right_Alt) == .Press {
					state.camera.fovx = glm.clamp(
						state.camera.fovx - 5 * f32(state.window.scroll.y),
						5,
						120,
					)
				}

				if window_get_key(state.window, .Left_Control) == .Press ||
				   window_get_key(state.window, .Right_Control) == .Press {
					state.camera.speed = glm.clamp(
						state.camera.speed + f32(state.window.scroll.y),
						1,
						25,
					)
				}

				if window_get_key(state.window, .Escape) == .Press {
					log.debugf("Escape pressed, closing window")
					set_window_should_close(state.window, true)
				}

				if rdoc_api != nil &&
				   window_get_key(state.window, .F2) == .Press &&
				   window_get_prev_key(state.window, .F2) != .Press {
					capture_frame = true
				}

				if window_get_key(state.window, .F1) == .Press &&
				   window_get_prev_key(state.window, .F1) != .Press {
					state.render_ui = !state.render_ui
				}

				if window_get_key(state.window, .R) == .Press &&
				   window_get_prev_key(state.window, .R) != .Press {
					sync.guard(&state.world.lock)
					for _, &c in state.world.chunks {
						if c.mesh == nil {continue}
						append(&state.world.msg_stack, Meshgen_Msg_Tombstone{c.mesh})
						c.mesh = nil
						world_mark_chunk_remesh(&state.world, &c)
					}
				}

				if state.render_ui {
					if prof.event("update ui") {
						mu_update_ui(&state, delta_time)
					}
				}

				@(static) p, f: glm.vec3
				if state.frozen_frustum == nil {
					p = state.camera.pos
					f = state.camera.front
				} else {
					append(&state.frame.line_vertices, Line_Vert{p, {0, 0xff, 0, 0xff}})
					append(
						&state.frame.line_vertices,
						Line_Vert{p + f * HIT_DISTANCE, {0, 0xff, 0, 0xff}},
					)
				}

				pos, hit := cast_ray_to_block(state.world, p, f, HIT_DISTANCE)
				if hit {
					world_pos := block_pos_to_world_pos(pos)
					chunk_pos := block_pos_to_chunk_pos(pos)
					local_pos := block_pos_to_local_pos(pos)
					chunk, cok := get_world_chunk(state.world, chunk_pos)
					if cok && chunk != nil {
						v := &state.frame.line_vertices
						C :: RGBA{0xff, 0xff, 0xff, 0xff}
						// bottom
						append(v, Line_Vert{world_pos + {0, 0, 0}, C})
						append(v, Line_Vert{world_pos + {1, 0, 0}, C})
						append(v, Line_Vert{world_pos + {1, 0, 0}, C})
						append(v, Line_Vert{world_pos + {1, 0, 1}, C})
						append(v, Line_Vert{world_pos + {1, 0, 1}, C})
						append(v, Line_Vert{world_pos + {0, 0, 1}, C})
						append(v, Line_Vert{world_pos + {0, 0, 1}, C})
						append(v, Line_Vert{world_pos + {0, 0, 0}, C})
						// top
						append(v, Line_Vert{world_pos + {0, 1, 0}, C})
						append(v, Line_Vert{world_pos + {1, 1, 0}, C})
						append(v, Line_Vert{world_pos + {1, 1, 0}, C})
						append(v, Line_Vert{world_pos + {1, 1, 1}, C})
						append(v, Line_Vert{world_pos + {1, 1, 1}, C})
						append(v, Line_Vert{world_pos + {0, 1, 1}, C})
						append(v, Line_Vert{world_pos + {0, 1, 1}, C})
						append(v, Line_Vert{world_pos + {0, 1, 0}, C})
						// left
						append(v, Line_Vert{world_pos + {0, 0, 0}, C})
						append(v, Line_Vert{world_pos + {0, 1, 0}, C})
						append(v, Line_Vert{world_pos + {1, 1, 0}, C})
						append(v, Line_Vert{world_pos + {1, 0, 0}, C})
						// right
						append(v, Line_Vert{world_pos + {0, 0, 1}, C})
						append(v, Line_Vert{world_pos + {0, 1, 1}, C})
						append(v, Line_Vert{world_pos + {1, 1, 1}, C})
						append(v, Line_Vert{world_pos + {1, 0, 1}, C})

						if .UI not_in state.window.flags &&
						   window_get_button(state.window, .Left) == .Press &&
						   window_get_prev_button(state.window, .Left) != .Press {
							sync.guard(&state.world.lock)
							chunk_update_block(&state.world, chunk, local_pos, {.Air})

							if local_pos.x == 0 {
								nb, nbok := get_world_chunk(state.world, chunk_pos + {-1, 0, 0})
								if nbok {
									world_mark_chunk_remesh_priority(&state.world, nb)
								}
							} else if local_pos.x == 15 {
								nb, nbok := get_world_chunk(state.world, chunk_pos + {+1, 0, 0})
								if nbok {
									world_mark_chunk_remesh_priority(&state.world, nb)
								}
							}
							if local_pos.y == 0 {
								nb, nbok := get_world_chunk(state.world, chunk_pos + {0, -1, 0})
								if nbok {
									world_mark_chunk_remesh_priority(&state.world, nb)
								}
							} else if local_pos.y == 15 {
								nb, nbok := get_world_chunk(state.world, chunk_pos + {0, +1, 0})
								if nbok {
									world_mark_chunk_remesh_priority(&state.world, nb)
								}
							}
							if local_pos.z == 0 {
								nb, nbok := get_world_chunk(state.world, chunk_pos + {0, 0, -1})
								if nbok {
									world_mark_chunk_remesh_priority(&state.world, nb)
								}
							} else if local_pos.z == 15 {
								nb, nbok := get_world_chunk(state.world, chunk_pos + {0, 0, +1})
								if nbok {
									world_mark_chunk_remesh_priority(&state.world, nb)
								}
							}
						}
					}
				}

				update_camera(&state, delta_time)

				{
					N := i32(1.2 * f32(state.render_distance))
					cam_chunk_pos := world_pos_to_chunk_pos(state.camera.pos)
					cam_chunk_pos.y = 0

					frustum := create_frustum(
						state.frozen_frustum.? or_else state.camera.projection_matrix *
						state.camera.view_matrix,
					)

					if prof.event("generate near chunks") {
						for y in i32(0) ..= 1 {
							for z in i32(-N) ..= N {
								for x in i32(-N) ..= N {
									chunk_pos := cam_chunk_pos + {x, y, z}
									if !frustum_contains_chunk(frustum, chunk_pos) {
										continue
									}
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
					}

					if prof.event("demesh chunks") {
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
				}

				if prof.event("update world") {
					update_world(&state.world, state.camera.pos)
				}

				update_window(&state.window)
			}

			when false {
				{
					clear(&state.frame.memory_usage)
					for _, chunk in state.world.chunks {
						mesh := chunk.mesh
						if mesh == nil {continue}
						append(
							&state.frame.memory_usage,
							[7]int {
								len(mesh.opaque) * size_of(Mesh_Face) +
								len(mesh.opaque_indices) * size_of(Mesh_Face_Indexes),
								cap(mesh.opaque) * size_of(Mesh_Face) +
								cap(mesh.opaque_indices) * size_of(Mesh_Face_Indexes),
								len(mesh.transparent) * size_of(Mesh_Face) +
								len(mesh.transparent_indices) * size_of(Mesh_Face_Indexes),
								cap(mesh.transparent) * size_of(Mesh_Face) +
								cap(mesh.transparent_indices) * size_of(Mesh_Face_Indexes),
								len(chunk.blocks) * size_of(Block),
								len(mesh.water) * size_of(Mesh_Face) +
								len(mesh.water_indices) * size_of(Mesh_Face_Indexes),
								cap(mesh.water) * size_of(Mesh_Face) +
								cap(mesh.water_indices) * size_of(Mesh_Face_Indexes),
							},
						)
					}
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

					if rdoc.GetCapture(
						   rdoc_api,
						   cap_idx,
						   cast(cstring)raw_data(fp),
						   &fp_len,
						   &ts,
					   ) !=
					   0 {
						ensure(int(fp_len) < len(fp))
						cwd := os.get_current_directory(context.temp_allocator)

						cap_path := filepath.join(
							{cwd, string(fp[:fp_len])},
							context.temp_allocator,
						)

						log.infof("loading capture {}", cap_path)

						if rdoc.IsTargetControlConnected(rdoc_api) {
							rdoc.ShowReplayUI(rdoc_api)
						} else {
							pid := rdoc.LaunchReplayUI(
								rdoc_api,
								1,
								cast(cstring)raw_data(cap_path),
							)
							if pid != 0 {
								log.infof("launched RenderDoc (pid={})", pid)
							}
						}
					}
				}
			}

			if prof.event("render iteration") {
				SKY_COLOUR := RGBA32{0.3, 0.6, 0.8, 1}
				gl.Viewport(0, 0, state.window.size.x, state.window.size.y)
				gl.ClearColor(SKY_COLOUR[0], SKY_COLOUR[1], SKY_COLOUR[2], SKY_COLOUR[3])
				gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

				projection_matrix := state.camera.projection_matrix
				view_matrix := state.camera.view_matrix
				proj_view := projection_matrix * view_matrix
				frustum: Frustum
				{
					cam := state.camera
					aspect := window_aspect_ratio(state.window)
					fovy := 2 * glm.atan(glm.tan(glm.radians(cam.fovx) / 2) / aspect)
					proj := glm.mat4Perspective(
						fovy,
						aspect,
						NEAR_PLANE,
						f32(state.render_distance + 1) * CHUNK_SIZE,
					)
					frustum_matrix := state.frozen_frustum.? or_else proj * view_matrix
					frustum = create_frustum(frustum_matrix)
				}

				// Ensure stuff is reset
				gl.Enable(gl.CULL_FACE)
				gl.Enable(gl.DEPTH_TEST)
				gl.Enable(gl.SCISSOR_TEST)

				if prof.event("render chunks") {
					bind_framebuffer(state.fbo, .All)
					defer unbind_framebuffer(.All)
					gl.Viewport(0, 0, state.window.size.x, state.window.size.y)
					gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

					set_uniforms :: proc(
						r: Renderer,
						state: ^State,
						sky: RGBA32,
						proj_view: glm.mat4,
					) {
						bind_renderer(r)
						set_uniform(r.shader, "u_proj_view", proj_view)
						set_uniform(r.shader, "u_campos", state.camera.pos)
						set_uniform(r.shader, "u_ao", u32(state.ao))
						set_uniform(r.shader, "u_ao_debug", u32(state.ao_debug))

						if state.fog_enabled {
							set_uniform(
								r.shader,
								"u_fog_start",
								f32(state.render_distance) * CHUNK_SIZE - CHUNK_SIZE / 4,
							)
							set_uniform(
								r.shader,
								"u_fog_end",
								f32(state.render_distance) * CHUNK_SIZE,
							)
							set_uniform(r.shader, "u_fog_colour", sky)
						} else {
							set_uniform(r.shader, "u_fog_start", max(f32))
							set_uniform(r.shader, "u_fog_end", max(f32))
						}
					}

					sync.shared_guard(&state.world.lock)

					opaque_chunks := &state.frame.opaque_chunks
					transparent_chunks := &state.frame.transparent_chunks
					water_chunks := &state.frame.water_chunks
					if prof.event("frustum culling/mesh selection") {
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
					}

					context.user_ptr = &state

					if prof.event("sort transparent chunks") {
						slice.sort_by(transparent_chunks[:], proc(i, j: ^Chunk) -> bool {
							state := cast(^State)context.user_ptr
							i_dist := glm.length(state.camera.pos - get_chunk_centre(i))
							j_dist := glm.length(state.camera.pos - get_chunk_centre(j))
							return i_dist > j_dist
						})
					}

					if prof.event("sort water chunks") {
						slice.sort_by(water_chunks[:], proc(i, j: ^Chunk) -> bool {
							state := cast(^State)context.user_ptr
							i_dist := glm.length(state.camera.pos - get_chunk_centre(i))
							j_dist := glm.length(state.camera.pos - get_chunk_centre(j))
							return i_dist > j_dist
						})
					}

					if prof.event("sort water faces") {
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
					}

					if prof.event("render opaque meshes") {
						bind_renderer(opaque_renderer)
						defer unbind_renderer()
						bind_texture(block_atlas.texture)
						set_uniforms(opaque_renderer, &state, SKY_COLOUR, proj_view)

						gl.Disable(gl.BLEND) // Disable blending for opaque meshes; slight performance boost
						for &chunk in opaque_chunks {
							pos := chunk.pos * CHUNK_SIZE
							set_uniform(opaque_renderer.shader, "u_chunkpos", pos)
							renderer_sub_vertices(opaque_renderer, 0, chunk.mesh.opaque[:])
							renderer_sub_indices(opaque_renderer, 0, chunk.mesh.opaque_indices[:])
							gl.DrawElements(
								gl.TRIANGLES,
								FACE_INDEX_COUNT * cast(i32)len(chunk.mesh.opaque),
								gl.UNSIGNED_INT,
								nil,
							)
						}
					}

					gl.Enable(gl.BLEND)

					if prof.event("render transparent meshes") {
						bind_renderer(transparent_renderer)
						defer unbind_renderer()
						bind_texture(block_atlas.texture)
						set_uniforms(transparent_renderer, &state, SKY_COLOUR, proj_view)

						for &chunk in transparent_chunks {
							pos := chunk.pos * CHUNK_SIZE
							set_uniform(transparent_renderer.shader, "u_chunkpos", pos)
							renderer_sub_vertices(
								transparent_renderer,
								0,
								chunk.mesh.transparent[:],
							)
							renderer_sub_indices(
								transparent_renderer,
								0,
								chunk.mesh.transparent_indices[:],
							)
							gl.DrawElements(
								gl.TRIANGLES,
								FACE_INDEX_COUNT * cast(i32)len(chunk.mesh.transparent),
								gl.UNSIGNED_INT,
								nil,
							)
						}
					}

					if prof.event("render water meshes") {
						bind_renderer(water_renderer)
						defer unbind_renderer()
						bind_texture(block_atlas.texture)
						set_uniforms(water_renderer, &state, SKY_COLOUR, proj_view)

						for &chunk in water_chunks {
							pos := chunk.pos * CHUNK_SIZE
							set_uniform(water_renderer.shader, "u_time", cast(f32)current_time)
							set_uniform(water_renderer.shader, "u_atlas_size", ATLAS_SIZE)
							set_uniform(water_renderer.shader, "u_atlas_block_size", cast(f32)128)
							set_uniform(water_renderer.shader, "u_chunkpos", pos)
							renderer_sub_vertices(water_renderer, 0, chunk.mesh.water[:])
							renderer_sub_indices(water_renderer, 0, chunk.mesh.water_indices[:])
							gl.DrawElements(
								gl.TRIANGLES,
								FACE_INDEX_COUNT * cast(i32)len(chunk.mesh.water),
								gl.UNSIGNED_INT,
								nil,
							)
						}
					}
				}

				gl.Disable(gl.DEPTH_TEST)

				if prof.event("framebuffer blit") {
					if .Wireframe in state.camera.flags {
						gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
					}
					defer if .Wireframe in state.camera.flags {
						gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
					}

					bind_renderer(fullscreen_renderer)
					defer unbind_renderer()

					bind_texture(fbo_colour_tex)
					gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)
				}

				defer clear(&state.frame.line_vertices)
				if prof.event("render lines") {
					if state.render_frustum {
						frustum_vertices := get_frustum_vertices(frustum)
						append(&state.frame.line_vertices, ..frustum_vertices[:])
					}

					if len(state.frame.line_vertices) > 0 {
						// Remove far plane temporarily
						old_far_plane := state.far_plane
						state.far_plane = false
						defer state.far_plane = old_far_plane
						_update_camera_axes(&state)
						projection_matrix = state.camera.projection_matrix
						view_matrix = state.camera.view_matrix
						proj_view = projection_matrix * view_matrix

						bind_renderer(line_renderer)
						defer unbind_renderer()

						set_uniform(line_shader, "u_proj_view", proj_view)

						renderer_vertices(line_renderer, state.frame.line_vertices[:])

						gl.DrawArrays(gl.LINES, 0, cast(i32)len(state.frame.line_vertices))
					}
				}

				{ 	// TODO: Do this but better
					if .Wireframe in state.camera.flags {
						gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
					}
					defer if .Wireframe in state.camera.flags {
						gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
					}

					projection_matrix = glm.mat4Ortho3d(
						0,
						f32(state.window.size.x),
						f32(state.window.size.y),
						0,
						-1,
						1,
					)
					view_matrix = glm.identity(glm.mat4)
					proj_view = projection_matrix * view_matrix

					SCALE :: 0.5
					C :: RGBA{0xff, 0xff, 0xff, 0xff}

					uv := ui_atlas.uvs["crosshair.png"]
					size := SCALE * (uv[1] - uv[0]) * ui_atlas.size

					r := RectF {
						x = (f32(state.window.size.x) - size.x) / 2,
						y = (f32(state.window.size.y) - size.y) / 2,
						w = size.x,
						h = size.y,
					}

					bind_renderer(state.ui.renderer)
					defer unbind_renderer()
					bind_texture(ui_atlas.texture)
					defer unbind_texture()

					set_uniform(state.ui.renderer.shader, "u_proj_view", proj_view)

					renderer_sub_vertices(
						state.ui.renderer,
						0,
						[]UI_Vert {
							{{r.x, r.y}, uv[0], C},
							{{r.x + r.w, r.y}, {uv[1].x, uv[0].y}, C},
							{{r.x, r.y + r.h}, {uv[0].x, uv[1].y}, C},
							{{r.x + r.w, r.y + r.h}, uv[1], C},
						},
					)

					renderer_sub_indices(
						state.ui.renderer,
						0,
						transmute([][1]u32)[]u32{2, 1, 0, 2, 3, 1},
					)

					gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)
				}

				if state.render_ui {
					if prof.event("render ui") {
						mu_render_ui(&state)
					}
				}
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
