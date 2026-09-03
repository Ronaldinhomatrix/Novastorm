shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

/*
================================================================================
  NOVASTORM - ULTRA TERRAIN VARIATION SHADER (PC ULTRA)
  - Projeção Triplanar em World Space (sem estiramento em 360°)
  - Slope Blending: Falésias rochosas escuras vs Chão/Platô de sedimento
  - Macro Noise Tinting: Manchas procedurais a cada 500m-1000m (quebra repetição)
  - Altitude Tinting: Vales mais quentes/sedimentados e picos mais claros
================================================================================
*/

group_uniforms Texturas_Base;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float uv_scale = 0.015;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;
uniform float normal_scale : hint_range(0.0, 3.0) = 1.3;

group_uniforms Inclinacao_Slope;
uniform vec4 flat_tint : source_color = vec4(1.08, 0.98, 0.86, 1.0);  // Platôs e chão plano (sedimento/areia)
uniform vec4 cliff_tint : source_color = vec4(0.78, 0.72, 0.68, 1.0); // Paredões verticais (rocha crua/escura)
uniform float slope_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float slope_blend_smoothness : hint_range(0.01, 0.5) = 0.22;
uniform float flat_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float cliff_roughness : hint_range(0.0, 1.0) = 0.92;

group_uniforms Variacao_Macro_Manchas;
uniform float macro_noise_scale = 0.0012; // Repete a cada ~800 metros
uniform float macro_noise_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec4 tint_warm_strata : source_color = vec4(1.14, 0.94, 0.80, 1.0);  // Faixas minerais quentes/avermelhadas
uniform vec4 tint_cool_strata : source_color = vec4(0.86, 0.90, 0.96, 1.0);  // Faixas minerais frias/ardósia

group_uniforms Altitude_Tint;
uniform float height_min = 0.0;
uniform float height_max = 600.0;
uniform float height_blend_strength : hint_range(0.0, 1.0) = 0.20;
uniform vec4 valley_tint : source_color = vec4(0.92, 0.88, 0.82, 1.0);
uniform vec4 peak_tint : source_color = vec4(1.08, 1.05, 1.0, 1.0);

group_uniforms Micro_Detalhe;
uniform float micro_detail_strength : hint_range(0.0, 0.2) = 0.04;

varying vec3 world_pos;
varying vec3 world_normal;

// Ruído analítico determinístico para variação macro (zero custo de VRAM)
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += a * noise2d(p);
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 1. Pesos da projeção Triplanar baseados na orientação geométrica
	vec3 blend_weights = abs(world_normal);
	blend_weights = pow(blend_weights, vec3(triplanar_sharpness));
	blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z);

	vec2 uv_x = world_pos.zy * uv_scale;
	vec2 uv_y = world_pos.xz * uv_scale;
	vec2 uv_z = world_pos.xy * uv_scale;

	// 2. Amostragem de cor Triplanar
	vec4 col_x = texture(albedo_texture, uv_x);
	vec4 col_y = texture(albedo_texture, uv_y);
	vec4 col_z = texture(albedo_texture, uv_z);
	vec4 base_albedo = col_x * blend_weights.x + col_y * blend_weights.y + col_z * blend_weights.z;

	// 3. Amostragem do Normal Map Triplanar
	vec3 n_x = texture(normal_texture, uv_x).rgb * 2.0 - 1.0;
	vec3 n_y = texture(normal_texture, uv_y).rgb * 2.0 - 1.0;
	vec3 n_z = texture(normal_texture, uv_z).rgb * 2.0 - 1.0;

	vec3 wn_x = vec3(n_x.z * sign(world_normal.x), n_x.y, -n_x.x * sign(world_normal.x));
	vec3 wn_y = vec3(n_y.x, n_y.z * sign(world_normal.y), -n_y.y * sign(world_normal.y));
	vec3 wn_z = vec3(n_z.x * sign(world_normal.z), n_z.y, n_z.z * sign(world_normal.z));

	vec3 blended_world_normal = normalize(wn_x * blend_weights.x + wn_y * blend_weights.y + wn_z * blend_weights.z);
	vec3 final_world_normal = normalize(mix(world_normal, blended_world_normal, normal_scale));

	// 4. Variação por Inclinação (Slope Blending: Paredão vs Chão Plano)
	float slope = clamp(world_normal.y, 0.0, 1.0);
	float slope_factor = smoothstep(slope_threshold - slope_blend_smoothness, slope_threshold + slope_blend_smoothness, slope);
	vec3 slope_color = mix(cliff_tint.rgb, flat_tint.rgb, slope_factor);

	// 5. Variação Macro por Ruído Procedural (Manchas de 800m que quebram a monotonia)
	float macro_noise = fbm(world_pos.xz * macro_noise_scale);
	vec3 macro_tint = mix(tint_warm_strata.rgb, tint_cool_strata.rgb, macro_noise);
	macro_tint = mix(vec3(1.0), macro_tint, macro_noise_strength);

	// 6. Variação por Altitude (Vales vs Cumes)
	float height_factor = clamp((world_pos.y - height_min) / max(height_max - height_min, 1.0), 0.0, 1.0);
	vec3 height_tint = mix(valley_tint.rgb, peak_tint.rgb, height_factor);
	height_tint = mix(vec3(1.0), height_tint, height_blend_strength);

	// 7. Micro-detalhe de grão para aproximações da câmera
	float micro_grain = (noise2d(world_pos.xz * 0.4) - 0.5) * micro_detail_strength;

	// 8. Composição final
	ALBEDO = (base_albedo.rgb * slope_color * macro_tint * height_tint) + vec3(micro_grain);
	ROUGHNESS = mix(cliff_roughness, flat_roughness, slope_factor);
	SPECULAR = 0.25;
	NORMAL = (VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz;
}
