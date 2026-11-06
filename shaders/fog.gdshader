shader_type canvas_item;

uniform vec2 center = vec2(0.5, 0.5);
uniform vec2 resolution = vec2(1280.0, 720.0);
uniform float clear_radius = 160.0;
uniform float fade_radius = 300.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.96;
// B12：停电时沿玩家朝向切开一块锥形可视区
uniform float cone_on = 0.0;
uniform vec2 cone_dir = vec2(0.0, 1.0);
uniform float cone_length = 260.0;
uniform float cone_half_angle = 0.42;

void fragment() {
	vec2 d = (UV - center) * resolution;
	float dist = length(d);
	float a = smoothstep(clear_radius, fade_radius, dist);
	if (cone_on > 0.5) {
		vec2 dir = normalize(cone_dir);
		float along = dot(d, dir);
		float across = abs(dot(d, vec2(-dir.y, dir.x)));
		float reach = clamp(along / max(1.0, cone_length), 0.0, 1.0);
		float spread = max(8.0, cone_half_angle * max(along, 0.0));
		float edge = 1.0 - smoothstep(spread * 0.55, spread, across);
		float tip = 1.0 - smoothstep(0.82, 1.0, reach);
		float cone = step(0.0, along) * edge * tip;
		a *= 1.0 - clamp(cone, 0.0, 1.0) * 0.97;
	}
	COLOR = vec4(vec3(0.03, 0.03, 0.035), a * max_alpha);
}
