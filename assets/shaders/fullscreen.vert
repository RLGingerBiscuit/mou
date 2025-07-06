#version 330 core

layout(location = 0) in vec2 position0;
layout(location = 1) in vec2 tex_coord0;

out vec2 tex_coord;

void main() {
    gl_Position = vec4(position0, 0.0, 1.0);
    tex_coord = tex_coord0;
}
