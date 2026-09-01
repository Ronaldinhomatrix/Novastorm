shader_type canvas_item;

uniform vec4 stripe_color : source_color = vec4(1.0, 0.65, 0.0, 1.0);
uniform vec4 bg_color : source_color = vec4(0.12, 0.04, 0.0, 0.95);
uniform float stripe_width : hint_range(5.0, 100.0) = 24.0;
uniform float speed = 40.0;
uniform float angle = 0.785398; // 45 graus

void fragment() {
	vec2 pos = FRAGCOORD.xy;
	// Rotação da coordenada para gerar listras diagonais
	float cos_a = cos(angle);
	float sin_a = sin(angle);
	float rotated_x = pos.x * cos_a - pos.y * sin_a + TIME * speed;
	
	float pattern = step(0.5, fract(rotated_x / stripe_width));
	COLOR = mix(bg_color, stripe_color, pattern);
}
