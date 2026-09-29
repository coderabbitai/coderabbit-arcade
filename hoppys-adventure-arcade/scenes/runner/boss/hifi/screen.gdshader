shader_type spatial;
render_mode cull_back;
uniform vec4 accent : source_color = vec4(1.0,0.302,0.239,1.0);
uniform float clock = 0.0;
uniform float intensity = 1.0;
uniform float accent_gain = 0.7;
uniform bool accent_path = false;
uniform vec2 check_start = vec2(-0.55,0.0);
uniform vec2 check_elbow = vec2(-0.15,-0.4);
uniform vec2 check_end = vec2(0.55,0.4);
uniform vec2 glyph_grid = vec2(24.0,12.0);
uniform bool instance_accent = false;
uniform int symbol = 0;
varying vec4 tile_color;
void vertex() { tile_color = COLOR; }
float glyph(vec2 p) {
	vec2 cell = floor(p);
	vec2 ink = fract(p);
	float seed = fract(sin(dot(cell, vec2(37.1,91.7))) * 437.31);
	return step(0.28, seed) * step(0.16, ink.x) * step(ink.x, 0.8) * step(0.2, ink.y) * step(ink.y, 0.75);
}
float line(vec2 p, vec2 a, vec2 b, float width) {
	vec2 d = b-a;
	float t = clamp(dot(p-a,d)/dot(d,d), 0.0, 1.0);
	return 1.0-smoothstep(width, width+0.025, length(p-a-d*t));
}
void fragment() {
	vec2 p = UV*2.0-1.0;
	vec3 tint = instance_accent ? tile_color.rgb : accent.rgb;
	float mask = glyph(UV*glyph_grid + vec2(0.0,floor(clock*3.0))) * 0.5;
	if (symbol == 1) {
		// Large check / cross, selected by the same per-instance PASS/FAIL tint.
		bool pass_state = tile_color.g > tile_color.r;
		mask = pass_state ? max(line(p,check_start,check_elbow,0.1),line(p,check_elbow,check_end,0.1)) : max(line(p,vec2(-0.45),vec2(0.45),0.1),line(p,vec2(-0.45,0.45),vec2(0.45,-0.45),0.1));
	} else if (symbol == 2) {
		// Two incoming chevrons stop before a separate central conflict marker.
		float left = max(line(p,vec2(-0.8,-0.48),vec2(-0.38,0.0),0.07),line(p,vec2(-0.8,0.48),vec2(-0.38,0.0),0.07));
		float right = max(line(p,vec2(0.8,-0.48),vec2(0.38,0.0),0.07),line(p,vec2(0.8,0.48),vec2(0.38,0.0),0.07));
		float conflict = max(line(p,vec2(0.0,-0.42),vec2(0.0,0.06),0.07),1.0-smoothstep(0.07,0.095,length(p-vec2(0.0,0.4))));
		mask = max(max(left,right),conflict);
	} else if (symbol == 3) {
		// Deprecation symbol: a broken status ring and a heavy diagonal strike.
		mask = (1.0-smoothstep(0.08,0.12,abs(length(p)-0.58)))*step(-0.35,p.y);
		mask = max(mask,line(p,vec2(-0.55,0.55),vec2(0.55,-0.55),0.1));
	} else if (symbol == 4) {
		mask = 1.0;
	}
	float edge = step(0.96,max(abs(p.x),abs(p.y)));
	float rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),3.0);
	float pulse = 0.9+0.1*sin(clock*7.0);
	ALBEDO = vec3(0.025,0.04,0.065);
	METALLIC = 0.65;
	ROUGHNESS = 0.28;
	float gain = accent_path ? min(accent_gain,0.8) : min(accent_gain*intensity,0.8);
	EMISSION = tint*clamp(mask+edge*0.35+rim*0.12,0.0,1.0)*pulse*gain;
}
