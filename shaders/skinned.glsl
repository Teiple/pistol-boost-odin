@header package shaders
@header import sg "../sokol-odin/sokol/gfx"
@ctype mat4 matrix[4,4]f32

@vs vs_skinned
layout(binding=0) uniform vs_skinned_params {
    mat4 mvp;
    mat4 bones[64];
};

in vec4 pos;
in vec4 color0;
in vec2 texcoord0;
in vec4 joints;
in vec4 weights;

out vec4 color;
out vec2 uv;

void main() {
    mat4 skin_mat =
        weights.x * bones[int(joints.x)] +
        weights.y * bones[int(joints.y)] +
        weights.z * bones[int(joints.z)] +
        weights.w * bones[int(joints.w)];

    vec4 skinned_pos = skin_mat * pos;
    gl_Position = mvp * skinned_pos;
    color = color0;
    uv = texcoord0;
}
@end

@fs fs_skinned
layout(binding=0) uniform texture2D skinned_tex;
layout(binding=0) uniform sampler skinned_smp;

in vec4 color;
in vec2 uv;
out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(skinned_tex, skinned_smp), uv) * color;
}
@end

@program skinned vs_skinned fs_skinned
