shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

// 監視モニターの画面。SubViewport の映像に走査線・ノイズ・にじみ・グリッチを重ねる。
// screen_tex は monitor.gd が実行時に SubViewport.get_texture() を入れる。

uniform sampler2D screen_tex : filter_nearest, repeat_disable;
uniform float static_amount : hint_range(0.0, 1.0) = 0.10;   // 砂嵐の混ざり具合
uniform float scanline : hint_range(0.0, 1.0) = 0.30;        // 走査線の濃さ
uniform float glitch : hint_range(0.0, 1.0) = 0.0;           // 横方向の乱れ
uniform float bleed : hint_range(0.0, 0.02) = 0.004;         // 色にじみ
uniform float brightness = 1.25;
uniform float vignette : hint_range(0.0, 2.0) = 1.0;
uniform vec3 tint : source_color = vec3(0.82, 0.95, 0.88);
uniform float rows = 180.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float t = TIME;
	vec2 uv = UV;

	// 走査線の行ごとに稀に横ずれ(トラッキングの乱れ)
	float row = floor(uv.y * rows);
	float band = hash12(vec2(row, floor(t * 9.0)));
	float shift = 0.0;
	if (band > 0.988 - glitch * 0.35) {
		shift = (hash12(vec2(row * 1.7, floor(t * 13.0))) - 0.5) * (0.02 + glitch * 0.18);
	}
	// 全体のわずかな揺れ
	shift += sin(t * 1.7 + uv.y * 7.0) * 0.0016 * (1.0 + glitch * 6.0);
	uv.x += shift;

	vec2 suv = clamp(uv, vec2(0.001), vec2(0.999));
	// 色にじみ(RGB を横にずらす)
	float r = texture(screen_tex, clamp(suv + vec2(bleed, 0.0), vec2(0.001), vec2(0.999))).r;
	float g = texture(screen_tex, suv).g;
	float b = texture(screen_tex, clamp(suv - vec2(bleed, 0.0), vec2(0.001), vec2(0.999))).b;
	vec3 c = vec3(r, g, b) * brightness;

	// 砂嵐
	float n = hash12(uv * vec2(420.0, 260.0) + vec2(t * 53.0, t * 31.0));
	float amt = clamp(static_amount + glitch * 0.35, 0.0, 1.0);
	c = mix(c, vec3(n) * 0.9, amt);

	// 走査線 + ゆっくり流れる明暗の帯
	float sl = 0.5 + 0.5 * sin(uv.y * rows * 6.28318);
	c *= 1.0 - scanline * sl;
	float roll = fract(uv.y + t * 0.13);
	c *= 1.0 + 0.10 * smoothstep(0.96, 1.0, roll);

	// 周辺減光
	vec2 d = uv - 0.5;
	c *= 1.0 - dot(d, d) * vignette;

	c *= tint;
	ALBEDO = max(c, vec3(0.0));
}
