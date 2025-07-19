package mou

import "core:fmt"
import "core:log"
import glm "core:math/linalg/glsl"
import "core:os"
import path "core:path/filepath"
import "core:slice"
import "core:strings"
import gl "vendor:OpenGL"
import stbi "vendor:stb/image"
import stbrp "vendor:stb/rect_pack"

_ :: fmt
_ :: stbi

ATLAS_WIDTH :: 128
ATLAS_HEIGHT :: 128
ATLAS_MIPS :: 5
ATLAS_MIP_BIAS :: 0
ATLAS_PADDING :: 0

#assert(ATLAS_MIPS >= 1)

Atlas :: struct {
	uvs:     map[string][2]glm.vec2,
	texture: Texture,
}

make_atlas :: proc(asset_path: string) -> (atlas: Atlas) {
	atlas.uvs = make(map[string][2]glm.vec2)

	asset_fd, _ := os.open(asset_path)
	defer os.close(asset_fd)

	Packer :: struct {
		atlas: ^Atlas,
		imgs:  [dynamic]Image,
	}

	atlas_mips: [ATLAS_MIPS]Image

	for i in i32(0) ..< ATLAS_MIPS {
		w, h: i32 = ATLAS_WIDTH, ATLAS_HEIGHT
		w >>= u32(i)
		h >>= u32(i)
		atlas_mips[i] = create_image(
			"::/atlas.png",
			w,
			h,
			do_log = false,
			allocator = context.temp_allocator,
		)
	}
	defer {
		for i in 0 ..< ATLAS_MIPS {
			destroy_image(&atlas_mips[i], false)
		}
	}
	defer when ODIN_DEBUG {
		for i in 0 ..< ATLAS_MIPS {
			stbi.write_bmp(
				fmt.ctprintf("atlas{}.bmp", i),
				atlas_mips[i].width,
				atlas_mips[i].height,
				atlas_mips[i].channels,
				raw_data(atlas_mips[i].data),
			)
		}
	}

	packer := Packer {
		atlas = &atlas,
		imgs  = make([dynamic]Image, context.temp_allocator),
	}
	defer {
		for &img in packer.imgs {
			destroy_image(&img, false)
		}
		delete(packer.imgs)
	}

	log.debug("Collecting textures...")
	path.walk(asset_path, _walk_proc, &packer)

	// Place larger images first
	slice.sort_by(packer.imgs[:], proc(i, j: Image) -> bool {
		return i.width * i.height > j.width * j.height
	})

	ctx: stbrp.Context
	nodes := make([]stbrp.Node, ATLAS_WIDTH - ATLAS_PADDING, context.temp_allocator)
	defer delete(nodes, context.temp_allocator)
	stbrp.init_target(&ctx, ATLAS_WIDTH, ATLAS_HEIGHT, raw_data(nodes), i32(len(nodes)))

	rects := make([]stbrp.Rect, len(packer.imgs), context.temp_allocator)
	defer delete(rects, context.temp_allocator)

	for img, i in packer.imgs {
		rects[i] = {
			id = i32(i),
			w  = stbrp.Coord(img.width) + ATLAS_PADDING * 2,
			h  = stbrp.Coord(img.height) + ATLAS_PADDING * 2,
		}
	}

	if 0 == stbrp.pack_rects(&ctx, raw_data(rects), i32(len(rects))) {
		log.error("Could not pack all textures")
		os.exit(1)
	}

	// img[0] is always the largest
	tmp_data := make(
		[]u8,
		4 * (packer.imgs[0].width * packer.imgs[0].height) / 2,
		context.temp_allocator,
	)
	defer delete(tmp_data, context.temp_allocator)

	for img, i in packer.imgs {
		rect := rects[i]
		rect.x += ATLAS_PADDING
		rect.y += ATLAS_PADDING
		rect.w -= 2 * ATLAS_PADDING
		rect.h -= 2 * ATLAS_PADDING

		image_blit(&atlas_mips[0], img, i32(rect.x), i32(rect.y))
		when ATLAS_MIPS > 1 {
			for j in i32(1) ..< ATLAS_MIPS {
				mrect := rect
				mrect.x >>= u32(j)
				mrect.y >>= u32(j)
				mrect.w >>= u32(j)
				mrect.h >>= u32(j)

				tmp_img := Image {
					channels = img.channels,
					width    = i32(mrect.w),
					height   = i32(mrect.h),
					data     = tmp_data,
				}

				ret := stbi.resize_uint8(
					raw_data(img.data),
					img.width,
					img.height,
					0,
					raw_data(tmp_data),
					tmp_img.width,
					tmp_img.height,
					0,
					tmp_img.channels,
				)
				assert(ret == 1, "Could not resize image for mip")

				image_blit(&atlas_mips[j], tmp_img, i32(mrect.x), i32(mrect.y))
			}
		}

		start_uv := glm.vec2{f32(rect.x), f32(rect.y)}
		end_uv := start_uv + {f32(rect.w), f32(rect.h)}

		// Yippee 0 to 1 is so fun :^)
		start_uv = start_uv / {ATLAS_WIDTH, ATLAS_HEIGHT}
		end_uv = end_uv / {ATLAS_WIDTH, ATLAS_HEIGHT}

		name := path.base(img.name)
		name = strings.clone(name)
		packer.atlas.uvs[name] = {start_uv, end_uv}
	}

	atlas.texture = image_to_texture(
		atlas_mips[0],
		min_filter = Filter.Nearest_Mipmap_Linear,
		wrap = Wrap.Clamp_To_Edge,
		mipmap = false,
	)
	bind_texture(atlas.texture)
	defer unbind_texture()
	_ :: gl
	when ATLAS_MIPS > 1 {
		// TODO: nicer API for manual mips
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, ATLAS_MIPS - 1)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_LOD, 0)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LOD, ATLAS_MIPS - 1)
		gl.TexParameterf(gl.TEXTURE_2D, gl.TEXTURE_LOD_BIAS, ATLAS_MIP_BIAS)
		for i in i32(1) ..< ATLAS_MIPS {
			mip := atlas_mips[i]
			gl.TexImage2D(
				gl.TEXTURE_2D,
				i,
				cast(i32)atlas.texture.internal_format,
				mip.width,
				mip.height,
				0,
				cast(u32)atlas.texture.format,
				gl.UNSIGNED_BYTE,
				raw_data(mip.data),
			)
		}
	}

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

		log.debugf("\tFound '{}'", info.name)

		img := load_image(info.fullpath, false, context.temp_allocator)
		append(&packer.imgs, img)

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
