package noise

import "core:fmt"
import "core:image"
import stbi "vendor:stb/image"

main_ :: proc() {
	fmt.eprintln("Hellope!")

	W :: 4096
	H :: 4096

	pixels := make([]image.RGB_Pixel, W * H)

	for y in 0 ..< H {
		for x in 0 ..< W {
			// n := perlin2d(f32(x), f32(y))
			xf := f32(x)
			yf := f32(y)
			n :=
				(perlin2d(xf / 64.0, yf / 64.0) * 1.00 +
					perlin2d(xf / 32.0, yf / 32.0) * 0.50 +
					perlin2d(xf / 16.0, yf / 16.0) * 0.25 +
					perlin2d(xf / 8.0, yf / 8.0) * 0.125) /
				1.75


			b := u8((n * 0.5 + 0.5) * 255)
			px := image.RGB_Pixel{b, b, b}
			pixels[y * H + x] = px
		}
	}

	stbi.write_bmp("noise.png", W, H, 3, raw_data(pixels))
	// write_bmp :: proc(filename: cstring, w, h, comp: c.int, data: rawptr)                             -> c.int ---

}
