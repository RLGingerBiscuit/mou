package mou

import "core:log"
import "core:mem"
import "core:strings"
import gl "vendor:OpenGL"

Texture :: struct {
	handle:          u32,
	width, height:   i32,
	levels:          i32,
	format:          Format,
	internal_format: Internal_Format,
	wrap:            Wrap,
	min_filter:      Filter,
	mag_filter:      Filter,
	// Only for debug
	name:            string,
	allocator:       mem.Allocator,
}

Format :: enum u32 {
	Depth = gl.DEPTH_COMPONENT,
	Red   = gl.RED,
	RGB   = gl.RGB,
	RGBA  = gl.RGBA,
}

Internal_Format :: enum u32 {
	Depth24 = gl.DEPTH_COMPONENT24,
	R8      = gl.R8,
	RGB8    = gl.RGB8,
	RGBA8   = gl.RGBA8,
}

Wrap :: enum i32 {
	Clamp_To_Edge   = gl.CLAMP_TO_EDGE,
	Clamp_To_Border = gl.CLAMP_TO_BORDER,
	Mirrored_Repeat = gl.MIRRORED_REPEAT,
	Repeat          = gl.REPEAT,
}

Filter :: enum i32 {
	Nearest                = gl.NEAREST,
	Linear                 = gl.LINEAR,
	Nearest_Mipmap_Nearest = gl.NEAREST_MIPMAP_NEAREST,
	Linear_Mipmap_Nearest  = gl.LINEAR_MIPMAP_NEAREST,
	Nearest_Mipmap_Linear  = gl.NEAREST_MIPMAP_LINEAR,
	Linear_Mipmap_Linear   = gl.LINEAR_MIPMAP_LINEAR,
}

texture_format_size :: proc(format: Format) -> i32 {
	// odinfmt:disable
	switch format {
	case .Depth: return 1
	case .Red:   return 1
	case .RGB:   return 3
	case .RGBA:  return 4
	}
	// odinfmt:enable
	unreachable()
}

texture_internal_format :: proc(format: Format) -> Internal_Format {
	// odinfmt:disable
	switch format {
	case .Depth: return .Depth24
	case .Red:   return .R8
	case .RGB:   return .RGB8
	case .RGBA:  return .RGBA8
	}
	// odinfmt:enable
	unreachable()
}

texture_mipmap_level_count :: proc(width, height: i32) -> i32 {
	w := max(width, 1)
	h := max(height, 1)
	levels: i32 = 1
	for w > 1 || h > 1 {
		if w > 1 {
			w /= 2
		}
		if h > 1 {
			h /= 2
		}
		levels += 1
	}
	return levels
}

make_texture :: proc(
	name: string,
	width, height: i32,
	format: Format,
	wrap := Wrap.Repeat,
	min_filter := Filter.Nearest,
	mag_filter := Filter.Nearest,
	levels: i32 = 1,
	gen_mips := false,
	loc := #caller_location,
) -> (
	tex: Texture,
) {
	tex.name = strings.clone(name)
	tex.width = width
	tex.height = height
	tex.format = format
	tex.internal_format = texture_internal_format(format)
	tex.wrap = wrap
	tex.min_filter = min_filter
	tex.mag_filter = mag_filter

	levels := levels
	levels = max(1, min(levels, texture_mipmap_level_count(width, height)))
	tex.levels = levels

	when ODIN_DEBUG {
		gl.CreateTextures(gl.TEXTURE_2D, 1, &tex.handle, loc = loc)
		texture_parameter(tex, gl.TEXTURE_WRAP_S, cast(i32)wrap, loc = loc)
		texture_parameter(tex, gl.TEXTURE_WRAP_T, cast(i32)wrap, loc = loc)
		texture_parameter(tex, gl.TEXTURE_MIN_FILTER, cast(i32)min_filter, loc = loc)
		texture_parameter(tex, gl.TEXTURE_MAG_FILTER, cast(i32)mag_filter, loc = loc)
		gl.TextureStorage2D(
			tex.handle,
			levels,
			cast(u32)tex.internal_format,
			tex.width,
			tex.height,
			loc = loc,
		)
	} else {
		gl.CreateTextures(gl.TEXTURE_2D, 1, &tex.handle)
		texture_parameter(tex, gl.TEXTURE_WRAP_S, cast(i32)wrap)
		texture_parameter(tex, gl.TEXTURE_WRAP_T, cast(i32)wrap)
		texture_parameter(tex, gl.TEXTURE_MIN_FILTER, cast(i32)min_filter)
		texture_parameter(tex, gl.TEXTURE_MAG_FILTER, cast(i32)mag_filter)
		gl.TextureStorage2D(
			tex.handle,
			levels,
			cast(u32)tex.internal_format,
			tex.width,
			tex.height,
		)
	}

	return
}

texture_set_level :: proc(
	tex: Texture,
	level: i32,
	width, height: i32,
	data: []byte,
	loc := #caller_location,
) {
	if len(data) < int(width * height * texture_format_size(tex.format)) {
		log.warnf("Setting texture {} level {}: was not provided enough bytes", tex.name, level)
		return
	}
	when ODIN_DEBUG {
		gl.TextureSubImage2D(
			tex.handle,
			level,
			0,
			0,
			width,
			height,
			cast(u32)tex.format,
			gl.UNSIGNED_BYTE,
			raw_data(data),
			loc = loc,
		)
	} else {
		gl.TextureSubImage2D(
			tex.handle,
			level,
			0,
			0,
			width,
			height,
			cast(u32)tex.format,
			gl.UNSIGNED_BYTE,
			raw_data(data),
		)
	}
}

generate_texture_mipmap :: proc(tex: Texture, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.GenerateTextureMipmap(tex.handle, loc = loc)
	} else {
		gl.GenerateTextureMipmap(tex.handle)
	}
}

texture_parameter_i32 :: proc(tex: Texture, pname: u32, value: i32, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.TextureParameteri(tex.handle, pname, value, loc = loc)
	} else {
		gl.TextureParameteri(tex.handle, pname, value)
	}
}

texture_parameter_f32 :: proc(tex: Texture, pname: u32, value: f32, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.TextureParameterf(tex.handle, pname, value, loc = loc)
	} else {
		gl.TextureParameterf(tex.handle, pname, value)
	}
}

texture_parameter :: proc {
	texture_parameter_i32,
	texture_parameter_f32,
}

texture_set :: proc(tex: Texture, data: []byte, gen_mips := false, loc := #caller_location) {
	texture_set_level(tex, 0, tex.width, tex.height, data, loc = loc)
	if gen_mips {
		generate_texture_mipmap(tex, loc = loc)
	}
}

texture_update :: proc(tex: Texture, data: []byte, loc := #caller_location) {
	texture_set(tex, data, loc = loc)
}

image_to_texture :: proc(
	img: Image,
	wrap := Wrap.Repeat,
	min_filter := Filter.Nearest,
	mag_filter := Filter.Nearest,
	levels: i32 = 1,
	gen_mips := false,
	loc := #caller_location,
) -> (
	tex: Texture,
) {
	format: Format
	// odinfmt:disable
	switch img.channels {
	case 1: format = .Red
	case 3: format = .RGB
	case 4: format = .RGBA
	}
	// odinfmt:enable

	tex = make_texture(
		img.name,
		img.width,
		img.height,
		format,
		wrap,
		min_filter,
		mag_filter,
		levels,
		gen_mips,
		loc = loc,
	)
	texture_set(tex, img.data, loc = loc)
	return tex
}

load_texture :: proc(path: string) -> (tex: Texture) {
	img := load_image(path, false)
	defer destroy_image(&img, false)
	return image_to_texture(img)
}

bind_texture_unit :: proc(unit: u32, tex: Texture, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.BindTextureUnit(unit, tex.handle, loc = loc)
	} else {
		gl.BindTextureUnit(unit, tex.handle)
	}
}

unbind_texture_unit :: proc(unit: u32, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.BindTextureUnit(unit, 0, loc = loc)
	} else {
		gl.BindTextureUnit(unit, 0)
	}
}

destroy_texture :: proc(tex: ^Texture, loc := #caller_location) {
	log.debugf("Destroying texture '{}'", tex.name)
	when ODIN_DEBUG {
		gl.DeleteTextures(1, &tex.handle, loc = loc)
	} else {
		gl.DeleteTextures(1, &tex.handle)
	}
	delete(tex.name)
	tex^ = {}
}
