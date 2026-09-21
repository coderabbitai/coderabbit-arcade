shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
uniform float clock = 0.0;
uniform vec4 membrane_color : source_color = vec4(0.388235,0.976471,0.698039,1.0);
void vertex() {
	VERTEX.z += sin(clock*30.0+VERTEX.x*3.0)*0.07*(VERTEX.x+0.5);
}
void fragment() {
	float rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.0);
	float vein = 1.0-smoothstep(0.02,0.05,abs(fract(UV.x*5.0+UV.y*2.0)-0.5));
	ALBEDO = membrane_color.rgb*0.45;
	METALLIC = 0.15;
	ROUGHNESS = 0.3;
	EMISSION = membrane_color.rgb*(rim*0.35+vein*0.18);
	ALPHA = 0.18+rim*0.25+vein*0.28;
}
