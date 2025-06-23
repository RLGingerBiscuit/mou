package mou

import "core:fmt"
import "core:math"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import "core:slice"
import "core:unicode/utf8"
import stbi "third:stb/image"
import stbrp "third:stb/rect_pack"
import stbtt "third:stb/truetype"
import gl "vendor:OpenGL"
import mu "vendor:microui"

_ :: stbi

FONT_ATLAS_WIDTH :: 512
FONT_ATLAS_HEIGHT :: 512
FONT_HEIGHT :: 18
FONT_FIRST_CODEPOINT :: 32
FONT_LAST_CODEPOINT :: 255
POINTS_TO_PIXELS :: f32(96) / f32(72)

Font :: struct {
	info:   stbtt.fontinfo,
	data:   []byte,
	glyphs: []stbtt.packedchar,
	tex:    Texture,
	icons:  [mu.Icon]mu.Rect,
	pixel:  mu.Vec2, // single pixel (for rectangles)
}

UI_State :: struct {
	ctx:      ^mu.Context,
	font:     Font,
	// Rendering
	vao:      Vertex_Array,
	vbo, ebo: Buffer,
	shader:   Shader,
}

mu_init_ui :: proc(state: ^State) {
	state.ui.ctx = new(mu.Context)
	mu.init(state.ui.ctx)
	state.ui.ctx.style.font = cast(mu.Font)&state.ui.font

	font_data, ok := os.read_entire_file("assets/fonts/Inter/Inter-Bold.ttf")
	// font_data, ok := os.read_entire_file("assets/fonts/Jellee/Jellee-Bold.ttf")
	assert(ok)
	state.ui.font.data = font_data

	assert(!!stbtt.InitFont(&state.ui.font.info, raw_data(font_data), 0))

	{
		ICONS :: [?]mu.Icon{.CLOSE, .CHECK, .COLLAPSED, .EXPANDED, .RESIZE}

		font_img := create_image(
			"::/font.png",
			FONT_ATLAS_WIDTH,
			FONT_ATLAS_HEIGHT,
			1,
			false,
			context.temp_allocator,
		)
		defer destroy_image(&font_img, false)
		defer when ODIN_DEBUG do stbi.write_bmp(
			"font.bmp",
			font_img.width,
			font_img.height,
			font_img.channels,
			raw_data(font_img.data),
		)

		ranges: [1]stbtt.pack_range
		ranges[0].first_unicode_codepoint_in_range = FONT_FIRST_CODEPOINT
		// ranges[0].num_chars = i32('~' - ' ')
		ranges[0].num_chars = FONT_LAST_CODEPOINT - FONT_FIRST_CODEPOINT
		ranges[0].font_size = stbtt.POINT_SIZE(f32(FONT_HEIGHT))
		state.ui.font.glyphs = make([]stbtt.packedchar, ranges[0].num_chars)
		ranges[0].chardata_for_range = raw_data(state.ui.font.glyphs)

		num_chars: i32 = 0
		for range in ranges {
			num_chars += range.num_chars
		}

		// `+ 1` for single pixel
		rects := make([]stbrp.Rect, num_chars + len(ICONS) + 1, context.temp_allocator)
		defer delete(rects, context.temp_allocator)

		pctx: stbtt.pack_context
		stbtt.PackBegin(
			&pctx,
			raw_data(font_img.data),
			FONT_ATLAS_WIDTH,
			FONT_ATLAS_HEIGHT,
			0,
			1,
			nil,
		)
		defer stbtt.PackEnd(&pctx)
		stbtt.PackSetOversampling(&pctx, 2, 2)

		stbtt.PackFontRangesGatherRects(
			&pctx,
			&state.ui.font.info,
			&ranges[0],
			cast(i32)len(ranges),
			raw_data(rects),
		)

		{
			px_rect := slice.last_ptr(rects)
			px_rect.w = 1
			px_rect.h = 1
		}

		{
			icon_rects := rects[num_chars:len(rects) - 1]
			assert(len(icon_rects) == len(ICONS))
			for icon, i in ICONS {
				src := mu.default_atlas[i32(icon)]
				icon_rects[i].w = cast(stbrp.Coord)src.w
				icon_rects[i].h = cast(stbrp.Coord)src.h
			}
		}

		assert(
			1 ==
			stbrp.pack_rects(
				cast(^stbrp.Context)pctx.pack_info,
				raw_data(rects),
				cast(i32)len(rects),
			),
			"Didn't pack all rects",
		)

		stbtt.PackFontRangesRenderIntoRects(
			&pctx,
			&state.ui.font.info,
			&ranges[0],
			cast(i32)len(ranges),
			raw_data(rects),
		)

		{
			px_rect := slice.last(rects)
			x, y := cast(i32)px_rect.x, cast(i32)px_rect.y
			state.ui.font.pixel = {x, y}
			font_img.data[y * font_img.width + x] = 255
		}

		{
			icon_rects := rects[num_chars:len(rects) - 1]
			assert(len(icon_rects) == len(ICONS))
			for icon, i in ICONS {
				assert(cast(bool)icon_rects[i].was_packed)
				src := mu.default_atlas[i32(icon)]
				rect := icon_rects[i]

				icon_rect := &state.ui.font.icons[icon]
				icon_rect.x = cast(i32)icon_rects[i].x
				icon_rect.y = cast(i32)icon_rects[i].y
				icon_rect.w = cast(i32)icon_rects[i].w
				icon_rect.h = cast(i32)icon_rects[i].h

				for y in 0 ..< src.h {
					dst_offset := (i32(rect.y) + y) * font_img.width + i32(rect.x)
					src_offset := (src.y + y) * mu.DEFAULT_ATLAS_WIDTH + src.x
					mem.copy_non_overlapping(
						&font_img.data[dst_offset],
						&mu.default_atlas_alpha[src_offset],
						cast(int)src.w,
					)
				}

				// FIXME: add cropping to blit function
				// image_blit(
				// 	&font_img,
				// 	{width = src.w, height = src.h, data = potato, channels = 1},
				// 	cast(i32)icon_rects[i].x,
				// 	cast(i32)icon_rects[i].y,
				// )
			}
		}

		state.ui.font.tex = image_to_texture(font_img, .Clamp_To_Edge, mipmap = false)

		state.ui.ctx.text_height = proc(font_ptr: mu.Font) -> i32 {
			font := cast(^Font)font_ptr
			scale := stbtt.ScaleForMappingEmToPixels(&font.info, FONT_HEIGHT)

			ascent, descent, line_gap: i32
			stbtt.GetFontVMetrics(&font.info, &ascent, &descent, &line_gap)

			height := f32(ascent - descent + line_gap) * scale + 0.5

			return cast(i32)math.round(height)
		}
		state.ui.ctx.text_width = proc(font_ptr: mu.Font, str: string) -> i32 {
			font := cast(^Font)font_ptr
			scale := stbtt.ScaleForMappingEmToPixels(&font.info, FONT_HEIGHT * POINTS_TO_PIXELS)

			width: f32 = 0
			i := 0
			str := str
			for i < len(str) {
				char, char_sz := utf8.decode_rune(str)
				i += char_sz
				str = str[char_sz:]

				glyph_index := stbtt.FindGlyphIndex(&font.info, char)

				box: [2]mu.Vec2
				stbtt.GetGlyphBitmapBox(
					&font.info,
					glyph_index,
					scale,
					scale,
					&box[0].x,
					&box[0].y,
					&box[1].x,
					&box[1].y,
				)

				advance_width, left_side_bearing: i32
				stbtt.GetGlyphHMetrics(&font.info, glyph_index, &advance_width, &left_side_bearing)

				width += f32(left_side_bearing + advance_width) * scale

				if i + 1 < len(str) {
					char2, _ := utf8.decode_rune(str)
					glyph_index_2 := stbtt.FindGlyphIndex(&font.info, char2)

					kerning := stbtt.GetGlyphKernAdvance(&font.info, glyph_index, glyph_index_2)
					width += f32(kerning) * scale
				}
			}

			return cast(i32)math.round(width)
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
	vertex_attrib_pointer(0, 2, .Float, false, size_of(Vert), offset_of(Vert, pos))
	// tex_coord [x,y]
	vertex_attrib_pointer(1, 2, .Float, false, size_of(Vert), offset_of(Vert, tex_coord))
	// colour [rgba]
	vertex_attrib_i_pointer(2, 1, .Unsigned_Int, size_of(Vert), offset_of(Vert, colour))

	// unbind_buffer(.Element_Array)
	unbind_buffer(.Array)
	unbind_vertex_array()
}

mu_destroy_ui :: proc(state: ^State) {
	delete(state.ui.font.glyphs)
	delete(state.ui.font.data)
	destroy_texture(&state.ui.font.tex)
	destroy_shader(&state.ui.shader)
	destroy_buffer(&state.ui.vbo)
	destroy_buffer(&state.ui.ebo)
	destroy_vertex_array(&state.ui.vao)
	free(state.ui.ctx)
}

mu_update_ui :: proc(state: ^State, dt: f64) {
	wnd := &state.window
	ctx := state.ui.ctx

	if .UI in wnd.flags {
		buttons_map := [mu.Mouse]Mouse_Button {
			.LEFT   = .Left,
			.RIGHT  = .Right,
			.MIDDLE = .Middle,
		}

		key_map := [mu.Key][2]Key {
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

	if mu.window(ctx, "Minceraft", {10, 10, 400, 260}, {.NO_CLOSE, .NO_RESIZE}) {
		LABEL_WIDTH :: 160

		mu.layout_row(ctx, {LABEL_WIDTH, -1})

		mu.label(ctx, "Frame Time:")
		mu.text(ctx, fmt.tprintf("{:.3f}", dt))

		mu.label(ctx, "Coords:")
		mu.text(
			ctx,
			fmt.tprintf(
				"X: {:.1f}, Y: {:.1f}, Z: {:.1f}",
				state.camera.pos.x,
				state.camera.pos.y,
				state.camera.pos.z,
			),
		)

		mu.label(ctx, "Camera:")
		mu.text(
			ctx,
			fmt.tprintf(
				"Yaw: {:.1f}, Pitch: {:.1f}",
				glm.mod(glm.abs(state.camera.yaw), 360),
				state.camera.pitch,
			),
		)

		mu.label(ctx, "Render Distance:")
		temp_render_distance := cast(f32)state.render_distance
		mu.number(ctx, &temp_render_distance, 1, "%.0f")
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
	}
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
		bind_texture(state.ui.font.tex)
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

		unbind_buffer(.Array)
		unbind_vertex_array()

		buf_idx = 0
	}

	RectF :: struct {
		x, y, w, h: f32,
	}

	push_quad :: proc(state: ^State, dst: RectF, src: RectF, colour: mu.Color) {
		if buf_idx == BUF_SZ {flush(state)}

		tex_idx := buf_idx * 4
		element_idx := buf_idx * 4
		index_idx := buf_idx * 6
		buf_idx += 1

		x := src.x / FONT_ATLAS_WIDTH
		y := src.y / FONT_ATLAS_HEIGHT
		w := src.w / FONT_ATLAS_WIDTH
		h := src.h / FONT_ATLAS_HEIGHT

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
		x, y := state.ui.font.pixel.x, state.ui.font.pixel.y
		dst := RectF{f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)}
		push_quad(state, dst, {f32(x), f32(y), 1, 1}, colour)
		when FLUSH_ALL do flush(state)
	}

	draw_text :: proc(state: ^State, text: string, pos: mu.Vec2, colour: mu.Color) {
		font := &state.ui.font

		scale := stbtt.ScaleForMappingEmToPixels(&font.info, FONT_HEIGHT * POINTS_TO_PIXELS)
		x, y := f32(pos.x), f32(pos.y)
		quad: stbtt.aligned_quad

		y += FONT_HEIGHT

		text := text
		for len(text) > 0 {
			// FIXME: non-ascii codepoints
			char, char_sz := utf8.decode_rune(text)
			text = text[char_sz:]
			char_index := i32(char - ' ')
			assert(char_index >= 0 && char_index < 96)

			// NOTE: 1 for width/height is passed here so no uv scaling is performed
			stbtt.GetPackedQuad(raw_data(font.glyphs), 1, 1, char_index, &x, &y, &quad, false)

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

			push_quad(state, dst, src, colour)

			if len(text) > 0 {
				char2, _ := utf8.decode_rune(text)
				kerning := stbtt.GetCodepointKernAdvance(&font.info, char, char2)
				x += f32(kerning) * scale
			}
		}
	}

	draw_icon :: proc(state: ^State, id: mu.Icon, rect: mu.Rect, colour: mu.Color) {
		src_i := state.ui.font.icons[id]
		src := RectF{f32(src_i.x), f32(src_i.y), f32(src_i.w), f32(src_i.h)}
		x := cast(f32)(rect.x + (rect.w - src_i.w) / 2)
		y := cast(f32)(rect.y + (rect.h - src_i.h) / 2)
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
	pos:       glm.vec2,
	tex_coord: glm.vec2,
	colour:    mu.Color,
}
@(private = "file")
vbo_buf: [BUF_SZ * 4]Vert
@(private = "file")
ebo_buf: [BUF_SZ * 6]u32
@(private = "file")
buf_idx: u32 = 0
