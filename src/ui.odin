package mou

import "core:fmt"
import glm "core:math/linalg/glsl"
import gl "vendor:OpenGL"
import "vendor:glfw"
import mu "vendor:microui"

_ :: glfw
_ :: gl

init_ui :: proc(state: ^State) {
	img := create_image("::/font.png", mu.DEFAULT_ATLAS_WIDTH, mu.DEFAULT_ATLAS_HEIGHT, false)
	defer destroy_image(&img, false)

	for alpha, i in mu.default_atlas_alpha {
		i := i
		i *= 4
		img.data[i + 0] = 255
		img.data[i + 0] = 255
		img.data[i + 0] = 255
		img.data[i + 0] = alpha
	}

	state.ui_tex = image_to_texture(img)

	state.ui_shader = make_shader("assets/shaders/ui.vert", "assets/shaders/ui.frag")

	state.ui_vao = make_vertex_array()
	state.ui_vbo = make_buffer(.Array, .Dynamic)
	state.ui_ebo = make_buffer(.Element_Array, .Dynamic)

	bind_vertex_array(state.ui_vao)
	bind_buffer(state.ui_ebo)
	buffer_data(state.ui_ebo, ebo_buf[:])

	bind_buffer(state.ui_vbo)
	buffer_data(state.ui_vbo, vbo_buf[:])

	// position [x,y]
	vertex_attrib_i_pointer(0, 2, .Int, size_of(Vert), offset_of(Vert, pos))
	// tex_coord [x,y]
	vertex_attrib_pointer(1, 2, .Float, false, size_of(Vert), offset_of(Vert, tex_coord))
	// colour [rgba]
	vertex_attrib_i_pointer(2, 1, .Unsigned_Int, size_of(Vert), offset_of(Vert, colour))

	// unbind_buffer(.Element_Array)
	unbind_buffer(.Array)
	unbind_vertex_array()
}

destroy_ui :: proc(state: ^State) {
	destroy_texture(&state.ui_tex)
	destroy_shader(&state.ui_shader)
	destroy_buffer(&state.ui_vbo)
	destroy_buffer(&state.ui_ebo)
	destroy_vertex_array(&state.ui_vao)
}

update_ui :: proc(state: ^State, dt: f64) {
	ctx := state.window.ui_ctx

	// /* This is scoped and is intended to be use in the condition of a if-statement */
	@(deferred_in = scoped_end_panel)
	panel :: proc(ctx: ^mu.Context, name: string, opts := mu.Options{}) -> bool {
		mu.begin_panel(ctx, name, opts)
		return true
	}

	scoped_end_panel :: proc(ctx: ^mu.Context, _: string, _: mu.Options) {
		mu.end_panel(ctx)
	}

	checkbox_no_label :: proc(ctx: ^mu.Context, label: string, state: ^bool) -> (res: mu.Result_Set) {
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

	if mu.window(ctx, "Minceraft", {10, 10, 300, 160}, {.NO_CLOSE, .NO_RESIZE}) {
		LABEL_WIDTH :: 90

		mu.layout_row(ctx, {LABEL_WIDTH, -1})

		mu.label(ctx, "FPS:")
		mu.text(ctx, fmt.tprintf("{:.1f}", 1 / dt))

		mu.label(ctx, "Coords:")
		mu.text(
			ctx,
			fmt.tprintf(
				"{:.1f}, {:.1f}, {:.1f}",
				state.camera.pos.x,
				state.camera.pos.y,
				state.camera.pos.z,
			),
		)

		mu.label(ctx, "Render Distance:")
		tmp_rnd_dst := cast(f32)state.render_distance
		mu.number(ctx, &tmp_rnd_dst, 1, "%.0f")
		if tmp_rnd_dst < 1 {
			tmp_rnd_dst = 1
		}
		if tmp_rnd_dst > MAX_RENDER_DISTANCE {
			tmp_rnd_dst = MAX_RENDER_DISTANCE
		}
		state.render_distance = cast(i32)tmp_rnd_dst

		mu.label(ctx, "Fog:")
		checkbox_no_label(ctx, "fog_enabled", &state.fog_enabled)

		mu.label(ctx, "Clip Plane:")
		checkbox_no_label(ctx, "far_plane", &state.far_plane)
	}
}

render_ui :: proc(state: State) {
	flush :: proc(state: State) {
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

		bind_vertex_array(state.ui_vao)

		use_shader(state.ui_shader)
		bind_texture(state.ui_tex)
		gl.UniformMatrix4fv(
			gl.GetUniformLocation(state.ui_shader.handle, "u_mvp"),
			1,
			false,
			&u_mvp[0, 0],
		)

		bind_buffer(state.ui_vbo)

		buffer_sub_data(state.ui_vbo, 0, vbo_buf[:4 * buf_idx])
		buffer_sub_data(state.ui_ebo, 0, ebo_buf[:6 * buf_idx])

		gl.DrawElements(gl.TRIANGLES, cast(i32)buf_idx * 6, gl.UNSIGNED_INT, nil)

		unbind_buffer(.Array)
		unbind_vertex_array()

		buf_idx = 0
	}

	push_quad :: proc(state: State, dst, src: mu.Rect, colour: mu.Color) {
		if buf_idx == BUF_SZ {flush(state)}

		tex_idx := buf_idx * 4
		element_idx := buf_idx * 4
		index_idx := buf_idx * 6
		buf_idx += 1

		x := cast(f32)src.x / mu.DEFAULT_ATLAS_WIDTH
		y := cast(f32)src.y / mu.DEFAULT_ATLAS_HEIGHT
		w := cast(f32)src.w / mu.DEFAULT_ATLAS_WIDTH
		h := cast(f32)src.h / mu.DEFAULT_ATLAS_HEIGHT

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
	FLUSH_ALL :: false

	draw_rect :: proc(state: State, rect: mu.Rect, colour: mu.Color) {
		push_quad(state, rect, mu.default_atlas[mu.DEFAULT_ATLAS_WHITE], colour)
		when FLUSH_ALL do flush(state)
	}

	draw_text :: proc(state: State, text: string, pos: mu.Vec2, colour: mu.Color) {
		dst := mu.Rect{pos.x, pos.y, 0, 0}
		for char in text {
			src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + int(char)]
			dst.w = src.w
			dst.h = src.h
			push_quad(state, dst, src, colour)
			dst.x += dst.w
		}
		when FLUSH_ALL do flush(state)
	}

	draw_icon :: proc(state: State, id: mu.Icon, rect: mu.Rect, colour: mu.Color) {
		src := mu.default_atlas[i32(id)]
		x := rect.x + (rect.w - src.w) / 2
		y := rect.y + (rect.h - src.h) / 2
		push_quad(state, {x, y, src.w, src.h}, src, colour)
		when FLUSH_ALL do flush(state)
	}

	// FIXME: doesn't update mu viewport unless move mu window to top left
	gl.Viewport(0, 0, state.window.size.x, state.window.size.y)
	gl.Enable(gl.SCISSOR_TEST)
	gl.Disable(gl.CULL_FACE)
	gl.Disable(gl.DEPTH_TEST)
	gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)

	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(state.window.ui_ctx, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Text:
			draw_text(state, cmd.str, cmd.pos, cmd.color)

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
Vert :: struct #packed {
	pos:       [2]i32,
	tex_coord: [2]f32,
	colour:    mu.Color,
}
@(private = "file")
vbo_buf: [BUF_SZ * 4]Vert
@(private = "file")
ebo_buf: [BUF_SZ * 6]u32
@(private = "file")
buf_idx: u32 = 0
