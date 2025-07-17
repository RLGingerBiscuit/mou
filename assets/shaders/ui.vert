#version 330 core

#include <include/utils.glsl>

layout(location = 0) in vec2 position0;
layout(location = 1) in vec2 tex_coord0;
layout(location = 2) in uint vertex_colour0;

uniform mat4 u_proj_view;

out vec2 tex_coord;
out vec4 vertex_colour;

void main() {
    gl_Position = u_proj_view * vec4(position0, 0.0, 1.0);
    tex_coord = tex_coord0;
    vertex_colour = unpack_colour(vertex_colour0);
}
