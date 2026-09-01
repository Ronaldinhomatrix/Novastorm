shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 shield_color : source_color = vec4(0.0, 0.85, 1.0, 1.0);
uniform vec4 impact_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.4;
uniform float hex_scale : hint_range(5.0, 60.0) = 18.0;
uniform float hex_line_width : hint_range(0.01, 0.3) = 0.08;
uniform float energy_intensity : hint_range(0.0, 3.0) = 0.75;
uniform float impact_flash : hint_range(0.0, 1.0) = 0.0;

// Hexagonal distance calculation
float hex_dist(vec2 p) {
	p = abs(p);
	return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
}

vec4 hex_coords(vec2 uv) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	float edge = 0.5 - hex_dist(gv);
	return vec4(gv, edge, 0.0);
}

void fragment() {
	// Fresnel effect (bordas suaves e elegantes)
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	
	// Grade hexagonal em coordenadas UV
	vec2 uv_scaled = vec2(UV.x * 2.0, UV.y) * hex_scale;
	vec4 h = hex_coords(uv_scaled);
	float hex_border = smoothstep(hex_line_width, 0.0, h.z);
	
	// Onda de energia suave
	float wave = sin(UV.y * 18.0 - TIME * 6.0) * 0.5 + 0.5;
	float grid_energy = hex_border * 0.7 + (1.0 - hex_border) * 0.08 * wave;
	
	// Brilho composto moderado e balanceado
	float brightness = (fresnel * 0.6 + grid_energy * 0.4 + fresnel * grid_energy * 0.8) * energy_intensity;
	
	vec3 base_col = mix(shield_color.rgb, impact_color.rgb, impact_flash);
	vec3 final_rgb = base_col * (brightness * (0.9 + impact_flash * 0.8));
	
	ALBEDO = final_rgb;
	ALPHA = clamp(brightness, 0.0, 1.0);
}
