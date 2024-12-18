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
	Alpha = gl.ALPHA,
	RGB   = gl.RGB,
	RGBA  = gl.RGBA,
}

image_to_texture :: proc(
	img: Image,
	format := Format.RGBA,
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

	gl.GenTextures(1, &tex.handle)
	gl.BindTexture(gl.TEXTURE_2D, tex.handle)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		cast(i32)format,
		tex.width,
		tex.height,
		0,
		cast(u32)format,
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
