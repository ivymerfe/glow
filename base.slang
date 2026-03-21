struct PushConstants
{
    float4 camera_pos;
    float4 camera_forward;
    float4 camera_right;
    float4 camera_up;
    uint[4] input_state;
    float2 mouse;
    float2 resolution;
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

bool isPressed(uint key)
{
    uint idx = key >> 5;
    uint bit = key & 31;
    return (scene.input_state[idx] & (1 << bit)) != 0;
}

static const uint KEY_MOUSE_LEFT = 0;
static const uint KEY_MOUSE_RIGHT = 1;
static const uint KEY_MOUSE_MIDDLE = 2;
static const uint KEY_MOUSE_4 = 3;
static const uint KEY_MOUSE_5 = 4;

static const uint KEY_A = 5;
static const uint KEY_B = 6;
static const uint KEY_C = 7;
static const uint KEY_D = 8;
static const uint KEY_E = 9;
static const uint KEY_F = 10;
static const uint KEY_G = 11;
static const uint KEY_H = 12;
static const uint KEY_I = 13;
static const uint KEY_J = 14;
static const uint KEY_K = 15;
static const uint KEY_L = 16;
static const uint KEY_M = 17;
static const uint KEY_N = 18;
static const uint KEY_O = 19;
static const uint KEY_P = 20;
static const uint KEY_Q = 21;
static const uint KEY_R = 22;
static const uint KEY_S = 23;
static const uint KEY_T = 24;
static const uint KEY_U = 25;
static const uint KEY_V = 26;
static const uint KEY_W = 27;
static const uint KEY_X = 28;
static const uint KEY_Y = 29;
static const uint KEY_Z = 30;

static const uint KEY_1 = 31;
static const uint KEY_2 = 32;
static const uint KEY_3 = 33;
static const uint KEY_4 = 34;
static const uint KEY_5 = 35;
static const uint KEY_6 = 36;
static const uint KEY_7 = 37;
static const uint KEY_8 = 38;
static const uint KEY_9 = 39;
static const uint KEY_0 = 40;

static const uint KEY_ENTER = 41;
static const uint KEY_ESCAPE = 42;
static const uint KEY_BACKSPACE = 43;
static const uint KEY_TAB = 44;
static const uint KEY_SPACE = 45;
static const uint KEY_MINUS = 46;
static const uint KEY_EQUAL = 47;
static const uint KEY_LEFT_BRACKET = 48;
static const uint KEY_RIGHT_BRACKET = 49;
static const uint KEY_BACKSLASH = 50;
static const uint KEY_SEMICOLON = 51;
static const uint KEY_APOSTROPHE = 52;
static const uint KEY_GRAVE = 53;
static const uint KEY_COMMA = 54;
static const uint KEY_PERIOD = 55;
static const uint KEY_SLASH = 56;

static const uint KEY_LEFT_CTRL = 96;
static const uint KEY_LEFT_SHIFT = 97;
static const uint KEY_LEFT_ALT = 98;
static const uint KEY_LEFT_SUPER = 99;
static const uint KEY_RIGHT_CTRL = 100;
static const uint KEY_RIGHT_SHIFT = 101;
static const uint KEY_RIGHT_ALT = 102;
static const uint KEY_RIGHT_SUPER = 103;
