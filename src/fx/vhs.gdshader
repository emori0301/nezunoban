shader_type canvas_item;
// VHS ポストエフェクト。SubViewportContainer の material に付けて TEXTURE(= SubViewport の絵)を加工する。
// 既定値は「HUD の 16px の文字が読める」強さ。恐怖演出で intensity / tracking_amount を上げる。

uniform float intensity : hint_range(0.0, 1.0) = 0.32;   // 全体の効き
uniform float chroma_px : hint_range(0.0, 3.0) = 0.85;   // 色にじみ(元解像度のピクセル数)
uniform float noise_amount : hint_range(0.0, 1.0) = 0.075;
uniform float scanline_amount : hint_range(0.0, 1.0) = 0.34;
uniform float jitter_amount : hint_range(0.0, 1.0) = 0.35;
uniform float tracking_amount : hint_range(0.0, 1.0) = 0.0;  // トラッキングノイズ帯の強さ
uniform float tracking_pos : hint_range(-0.5, 1.5) = 0.5;    // 帯の位置(0..1)
uniform float vignette_amount : hint_range(0.0, 2.0) = 0.80;
uniform float crush : hint_range(0.0, 1.0) = 0.35;       // 黒の潰れ
uniform float levels : hint_range(4.0, 64.0) = 28.0;     // 量子化段数
uniform float darken : hint_range(0.0, 1.0) = 0.0;
uniform float desat : hint_range(0.0, 1.0) = 0.12;
uniform vec4 tint : source_color = vec4(0.84, 0.95, 1.0, 1.0);
uniform vec2 src_size = vec2(640.0, 360.0);

float h21(vec2 p) {
	p = fract(p * vec2(443.8975, 397.2973));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

void fragment() {
	float t = TIME;
	float k = 0.35 + 0.65 * intensity;
	vec2 uv = UV;

	// テープの上下ジッター
	float wob = sin(t * 0.83) * 0.55 + sin(t * 2.71 + 1.3) * 0.30 + sin(t * 13.0) * 0.15;
	uv.y += wob * 0.0010 * jitter_amount * k;

	// 走査線単位の横ゆれ
	float line = floor(uv.y * src_size.y);
	float lr = h21(vec2(line * 0.137, floor(t * 20.0)));
	float hs = (lr - 0.5) * 0.0032 * jitter_amount * k;

	// トラッキングノイズ帯
	float band_h = 0.030 + 0.055 * tracking_amount;
	float dband = abs(fract(uv.y - tracking_pos + 0.5) - 0.5);
	float band = smoothstep(band_h, 0.0, dband) * tracking_amount;
	hs += band * (lr - 0.5) * 0.070 + band * 0.010;

	uv.x += hs;
	uv = clamp(uv, vec2(0.001), vec2(0.999));

	// 色にじみ(クロマ横ずれ)
	float c = chroma_px / src_size.x * (0.55 + 1.5 * intensity) + band * 0.005;
	vec4 base = texture(TEXTURE, uv);
	float r = texture(TEXTURE, vec2(uv.x + c, uv.y)).r;
	float b = texture(TEXTURE, vec2(uv.x - c, uv.y)).b;
	vec3 col = vec3(r, base.g, b);

	// ヘッドの尾を引くにじみ
	vec3 smear = texture(TEXTURE, vec2(uv.x - 2.0 / src_size.x, uv.y)).rgb;
	col = mix(col, max(col, smear * 0.88), 0.26 * k);

	// 彩度落とし → 黒潰し → 寒色寄せ
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), desat);
	col = pow(max(col, vec3(0.0)), vec3(1.0 + 0.45 * crush));
	col *= tint.rgb;
	col += vec3(0.010, 0.014, 0.020);

	// 細かいノイズ
	float n = h21(uv * src_size + vec2(t * 91.7, t * 53.3));
	col += (n - 0.5) * noise_amount * (0.5 + k);
	col += band * (n - 0.30) * 0.40;

	// 走査線(元解像度 1px 周期 = 出力 2px)
	float sl = 0.5 + 0.5 * cos(uv.y * src_size.y * 6.2831853);
	col *= 1.0 - scanline_amount * 0.42 * sl;
	col *= 1.0 - 0.045 * k * (0.5 + 0.5 * sin(uv.y * 860.0 + t * 5.0));

	// ビネット
	vec2 vo = (uv - 0.5) * vec2(1.06, 1.0);
	float v = 1.0 - vignette_amount * dot(vo, vo) * 1.30;
	col *= clamp(v, 0.0, 1.0);

	// 量子化 + ディザ
	float dth = h21(floor(FRAGCOORD.xy) + vec2(t * 3.0, t * 7.0)) - 0.5;
	col = floor(col * levels + 0.5 + dth * 0.85) / levels;

	col *= 1.0 - darken;
	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
