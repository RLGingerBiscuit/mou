#version 330 core

#include <include/utils.glsl>

layout(location = 0) in vec3 position0;
layout(location = 1) in vec2 tex_coord0;
layout(location = 2) in uint vertex_colour0;
layout(location = 3) in float ao0;

// Per-frame
uniform float u_time;
uniform mat4 u_proj_view;
uniform vec3 u_campos;
uniform uint u_ao;
uniform uint u_ao_debug;

uniform float u_atlas_block_size;
uniform vec2 u_atlas_size;

// Per-chunk
uniform ivec3 u_chunkpos;

out vec2 tex_coord;
out vec4 vertex_colour;
out float vertex_distance;

const float FLOW_SECONDS = 4;

const float HEIGHT_VARIANCE = 0.05;

void main() {
    vec3 position = position0 + vec3(u_chunkpos);

    // height movement
    position.y += HEIGHT_VARIANCE/2 - HEIGHT_VARIANCE/2 * sin(u_time);

    gl_Position = u_proj_view * vec4(position, 1.0);
    tex_coord = tex_coord0 / 2.0 + vec2(u_atlas_block_size)/u_atlas_size;
    vertex_distance = length(u_campos - position);

    // flowing
    tex_coord -= vec2(mod(u_time, FLOW_SECONDS)) * vec2(u_atlas_block_size)/u_atlas_size/FLOW_SECONDS;

    float ao = ubool(u_ao) ? ao0 : 0;
    vertex_colour = colour_mix(vec4(1), vec4(vec3(0), 1), ao);
    if (!ubool(u_ao_debug))
        vertex_colour = vertex_colour * unpack_colour(vertex_colour0);
}
