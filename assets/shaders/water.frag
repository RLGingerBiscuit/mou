#version 330 core

#include <include/fog.glsl>
#include <include/utils.glsl>

in vec2 tex_coord;
in vec4 vertex_colour;
in float vertex_distance;

layout(location = 0) out vec4 frag_colour;

// Per-frame
uniform sampler2D u_atlas;
uniform float u_fog_start;
uniform float u_fog_end;
uniform vec4 u_fog_colour;
uniform uint u_ao_debug;

// Per-chunk
uniform float u_visibility;

void main() {
    vec4 colour;
    if (ubool(u_ao_debug))
        colour = vertex_colour;
    else
        colour = texture(u_atlas, tex_coord) * vertex_colour;

    if (colour.a < 0.1) {
        discard;
    }

    colour = mix(u_fog_colour * vec4(1, 1, 1, colour.a), colour, u_visibility);
    frag_colour = linear_fog(colour, vertex_distance, u_fog_start, u_fog_end, u_fog_colour);
}
