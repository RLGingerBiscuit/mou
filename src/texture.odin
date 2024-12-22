package mou

import "core:log"
import "core:mem"
import "core:strings"
import gl "vendor:OpenGL"

Texture :: struct {
	handle:        u32,
	width, height: i32,
	// Only for debug
	name:          string,
	allocator:     mem.Allocator,
}

Format :: enum i32 {
	R8   = gl.R8,
	Red  = gl.RED,
	RGB  = gl.RGB,
	RGBA = gl.RGBA,
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

destroy_texture :: proc(tex: ^Texture) {
	context.allocator = tex.allocator
	log.debugf("Destroying texture '{}'", tex.name)
	gl.DeleteTextures(1, &tex.handle)
	delete(tex.name)
	tex^ = {}

}
