import base;

float hash(float a, float b) {
    return fract(sin(a*127.1 + b*311.7)*40000);
}

float test_hash(  float ix , float iy, float z ) {
    float c = hash(ix,iy);
    float d = hash(ix+1,iy);
    return lerp(c,d, z);
}

[shader("pixel")]
float4 main(VertexOutput in) : SV_Target0
{
    float2 uv = in.uv;
    uv.y = 1 - uv.y;
    float val1 = test_hash(floor(uv.x*4),4,frac(uv.x*4));
    return float4(float3(val1),1);
}

