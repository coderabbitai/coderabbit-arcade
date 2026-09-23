shader_type spatial;
render_mode cull_back;
uniform bool module_mode = false;
uniform float bend = 0.0;
uniform float bend_start = 6.0;
uniform float clock = 0.0;
uniform float frame_metallic : hint_range(0.0, 1.0) = 0.28;
uniform vec4 base_tint : source_color = vec4(0.263, 0.329, 0.392, 1.0);
uniform float baked_gain = 0.85;
uniform float rim_gain = 0.10;
uniform float ceiling_gain = 0.60;
varying float overhead;
varying vec3 material_position;
varying float rack_variant;
varying float wear_seed;
uniform sampler2D atlas : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
// The corridor submits each module's yaw, origin, and its inverse rotation scalars.
// No matrix inversions per vertex, including instanced draws.
vec3 yaw_rotate(vec3 v, float c, float s) {
	return vec3(c*v.x + s*v.z, v.y, -s*v.x + c*v.z);
}
void vertex() {
	rack_variant = COLOR.b*3.0;
	wear_seed = 0.0;
	float origin_s = 0.0;
	if (module_mode) {
		rack_variant = floor(INSTANCE_CUSTOM.w/16.0);
		wear_seed = mod(INSTANCE_CUSTOM.w,16.0);
		// Only the shared 0/1 batch carries nonzero CUSTOM0 deltas.
		VERTEX += CUSTOM0.xyz * float(rack_variant == 1.0);
		origin_s = sin(-atan(2.0*bend*max(0.0,-INSTANCE_CUSTOM.x-bend_start)));
	}
	material_position = VERTEX;
	overhead = step(6.1, VERTEX.y);
	float source_z = VERTEX.z;
	if (module_mode) { source_z += INSTANCE_CUSTOM.x; }
	float local_yaw = -atan(2.0*bend*max(0.0, -source_z-bend_start));
	float c = cos(local_yaw);
	float s = sin(local_yaw);
	// Rotate the full tangent frame at the vertex, then undo the CPU instance yaw.
	NORMAL = yaw_rotate(NORMAL, c, s);
	TANGENT = yaw_rotate(TANGENT, c, s);
	BINORMAL = yaw_rotate(BINORMAL, c, s);
	if (module_mode) {
		NORMAL = yaw_rotate(NORMAL, INSTANCE_CUSTOM.z, -origin_s);
		TANGENT = yaw_rotate(TANGENT, INSTANCE_CUSTOM.z, -origin_s);
		BINORMAL = yaw_rotate(BINORMAL, INSTANCE_CUSTOM.z, -origin_s);
	}
	if (module_mode) {
		vec3 p = VERTEX + vec3(0.0, 0.0, INSTANCE_CUSTOM.x);
		float d = max(0.0, -p.z - bend_start);
		p.x += bend * d * d;
		p -= vec3(INSTANCE_CUSTOM.y, 0.0, INSTANCE_CUSTOM.x);
		VERTEX = vec3(INSTANCE_CUSTOM.z*p.x - origin_s*p.z, p.y, origin_s*p.x + INSTANCE_CUSTOM.z*p.z);
	} else {
		float d = max(0.0, -VERTEX.z - bend_start);
		VERTEX.x += bend * d * d;
	}
}
uniform sampler2D circuit_map : filter_linear_mipmap_anisotropic, repeat_enable;
float line_mask(float d, float width) {
	return 1.0-smoothstep(width,width+max(fwidth(d),0.001),d);
}
float stencil(vec2 p) {
	// RACK 0x7F / NODE 03 / CI, in three stencilled rows.
	float row = floor(p.y);
	float col = floor(p.x);
	float code = 0.0;
	if (row==0.0) {
		if (col==0.0) code=50.0; if (col==1.0) code=33.0; if (col==2.0) code=35.0; if (col==3.0) code=43.0;
		if (col==5.0) code=16.0; if (col==6.0) code=56.0; if (col==7.0) code=23.0; if (col==8.0) code=38.0;
	} else if (row==1.0) {
		if (col==0.0) code=46.0; if (col==1.0) code=47.0; if (col==2.0) code=36.0; if (col==3.0) code=37.0;
		if (col==5.0) code=16.0; if (col==6.0) code=19.0;
	} else if (row==2.0) { if (col==0.0) code=35.0; if (col==1.0) code=41.0; }
	vec2 cell=fract(p);
	// Lowercase x uses a reduced cap stroke at the shared baseline.
	if (row==0.0 && col==6.0) {
		cell.y=(cell.y-0.30)/0.70;
		if (cell.y<0.0 || cell.y>1.0) return 0.0;
	}
	float ink=texture(atlas,(vec2(mod(code,8.0),floor(code/8.0))+cell)/8.0).a;
	return ink*(1.0-line_mask(abs(cell.y-0.5),0.025));
}
// Aperiodic material-space grain, in metres, with footprint filtering before
// subpixel cells alias. Its zero mean preserves the established frame exposure.
float grain_hash(vec2 cell) {
	return fract(sin(dot(cell,vec2(127.1,311.7)))*43758.5453)*2.0-1.0;
}
float filtered_grain(vec2 metres, vec2 cell_size) {
	vec2 q = metres/cell_size;
	vec2 cell = floor(q);
	vec2 t = fract(q);
	t = t*t*(3.0-2.0*t);
	float value = mix(mix(grain_hash(cell),grain_hash(cell+vec2(1.0,0.0)),t.x),
		mix(grain_hash(cell+vec2(0.0,1.0)),grain_hash(cell+vec2(1.0,1.0)),t.x),t.y);
	float footprint = max(fwidth(q.x),fwidth(q.y));
	return value*(1.0-smoothstep(0.5,1.0,footprint));
}
void fragment() {
	float inset = mix(0.62, 1.0, clamp(COLOR.r / 0.263, 0.0, 1.0));
	float bevel = UV2.x;
	float ao = UV2.y * inset;
	// 2 m map footprint; seams and wear span several pixels even in gameplay.
	vec2 p = material_position.zy;
	vec2 map_uv = p*0.5;
	vec3 plating = texture(albedo_map, map_uv).rgb;
	vec2 cell = fract(p/vec2(0.8,0.6));
	vec2 edges = min(cell,1.0-cell)*vec2(0.8,0.6);
	float groove_d = min(edges.x,edges.y);
	float groove = line_mask(groove_d,0.012);
	float bevel_lip = line_mask(abs(groove_d-0.032),0.010);
	// Half-pitch fasteners with signed local coordinates for a lit upper rim.
	vec2 corner = mod(p-vec2(0.085)+vec2(0.20,0.15),vec2(0.40,0.30))-vec2(0.20,0.15);
	vec2 sub_cell = fract(p/vec2(0.20,0.15));
	vec2 sub_edges = min(sub_cell,1.0-sub_cell)*vec2(0.20,0.15);
	float sub_d = min(sub_edges.x,sub_edges.y);
	float sub_groove = line_mask(sub_d,0.006);
	float sub_lip = line_mask(abs(sub_d-0.012),0.004);
	// Five recessed louvres on one of every three primary panels.
	vec2 panel_id = floor(p/vec2(0.8,0.6));
	vec2 panel_p = cell*vec2(0.8,0.6);
	float vent_select = 1.0-step(0.5,mod(panel_id.x+panel_id.y+wear_seed,3.0));
	float vent = 0.0;
	for (int slat=0; slat<5; slat++) {
		vent += line_mask(abs(panel_p.y-(0.27+float(slat)*0.03)),0.006);
	}
	vent *= vent_select*step(0.16,panel_p.x)*step(panel_p.x,0.64);
	float rivet_d = length(corner);
	float rivet = line_mask(rivet_d,0.032);
	float rivet_rim = line_mask(abs(rivet_d-0.04),0.008);
	// Seed changes only wear and label selection, never rivet/seam registration.
	vec2 wear_p = p + vec2(fract(sin(wear_seed*17.13)*437.53)*19.0,fract(sin(wear_seed*39.71)*853.13)*11.0);
	float fine_grain = filtered_grain(wear_p,vec2(0.022,0.008));
	float medium_grain = filtered_grain(wear_p+vec2(7.3,2.9),vec2(0.18,0.09));
	float scuff = filtered_grain(wear_p+vec2(3.7,8.1),vec2(0.30,0.10));
	float grime_signed = filtered_grain(wear_p+vec2(9.1,5.3),vec2(0.65,0.28));
	float grime = 0.5+0.5*grime_signed;
	// Both ALBEDO and baked bounce receive actual face detail; normals are secondary.
	// Balanced, bounded grain changes contrast without a global exposure increase.
	plating = clamp(vec3(0.74)+(plating-vec3(0.55))*0.65
		+vec3(fine_grain*0.08+medium_grain*0.10+scuff*0.07-grime_signed*0.12
		-groove*0.34+bevel_lip*0.52-sub_groove*0.16+sub_lip*0.26
		+rivet*0.34+rivet_rim*sign(corner.y)*0.30-vent*0.28),vec3(0.40),vec3(1.20));
	float label = stencil(vec2((p.x+2.5)*5.0,(5.9-p.y)*5.0+mod(rack_variant+floor(fract(sin(wear_seed*17.13+4.7)*437.53)*3.0),3.0)));
	// A compact CI stencil repeats inside every broad primary plate, not only at y=5.9.
	vec2 local_label = vec2((panel_p.x-0.50)*10.0,(0.19-panel_p.y)*10.0+2.0);
	float local_ink = stencil(local_label)*step(0.50,panel_p.x)*step(panel_p.x,0.70)*step(0.09,panel_p.y)*step(panel_p.y,0.19);
	label = max(label,local_ink);
	plating = mix(plating,vec3(1.20),label*0.85);
	float stripe_zone = step(1.65,p.x)*step(p.x,2.8)*step(4.7,p.y)*step(p.y,4.95);
	// Selected layouts expose this plate; the others mask it with their upper screen.
	stripe_zone *= step(0.5,rack_variant)*step(rack_variant,2.5)*float(module_mode);
	float stripe = step(0.5,fract((p.x+p.y)*3.0));
	plating *= 1.0-stripe_zone*stripe*0.80;
	ALBEDO = base_tint.rgb * plating * inset;
	AO = clamp(1.0-groove*0.65-grime*0.15,0.25,1.0);
	METALLIC = frame_metallic;
	ROUGHNESS = clamp(texture(roughness_map, map_uv).r+fine_grain*0.06+grime*0.06-scuff*0.08,0.25,0.45);
	NORMAL_MAP = texture(normal_map, map_uv).rgb;
	NORMAL_MAP_DEPTH = 0.60;
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	float overhead_attenuation = mix(1.0, ceiling_gain, overhead);
	// Low-energy baked bounce reveals solid surfaces independently of Compatibility ambient.
	vec3 baked = base_tint.rgb * plating * baked_gain * ao * (0.75 + bevel*1.5);
	vec3 accent = vec3(0.388,0.976,0.698);
	vec3 detail = accent * (COLOR.a + texture(circuit_map, UV).r * 0.035) * (0.85+0.15*sin(clock*3.14));
	// Tray light bars retain their masked output; only metal fill and rim are attenuated.
	EMISSION = (baked + accent*rim*rim_gain*ao) * overhead_attenuation + detail;
}
