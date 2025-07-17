#version 330 core

#include <include/utils.glsl>

layout(location = 0) in vec3 position0;
layout(location = 1) in uint colour0;

uniform mat4 u_proj_view;

out vec4 vertex_colour;

void main() {
    gl_Position = u_proj_view * vec4(position0, 1.0);
    vertex_colour = unpack_colour(colour0);
}
