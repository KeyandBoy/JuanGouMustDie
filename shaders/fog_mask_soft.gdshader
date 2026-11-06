shader_type canvas_item;

// 探索遮罩的柔和边界：对「每格 1 像素」的遮罩纹理做两圈帐篷模糊，
// 再叠加纹理自身的线性过滤，得到约 3~4 格宽的渐变光晕。
// 这样房间/走廊的点亮边界是光，而不是硬邦邦的方块。

void fragment() {
	vec2 t = TEXTURE_PIXEL_SIZE;
	vec4 c = texture(TEXTURE, UV) * 4.0;
	// 内圈：上下左右权重 2
	c += (texture(TEXTURE, UV + vec2(t.x, 0.0)) + texture(TEXTURE, UV - vec2(t.x, 0.0))
		+ texture(TEXTURE, UV + vec2(0.0, t.y)) + texture(TEXTURE, UV - vec2(0.0, t.y))) * 2.0;
	// 内圈斜角：权重 1
	c += texture(TEXTURE, UV + t);
	c += texture(TEXTURE, UV - t);
	c += texture(TEXTURE, UV + vec2(t.x, -t.y));
	c += texture(TEXTURE, UV + vec2(-t.x, t.y));
	// 外圈：再往外一格，权重 0.8（把光晕再拉开一点）
	c += (texture(TEXTURE, UV + vec2(2.0 * t.x, 0.0)) + texture(TEXTURE, UV - vec2(2.0 * t.x, 0.0))
		+ texture(TEXTURE, UV + vec2(0.0, 2.0 * t.y)) + texture(TEXTURE, UV - vec2(0.0, 2.0 * t.y))) * 0.8;
	COLOR = c / 19.2;
}
