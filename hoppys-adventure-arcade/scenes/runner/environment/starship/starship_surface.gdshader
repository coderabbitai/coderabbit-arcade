shader_type spatial;
render_mode cull_disabled;
uniform sampler2D detail_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(0.48, 0.52, 0.47, 1.0);
uniform float metallic = 0.0;
uniform float glow = 0.0;
uniform float clock = 0.0;
uniform float scroll = 0.0;
uniform float bend = 0.0;
uniform mat4 bend_frame = mat4(1.0);
uniform bool floor_mode = false;
uniform bool window_mode = false;
varying vec3 surface;
void vertex() {
 surface = (inverse(bend_frame) * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 float d = max(0.0, -surface.z - 6.0);
 VERTEX += (inverse(MODEL_MATRIX) * bend_frame * vec4(bend*d*d, 0.0, 0.0, 0.0)).xyz;
}
void fragment() {
 vec2 uv = UV;
 if (floor_mode) { uv = vec2(surface.x, surface.z-scroll)*0.5; }
 float grain = texture(detail_map, uv*1.8).r;
 vec3 base = tint.rgb * COLOR.rgb;
 float edge = 1.0;
 if (floor_mode) {
  vec2 p = vec2(surface.x, surface.z-scroll);
  vec2 cell = fract(p/vec2(2.0,3.0));
  vec2 joint = min(cell,1.0-cell)*vec2(2.0,3.0);
  float distance = min(joint.x,joint.y);
  float aa = max(fwidth(distance),0.002);
  float seam = smoothstep(0.016-aa,0.016+aa,distance);
  float bevel = 1.0-smoothstep(0.022,0.065,distance);
  edge = mix(0.20,1.0,seam)+bevel*seam*0.24;
  float panel_variation = fract(sin(dot(floor(p/vec2(2.0,3.0)),vec2(12.989,78.233)))*43758.5453);
  base *= mix(0.88,1.07,panel_variation);
 }
 float brush = texture(detail_map,uv*vec2(1.0,55.0)).r;
 ALBEDO = base * (0.91+grain*0.07+brush*0.05)*edge;
 if(floor_mode) {
  float lane = 1.0-smoothstep(0.01,0.025,abs(abs(surface.x)-1.0));
  float edge_strip = smoothstep(3.36,3.40,abs(surface.x))*(1.0-smoothstep(3.7,3.74,abs(surface.x)));
  float chevron = step(0.5,fract((surface.z-scroll)*0.8+abs(surface.x)*1.4));
  ALBEDO = mix(ALBEDO,vec3(0.15,0.23,0.27),lane*0.7);
  vec2 tile = fract(vec2(surface.x,surface.z-scroll)/vec2(2.0,3.0))*vec2(2.0,3.0);
  vec2 fastener = min(tile,vec2(2.0,3.0)-tile)-vec2(0.13);
  float bolt = 1.0-smoothstep(0.035,0.052,length(fastener));
  float bolt_core = 1.0-smoothstep(0.014,0.024,length(fastener));
  ALBEDO *= 1.0+bolt*0.5-bolt_core*0.8;
  ALBEDO = mix(ALBEDO,mix(vec3(0.035,0.055,0.075),vec3(0.43,0.49,0.48),chevron),edge_strip*0.75);
 }
 ROUGHNESS = mix(0.72,0.36,metallic);
 METALLIC = metallic;
 NORMAL_MAP = normalize(vec3((texture(detail_map,uv*1.8+vec2(0.008,0.0)).r-grain)*0.8,(texture(detail_map,uv*1.8+vec2(0.0,0.008)).r-grain)*0.8,1.0))*0.5+0.5;
 NORMAL_MAP_DEPTH = 0.18;
 EMISSION = ALBEDO * (0.20 + glow*(0.88+0.12*sin(clock*4.0+surface.z)));
 if (window_mode) {
  vec2 sky = vec2(surface.z,surface.y)*0.065;
  vec2 cells = floor(sky*130.0);
  float random = fract(sin(dot(cells,vec2(12.9898,78.233)))*43758.5453);
  vec2 point = fract(sky*130.0)-vec2(0.5);
  float star = (1.0-smoothstep(0.025,0.14,length(point)))*step(0.976,random);
  float cloud = texture(detail_map,sky*0.7).r;
  vec3 space = mix(vec3(0.003,0.009,0.022),vec3(0.035,0.075,0.12),cloud*cloud);
  vec2 planet_uv = vec2((surface.z+18.0)*0.027,(surface.y-3.4)*0.22);
  float radius = length(planet_uv);
  float planet = (1.0-smoothstep(0.25,0.254,radius))*step(surface.x,0.0);
  float rim = exp(-abs(radius-0.251)*170.0)*0.15*step(surface.x,0.0);
  float bands = 0.6+0.2*sin(planet_uv.y*180.0+cloud*4.0);
  float light = smoothstep(-0.24,0.17,planet_uv.x)*(1.0-smoothstep(0.0,0.27,radius))*2.0;
  space = mix(space,vec3(0.12,0.23,0.30)*bands*light,planet);
  EMISSION = space+vec3(0.24,0.53,0.72)*rim+vec3(star*0.55)*(1.0-planet);
  ALBEDO = vec3(0.008,0.015,0.025);
  METALLIC = 0.15;
  ROUGHNESS = 0.85;
  NORMAL_MAP_DEPTH = 0.0;
 }
}
