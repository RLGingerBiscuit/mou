#version 330 core

#include <include/fog.glsl>

in vec2 tex_coord;
in vec4 vertex_colour;
in float vertex_distance;

out vec4 frag_colour;

uniform sampler2D u_atlas;
uniform float u_fog_start;
uniform float u_fog_end;
uniform vec4 u_fog_colour;

void main() {
    vec4 colour = texture(u_atlas, tex_coord) * vertex_colour;
    if (colour.a < 0.1) {
        discard;
    }
    frag_colour = linear_fog(colour, vertex_distance, u_fog_start, u_fog_end, u_fog_colour);
}
