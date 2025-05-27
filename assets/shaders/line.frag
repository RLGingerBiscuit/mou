#version 330 core

// in vec4 vertex_colour;

out vec4 frag_colour;

uniform vec3 u_line_colour;

void main() {
    // frag_colour = vec4(vertex_colour, 1);
    frag_colour = vec4(u_line_colour, 1);
}
