shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Shader Planetário de Órbita Realista (1 único draw call).
// Integra textura de alta definição (continentes, oceanos e nuvens),
// reflexo especular equilibrado na água, terminador dia/noite e o
// brilho de dispersão atmosférica (Rayleigh Limb Glow) na silhueta do horizonte.

uniform sampler2D planet_texture : source_color, filter_linear_mipmap;
uniform vec3 sun_direction = vec3(0.6, 0.4, 0.7);

uniform vec4 atmosphere_limb_color : source_color = vec4(0.2, 0.7, 1.0, 1.0);
uniform vec4 twilight_limb_color : source_color = vec4(0.95, 0.5, 0.2, 1.0);
uniform float rim_power : hint_range(1.0, 10.0) = 5.0;
uniform float rim_intensity : hint_range(0.1, 4.0) = 1.8;

void fragment() {
	vec4 tex = texture(planet_texture, UV);
	vec3 surface_albedo = tex.rgb;
	float ocean_specular_mask = tex.a;

	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);

	// Efeito Fresnel estrito nas bordas do planeta (Rayleigh Limb Glow)
	float fresnel = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), rim_power);

	// Direção da luz solar
	vec3 sun_dir_cam = normalize((VIEW_MATRIX * vec4(normalize(sun_direction), 0.0)).xyz);
	float sun_dot = dot(n, sun_dir_cam);
	float day_factor = clamp((sun_dot + 0.2) / 1.2, 0.0, 1.0);

	// Brilho da silhueta atmosférica
	vec3 limb_color = mix(twilight_limb_color.rgb, atmosphere_limb_color.rgb, clamp(sun_dot * 3.0, 0.0, 1.0));
	vec3 atmosphere_glow = limb_color * fresnel * rim_intensity * (day_factor * 0.9 + 0.1);

	ALBEDO = surface_albedo;
	EMISSION = atmosphere_glow;

	// Superfície equilibrada sem estouro especular
	ROUGHNESS = mix(0.95, 0.45, ocean_specular_mask);
	SPECULAR = mix(0.02, 0.35, ocean_specular_mask);
}
