shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform float height = 0.0;
void fragment() {
 float radius = length((UV-vec2(0.5))*2.0);
 ALBEDO = vec3(0.005,0.008,0.015);
 ALPHA = (1.0-smoothstep(0.12,1.0,radius))*0.48/(1.0+height*1.4);
}
