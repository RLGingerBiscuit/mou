package mou

import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import stbi "third:stb/image"

Image :: struct {
	data:          []byte `fmt:"-"`,
	width, height: i32,
	channels:      i32,
	_loaded:       bool `fmt:"-"`, // true if an image was loaded from disk, false otherwise
	// Only for debug
	name:          string,
	allocator:     mem.Allocator `fmt:"-"`,
}

create_image :: proc(
	name: string,
	width: i32,
	height: i32,
	channels: i32 = 4,
	do_log := true,
	allocator := context.allocator,
) -> (
	img: Image,
) {
	context.allocator = allocator

	if do_log do log.debugf("Creating image '{}'", name)

	img.data = make([]byte, width * height * channels)
	img.width = width
	img.height = height
	img.channels = channels

	img.name = strings.clone(name)
	img.allocator = allocator

	return
}

load_image :: proc(path: string, do_log := true, allocator := context.allocator) -> (img: Image) {
	context.allocator = allocator

	if do_log do log.debugf("Loading image '{}'", path)
	data, err := os.read_entire_file_or_err(path, context.temp_allocator)
	if err != nil {
		log.fatalf("\tError loading image '{}': {}", path, err)
		os.exit(1)
	}
	defer delete(data, context.temp_allocator)

	x, y, ch: i32
	raw := stbi.load_from_memory(raw_data(data), cast(i32)len(data), &x, &y, &ch, 0)
	img.data = raw[:x * y * ch]
	img.width = x
	img.height = y
	img.channels = ch

	img.name = strings.clone(path)
	img.allocator = allocator
	img._loaded = true

	return
}

destroy_image :: proc(img: ^Image, do_log := true) {
	context.allocator = img.allocator
	if do_log do log.debugf("Destroying image '{}'", img.name)
	if img._loaded {
		stbi.image_free(raw_data(img.data))
	} else {
		delete(img.data)
	}
	delete(img.name)
	img^ = {}
}

image_blit :: proc(destination: ^Image, source: Image, x, y: i32) {
	// TODO: alpha blending

	// bounds in destination image
	bounds: [2][2]i32
	bounds[0].x = x
	bounds[0].y = y
	bounds[1].x = x + source.width - 1
	bounds[1].y = y + source.height - 1

	// bounds in source image
	source_bounds: [2][2]i32
	source_bounds[1].x = source.width - 1
	source_bounds[1].y = source.height - 1

	if bounds[0].x < 0 {
		source_bounds[0].x += bounds[0].x
		bounds[0].x = 0
	}
	if bounds[0].y < 0 {
		source_bounds[0].y += bounds[0].y
		bounds[0].y = 0
	}

	if bounds[1].x >= destination.width {
		source_bounds[1].x = destination.width - bounds[0].x
		bounds[1].x = destination.width - 1
	}
	if bounds[1].y >= destination.height {
		source_bounds[1].y = destination.height - bounds[0].y
		bounds[1].y = destination.height - 1
	}

	clipped_width := bounds[1].x - bounds[0].x + 1
	clipped_height := bounds[1].y - bounds[0].y + 1

	if clipped_width <= 0 || clipped_height <= 0 {
		return
	}

	for dy in 0 ..< clipped_height {
		destination_offset :=
			destination.channels * ((bounds[0].y + dy) * destination.width + bounds[0].x)
		source_offset :=
			source.channels * ((source_bounds[0].y + dy) * source.width + source_bounds[0].x)

		if destination.channels == source.channels {
			mem.copy_non_overlapping(
				&destination.data[destination_offset],
				&source.data[source_offset],
				int(clipped_width * source.channels),
			)
			continue
		}
		assert(destination.channels > source.channels)

		if source.channels == 1 {
			// Grayscale
			for dx in 0 ..< clipped_width {
				sdx := dx * source.channels
				ddx := dx * destination.channels
				px := source.data[source_offset + sdx]
				destination.data[destination_offset + ddx + 0] = px
				if destination.channels == 2 {
					// Grayscale + Alpha
					destination.data[destination_offset + ddx + 1] = 255
				}
				if destination.channels >= 3 {
					// RGB(A)
					destination.data[destination_offset + ddx + 1] = px
					destination.data[destination_offset + ddx + 2] = px
				}
				if destination.channels >= 4 {
					// RGBA
					destination.data[destination_offset + ddx + 3] = 255
				}
			}
		} else if source.channels == 2 {
			// Grayscale + Alpha
			for dx in 0 ..< clipped_width {
				sdx := dx * source.channels
				ddx := dx * destination.channels
				g := source.data[source_offset + sdx + 0]
				a := source.data[source_offset + sdx + 1]
				destination.data[destination_offset + ddx + 0] = g
				destination.data[destination_offset + ddx + 1] = g
				destination.data[destination_offset + ddx + 2] = g
				if destination.channels >= 4 {
					// RGBA
					destination.data[destination_offset + ddx + 3] = a
				}
			}
		} else if source.channels == 3 {
			// RGB
			for dx in 0 ..< clipped_width {
				sdx := dx * source.channels
				ddx := dx * destination.channels
				mem.copy_non_overlapping(
					&destination.data[destination_offset + ddx],
					&source.data[source_offset + sdx],
					3,
				)
				if destination.channels >= 4 {
					// RGBA
					destination.data[destination_offset + ddx + 3] = 255
				}
			}
		}
	}
}
