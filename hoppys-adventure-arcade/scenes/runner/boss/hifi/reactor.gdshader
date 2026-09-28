shader_type spatial;
render_mode cull_back;
uniform vec4 accent : source_color = vec4(0.388,0.976,0.698,1.0);
uniform float clock = 0.0;
uniform float intensity = 1.0;
void fragment() {
	float rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),3.0);
	float belt = 1.0-smoothstep(0.08,0.12,abs(UV.y-0.5));
	float seams = 1.0-smoothstep(0.025,0.055,abs(fract(UV.x*8.0)-0.5));
	float mask = max(belt,seams);
	ALBEDO = accent.rgb * 0.12;
	METALLIC = 0.35;
	ROUGHNESS = 0.25;
	EMISSION = accent.rgb * min(0.6, (mask*0.48 + rim*0.12) * (0.9+0.1*sin(clock*3.0)));
}
