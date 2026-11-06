shader_type canvas_item;

// 探索遮罩：R 通道 = 「当前所在区域」标记，A = 基础暗度。
// 先对整张遮罩做两圈帐篷模糊（边界柔和），再按玩家位置叠一个圆形照明，
// 所以点亮区域是「以玩家为圆心的光」，不是房间形状的方块。

uniform vec4 mask_color : source_color = vec4(0.035, 0.042, 0.058, 1.0);
uniform vec2 map_cells = vec2(1.0, 1.0);
uniform vec2 light_center = vec2(0.0, 0.0);
uniform float light_radius = 11.0;
uniform float light_soft = 6.0;

void fragment() {
	vec2 t = TEXTURE_PIXEL_SIZE;
	vec4 c = texture(TEXTURE, UV) * 4.0;
	c += (texture(TEXTURE, UV + vec2(t.x, 0.0)) + texture(TEXTURE, UV - vec2(t.x, 0.0))
		+ texture(TEXTURE, UV + vec2(0.0, t.y)) + texture(TEXTURE, UV - vec2(0.0, t.y))) * 2.0;
	c += texture(TEXTURE, UV + t);
	c += texture(TEXTURE, UV - t);
	c += texture(TEXTURE, UV + vec2(t.x, -t.y));
	c += texture(TEXTURE, UV + vec2(-t.x, t.y));
	c += (texture(TEXTURE, UV + vec2(2.0 * t.x, 0.0)) + texture(TEXTURE, UV - vec2(2.0 * t.x, 0.0))
		+ texture(TEXTURE, UV + vec2(0.0, 2.0 * t.y)) + texture(TEXTURE, UV - vec2(0.0, 2.0 * t.y))) * 0.8;
	c /= 19.2;

	// 圆形照明只作用在「当前区域」内：c.r 是当前区域标记，模糊后在墙边自然淡出
	float cur = smoothstep(0.25, 0.75, c.r);
	vec2 p = UV * map_cells;
	float lit = 1.0 - smoothstep(light_radius, light_radius + light_soft, distance(p, light_center));
	lit *= cur;
	COLOR = vec4(mask_color.rgb, c.a * (1.0 - lit));
}
