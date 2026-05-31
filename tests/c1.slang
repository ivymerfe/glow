// source: https://www.shadertoy.com/view/Ms2SD1 - Seascape by TDM
import base;

const static int NUM_STEPS = 32;
const static float PI = 3.141592;
const static float EPSILON = 1e-5;

const static int ITER_GEOMETRY = 3;
const static int ITER_FRAGMENT = 5;
const static float SEA_HEIGHT = 0.4;
const static float SEA_CHOPPY = 4.0;
const static float SEA_SPEED = 1.2;
const static float SEA_FREQ = 0.2;
const static float3 SEA_BASE = float3(0.0, 0.09, 0.18);
const static float3 SEA_WATER_COLOR = float3(0.1, 0.9, 0.6) * 0.6;
const static float2x2 octave_m = float2x2(1.6, 1.2, -1.2, 1.6);

float hash( float2 p ) {
	 float h = dot(p,float2(127.1,311.7));	
    return fract(sin(h)*43758.5453123);
}

// float hash(float2 p)
// {
//     // split dot product into high and low parts
//     float2 p_hi = floor(p);
//     float2 p_lo = p - p_hi;
//     float h_hi = dot(p_hi, float2(127.1, 311.7));
//     float h_lo = dot(p_lo, float2(127.1, 311.7));
//     return frac(sin(h_hi + h_lo) * 43758.5453123);
// }

float noise( in float2 p ) {
    float2 i = floor( p );
    float2 f = fract( p );	
	float2 u = f*f*(3.0-2.0*f);
    float a = hash(i + float2(0, 0));
    float b = hash(i + float2(1, 0));
    float c = hash(i + float2(0, 1));
    float d = hash(i + float2(1, 1));
    return -1.0 + 2.0 * lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y); 
}

float sea_octave(float2 uv, float choppy)
{
    uv += noise(uv);
    float2 wv = 1.0 - abs(sin(uv));
    float2 swv = abs(cos(uv));
    wv = lerp(wv, swv, saturate(wv));
    return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
}

float map(float3 p, float time)
{
    float freq = SEA_FREQ;
    float amp = SEA_HEIGHT;
    float choppy = SEA_CHOPPY;
    float2 uv = p.xz;
    uv.x *= 0.75;
    float d, h = 0.0;

    for (int i = 0; i < ITER_GEOMETRY; i++)
    {
        d = sea_octave((uv + time) * freq, choppy);
        d += sea_octave((uv - time) * freq, choppy);
        h += d * amp;
        uv = mul(uv, octave_m);
        freq *= 1.9;
        amp *= 0.22;
        choppy = lerp(choppy, 1.0, 0.2);
    }

    return p.y - h;
}

float map_detailed(float3 p, float time)
{
    float freq = SEA_FREQ;
    float amp = SEA_HEIGHT;
    float choppy = SEA_CHOPPY;
    float2 uv = p.xz;
    uv.x *= 0.75;
    float d, h = 0.0;

    for (int i = 0; i < ITER_FRAGMENT; i++)
    {
        d = sea_octave((uv + time) * freq, choppy);
        d += sea_octave((uv - time) * freq, choppy);
        h += d * amp;
        uv = mul(uv, octave_m);
        freq *= 1.9;
        amp *= 0.22;
        choppy = lerp(choppy, 1.0, 0.2);
    }

    return p.y - h;
}

float diffuse(float3 n, float3 l, float p)
{
    return pow(dot(n, l) * 0.4 + 0.6, p);
}

float specular(float3 n, float3 l, float3 e, float s)
{
    float nrm = (s + 8.0) / (PI * 8.0);
    return pow(max(dot(reflect(e, n), l), 0.0), s) * nrm;
}

float3 getSkyColor(float3 e)
{
    e.y = (max(e.y, 0.0) * 0.8 + 0.2) * 0.8;
    return float3(pow(1.0 - e.y, 2.0), 1.0 - e.y, 0.6 + (1.0 - e.y) * 0.4) * 1.1;
}

float3 getSeaColor(float3 p, float3 n, float3 l, float3 eye, float3 dist)
{
    float fresnel = clamp(1.0 - dot(n, -eye), 0.0, 1.0);
    fresnel = min(fresnel * fresnel * fresnel, 0.5);

    float3 reflected = getSkyColor(reflect(eye, n));
    float3 refracted = SEA_BASE + diffuse(n, l, 80.0) * SEA_WATER_COLOR * 0.12;

    float3 color = lerp(refracted, reflected, fresnel);
    float atten = max(1.0 - dot(dist, dist) * 0.001, 0.0);
    color += SEA_WATER_COLOR * (p.y - SEA_HEIGHT) * 0.18 * atten;
    color += specular(n, l, eye, 600.0 / sqrt(dot(dist, dist)));

    return color;
}

float3 getNormal(float3 p, float eps, float time)
{
    float3 n;
    n.y = map_detailed(p, time);
    n.x = map_detailed(p + float3(eps, 0, 0), time) - n.y;
    n.z = map_detailed(p + float3(0, 0, eps), time) - n.y;
    n.y = eps;
    return normalize(n);
}

float heightMapTracing(float3 ori, float3 dir, out float3 p, float time)
{
    float tm = 0.0;
    float tx = 1000.0;
    float hx = map(ori + dir * tx, time);
    if (hx > 0.0)
    {
        p = ori + dir * tx;
        return tx;
    }

    float hm = map(ori, time);
    for (int i = 0; i < NUM_STEPS; i++)
    {
        float tmid = lerp(tm, tx, hm / (hm - hx));
        p = ori + dir * tmid;
        float hmid = map(p, time);
        if (hmid < 0.0)
        {
            tx = tmid;
            hx = hmid;
        }
        else
        {
            tm = tmid;
            hm = hmid;
        }
        if (abs(hmid) < EPSILON)
            break;
    }
    return lerp(tm, tx, hm / (hm - hx));
}

[shader("pixel")]
[glowCamera]
float4 main(VertexOutput in) : SV_Target0
{
    float2 uv = in.uv * 2.0 - 1.0;
    uv.y *= -1.0;
    uv.x *= scene.resolution.x / scene.resolution.y;

    float time = scene.time;

    float3 ori = scene.position;
    ori.y += 10;
    float3 dir = normalize(scene.right * uv.x + scene.up * uv.y + scene.forward * 1.5).xyz;

    float3 p;
    heightMapTracing(ori, dir, p, time);
    float3 dist = p - ori;
    float3 n = getNormal(p, 0.01, time);
    float3 light = normalize(float3(0.0, 1.0, 0.8));

    float3 col = lerp(
        getSkyColor(dir),
        getSeaColor(p, n, light, dir, dist),
        pow(smoothstep(0.0, -0.02, dir.y), 0.2));

    return float4(pow(col, 2.2), 1.0);
}

