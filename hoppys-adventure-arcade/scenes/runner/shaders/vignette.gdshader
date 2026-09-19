shader_type canvas_item;
render_mode unshaded;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.0,0.302,0.239,1.0);
uniform float pulse = 0.0;
uniform float scanlines = 0.06;
void fragment() {
	float edge = smoothstep(0.25, 1.25, length((UV-0.5)*2.0));
	float scan = step(0.5, fract(FRAGCOORD.y*0.5))*scanlines;
	COLOR = vec4(color.rgb * strength, clamp(edge*strength*(0.8+0.2*pulse)+scan, 0.0, 0.95));
}
