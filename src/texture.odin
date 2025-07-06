package mou

import "core:log"
import "core:mem"
import "core:strings"
import gl "vendor:OpenGL"

Texture :: struct {
	handle:          u32,
	width, height:   i32,
	mipmap:          bool,
	format:          Format,
	internal_format: Format,
	// Only for debug
	name:            string,
	allocator:       mem.Allocator,
}

Format :: enum i32 {
	Depth = gl.DEPTH_COMPONENT,
	R8    = gl.R8,
	Red   = gl.RED,
	RGB   = gl.RGB,
	RGBA  = gl.RGBA,
}

Wrap :: enum i32 {
	Clamp_To_Edge   = gl.CLAMP_TO_EDGE,
	Clamp_To_Border = gl.CLAMP_TO_BORDER,
	Mirrored_Repeat = gl.MIRRORED_REPEAT,
	Repeat          = gl.REPEAT,
}

Filter :: enum i32 {
	Nearest = gl.NEAREST,
	Linear  = gl.LINEAR,
}

texture_format_bytes :: proc(format: Format) -> i32 {
	// odinfmt:disable
	switch format {
	case .Depth:	return 1 // TODO: Don't use unsized variant?
	case .R8, .Red:	return 1
	case .RGB:		return 3
	case .RGBA:		return 4
	}
	// odinfmt:enable
	unreachable()
}

make_texture :: proc(
	name: string,
	width, height: i32,
	format: Format,
	wrap := Wrap.Repeat,
	filter := Filter.Nearest,
	mipmap := true,
	allocator := context.allocator,
) -> (
	tex: Texture,
) {
	context.allocator = allocator

	tex.name = strings.clone(name)
	tex.width = width
	tex.height = height
	tex.mipmap = mipmap
	tex.format = format
	tex.allocator = allocator
	
	// odinfmt:disable
	switch tex.format {
	case .Depth:	tex.internal_format = .Depth
	case .R8, .Red:	tex.internal_format = .Red
	case .RGB:		tex.internal_format = .RGB
	case .RGBA:		tex.internal_format = .RGBA
	}
	// odinfmt:enable

	gl.GenTextures(1, &tex.handle)
	gl.BindTexture(gl.TEXTURE_2D, tex.handle)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, cast(i32)wrap)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, cast(i32)wrap)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, cast(i32)filter)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, cast(i32)filter)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		cast(i32)tex.format,
		tex.width,
		tex.height,
		0,
		cast(u32)tex.internal_format,
		gl.UNSIGNED_BYTE,
		nil,
	)
	gl.BindTexture(gl.TEXTURE_2D, 0)

	return
}

texture_set :: proc(tex: Texture, data: []byte) {
	if len(data) < int(tex.width * tex.height * texture_format_bytes(tex.format)) {
		log.warnf("Setting texture {}: was not provided enough bytes", tex.name)
		return
	}

	bind_texture(tex)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		cast(i32)tex.format,
		tex.width,
		tex.height,
		0,
		cast(u32)tex.internal_format,
		gl.UNSIGNED_BYTE,
		raw_data(data),
	)
	if tex.mipmap {
		gl.GenerateMipmap(gl.TEXTURE_2D)
	}
	unbind_texture()
}

texture_update :: proc(tex: Texture, data: []byte) {
	if len(data) < int(tex.width * tex.height * texture_format_bytes(tex.format)) {
		log.warnf("Setting texture {}: was not provided enough bytes", tex.name)
		return
	}
	bind_texture(tex)
	gl.TexSubImage2D(
		gl.TEXTURE_2D,
		0,
		0,
		0,
		tex.width,
		tex.height,
		cast(u32)tex.format,
		gl.UNSIGNED_BYTE,
		raw_data(data),
	)
	unbind_texture()
}

image_to_texture :: proc(
	img: Image,
	wrap := Wrap.Repeat,
	filter := Filter.Nearest,
	mipmap := true,
	allocator := context.allocator,
) -> (
	tex: Texture,
) {
	context.allocator = allocator

	tex.name = strings.clone(img.name)
	tex.width = img.width
	tex.height = img.height
	tex.mipmap = mipmap
	tex.allocator = allocator

	format: Format
	internal_format: Format
	// odinfmt:disable
	switch img.channels {
	case 1: format = .R8;   internal_format = .Red
	case 3: format = .RGB;  internal_format = .RGB
	case 4: format = .RGBA; internal_format = .RGBA
	}
	// odinfmt:enable

	tex.format = format
	tex.internal_format = internal_format

	gl.GenTextures(1, &tex.handle)
	gl.BindTexture(gl.TEXTURE_2D, tex.handle)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, cast(i32)wrap)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, cast(i32)wrap)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, cast(i32)filter)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, cast(i32)filter)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		cast(i32)format,
		tex.width,
		tex.height,
		0,
		cast(u32)internal_format,
		gl.UNSIGNED_BYTE,
		raw_data(img.data),
	)
	if mipmap {
		gl.GenerateMipmap(gl.TEXTURE_2D)
	}
	gl.BindTexture(gl.TEXTURE_2D, 0)

	return tex
}

load_texture :: proc(path: string) -> (tex: Texture) {
	img := load_image(path, false)
	defer destroy_image(&img, false)
	return image_to_texture(img)
}

bind_texture :: proc(tex: Texture) {
	gl.BindTexture(gl.TEXTURE_2D, tex.handle)
}

unbind_texture :: proc() {
	gl.BindTexture(gl.TEXTURE_2D, 0)
}

destroy_texture :: proc(tex: ^Texture) {
	context.allocator = tex.allocator
	log.debugf("Destroying texture '{}'", tex.name)
	gl.DeleteTextures(1, &tex.handle)
	delete(tex.name)
	tex^ = {}
}
