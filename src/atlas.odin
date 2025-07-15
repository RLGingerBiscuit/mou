package mou

import "core:log"
import glm "core:math/linalg/glsl"
import "core:os"
import path "core:path/filepath"
import "core:strings"
import stbi "vendor:stb/image"

_ :: stbi

ATLAS_WIDTH :: 128
ATLAS_HEIGHT :: 128
ATLAS_PADDING :: 1

Atlas :: struct {
	uvs:       map[string][2]glm.vec2,
	texture:   Texture,
}

make_atlas :: proc(asset_path: string) -> (atlas: Atlas) {
	atlas.uvs = make(map[string][2]glm.vec2)

	asset_fd, _ := os.open(asset_path)
	defer os.close(asset_fd)

	Packer :: struct {
		atlas:        ^Atlas,
		img:          ^Image,
		max_y_in_row: i32,
		coords:       [2]i32,
	}

	atlas_img := create_image(
		"::/atlas.png",
		ATLAS_WIDTH,
		ATLAS_HEIGHT,
		do_log = false,
		allocator = context.temp_allocator,
	)
	defer destroy_image(&atlas_img, false)
	defer when ODIN_DEBUG do stbi.write_bmp(
		"atlas.bmp",
		atlas_img.width,
		atlas_img.height,
		atlas_img.channels,
		raw_data(atlas_img.data),
	)

	packer := Packer {
		atlas  = &atlas,
		img    = &atlas_img,
		coords = {ATLAS_PADDING, ATLAS_PADDING},
	}

	log.debug("Collecting textures...")
	path.walk(asset_path, _walk_proc, &packer)

	atlas.texture = image_to_texture(atlas_img)

	_walk_proc :: proc(
		info: os.File_Info,
		in_err: os.Error,
		data: rawptr,
	) -> (
		err: os.Error,
		skip_dir: bool,
	) {
		packer := cast(^Packer)data

		if info.is_dir {
			if info.name != "textures" {
				skip_dir = true
			}
			return
		}

		img := load_image(info.fullpath, false, context.temp_allocator)
		defer destroy_image(&img, false)

		log.debugf("\tFound '{}'", info.name)

		if packer.img.width - packer.coords.x < img.width {
			packer.coords.y += packer.max_y_in_row + ATLAS_PADDING
			packer.coords.x = ATLAS_PADDING
			packer.max_y_in_row = 0
		}

		packer.max_y_in_row = max(packer.max_y_in_row, img.height)

		image_blit(packer.img, img, packer.coords.x, packer.coords.y)

		start_uv := [2]f32{f32(packer.coords.x), f32(packer.coords.y)}
		end_uv := start_uv + {f32(img.width), f32(img.height)}

		// Yippee 0 to 1 is so fun :^)
		start_uv = {start_uv.x / ATLAS_WIDTH, start_uv.y / ATLAS_HEIGHT}
		end_uv = {end_uv.x / ATLAS_WIDTH, end_uv.y / ATLAS_HEIGHT}

		name := strings.clone(info.name)
		packer.atlas.uvs[name] = {start_uv, end_uv}

		packer.coords.x += img.width + ATLAS_PADDING

		return
	}

	return
}

destroy_atlas :: proc(atlas: ^Atlas) {
	for name in atlas.uvs {
		delete(name)
	}
	delete(atlas.uvs)
	destroy_texture(&atlas.texture)
	atlas^ = {}
}
