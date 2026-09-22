shader_type spatial;
render_mode cull_disabled;
uniform mat4 bend_frame = mat4(1.0);
uniform float bend = 0.0;
uniform float bend_start = 6.0;
uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform sampler2D wall_atlas : filter_linear_mipmap_anisotropic, repeat_disable;
uniform float lateral_scroll = 0.0;
uniform float scroll = 0.0;
uniform float clock = 0.0;
uniform float intensity = 0.25;
// Opt-in corridor bezel spacing. Shared boss/pickup users have no gap.
uniform float panel_period = 0.0;
// Local long axis: Z for corridor PlaneMeshes, X for front-facing QuadMeshes.
uniform vec3 horizontal_axis = vec3(0.0, 0.0, 1.0);
varying vec3 world;
varying float surface_horizontal;
void vertex() {
	vec3 before = (inverse(bend_frame) * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = max(0.0, -before.z - bend_start);
	// Convert the world-X offset to local space, including rotated wall planes.
	VERTEX += (inverse(MODEL_MATRIX) * bend_frame * vec4(bend * d * d, 0.0, 0.0, 0.0)).xyz;
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface_horizontal = dot(VERTEX, horizontal_axis);
}

float hash_cell(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float glyph_ink(vec2 p, float code) {
	vec2 tile = vec2(mod(code,8.0),floor(code/8.0));
	// Different glyph IDs are discontinuous atlas addresses, not large pixel footprints.
	// Derive LOD from the continuous glyph plane, never from tile selection/fract().
	return textureGrad(wall_atlas,(tile+clamp(fract(p),vec2(0.015),vec2(0.985)))/8.0,dFdx(p)/8.0,dFdy(p)/8.0).a;
}
float rain(vec2 p, float speed, float density, float salt) {
	float column = mod(floor(p.x),384.0);
	float seed = hash_cell(vec2(column,salt));
	p.y += clock*speed*(0.7+seed);
	float cell = mod(floor(p.y),32.0);
	float trail = mod(cell+seed*32.0,16.0);
	float gate = 1.0-smoothstep(density*16.0-1.0,density*16.0,trail);
	return glyph_ink(p,1.0+floor(hash_cell(vec2(column,cell+salt))*63.0))*gate*(0.8+0.2*trail/(density*16.0));
}
float module_variant(float index) {
	if (index==1.0 || index==5.0 || index==10.0) return 1.0;
	if (index==2.0 || index==7.0 || index==9.0) return 2.0;
	if (index==4.0 || index==8.0 || index==11.0) return 3.0;
	return 0.0;
}

void fragment() {
	if (panel_period <= 0.0) {

	float column = mod(floor((surface_horizontal - scroll - lateral_scroll) * 2.0), 192.0);
	float seed = fract(sin(column * 12.9898) * 43758.5453);
	vec2 p = vec2((surface_horizontal-scroll-lateral_scroll)*2.0, world.y*2.5 + clock*(0.4+seed));
	float glyph = mod(abs(column * 7.0 + floor(p.y) * 13.0), 63.0) + 1.0;
	vec2 tile = vec2(mod(glyph, 8.0), floor(glyph/8.0));
	float ink = texture(atlas, (tile + fract(p))/8.0).a;
	ink *= 1.0 - smoothstep(0.3, 1.5, length(max(fwidth(world), vec3(0.004))));
	// A slower second glyph plane shifts with viewing angle behind the front glass.
	// 0.75 preserves the exact 96 m wrap (192 columns become 144).
	vec2 rear = p*0.75 + vec2(VIEW.x, VIEW.y)*0.18 + vec2(0.0, clock*0.09);
	float rear_glyph = mod(abs(column*11.0+floor(rear.y)*17.0),63.0)+1.0;
	vec2 rear_tile = vec2(mod(rear_glyph,8.0),floor(rear_glyph/8.0));
	float back_ink = texture(atlas,(rear_tile+fract(rear))/8.0).a;
	float panel_mask = 1.0;
	if (panel_period > 0.0) {
		float panel_u = fract((surface_horizontal-scroll)/panel_period);
		panel_mask = smoothstep(0.02,0.07,panel_u) * (1.0-smoothstep(0.93,0.98,panel_u));
	}
	float glass_rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),3.0);
	float scan = 0.8 + 0.2 * sin(world.y*110.0);
	float fade = 1.0-smoothstep(22.0, 88.0, -world.z);
	ALBEDO = vec3(0.018,0.033,0.05);
	METALLIC = 0.65;
	ROUGHNESS = 0.28;
	EMISSION = vec3(0.388,0.976,0.698) * ((ink+back_ink*0.15)*intensity*scan*(0.3+seed*0.7)+glass_rim*0.025)*fade*panel_mask;

	} else {
	// Material coordinates repeat only after the complete 96 m loop.
	float along = mod(surface_horizontal-scroll,96.0);
	float index = mod(floor((56.0-along)/8.0),12.0);
	float variant = module_variant(index);
	float width = 6.3;
	float height = 2.35;
	float center = 3.0;
	float shift = 0.0;
	if (variant==1.0) { width=5.5; height=2.25; center=3.3; shift=-0.4; }
	if (variant==2.0) { width=6.1; height=2.3; center=2.7; shift=0.4; }
	if (variant==3.0) { width=6.5; height=2.65; }
	vec2 screen = vec2((mod(along,8.0)-4.0-shift)/width+0.5,(world.y-center)/height+0.5);
	vec2 edge = min(screen,1.0-screen);
	float recess = smoothstep(0.0,0.018,min(edge.x,edge.y));
	float vignette = 1.0-0.08*dot(screen-0.5,screen-0.5)*2.0;
	vec2 p = vec2(mod(along-lateral_scroll,96.0)*2.0,world.y*2.5);
	// Three independent depths, speeds and densities; all wrap column counts divide 96 m.
	float front = rain(p+VIEW.xy*0.025,1.7,0.78,3.0);
	float middle = rain(p*0.75+VIEW.xy*0.10,0.9,0.60,19.0);
	float rear = rain(p*0.5+VIEW.xy*0.22,0.35,0.64,41.0);
	vec2 listing_p = vec2(along*3.0,world.y*3.5);
	float listing_code = 1.0+floor(hash_cell(floor(listing_p))*63.0);
	float listing = glyph_ink(listing_p,listing_code)*0.30;
	float token = step(0.975,hash_cell(floor(p)))*glyph_ink(p,33.0+mod(floor(p.x),26.0));
	float error = step(0.998,hash_cell(vec2(index,floor(clock*2.0))))*step(0.80,fract(clock*7.0))*glyph_ink(p,1.0);
	float scan = 0.91+0.09*sin(world.y*175.0)*exp(-fwidth(world.y)*175.0);
	float rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),3.0);
	float sheen = pow(max(0.0,1.0-abs(screen.x+screen.y*0.35-0.6+VIEW.x*0.2)*3.0),12.0);
	// Hero module: schematic nodes and circuit routes behind the code, same accent.
	vec2 diagram_p = (screen-0.5)*vec2(5.0,3.0);
	float ring_d = abs(length(diagram_p)-0.8);
	float diagram = (1.0-smoothstep(0.018,0.018+max(fwidth(ring_d),0.005),ring_d))*0.24;
	float routes = min(abs(diagram_p.y),abs(diagram_p.x));
	diagram += (1.0-smoothstep(0.012,0.012+max(fwidth(routes),0.005),routes))*0.13;
	vec2 node_cell = mod(diagram_p+0.5,1.0)-0.5;
	float node_d = abs(length(node_cell)-0.10);
	diagram += (1.0-smoothstep(0.015,0.015+max(fwidth(node_d),0.005),node_d))*0.22;
	diagram *= step(2.5,variant);
	float fade = 1.0-smoothstep(22.0,88.0,-world.z);
	ALBEDO = vec3(0.025,0.045,0.055)*recess;
	METALLIC = 0.72;
	ROUGHNESS = 0.24;
	EMISSION = (vec3(0.388,0.976,0.698)*((front*1.35+middle*0.48+rear*0.24+listing+token*1.8+diagram)*intensity*scan*vignette+rim*0.012+sheen*0.012)+vec3(1.0,0.302,0.239)*error*0.3)*recess*fade;

	}
}
