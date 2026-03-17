struct PushConstants
{
    float4 camera_pos;
    float4 camera_forward;
    float4 camera_right;
    float4 camera_up;
    float2 mouse_pos;
    uint2 mouse_data;
    uint4 keyboard_down;
    float aspect_ratio;
    float time;
    uint frame_idx;
    uint pool_idx;
    uint start_idx;
    uint prev_idx;
    uint image_count;
}

[[vk::push_constant]]
PushConstants scene;

readonly RWTexture2D[] images;

struct VertexOutput
{
    float4 pos : SV_Position;
    float2 uv : POS_UV;
}

float3 prev(uint2 coord)
{
    return images[scene.pool_idx + scene.prev_idx].Load(int2(coord.x, coord.y)).rgb;
}

float3 read(uint image, uint2 coord)
{
    return images[scene.pool_idx + (scene.start_idx + image) % scene.image_count].Load(int2(coord.x, coord.y)).rgb;
}
