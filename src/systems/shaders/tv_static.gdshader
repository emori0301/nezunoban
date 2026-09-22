shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

// 控室のブラウン管の砂嵐。映像入力は無いので全部手続き的に作る。
// overlay_tex に顔やシルエットを入れ、overlay_amount を上げると砂嵐の中に浮かぶ。

uniform float noise_amount : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.0, 2.0) = 0.55;
uniform float scanline : hint_range(0.0, 1.0) = 0.35;
uniform float roll_speed = 0.22;
uniform float power : hint_range(0.0, 1.0) = 1.0;       // 消灯時は 0
uniform sampler2D overlay_tex : filter_linear, repeat_disable;
uniform bool has_overlay = false;
uniform float overlay_amount : hint_range(0.0, 1.0) = 0.0;
uniform float rows = 150.0;
uniform vec3 tint : source_color = vec3(0.86, 0.90, 0.95);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float t = TIME;
	vec2 uv = UV;
	vec2 d = uv - 0.5;
	vec3 c = vec3(0.0);

	if (power < 0.01) {
		// 消えているときは暗いガラス(うっすら反射)
		c = vec3(0.012, 0.013, 0.016) * (1.0 - dot(d, d));
	} else {
		// 砂嵐: 粗い粒 + 細かい粒
		float n1 = hash12(floor(uv * vec2(160.0, 110.0)) + vec2(t * 61.0, t * 37.0));
		float n2 = hash12(uv * vec2(640.0, 400.0) + vec2(t * 97.0, t * 53.0));
		float n = mix(n1, n2, 0.45);
		c = vec3(n) * brightness * noise_amount;

		// 横に流れる明るい帯(ヘッドスイッチングノイズ)
		float roll = fract(uv.y - t * roll_speed);
		c += vec3(0.12) * smoothstep(0.975, 1.0, roll);
		float tear = step(0.997, hash12(vec2(floor(uv.y * 90.0), floor(t * 7.0))));
		c += vec3(0.20) * tear;

		// 顔/シルエットを浮かせる
		if (has_overlay && overlay_amount > 0.001) {
			vec4 o = texture(overlay_tex, uv);
			float a = o.a * overlay_amount;
			// 砂嵐より暗い形として出す。輪郭を少しにじませる。
			c = mix(c, o.rgb * (0.25 + 0.35 * n), a);
		}

		// 走査線
		float sl = 0.5 + 0.5 * sin(uv.y * rows * 6.28318);
		c *= 1.0 - scanline * sl;

		// 周辺減光 + 角の丸み
		c *= 1.0 - dot(d, d) * 1.2;
		c *= tint;
	}
	ALBEDO = max(c, vec3(0.0));
}
