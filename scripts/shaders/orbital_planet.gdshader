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

// Filtragem Quíntica C2 suave (mantém bordas curvas sem degraus)
uniform bool use_smooth_sampling = true;

varying vec2 v_local_xz;
varying vec3 v_world_pos;

// ---------------------------------------------------------------------------
// Filtragem Quíntica C2-Contínua (Hermite de 5ª ordem):
// Interpolação suave e contínua sem quebras nem bordas falsas.
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
    vec2 planet_uv = (v_local_xz * uv_scale) + uv_offset;

    vec4 tex;
    if (use_smooth_sampling) {
        tex = texture_bicubic(planet_texture, planet_uv);
    } else {
        tex = texture(planet_texture, planet_uv);
    }

    vec3 surface_albedo     = tex.rgb;
    float ocean_specular_mask = tex.a;

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