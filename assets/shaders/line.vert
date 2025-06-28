#version 330 core

layout(location = 0) in vec3 position0;
// layout(location = 1) in vec3 colour0;

uniform mat4 u_mvp;

// out vec3 vertex_colour;

void main() {
    gl_Position = u_mvp * vec4(position0, 1.0);
    // vertex_colour = colour0;
}
