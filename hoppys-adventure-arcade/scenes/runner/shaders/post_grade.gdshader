shader_type canvas_item;
render_mode unshaded, blend_disabled;

// One fullscreen shading pass plus the renderer's implicit backbuffer copy.
// No mipmaps, convolution or additional shading passes.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float clock = 0.0;
uniform float grain_seed = 17.0;
uniform float grade : hint_range(0.0, 1.0) = 0.85;
uniform float grain : hint_range(0.0, 0.03) = 0.018;
uniform float vignette : hint_range(0.0, 1.0) = 0.16;
// Legacy pursuit API: same strength, color, corner_bars, pulse and scanlines.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.0, 0.302, 0.239, 1.0);
uniform float corner_bars : hint_range(0.0, 1.0) = 0.0;
uniform float pulse = 0.0;
uniform float scanlines = 0.0;
uniform float aberration : hint_range(0.0, 1.0) = 0.0;
uniform float letterbox : hint_range(0.0, 1.0) = 0.0;
uniform float speed : hint_range(0.0, 1.0) = 0.0;
uniform float bloom_lift : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32 + grain_seed);
	return fract(p.x * p.y);
}
vec3 filmic(vec3 x) {
	return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - 0.5;
	float edge = smoothstep(0.25, 1.25, length(centered * 2.0));
	// Pixel-sized channel separation, kept off the readable central lanes.
	vec2 split = centered * SCREEN_PIXEL_SIZE * aberration * edge * 7.0;
	vec3 src = texture(screen_texture, uv).rgb;
	if (aberration > 0.001) {
		src.r = texture(screen_texture, clamp(uv + split, vec2(0.0), vec2(1.0))).r;
		src.b = texture(screen_texture, clamp(uv - split, vec2(0.0), vec2(1.0))).b;
	}
	float luma = dot(src, vec3(0.2126, 0.7152, 0.0722));
	// Strong analytic grade; protect saturated danger reds and exact black.
	float curve = filmic(vec3(luma * 0.85)).r;
	vec3 graded = src * mix(1.0, curve / max(luma, 0.001), 0.85);
	float shadows = (1.0 - smoothstep(0.02, 0.32, luma)) * smoothstep(0.0, 0.08, luma);
	float highlights = smoothstep(0.5, 1.0, luma);
	graded += vec3(-0.020, 0.009, 0.045) * shadows;
	graded *= mix(vec3(1.0), vec3(0.96, 1.06, 1.01), highlights);
	graded = mix(graded, vec3(1.0, 0.941, 0.827) * luma, highlights * 0.18);
	float danger = smoothstep(0.08, 0.28, src.r - max(src.g, src.b));
	vec3 result = mix(src, graded, grade * (1.0 - danger * 0.9));
	// Nitro lifts bright pixels locally. Deliberately not a spatial bloom pass.
	result += src * smoothstep(0.55, 0.95, luma) * bloom_lift * 0.13;
	result += vec3(0.969, 0.537, 0.286) * edge * bloom_lift * 0.018;
	vec2 radial = centered * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float angle = atan(radial.y, radial.x);
	float spoke = pow(max(0.0, sin(angle * 48.0 + sin(angle * 19.0) * 4.0)), 6.0);
	float motion = pow(max(0.0, sin(length(radial) * 48.0 - clock * 19.0 + angle * 7.0)), 2.0);
	result += vec3(0.475, 0.878, 0.769) * spoke * (0.35 + 0.65 * motion) * edge * edge * speed * 0.22 * (1.0 + 0.5 * bloom_lift);
	result *= 1.0 - edge * vignette;
	float pursuit_alpha = clamp(edge * strength * (0.8 + 0.2 * pulse), 0.0, 0.72);
	result = mix(result, color.rgb * 0.28, pursuit_alpha);
	float noise = hash21(floor(FRAGCOORD.xy) + floor(clock * 24.0) * vec2(17.0, 31.0)) - 0.5;
	// Preserve pure black; retain 75 percent grain in deep navy.
	float grain_mask = smoothstep(0.0, 0.003, luma) * (0.75 + 0.25 * smoothstep(0.02, 0.2, luma));
	result += noise * grain * grain_mask;
	result *= 1.0 - step(0.5, fract(FRAGCOORD.y * 0.5)) * scanlines;
	float border = min(uv.y, 1.0 - uv.y);
	float pursuit_bars = (1.0 - smoothstep(corner_bars * 0.06, corner_bars * 0.06 + SCREEN_PIXEL_SIZE.y, border)) * step(0.001, corner_bars) * 0.65;
	float cinema_bars = (1.0 - smoothstep(letterbox * 0.065, letterbox * 0.065 + SCREEN_PIXEL_SIZE.y, border)) * step(0.001, letterbox);
	result *= 1.0 - max(pursuit_bars, cinema_bars);
	COLOR = vec4(clamp(result, 0.0, 1.0), 1.0);
}
