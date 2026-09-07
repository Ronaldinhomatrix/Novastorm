shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D planet_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 sun_direction = vec3(0.6, 0.4, 0.7);

uniform vec4 atmosphere_limb_color : source_color = vec4(0.2, 0.7, 1.0, 1.0);
uniform vec4 twilight_limb_color   : source_color = vec4(0.95, 0.5, 0.2, 1.0);
uniform float rim_power     : hint_range(1.0, 10.0) = 4.2;
uniform float rim_intensity : hint_range(0.1, 4.0)  = 2.0;

uniform float uv_scale  : hint_range(1e-06, 1e-03) = 3.5e-05;
uniform vec2  uv_offset = vec2(0.475, 0.475);

uniform float curve_start_radius = 4500.0;
uniform float curve_max_radius   = 12500.0;
uniform float curve_drop_height  = 3500.0;

// PC: true = bicubic smooth; Mobile: false = linear
uniform bool use_smooth_sampling = true;

// Opção 1: Micro-detalhamento fractal analítico (quebra o serrilhado de baixa resolução da textura)
uniform bool enable_procedural_detail = true;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.55;

varying vec2 v_local_xz;
varying vec3 v_world_pos;

// ---------------------------------------------------------------------------
// Ruído analítico procedural de alta velocidade (sem textura na VRAM)
// ---------------------------------------------------------------------------
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2(0.0, 0.0)), hash21(i + vec2(1.0, 0.0)), u.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}

// Fractal Brownian Motion (FBM) analítico de 3 oitavas
float procedural_fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
    for (int i = 0; i < 3; i++) {
        v += a * value_noise(p);
        p = rot * p * 2.02;
        a *= 0.5;
    }
    return v;
}

// ---------------------------------------------------------------------------
// Filtragem Quíntica C2-Contínua
// ---------------------------------------------------------------------------
vec4 texture_bicubic(sampler2D tex, vec2 uv) {
    vec2 tex_size    = vec2(textureSize(tex, 0));
    vec2 pixel       = uv * tex_size - 0.5;
    vec2 frac_part   = fract(pixel);
    vec2 floor_uv    = (floor(pixel) + 0.5) / tex_size;
    vec2 step_uv     = 1.0 / tex_size;

    vec2 t = frac_part * frac_part * frac_part * (frac_part * (frac_part * 6.0 - 15.0) + 10.0);

    vec4 c00 = texture(tex, floor_uv);
    vec4 c10 = texture(tex, floor_uv + vec2(step_uv.x, 0.0));
    vec4 c01 = texture(tex, floor_uv + vec2(0.0, step_uv.y));
    vec4 c11 = texture(tex, floor_uv + step_uv);

    return mix(mix(c00, c10, t.x), mix(c01, c11, t.x), t.y);
}

void vertex() {
    v_local_xz = VERTEX.xz;

    float r = length(VERTEX.xz);
    if (r > curve_start_radius) {
        float t = clamp((r - curve_start_radius) / (curve_max_radius - curve_start_radius), 0.0, 1.0);
        float curve = t * t * (3.0 - 2.0 * t);
        VERTEX.y -= curve * curve * curve_drop_height;

        vec2 dir = normalize(VERTEX.xz);
        float slope = (2.0 * t * curve_drop_height) / (curve_max_radius - curve_start_radius);
        NORMAL = normalize(vec3(dir.x * slope, 1.0, dir.y * slope));
    }
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 base_uv = (v_local_xz * uv_scale) + uv_offset;
    vec2 final_uv = base_uv;

    // Distorção de micro-relevo procedural nas coordenadas UV (Domain Warping):
    // Quebra linhas retas e blocos de pixels no litoral adicionando curvas naturais
    if (enable_procedural_detail) {
        vec2 noise_coord = v_local_xz * 0.008; // frequência espacial de escala fina
        float warp_x = procedural_fbm(noise_coord) - 0.5;
        float warp_y = procedural_fbm(noise_coord + vec2(43.12, 17.58)) - 0.5;
        
        // Aplica distorção proporcional a 1 ou 2 texels da textura
        vec2 tex_step = 1.0 / vec2(textureSize(planet_texture, 0));
        final_uv += vec2(warp_x, warp_y) * tex_step * (detail_strength * 2.8);
    }

    vec4 tex;
    if (use_smooth_sampling) {
        tex = texture_bicubic(planet_texture, final_uv);
    } else {
        tex = texture(planet_texture, final_uv);
    }

    vec3 surface_albedo     = tex.rgb;
    float ocean_specular_mask = tex.a;

    // Se o micro-detalhe estiver ativo, adiciona micro-variação de cor e relevo no terreno
    if (enable_procedural_detail) {
        float micro_shade = procedural_fbm(v_local_xz * 0.02) * 2.0 - 1.0;
        // Aplica relevo apenas nos continentes (onde o reflexo de água não é dominante)
        float land_factor = 1.0 - ocean_specular_mask;
        surface_albedo += surface_albedo * (micro_shade * 0.12 * detail_strength * land_factor);
    }

    vec3 n = normalize(NORMAL);
    vec3 v = normalize(VIEW);

    float fresnel  = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), rim_power);

    vec3 sun_dir_cam = normalize((VIEW_MATRIX * vec4(normalize(sun_direction), 0.0)).xyz);
    float sun_dot    = dot(n, sun_dir_cam);
    float day_factor = clamp((sun_dot + 0.2) / 1.2, 0.0, 1.0);

    vec3 limb_color      = mix(twilight_limb_color.rgb, atmosphere_limb_color.rgb, clamp(sun_dot * 3.0, 0.0, 1.0));
    vec3 atmosphere_glow = limb_color * fresnel * rim_intensity * (day_factor * 0.9 + 0.1);

    vec2 local_xz = (inverse(MODEL_MATRIX) * vec4(v_world_pos, 1.0)).xz;
    float dist     = length(local_xz);
    float edge_fade = 1.0 - smoothstep(curve_max_radius - 800.0, curve_max_radius, dist);

    ALBEDO    = surface_albedo;
    EMISSION  = atmosphere_glow;
    ALPHA     = edge_fade;
    ROUGHNESS = mix(0.95, 0.45, ocean_specular_mask);
    SPECULAR  = mix(0.02, 0.35, ocean_specular_mask);
}