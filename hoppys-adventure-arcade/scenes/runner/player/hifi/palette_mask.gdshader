shader_type spatial;
render_mode unshaded, fog_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
void fragment() {
	vec4 texel = texture(albedo_map, UV);
	if (texel.a * albedo_color.a < 0.5) { discard; }
	vec3 c = texel.rgb * albedo_color.rgb;
	// Linear-space source palette classes: orange cloth and cream fur.
	bool orange = c.r > 0.3 && c.g > 0.06 && c.g < c.r * 0.6 && c.b < c.g * 0.65;
	bool cream = min(c.r, min(c.g, c.b)) > 0.4 && max(c.r, max(c.g, c.b)) / min(c.r, min(c.g, c.b)) < 1.7
		&& max(c.r, max(c.g, c.b)) / min(c.r, min(c.g, c.b)) > 1.12;
	ALBEDO = orange ? vec3(1,0,0) : (cream ? vec3(0,1,0) : vec3(0,0,1));
}
