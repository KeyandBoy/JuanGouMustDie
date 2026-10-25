shader_type canvas_item;

uniform float outline_width = 1.0;
uniform vec4 outline_color : source_color = vec4(1.0, 0.86, 0.45, 1.0);
uniform float glow = 1.0;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * outline_width;
	vec4 original = texture(TEXTURE, UV);
	float near_alpha = 0.0;
	near_alpha = max(near_alpha, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	vec3 ring = outline_color.rgb * (glow + (1.0 - abs(0.5 - near_alpha) * 2.0) * 0.4);
	vec4 outline = vec4(ring, 1.0);
	COLOR = mix(outline, original, original.a);
}
