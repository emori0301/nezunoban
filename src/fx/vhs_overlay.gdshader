shader_type canvas_item;
// タイトル/エンディングなど「SubViewportContainer が無い場所」に重ねる簡易 VHS ノイズ。
// ColorRect に載せる。背景を透かしつつノイズ・走査線・ビネットだけを足す。

uniform float intensity : hint_range(0.0, 1.0) = 0.5;
uniform float noise_amount : hint_range(0.0, 1.0) = 0.12;
uniform float scanline_amount : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_amount : hint_range(0.0, 2.0) = 0.9;
uniform float tracking_amount : hint_range(0.0, 1.0) = 0.35;
uniform vec2 src_size = vec2(640.0, 360.0);

float h21(vec2 p) {
	p = fract(p * vec2(443.8975, 397.2973));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

void fragment() {
	float t = TIME;
	vec2 uv = UV;
	float n = h21(uv * src_size + vec2(t * 97.3, t * 61.1));
	float add = (n - 0.45) * noise_amount * intensity;

	float band_pos = fract(-t * 0.13);
	float d = abs(fract(uv.y - band_pos + 0.5) - 0.5);
	float band = smoothstep(0.045, 0.0, d) * tracking_amount * intensity;
	add += band * (h21(vec2(floor(uv.y * src_size.y), floor(t * 30.0))) - 0.2) * 0.55;

	float sl = 0.5 + 0.5 * cos(uv.y * src_size.y * 6.2831853);
	float mul = 1.0 - scanline_amount * 0.45 * sl * intensity;

	vec2 vo = uv - 0.5;
	mul *= clamp(1.0 - vignette_amount * dot(vo, vo) * 1.30, 0.0, 1.0);

	float bright = clamp(add * 3.4, 0.0, 1.0);
	vec3 col = vec3(bright);
	float a = clamp(bright * 1.7 + (1.0 - mul), 0.0, 1.0);
	COLOR = vec4(col * vec3(0.86, 0.95, 1.0), a);
}
