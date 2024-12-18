vec4 linear_fog(vec4 colour, float vertex_distance, float fog_start, float fog_end, vec4 fog_colour) {
    if (vertex_distance <= fog_start) {
        return colour;
    }

    float fog_value = vertex_distance < fog_end ? smoothstep(fog_start, fog_end, vertex_distance) : 1.0;
    return vec4(mix(colour.rgb, fog_colour.rgb, fog_value * fog_colour.a), colour.a);
}
