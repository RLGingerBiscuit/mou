#include <include/utils.glsl>

layout(location = 0) in vec3 position0;
layout(location = 1) in vec2 tex_coord0;
layout(location = 2) in uint vertex_colour0;
layout(location = 3) in uint ao0;

// Per-frame
uniform float u_time;
uniform mat4 u_proj_view;
uniform vec3 u_campos;
uniform uint u_ao;
uniform uint u_ao_debug;

// Per-chunk
uniform ivec3 u_chunkpos;

out vec2 tex_coord;
flat out uint tex_layer;
out vec4 vertex_colour;
out float vertex_distance;

const float FLOW_SECONDS = 4;

const float HEIGHT_VARIANCE = 0.05;

void main() {
    vec3 position = position0 + vec3(u_chunkpos);

    // height movement
    position.y += HEIGHT_VARIANCE/2 - HEIGHT_VARIANCE/2 * sin(u_time);

    gl_Position = u_proj_view * vec4(position, 1.0);
    tex_coord = tex_coord0;
    tex_layer = unpack_tex_layer(ao0);
    vertex_distance = length(u_campos - position);

    // flowing
    tex_coord -= vec2(mod(u_time, FLOW_SECONDS) / FLOW_SECONDS);

    float ao = ubool(u_ao) ? unpack_ao(ao0) : 0;
    vertex_colour = colour_mix(vec4(1), vec4(vec3(0), 1), ao);
    if (!ubool(u_ao_debug))
        vertex_colour = vertex_colour * unpack_colour(vertex_colour0);
}
