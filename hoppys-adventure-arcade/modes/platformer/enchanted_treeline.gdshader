shader_type canvas_item;
render_mode unshaded;

// One draw for the entire parallax strip: overlap changes the sampled artwork,
// never the number of translucent layers composited over the sky.
uniform float span_texels = 4000.0;
uniform float overlap_texels = 140.0;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float width = 1.0 / TEXTURE_PIXEL_SIZE.x;
	float stride = width - overlap_texels;
	float x = mod(UV.x * span_texels, stride);
	vec4 current = texture(TEXTURE, vec2(x / width, UV.y));
	vec4 previous = texture(TEXTURE, vec2(min(x + stride, width - 0.5) / width, UV.y));
	float weight = smoothstep(0.0, overlap_texels, x);
	// Blend premultiplied colors so transparent edge pixels cannot add dark halos.
	float alpha = mix(previous.a, current.a, weight);
	vec3 rgb = mix(previous.rgb * previous.a, current.rgb * current.a, weight);
	// Gaps in the floor expose the plate's lower edge. Fade it into the sky too.
	float bottom = 1.0 - smoothstep(0.9, 1.0, UV.y);
	COLOR = vec4(rgb / max(alpha, 0.00001), alpha * bottom) * tint;
}
