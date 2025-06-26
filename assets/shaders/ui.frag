#version 330 core

in vec2 tex_coord;
in vec4 vertex_colour;

out vec4 frag_colour;

uniform sampler2D font_tex;

void main() {
    frag_colour = vec4(texture(font_tex, tex_coord).x) * vertex_colour;
}
