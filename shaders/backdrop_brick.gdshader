shader_type canvas_item;

// 地图之外的「建筑实体」背景：深色砖纹，避免镜头走到地图边缘时出现一块死黑/纯色空白。
// 纯屏幕空间绘制，不参与世界滚动（它只在房间外面露出一角）。

uniform vec4 base_color : source_color = vec4(0.072, 0.082, 0.104, 1.0);
uniform vec4 line_color : source_color = vec4(0.046, 0.053, 0.070, 1.0);
uniform vec2 brick_size = vec2(46.0, 23.0);

void fragment() {
	vec2 p = FRAGCOORD.xy / brick_size;
	float row = floor(p.y);
	p.x += mod(row, 2.0) * 0.5;
	vec2 f = fract(p);
	float line = step(f.x, 0.03) + step(f.y, 0.05);
	vec3 c = mix(base_color.rgb, line_color.rgb, clamp(line, 0.0, 1.0));
	COLOR = vec4(c, 1.0);
}
