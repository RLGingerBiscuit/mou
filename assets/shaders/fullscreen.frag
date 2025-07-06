#version 330 core

in vec2 tex_coord;

out vec4 frag_colour;

uniform sampler2D u_scene;

void main() {
    frag_colour = texture(u_scene, tex_coord);
}
