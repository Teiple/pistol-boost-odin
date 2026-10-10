@header package shaders
@header import sg "../sokol-odin/sokol/gfx"
@ctype mat4 matrix[4,4]f32

@vs vs
layout(binding=0) uniform unlit_vs_params {
    mat4 mvp;
};

in vec4 pos;
in vec4 color0;
in vec2 texcoord0;

out vec4 color;
out vec2 uv;

void main() {
    gl_Position = mvp * pos;
    color = color0;
    uv = texcoord0;
}
@end

@fs fs
layout(binding=0) uniform texture2D unlit_tex;
layout(binding=0) uniform sampler unlit_smp;

in vec4 color;
in vec2 uv;
out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(unlit_tex, unlit_smp), uv) * color;
}
@end

@program unlit vs fs