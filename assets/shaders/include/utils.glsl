vec4 unpack_colour(uint colour) {
    return vec4(
        (float((colour & uint(0x000000ff)) >> 0)) / 255,
        (float((colour & uint(0x0000ff00)) >> 8)) / 255,
        (float((colour & uint(0x00ff0000)) >> 16)) / 255,
        (float((colour & uint(0xff000000)) >> 24)) / 255
    );
}
