shader_type canvas_item;

uniform vec4 fog_color : source_color = vec4(0.02, 0.02, 0.025, 1.0);
uniform float density = 0.95;
uniform float wisp = 0.35;
uniform float seed = 0.0;
uniform vec2 room_size = vec2(200.0, 120.0);
uniform float solid = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * noise(p);
		p = p * 2.03 + vec2(3.1, 1.7);
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 px = UV * room_size;
	float edge = min(min(px.x, room_size.x - px.x), min(px.y, room_size.y - px.y));
	float feather = smoothstep(0.0, 14.0, edge);

	if (solid > 0.5) {
		COLOR = vec4(fog_color.rgb, clamp(feather, 0.0, 1.0));
	} else {
		vec2 p = px * 0.018 + vec2(seed, seed * 1.7);

		vec2 flow = vec2(TIME * 0.045, TIME * 0.02);
		vec2 warp = vec2(fbm(p + flow + 4.3), fbm(p + flow + 9.1)) - 0.5;
		float n = fbm(p + warp * 1.6 + flow);
		float fine = fbm(p * 2.1 - flow * 1.3 + 11.0);

		float billow = smoothstep(0.30, 0.80, n);
		float core = smoothstep(0.58, 0.96, n * 0.65 + fine * 0.55);
		float gap = 1.0 - smoothstep(0.24, 0.52, fine);
		float shape = billow * (1.0 - wisp * 0.35) + core * wisp * 0.7;
		shape = clamp(shape - gap * wisp * 0.35, 0.0, 1.0);

		float a = density * (0.22 + 0.95 * shape);
		a *= feather;
		COLOR = vec4(fog_color.rgb, clamp(a, 0.0, 1.0));
	}
}
