shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.7, 0.1, 1.0);
uniform float chromatic_aberration : hint_range(0.0, 15.0) = 3.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.25;
uniform float glitch_speed = 8.0;
uniform float pulse_intensity : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec2 uv = UV;
	
	// Micro glitch horizontal esporádico
	float glitch = step(0.97, sin(TIME * glitch_speed + uv.y * 20.0)) * 0.008;
	vec2 uv_r = uv + vec2(chromatic_aberration * SCREEN_PIXEL_SIZE.x + glitch, 0.0);
	vec2 uv_g = uv;
	vec2 uv_b = uv - vec2(chromatic_aberration * SCREEN_PIXEL_SIZE.x + glitch, 0.0);
	
	vec4 col_r = texture(TEXTURE, uv_r);
	vec4 col_g = texture(TEXTURE, uv_g);
	vec4 col_b = texture(TEXTURE, uv_b);
	
	// Aberração cromática RGB split
	vec4 final_color = vec4(col_r.r, col_g.g, col_b.b, max(col_r.a, max(col_g.a, col_b.a)));
	
	// Scanlines holográficas horizontais
	float scanline = sin(uv.y * 300.0) * 0.5 + 0.5;
	final_color.rgb *= mix(1.0, 1.0 - scanline_intensity, scanline);
	
	// Brilho pulsante e tonalização sci-fi
	float pulse = 0.85 + 0.3 * sin(TIME * 6.0);
	final_color.rgb = mix(final_color.rgb, glow_color.rgb * 1.3, 0.35) * pulse * pulse_intensity;
	
	COLOR = final_color * COLOR;
}
