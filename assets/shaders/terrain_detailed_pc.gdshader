shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

/*
================================================================================
  NOVASTORM - ULTRA TERRAIN VARIATION SHADER (PC ULTRA)
  - Projeção Triplanar em Coordenadas de Mundo (UV uniforme sem estiramento)
  - Slope Blending: Falésias rochosas escuras vs Chão/Platô arenoso claro
  - Macro Noise Tinting: Grandes faixas geológicas (vermelha, ardósia, arenosa)
  - Altitude Tinting: Vales mais ricos e picos iluminados
  - Preservação 100% das sombras nativas (sem quebra de NORMAL)
================================================================================
*/

group_uniforms Texturas_Base;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float uv_scale = 0.015;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;
uniform float normal_scale : hint_range(0.0, 3.0) = 1.2;

group_uniforms Inclinacao_Slope;
// Contraste forte entre chão plano e paredes de rocha
uniform vec4 flat_tint : source_color = vec4(1.35, 1.15, 0.85, 1.0);  // Solo plano / platô / areia iluminada
uniform vec4 cliff_tint : source_color = vec4(0.55, 0.50, 0.52, 1.0); // Paredões verticais (rocha escura e crua)
uniform float slope_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float slope_blend_smoothness : hint_range(0.01, 0.5) = 0.20;
uniform float flat_roughness : hint_range(0.0, 1.0) = 0.80;
uniform float cliff_roughness : hint_range(0.0, 1.0) = 0.95;

group_uniforms Variacao_Macro_Geologica;
uniform float macro_noise_scale = 0.0008; // Repete a cada ~1.2 km de percurso
uniform float macro_noise_strength : hint_range(0.0, 1.0) = 0.60;
uniform vec4 strata_red_clay : source_color = vec4(1.35, 0.85, 0.68, 1.0);  // Trecho de terra avermelhada / cânion
uniform vec4 strata_cool_slate : source_color = vec4(0.75, 0.88, 1.12, 1.0); // Trecho de rocha fria / ardósia mineral

group_uniforms Altitude_Tint;
uniform float height_min = 100.0;
uniform float height_max = 1600.0;
uniform float height_blend_strength : hint_range(0.0, 1.0) = 0.30;
uniform vec4 valley_tint : source_color = vec4(0.85, 0.82, 0.78, 1.0);
uniform vec4 peak_tint : source_color = vec4(1.15, 1.10, 1.05, 1.0);

group_uniforms Micro_Detalhe;
uniform float micro_detail_strength : hint_range(0.0, 0.2) = 0.05;

varying vec3 world_pos;

// Funções de ruído procedural analítico (determinístico e zero custo de VRAM)
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
	float a = 0.6;
	for (int i = 0; i < 2; i++) {
		v += a * noise2d(p);
		p *= 2.05;
		a *= 0.45;
	}
	return v;
}

void vertex() {
	// Captura posição de mundo exata
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 1. Obtém o normal geométrico real em coordenadas de mundo (estável e imune a escala/rotação de mesh)
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// 2. Pesos Triplanar
	vec3 blend_weights = pow(abs(world_normal), vec3(triplanar_sharpness));
	blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z);

	vec2 uv_x = world_pos.zy * uv_scale;
	vec2 uv_y = world_pos.xz * uv_scale;
	vec2 uv_z = world_pos.xy * uv_scale;

	// 3. Amostragem Albedo Triplanar
	vec4 col_x = texture(albedo_texture, uv_x);
	vec4 col_y = texture(albedo_texture, uv_y);
	vec4 col_z = texture(albedo_texture, uv_z);
	vec3 base_albedo = (col_x * blend_weights.x + col_y * blend_weights.y + col_z * blend_weights.z).rgb;

	// 4. Variação por Inclinação (Slope Blending)
	// world_normal.y = 1.0 (chão perfeitamente plano), 0.0 (paredão vertical)
	float slope = clamp(world_normal.y, 0.0, 1.0);
	float slope_factor = smoothstep(slope_threshold - slope_blend_smoothness, slope_threshold + slope_blend_smoothness, slope);
	vec3 slope_color = mix(cliff_tint.rgb, flat_tint.rgb, slope_factor);

	// 5. Variação Macro Geológica (Grandes manchas em escala de quilômetros)
	float macro_n = fbm(world_pos.xz * macro_noise_scale);
	vec3 macro_tint = mix(strata_red_clay.rgb, strata_cool_slate.rgb, macro_n);
	macro_tint = mix(vec3(1.0), macro_tint, macro_noise_strength);

	// 6. Variação por Altitude (Vales profundos vs Topos de montanhas)
	float height_factor = clamp((world_pos.y - height_min) / max(height_max - height_min, 1.0), 0.0, 1.0);
	vec3 height_tint = mix(valley_tint.rgb, peak_tint.rgb, height_factor);
	height_tint = mix(vec3(1.0), height_tint, height_blend_strength);

	// 7. Micro-grão fino para detalhes próximos
	float micro_grain = (noise2d(world_pos.xz * 0.5) - 0.5) * micro_detail_strength;

	// 8. Amostragem do Normal Map Triplanar
	vec3 n_x = texture(normal_texture, uv_x).rgb;
	vec3 n_y = texture(normal_texture, uv_y).rgb;
	vec3 n_z = texture(normal_texture, uv_z).rgb;
	vec3 blended_normal_tex = n_x * blend_weights.x + n_y * blend_weights.y + n_z * blend_weights.z;

	// 9. Composição Final:
	// A cor final multiplica a textura base pelas variações marcantes de terreno
	ALBEDO = (base_albedo * slope_color * macro_tint * height_tint) + vec3(micro_grain);
	ROUGHNESS = mix(cliff_roughness, flat_roughness, slope_factor);
	SPECULAR = 0.2;

	// 10. Normal Map NATIVO do Godot:
	// Usamos NORMALMAP nativo para que o motor preserve perfeitamente o cálculo de luz direta e sombras!
	NORMALMAP = blended_normal_tex;
	NORMALMAP_DEPTH = normal_scale;
}
