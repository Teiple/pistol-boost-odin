@header package shaders
@header import sg "../sokol-odin/sokol/gfx"
@ctype float f32

@vs vs
in vec4 pos;
in vec4 color0;
in vec2 texcoord0;

out vec4 color;
out vec2 uv;

void main() {
    gl_Position = pos;
    color = color0;
    uv = texcoord0;
}
@end

@fs fs
layout(binding=0) uniform texture2D viewport_tex;
layout(binding=0) uniform sampler viewport_smp;
layout(binding=0) uniform viewport_fs_params {
    float gamma;
};

in vec4 color;
in vec2 uv;
out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(viewport_tex, viewport_smp), uv) * color;
    frag_color.rgb = pow(max(frag_color.rgb, vec3(0.0)), vec3(1.0 / gamma));
}
@end

@program viewport vs fs