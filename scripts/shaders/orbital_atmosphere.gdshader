shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

// Shader de Camada Atmosférica Orbital Realista
// Simula a fina película de gás azulado visível no horizonte planetário.

uniform vec3 sun_direction = vec3(0.6, 0.4, 0.7);
uniform vec4 day_atmosphere_color : source_color = vec4(0.2, 0.65, 1.0, 1.0);
uniform vec4 horizon_glow_color : source_color = vec4(0.6, 0.88, 1.0, 1.0);
uniform vec4 twilight_color : source_color = vec4(0.95, 0.5, 0.2, 1.0);

uniform float rim_power : hint_range(1.0, 12.0) = 5.5;
uniform float max_alpha : hint_range(0.1, 1.0) = 0.75;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);

	// Fresnel concentrado estritamente na tangente extrema do horizonte
	float ndotv = clamp(dot(n, v), 0.0, 1.0);
	float rim = pow(1.0 - ndotv, rim_power);

	// Direção do sol
	vec3 sun_dir_cam = normalize((VIEW_MATRIX * vec4(normalize(sun_direction), 0.0)).xyz);
	float sun_dot = dot(n, sun_dir_cam);
	float day_factor = clamp((sun_dot + 0.3) / 1.3, 0.0, 1.0);

	// Cor atmosférica: ciano elétrico de dia, âmbar no terminador, azul marinho suave à noite
	vec3 day_col = mix(day_atmosphere_color.rgb, horizon_glow_color.rgb, pow(rim, 2.0));
	vec3 lit_col = mix(twilight_color.rgb, day_col, clamp(sun_dot * 3.0, 0.0, 1.0));
	vec3 final_color = mix(vec3(0.02, 0.05, 0.15), lit_col, day_factor);

	ALBEDO = final_color;
	ALPHA = rim * max_alpha * (day_factor * 0.9 + 0.1);
}
