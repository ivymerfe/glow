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

struct VertexOutput
{
    float4 pos : SV_Position;
    float2 uv : POS_UV;
}

const static float PI = 3.1415926;

float3 palette(float t)
{
    float3 a = float3(0., 0., 0.);
    float3 b = float3(0.5, 0.5, 0.5);
    float3 c = float3(0.5, 1.0, 1.0);
    float3 d = float3(0.5, 0.4, 0.3);
    return a + b * cos(2. * PI * (c * t + d));
}

float g(float3 p, float s)
{
    p *= s;
    return abs(dot(sin(p), cos(p.zxy)) + 2.) / s;
}

[shader("pixel")]
float4 pass(VertexOutput in) : SV_Target0
{
    float2 uv = in.uv - 0.5;
    uv.x *= scene.aspect_ratio;
    float3 dir = normalize(float3(uv.x, uv.y, 1.0));
    float3 pos = float3(0., 0., scene.time * 0.1);
    float3 color = float3(0);
    float t = -1.0;
    for (int i = 0; i < 17; i++)
    {
        float3 p = float3(pos + dir * t);
        float d = abs(g(p, 2.0) - g(p, 4.0) - g(p, 10.)) / 3.;
        color += 0.1 * (palette(t)) / (abs(d) + 0.01);
        t += d + 0.4;
    }
    float2 r = (uv + 1) / 2;
    return float4(pow(tanh(color / 8.), 2.2), 1.0);
}
