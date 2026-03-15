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
    uint base_idx;
    uint prev_idx;
    uint buf_count;
}

[[vk::push_constant]]
PushConstants scene;

readonly RWTexture2D[] buffers;

struct VertexOutput
{
    float4 pos : SV_Position;
    float2 uv : POS_UV;
}

float3 prev(uint2 coord)
{
    return buffers[scene.prev_idx].Load(int2(coord.x, coord.y)).rgb;
}

float3 buf0(uint2 coord)
{
    return buffers[scene.base_idx].Load(int2(coord.x, coord.y)).rgb;
}


float3 avg3x3(uint2 coord)
{
    float3 col = float3(0.0, 0.0, 0.0);
    col += prev(coord);
    col += prev(coord + uint2(-1, 0));
    col += prev(coord + uint2(0, -1));
    col += prev(coord + uint2(1, 0));
    col += prev(coord + uint2(0, 1));
    col += prev(coord + uint2(-1, -1));
    col += prev(coord + uint2(-1, 1));
    col += prev(coord + uint2(1, -1));
    col += prev(coord + uint2(1, 1));
    return col / 9.0;
}

[shader("pixel")]
float4 pass_buffer(VertexOutput in) : SV_Target0
{
    uint2 coord = uint2(in.uv * float2(1920, 1080));
    if (scene.frame_idx == 0)
    {
        float2 uv = in.uv;
        if (uv.x < 0.1 && uv.y < 0.1)
            return float4(1.0, 0.5, 0.0, 1.0);
        else if (uv.x > 0.9 && uv.y > 0.9)
            return float4(0.0, 0.5, 1.0, 1.0);
        else
            return float4(0.0, 0.0, 0.0, 1.0);
    }
    float3 col = avg3x3(coord);
    col *= 1.666;
    col.g *= abs(cos(2.5 * (col.r - col.b)));
    if (col.r > col.b)
        col.b *= 0.6;
    else
        col.r *= 0.6;

    return float4(saturate(col), 1.0);
}

float get_thickness(float3 col)
{
    return (col.r + col.g + col.b) / 2.0;
}

float3 get_normal(uint2 coord)
{
    float hx1 = get_thickness(buf0(coord + uint2(1, 0)));
    float hx0 = get_thickness(buf0(coord + uint2(-1, 0)));
    float hy1 = get_thickness(buf0(coord + uint2(0, 1)));
    float hy0 = get_thickness(buf0(coord + uint2(0, -1)));
    return normalize(float3(
        (hx0 - hx1) * 2.0,
        (hy0 - hy1) * 2.0,
        -1.0));
}

float3 get_background(float3 rd)
{
    float3 horizon = float3(0.7, 0.3, 0.9);
    float3 zenith = float3(0.2, 0.4, 0.9);
    float y = clamp(rd.y * 0.5 + 0.5, 0.0, 1.0);
    return lerp(horizon, zenith, pow(y, 0.8));
}

[shader("pixel")]
float4 pass_draw(VertexOutput in) : SV_Target0
{
    uint2 coord = uint2(in.uv * float2(1920, 1080));
    float3 ink = buf0(coord);
    float3 thickness = get_thickness(ink);
    float3 normal = get_normal(coord);
    float3 light_dir = normalize(float3(0.5, 0.7, -0.8));
    float diff = saturate(dot(normal, light_dir));

    float3 col = lerp(get_background(normal), ink, thickness);
    col *= diff * 0.7 + 0.4;

    return float4(pow(col, 2.2), 1.0);
}
