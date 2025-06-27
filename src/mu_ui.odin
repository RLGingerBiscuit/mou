package mou

import "core:fmt"
import "core:log"
import glm "core:math/linalg/glsl"
import "core:mem"
import mu "third:microui"
import gl "vendor:OpenGL"
import fons "vendor:fontstash"
import stbi "vendor:stb/image"

_ :: stbi

FONT_HEIGHT :: 18
FONT_NORMAL :: mu.Font_Options {
	index = 0,
	size  = FONT_HEIGHT,
}
FONT_BOUNCY :: mu.Font_Options {
	index = 1,
	size  = FONT_HEIGHT,
}
FONT_MONO :: mu.Font_Options {
	index = 2,
	size  = FONT_HEIGHT,
}

FONT_ATLAS_WIDTH :: 512
FONT_ATLAS_HEIGHT :: 512

@(private = "file")
ICONS :: [?]mu.Icon{.CLOSE, .CHECK, .COLLAPSED, .EXPANDED, .RESIZE}

UI_State :: struct {
	ctx:      ^mu.Context, // Microui context
	font_ctx: fons.FontContext, // Fontstash context
	font_tex: Texture,
	icons:    [mu.Icon]mu.Rect,
	// Rendering
	vao:      Vertex_Array,
	vbo, ebo: Buffer,
	shader:   Shader,
}

mu_init_ui :: proc(state: ^State) {
	state.ui.ctx = new(mu.Context)
	mu.init(state.ui.ctx)
	state.ui.ctx.style.font = cast(mu.Font)&state.ui.font_ctx
	state.ui.ctx.style.font_opts = FONT_NORMAL
	state.ui.ctx.style.title_height = FONT_HEIGHT + 6

	{
		font := &state.ui.font_ctx

		font.userData = &state.ui
		font.callbackResize = proc(data: rawptr, w: int, h: int) {
			log.debugf("Font atlas resized: {}x{}", w, h)
		}
		font.callbackUpdate = proc(user_data: rawptr, dirty_rect: [4]f32, texture_data: rawptr) {
			ui := cast(^UI_State)user_data
			font := &ui.font_ctx
			pixels := (cast([^]byte)texture_data)[:font.width * font.height]
			log.debugf("Font atlas updated: {}", dirty_rect)
			// FIXME: We should only update the dirty rect
			bind_texture(ui.font_tex)
			texture_update(ui.font_tex, pixels)
			unbind_texture()

			when ODIN_DEBUG {
				stbi.write_bmp(
					"font.bmp",
					ui.font_tex.width,
					ui.font_tex.height,
					texture_format_bytes(ui.font_tex.format),
					texture_data,
				)
			}
		}

		fons.Init(font, FONT_ATLAS_WIDTH, FONT_ATLAS_HEIGHT, .TOPLEFT)

		font.userData = &state.ui
		state.ui.font_tex = make_texture(
			"::/font.png",
			FONT_ATLAS_WIDTH,
			FONT_ATLAS_HEIGHT,
			.Red,
			mipmap = false,
		)

		fons.AddFont(font, "Inter-Bold", "assets/fonts/Inter/Inter-Bold.ttf")
		fons.AddFont(font, "Jellee-Bold", "assets/fonts/Jellee/Jellee-Bold.ttf")
		fons.AddFont(
			font,
			"JetBrainsMono-Bold",
			"assets/fonts/JetBrainsMono/JetBrainsMono-Bold.ttf",
		)

		for icon in ICONS {
			src := mu.default_atlas[i32(icon)]
			ix, iy, ok := fons.__AtlasAddRect(font, cast(int)src.w + 2, cast(int)src.h + 2) // + 2 for padding
			if !ok {
				fons.ExpandAtlas(font, font.width * 2, font.height * 2)
				ix, iy, ok = fons.__AtlasAddRect(font, cast(int)src.w + 2, cast(int)src.h + 2) // + 2 for padding
				if !ok {
					log.fatal("Couldn't expand font atlas for icons")
					return
				}
			}
			state.ui.icons[icon].x = i32(ix) + 1 // skip padding here
			state.ui.icons[icon].y = i32(iy) + 1 // skip padding here
			state.ui.icons[icon].w = src.w
			state.ui.icons[icon].h = src.h

			// Copy over icon data
			for y in 0 ..< src.h {
				dst_offset := (i32(iy) + y) * i32(font.width) + i32(ix)
				src_offset := (src.y + y) * mu.DEFAULT_ATLAS_WIDTH + src.x
				mem.copy_non_overlapping(
					&font.textureData[dst_offset],
					&mu.default_atlas_alpha[src_offset],
					cast(int)src.w,
				)
			}
		}

		// We need to set the texture once before we can update it
		texture_set(state.ui.font_tex, font.textureData)

		state.ui.ctx.text_width =
		proc(user_data: mu.Font, opts: mu.Font_Options, str: string) -> i32 {
			font := cast(^fons.FontContext)user_data
			fons.SetFont(font, opts.index)
			fons.SetSpacing(font, cast(f32)opts.spacing)
			fons.SetSize(font, cast(f32)opts.size)
			return cast(i32)fons.TextBounds(font, str)
		}

		state.ui.ctx.text_height = proc(user_data: mu.Font, opts: mu.Font_Options) -> i32 {
			font := cast(^fons.FontContext)user_data
			fons.SetFont(font, opts.index)
			fons.SetSpacing(font, cast(f32)opts.spacing)
			fons.SetSize(font, cast(f32)opts.size)
			ascent, descent, _ := fons.VerticalMetrics(font)
			return i32(ascent - descent)
		}
	}

	state.ui.shader = make_shader("assets/shaders/ui.vert", "assets/shaders/ui.frag")

	state.ui.vao = make_vertex_array()
	state.ui.vbo = make_buffer(.Array, .Dynamic)
	state.ui.ebo = make_buffer(.Element_Array, .Dynamic)

	bind_vertex_array(state.ui.vao)
	bind_buffer(state.ui.ebo)
	buffer_data(state.ui.ebo, ebo_buf[:])

	bind_buffer(state.ui.vbo)
	buffer_data(state.ui.vbo, vbo_buf[:])

	// position [x,y]
	vertex_attrib_pointer(0, 2, .Float, false, size_of(UI_Vert), offset_of(UI_Vert, pos))
	// tex_coord [x,y]
	vertex_attrib_pointer(1, 2, .Float, false, size_of(UI_Vert), offset_of(UI_Vert, tex_coord))
	// colour [rgba]
	vertex_attrib_i_pointer(2, 1, .Unsigned_Int, size_of(UI_Vert), offset_of(UI_Vert, colour))

	// unbind_buffer(.Element_Array)
	unbind_buffer(.Array)
	unbind_vertex_array()
}

mu_destroy_ui :: proc(state: ^State) {
	fons.Destroy(&state.ui.font_ctx)
	destroy_texture(&state.ui.font_tex)
	destroy_shader(&state.ui.shader)
	destroy_buffer(&state.ui.vbo)
	destroy_buffer(&state.ui.ebo)
	destroy_vertex_array(&state.ui.vao)
	free(state.ui.ctx)
}

mu_update_ui :: proc(state: ^State, dt: f64) {
	fons.BeginState(&state.ui.font_ctx)

	wnd := &state.window
	ctx := state.ui.ctx

	if .UI in wnd.flags {
		@(static) buttons_map := [mu.Mouse]Mouse_Button {
			.LEFT   = .Left,
			.RIGHT  = .Right,
			.MIDDLE = .Middle,
		}

		@(static) key_map := [mu.Key][2]Key {
			.SHIFT     = {.Left_Shift, .Right_Shift},
			.CTRL      = {.Left_Control, .Right_Control},
			.ALT       = {.Left_Alt, .Right_Alt},
			.BACKSPACE = {.Backspace, .Unknown},
			.DELETE    = {.Delete, .Unknown},
			.RETURN    = {.Enter, .Enter},
			.LEFT      = {.Left, .Unknown},
			.RIGHT     = {.Right, .Unknown},
			.HOME      = {.Home, .Unknown},
			.END       = {.End, .Unknown},
			.A         = {.A, .Unknown},
			.X         = {.X, .Unknown},
			.C         = {.C, .Unknown},
			.V         = {.V, .Unknown},
		}

		_ = buttons_map
		_ = key_map

		mu.input_mouse_move(ctx, i32(wnd.cursor.x), i32(wnd.cursor.y))

		for bgl, bmu in buttons_map {
			switch {
			case wnd.buttons[bgl] == .Press && wnd.prev_buttons[bgl] == .Release:
				mu.input_mouse_down(ctx, i32(wnd.cursor.x), i32(wnd.cursor.y), bmu)
			case wnd.buttons[bgl] == .Release && wnd.prev_buttons[bgl] == .Press:
				mu.input_mouse_up(ctx, i32(wnd.cursor.x), i32(wnd.cursor.y), bmu)
			}
		}

		// TODO: convert and forward key map
		// TODO: forward text input
	}

	// /* This is scoped and is intended to be use in the condition of a if-statement */
	@(deferred_in = scoped_end_panel)
	panel :: proc(ctx: ^mu.Context, name: string, opts := mu.Options{}) -> bool {
		mu.begin_panel(ctx, name, opts)
		return true
	}

	scoped_end_panel :: proc(ctx: ^mu.Context, _: string, _: mu.Options) {
		mu.end_panel(ctx)
	}

	checkbox_no_label :: proc(
		ctx: ^mu.Context,
		label: string,
		state: ^bool,
	) -> (
		res: mu.Result_Set,
	) {
		id := mu.get_id(ctx, uintptr(state))
		r := mu.layout_next(ctx)
		box := mu.Rect{r.x, r.y, r.h, r.h}
		mu.update_control(ctx, id, r, {})
		/* handle click */
		if .LEFT in ctx.mouse_released_bits && ctx.hover_id == id {
			res += {.CHANGE}
			state^ = !state^
		}
		/* draw */
		mu.draw_control_frame(ctx, id, box, .BASE, {})
		if state^ {
			mu.draw_icon(ctx, .CHECK, box, ctx.style.colors[.TEXT])
		}
		return
	}

	mu.begin(ctx)
	defer mu.end(ctx)

	if mu.window(ctx, "Minceraft", {10, 10, 420, 340}, {.NO_CLOSE}, FONT_BOUNCY) {
		LABEL_WIDTH :: 160

		mu.layout_row(ctx, {LABEL_WIDTH, -1})

		mu.label(ctx, "Frame Time:")
		mu.text(ctx, fmt.tprintf("{:.1f}ms", dt * 1000), FONT_MONO)

		mu.label(ctx, "Coords:")
		mu.text(
			ctx,
			fmt.tprintf(
				"X: {:.1f}, Y: {:.1f}, Z: {:.1f}",
				state.camera.pos.x,
				state.camera.pos.y,
				state.camera.pos.z,
			),
			FONT_MONO,
		)

		mu.label(ctx, "Camera:")
		mu.text(
			ctx,
			fmt.tprintf(
				"Yaw: {:.1f}, Pitch: {:.1f}",
				glm.mod(glm.abs(state.camera.yaw), 360),
				state.camera.pitch,
			),
			FONT_MONO,
		)

		mu.label(ctx, "Render Distance:")
		temp_render_distance := cast(f32)state.render_distance
		mu.number(ctx, &temp_render_distance, 1, "%.0f", font_opts = FONT_MONO)
		if temp_render_distance < 1 {
			temp_render_distance = 1
		}
		if temp_render_distance > MAX_RENDER_DISTANCE {
			temp_render_distance = MAX_RENDER_DISTANCE
		}
		state.render_distance = cast(i32)temp_render_distance

		temp_wireframe_enabled := .Wireframe in state.camera.flags
		mu.label(ctx, "Wireframe:")
		if .CHANGE in checkbox_no_label(ctx, "wireframe_enabled", &temp_wireframe_enabled) {
			if temp_wireframe_enabled {
				state.camera.flags |= {.Wireframe}
			} else {
				state.camera.flags &~= {.Wireframe}
			}
		}

		mu.label(ctx, "Fog:")
		checkbox_no_label(ctx, "fog_enabled", &state.fog_enabled)

		mu.label(ctx, "Clip Plane:")
		checkbox_no_label(ctx, "far_plane", &state.far_plane)

		mu.label(ctx, "Render Frustum:")
		checkbox_no_label(ctx, "render_frustum", &state.render_frustum)

		_, temp_frozen_frustum := state.frozen_frustum.?
		mu.label(ctx, "Freeze Frustum:")
		if .CHANGE in checkbox_no_label(ctx, "frozen_frustum", &temp_frozen_frustum) {
			state.frozen_frustum =
				temp_frozen_frustum ? (state.camera.projection_matrix * state.camera.view_matrix) : nil
		}

		temp_mem_usage: [5]int
		for usage in state.frame.memory_usage {
			temp_mem_usage += usage
		}

		mu.label(ctx, "Opaque Mem Usage:")
		if temp_mem_usage[0] != 0 {
			mu.text(
				ctx,
				fmt.tprintf(
					"{:.2f} MiB ({:.2f} MiB, {:.2f}x)",
					f32(temp_mem_usage[0]) / mem.Megabyte,
					f32(temp_mem_usage[1]) / mem.Megabyte,
					(f32(temp_mem_usage[1]) / (f32(temp_mem_usage[0]))),
				),
				FONT_MONO,
			)
		} else {
			mu.text(
				ctx,
				fmt.tprintf(
					"{:.2f} MiB ({:.2f} MiB)",
					f32(temp_mem_usage[0]) / mem.Megabyte,
					f32(temp_mem_usage[1]) / mem.Megabyte,
				),
				FONT_MONO,
			)
		}

		mu.label(ctx, "Trans. Mem Usage:")
		if temp_mem_usage[2] != 0 {
			mu.text(
				ctx,
				fmt.tprintf(
					"{:.2f} MiB ({:.2f} MiB, {:.2f}x)",
					f32(temp_mem_usage[2]) / mem.Megabyte,
					f32(temp_mem_usage[3]) / mem.Megabyte,
					(f32(temp_mem_usage[3]) / (f32(temp_mem_usage[2]))),
				),
				FONT_MONO,
			)
		} else {
			mu.text(
				ctx,
				fmt.tprintf(
					"{:.2f} MiB ({:.2f} MiB)",
					f32(temp_mem_usage[2]) / mem.Megabyte,
					f32(temp_mem_usage[3]) / mem.Megabyte,
				),
				FONT_MONO,
			)
		}

		mu.label(ctx, "Block Mem Usage:")
		mu.text(ctx, fmt.tprintf("{:.2f} MiB", f32(temp_mem_usage[4]) / mem.Megabyte), FONT_MONO)
	}

	fons.EndState(&state.ui.font_ctx)
}

mu_render_ui :: proc(state: ^State) {
	flush :: proc(state: ^State) {
		if buf_idx == 0 {return}

		projection_matrix := glm.mat4Ortho3d(
			0,
			f32(state.window.size.x),
			f32(state.window.size.y),
			0,
			-1,
			1,
		)
		view_matrix := glm.identity(glm.mat4)
		u_mvp := projection_matrix * view_matrix

		bind_vertex_array(state.ui.vao)

		use_shader(state.ui.shader)
		bind_texture(state.ui.font_tex)
		gl.UniformMatrix4fv(
			gl.GetUniformLocation(state.ui.shader.handle, "u_mvp"),
			1,
			false,
			&u_mvp[0, 0],
		)

		bind_buffer(state.ui.vbo)

		buffer_sub_data(state.ui.vbo, 0, vbo_buf[:4 * buf_idx])
		buffer_sub_data(state.ui.ebo, 0, ebo_buf[:6 * buf_idx])

		gl.DrawElements(gl.TRIANGLES, cast(i32)buf_idx * 6, gl.UNSIGNED_INT, nil)

		unbind_texture()
		unbind_buffer(.Array)
		unbind_vertex_array()

		buf_idx = 0
	}

	push_quad :: proc(state: ^State, dst: RectF, src: RectF, colour: mu.Color) {
		if buf_idx == BUF_SZ {flush(state)}

		font := &state.ui.font_ctx

		tex_idx := buf_idx * 4
		element_idx := buf_idx * 4
		index_idx := buf_idx * 6
		buf_idx += 1

		x := src.x / f32(font.width)
		y := src.y / f32(font.height)
		w := src.w / f32(font.width)
		h := src.h / f32(font.height)

		vbo_buf[tex_idx + 0] = {{dst.x, dst.y}, {x, y}, colour}
		vbo_buf[tex_idx + 1] = {{dst.x + dst.w, dst.y}, {x + w, y}, colour}
		vbo_buf[tex_idx + 2] = {{dst.x, dst.y + dst.h}, {x, y + h}, colour}
		vbo_buf[tex_idx + 3] = {{dst.x + dst.w, dst.y + dst.h}, {x + w, y + h}, colour}

		ebo_buf[index_idx + 0] = element_idx + 0
		ebo_buf[index_idx + 1] = element_idx + 1
		ebo_buf[index_idx + 2] = element_idx + 2
		ebo_buf[index_idx + 3] = element_idx + 2
		ebo_buf[index_idx + 4] = element_idx + 3
		ebo_buf[index_idx + 5] = element_idx + 1
	}

	// For debugging purposes
	FLUSH_ALL :: true

	draw_rect :: proc(state: ^State, rect: mu.Rect, colour: mu.Color) {
		dst := RectF{f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)}
		push_quad(state, dst, {0, 0, 1, 1}, colour) // NOTE: fontstash always has a 2x2 rect @ 0,0
		when FLUSH_ALL do flush(state)
	}

	draw_text :: proc(
		state: ^State,
		text: string,
		pos: mu.Vec2,
		colour: mu.Color,
		opts: mu.Font_Options,
	) {
		font := &state.ui.font_ctx
		x := f32(pos.x)
		y := f32(pos.y)

		fons.SetFont(font, opts.index)
		fons.SetSpacing(font, cast(f32)opts.spacing)
		fons.SetSize(font, cast(f32)opts.size)

		{
			asc, _, _ := fons.VerticalMetrics(font)
			y += asc
		}

		quad: fons.Quad
		iter := fons.TextIterInit(font, x, y, text)

		for fons.TextIterNext(font, &iter, &quad) {
			src := RectF {
				x = quad.s0,
				y = quad.t0,
				w = quad.s1 - quad.s0,
				h = quad.t1 - quad.t0,
			}
			dst := RectF {
				x = quad.x0,
				y = quad.y0,
				w = quad.x1 - quad.x0,
				h = quad.y1 - quad.y0,
			}
			// Unscale
			src.x *= f32(font.width)
			src.w *= f32(font.width)
			src.y *= f32(font.height)
			src.h *= f32(font.height)

			push_quad(state, dst, src, colour)
		}

		when FLUSH_ALL do flush(state)
	}

	draw_icon :: proc(state: ^State, id: mu.Icon, rect: mu.Rect, colour: mu.Color) {
		icon := state.ui.icons[id]
		src := RectF{f32(icon.x), f32(icon.y), f32(icon.w), f32(icon.h)}
		x := cast(f32)(rect.x + (rect.w - icon.w) / 2)
		y := cast(f32)(rect.y + (rect.h - icon.h) / 2)
		dst := RectF{x, y, src.w, src.h}
		push_quad(state, dst, src, colour)
		when FLUSH_ALL do flush(state)
	}

	// FIXME: doesn't update mu viewport unless move mu window to top left
	gl.Viewport(0, 0, state.window.size.x, state.window.size.y)
	gl.Enable(gl.SCISSOR_TEST)
	gl.Disable(gl.CULL_FACE)
	gl.Disable(gl.DEPTH_TEST)
	gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)

	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(state.ui.ctx, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Text:
			draw_text(state, cmd.str, cmd.pos, cmd.color, cmd.opts)

		case ^mu.Command_Rect:
			draw_rect(state, cmd.rect, cmd.color)

		case ^mu.Command_Icon:
			draw_icon(state, cmd.id, cmd.rect, cmd.color)

		case ^mu.Command_Clip:
			gl.Scissor(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h)

		case ^mu.Command_Jump:
			panic("unreachable " + #procedure)
		}
	}

	flush(state)

	if .Wireframe in state.camera.flags {
		gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
	}
	gl.Enable(gl.DEPTH_TEST)
	gl.Enable(gl.CULL_FACE)
	gl.Disable(gl.SCISSOR_TEST)
}

@(private = "file")
BUF_SZ :: 16384
@(private = "file")
UI_Vert :: struct #packed {
	pos:       glm.vec2,
	tex_coord: glm.vec2,
	colour:    mu.Color,
}
@(private = "file")
vbo_buf: [BUF_SZ * 4]UI_Vert
@(private = "file")
ebo_buf: [BUF_SZ * 6]u32
@(private = "file")
buf_idx: u32 = 0

@(private = "file")
RectF :: struct {
	x, y, w, h: f32,
}
