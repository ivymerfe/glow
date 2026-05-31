#version 450

layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 fragColor;

layout(push_constant) uniform PushConstants {
    vec2 resolution;
    vec2 mouse;
    uvec4 input_;
    vec3 position;
    float time;
    vec3 forward;
    uint frame_idx;
    vec3 right;
    uint pool_idx;
    vec3 up;
    uint start_idx;
    uint prev_idx;
    uint image_count;
} scene;

float hash(float a, float b) {
    return fract(sin(a*127.1 + b*311.7)*40000);
}

float test_hash(  float ix , float iy, float z ) {
    float c = hash(ix,iy);
    float d = hash(ix+1,iy);
    return mix(c,d, z);
}

void main()
{
    vec2 fuv = uv;
    fuv.y = 1.0 - fuv.y;

    float val1 = test_hash(floor(fuv.x*4.),4., fract(fuv.x*4.));

    fragColor = vec4(vec3(val1), 1.0);
}
