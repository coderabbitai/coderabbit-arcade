shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float phase = 0.0;
uniform float clock = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	float side = step(0.5, uv.x);
	if (phase > 2.5) {
		float band = step(0.96, fract(sin(floor(uv.y * 90.0) + floor(clock * 9.0)) * 43758.5453));
		uv.x += band * sin(clock * 20.0) * 0.004;
	}
	vec4 c = texture(screen_texture, uv);
	if (phase > 1.5) {
		c.rgb *= mix(vec3(0.90,1.02,1.04),vec3(1.04,0.93,0.99),side);
		if (abs(SCREEN_UV.x-0.5) < 0.0012) c.rgb = mix(vec3(0.2,0.9,1.0),vec3(1.0,0.3,0.5),side);
	}
	COLOR = c;
}
