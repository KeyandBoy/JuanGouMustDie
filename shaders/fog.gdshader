shader_type canvas_item;

uniform vec2 center = vec2(0.5, 0.5);
uniform vec2 resolution = vec2(1280.0, 720.0);
uniform float clear_radius = 160.0;
uniform float fade_radius = 300.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.96;

void fragment() {
	float dist = length((UV - center) * resolution);
	float a = smoothstep(clear_radius, fade_radius, dist);
	COLOR = vec4(vec3(0.03, 0.03, 0.035), a * max_alpha);
}
