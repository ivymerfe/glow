module vs;

struct PushConstants
{
    float4 camera_pos;
    float4 camera_forward;
    float4 camera_right;
    float4 camera_up;
    float2 mouse_pos;
    uint2 mouse_data;
    uint4 keyboard_pressed;
    uint4 keyboard_down;
    float aspect_ratio;
    float time;
    uint frame_index;
}

[[vk::push_constant]]
PushConstants scene;

struct VertexOutput
{
    float4 pos : SV_Position;
    float2 uv : POS_UV;
}

static const float2 TRI[3] = {
    float2(-1.0, -1.0),
    float2(+3.0, -1.0),
    float2(-1.0, +3.0),
};

[shader("vertex")]
VertexOutput main(uint vertexIndex: SV_VertexID)
{
    VertexOutput out;
    out.pos.xy = TRI[vertexIndex];
    out.uv.x = (out.pos.x + 1.0) * 0.5;
    out.uv.y = (out.pos.y + 1.0) * 0.5;
    return out;
}
