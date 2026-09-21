shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;
// Opaque depth-tested mouth. Black albedo receives no key/fill lighting;
// emission represents the well's own recessed illumination, not a floor decal.
uniform vec2 opening_size = vec2(4.9,2.5);
uniform float well_depth = 1.6;
uniform vec4 bottom_color : source_color = vec4(0.031373,0.066667,0.109804,1.0);
uniform vec4 wall_shadow : source_color = vec4(0.043137,0.105882,0.164706,1.0);
uniform vec4 wall_color : source_color = vec4(0.262745,0.329412,0.392157,1.0);
uniform vec4 accent : source_color = vec4(1.0,0.301961,0.239216,1.0);
uniform vec4 cable_color : source_color = vec4(0.0,1.0,0.533333,1.0);
uniform float clock = 0.0;
varying vec3 local_point;
void vertex() {
	local_point = VERTEX;
}
void fragment() {
	// VIEW points toward the eye in view space. Transform a direction (w=0),
	// then negate for a ray into the well. No screen-size or 3D-scale dependency.
	vec3 ray = -normalize((inverse(MODEL_MATRIX) * INV_VIEW_MATRIX * vec4(VIEW,0.0)).xyz);
	vec2 half_size = opening_size*0.5;
	// Parallel rays must yield a distant intersection, never 0/0 or NaN.
	float wall_x = abs(ray.x) < 0.00001 ? 100000.0 : (sign(ray.x)*half_size.x-local_point.x)/ray.x;
	float wall_z = abs(ray.z) < 0.00001 ? 100000.0 : (sign(ray.z)*half_size.y-local_point.z)/ray.z;
	float bottom_t = well_depth/max(-ray.y,0.00001);
	float t = min(bottom_t,min(wall_x,wall_z));
	vec3 hit = local_point+ray*t;
	float wall = 1.0-step(bottom_t-0.0001,t);
	float height = clamp(1.0+hit.y/well_depth,0.0,1.0);
	float far_wall = wall*(1.0-step(wall_x,wall_z))*step(ray.z,0.0);
	float cable = wall*(1.0-smoothstep(0.014,0.040,abs(fract(hit.x*2.4+sin(hit.y*2.0)*0.025)-0.5)));
	// Broad reflected wall light falls toward the dark floor of the shaft.
	float wall_mask = wall*smoothstep(0.60,1.0,height);
	vec3 wall_hue = mix(wall_shadow.rgb,wall_color.rgb,height);
	wall_hue /= max(dot(wall_hue,vec3(0.2126,0.7152,0.0722)),0.001);
	vec3 interior_light = wall_hue*wall_mask*(0.07+0.03*far_wall)*(1.0-cable*0.60);
	float cable_core = wall*(1.0-smoothstep(0.002,0.007,abs(fract(hit.x*2.4+sin(hit.y*2.0)*0.025)-0.5)));
	float seam = far_wall*smoothstep(0.975,0.998,height)*(1.0-cable);
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = bottom_color.rgb*0.001 + interior_light + cable_color.rgb*cable_core*max(wall_mask,0.15)*0.02 + accent.rgb*seam*0.12*(1.0+0.15*sin(clock*6.28318));
}
