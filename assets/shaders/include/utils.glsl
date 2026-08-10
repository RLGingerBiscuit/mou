#define ALPHA_CUTOUT_THRESHOLD 0.1

vec4 unpack_colour(uint colour) {
    return vec4(
        (float((colour & uint(0x000000ff)) >> 0)) / 255,
        (float((colour & uint(0x0000ff00)) >> 8)) / 255,
        (float((colour & uint(0x00ff0000)) >> 16)) / 255,
        (float((colour & uint(0xff000000)) >> 24)) / 255
    );
}

vec4 colour_mix(vec4 a, vec4 b, float t) {
    return (1 - t) * a + t * b;
}

bool ubool(uint x) {
    return x != uint(0);
}

float unpack_ao(uint packed_ao) {
    return float(packed_ao & 0x3u) * 0.25;
}

uint unpack_tex_layer(uint packed_ao) {
    return (packed_ao >> 2) & 0xffu;
}
