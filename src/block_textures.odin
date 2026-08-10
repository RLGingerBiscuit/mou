package mou

import "core:log"
import "core:os"
import "core:path/filepath"
import gl "vendor:OpenGL"

BLOCK_TEXTURE_SIZE :: 128
BLOCK_TEXTURE_CHANNELS :: 4
BLOCK_TEXTURE_LEVELS :: 5 // 1 + 4 mips
BLOCK_TEXTURE_MIP_BIAS :: 0

#assert(BLOCK_TEXTURE_LEVELS >= 1)

make_block_textures :: proc(asset_path: string, mips := true) -> (tex: Texture) {
	level_count: i32 = BLOCK_TEXTURE_LEVELS if mips else 1

	tex = make_texture_array(
		"::/block_textures",
		BLOCK_TEXTURE_SIZE,
		BLOCK_TEXTURE_SIZE,
		len(Block_Texture),
		.RGBA,
		wrap = Wrap.Repeat,
		min_filter = Filter.Nearest_Mipmap_Linear if mips else Filter.Nearest,
		levels = level_count,
	)

	log.debugf("Loading block textures from '{}'...", asset_path)

	for name, texture in BLOCK_TEXTURE_ASSET_NAMES {
		path, path_err := filepath.join({asset_path, name}, context.temp_allocator)
		ensure(path_err == nil)
		defer delete(path, context.temp_allocator)

		if !os.exists(path) {
			log.panicf("Could not find block texture '{}'", path)
		}

		log.debugf("\tFound '{}' -> layer {}", name, i32(texture))

		// Every layer shares the one storage format, so force each texture to RGBA
		img := load_image(path, false, context.temp_allocator, BLOCK_TEXTURE_CHANNELS)
		defer destroy_image(&img, false)

		if img.width != BLOCK_TEXTURE_SIZE || img.height != BLOCK_TEXTURE_SIZE {
			log.panicf(
				"Block texture '{}' is {}x{}, expected {}x{}",
				name,
				img.width,
				img.height,
				BLOCK_TEXTURE_SIZE,
				BLOCK_TEXTURE_SIZE,
			)
		}

		texture_set_layer(tex, i32(texture), img.data)
	}

	if mips {
		texture_parameter(tex, gl.TEXTURE_MAX_LEVEL, level_count - 1)
		texture_parameter(tex, gl.TEXTURE_MIN_LOD, i32(0))
		texture_parameter(tex, gl.TEXTURE_MAX_LOD, level_count - 1)
		texture_parameter(tex, gl.TEXTURE_LOD_BIAS, BLOCK_TEXTURE_MIP_BIAS)
		// Layers are mipped independently, so unlike an atlas there's no bleeding between textures
		generate_texture_mipmap(tex)
	}

	return
}
