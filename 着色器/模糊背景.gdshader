shader_type canvas_item;
// 模糊背景：采样屏幕内容做模糊（铺满屏幕的 ColorRect 挂本材质）
// 双环 16 采样, 屏幕纹理无 mipmap, 不用 LOD 偏移
// blur_strength: 模糊半径   darken: 顺便压暗前景更聚焦

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_strength : hint_range(0.0, 10.0) = 4.0;
uniform float darken : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 sum = vec4(0.0);
	float r1 = 0.001 + 0.003 * blur_strength;  // 内环
	float r2 = 0.002 + 0.006 * blur_strength;  // 外环
	for (int i = 0; i < 8; i++) {
		float a = TAU * float(i) / 8.0;
		vec2 dir = vec2(cos(a), sin(a));
		sum += texture(screen_tex, uv + dir * r1);
		sum += texture(screen_tex, uv + dir * r2);
	}
	sum /= 16.0;
	vec3 blurred = mix(sum.rgb, vec3(0.0), darken);
	COLOR = vec4(blurred, 1.0);
}
