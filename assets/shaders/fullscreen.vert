#version 460 core

out vec2 tex_coord;

void main() {
    float x = -1 + float((gl_VertexID & 1) << 2);
    float y = -1 + float((gl_VertexID & 2) << 1);
    gl_Position = vec4(x, y, 0.0, 1.0);
    tex_coord = vec2((x + 1) * 0.5, (y + 1) * 0.5);
}
