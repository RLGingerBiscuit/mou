#version 330 core

#include <include/fog.glsl>

in vec2 tex_coord;
in vec4 vertex_colour;
in float vertex_distance;

out vec4 frag_colour;

uniform sampler2D atlas;
uniform float fog_start;
uniform float fog_end;
uniform vec4 fog_colour;

void main() {
    vec4 colour = texture(atlas, tex_coord) * vertex_colour;
    if (colour.a < 0.1) {
        discard;
    }
    frag_colour = linear_fog(colour, vertex_distance, fog_start, fog_end, fog_colour);
}
