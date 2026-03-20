struct PushConstants
{
    float4 camera_pos;
    float4 camera_forward;
    float4 camera_right;
    float4 camera_up;
    uint4 input_state;
    float mouse_x;
    float mouse_y;
    float width;
    float height;
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

float3 prev(int2 coord)
{
    return images[scene.pool_idx + scene.prev_idx].Load(coord).rgb;
}

float3 read(uint image, int2 coord)
{
    uint idx = scene.start_idx + image;
    uint wrapped = (idx >= scene.image_count) ? idx - scene.image_count : idx;
    return images[scene.pool_idx + wrapped].Load(coord).rgb;
}
