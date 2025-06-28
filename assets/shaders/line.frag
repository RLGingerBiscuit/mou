#version 330 core

in vec4 vertex_colour;

out vec4 frag_colour;

void main() {
    frag_colour = vertex_colour;
}
