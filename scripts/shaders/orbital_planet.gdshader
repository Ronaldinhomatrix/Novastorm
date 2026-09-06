shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Shader Planetário de Órbita: Cenário Plano com Bordas Arredondadas (Horizonte Curvo)
// Cria o efeito visual de um planeta colossal em escala imensa, com máxima performance.

uniform sampler2D planet_texture : source_color, filter_linear_mipmap;
uniform vec3 sun_direction = vec3(0.6, 0.4, 0.7);

uniform vec4 atmosphere_limb_color : source_color = vec4(0.2, 0.7, 1.0, 1.0);
uniform vec4 twilight_limb_color : source_color = vec4(0.95, 0.5, 0.2, 1.0);
uniform float rim_power : hint_range(1.0, 10.0) = 4.2;
uniform float rim_intensity : hint_range(0.1, 4.0) = 2.0;

uniform float curve_start_radius = 2800.0;
uniform float curve_max_radius = 7800.0;
uniform float curve_drop_height = 2200.0;

varying vec3 v_world_pos;

void vertex() {
	float r = length(VERTEX.xz);
	if (r > curve_start_radius) {
		float t = clamp((r - curve_start_radius) / (curve_max_radius - curve_start_radius), 0.0, 1.0);
		// Curva quadrática suave (arredondamento da borda do planeta)
		float curve = t * t * (3.0 - 2.0 * t);
		VERTEX.y -= curve * curve * curve_drop_height;

		// Inclina a normal para criar a tangente visual do horizonte
		vec2 dir = normalize(VERTEX.xz);
		float slope = (2.0 * t * curve_drop_height) / (curve_max_radius - curve_start_radius);
		vec3 new_norm = normalize(vec3(dir.x * slope, 1.0, dir.y * slope));
		NORMAL = new_norm;
	}
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(planet_texture, UV);
	vec3 surface_albedo = tex.rgb;
	float ocean_specular_mask = tex.a;

	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);

	// Efeito Fresnel atmosférico focado no arredondamento das bordas
	float fresnel = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), rim_power);

	// Direção da luz solar
	vec3 sun_dir_cam = normalize((VIEW_MATRIX * vec4(normalize(sun_direction), 0.0)).xyz);
	float sun_dot = dot(n, sun_dir_cam);
	float day_factor = clamp((sun_dot + 0.2) / 1.2, 0.0, 1.0);

	// Brilho da silhueta atmosférica na borda arredondada
	vec3 limb_color = mix(twilight_limb_color.rgb, atmosphere_limb_color.rgb, clamp(sun_dot * 3.0, 0.0, 1.0));
	vec3 atmosphere_glow = limb_color * fresnel * rim_intensity * (day_factor * 0.9 + 0.1);

	// Fade suave no extremo final do plano para mesclar perfeitamente com o espaço profundo
	vec2 local_xz = (inverse(MODEL_MATRIX) * vec4(v_world_pos, 1.0)).xz;
	float dist = length(local_xz);
	float edge_fade = 1.0 - smoothstep(curve_max_radius - 800.0, curve_max_radius, dist);

	ALBEDO = surface_albedo;
	EMISSION = atmosphere_glow;
	ALPHA = edge_fade;

	ROUGHNESS = mix(0.95, 0.45, ocean_specular_mask);
	SPECULAR = mix(0.02, 0.35, ocean_specular_mask);
}
