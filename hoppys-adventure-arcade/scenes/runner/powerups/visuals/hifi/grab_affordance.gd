extends RefCounted
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
## Shared vector glyphs and one merged beam/ring/halo surface. No engine TIME.
const TOOL_KINDS := [&"review_comment",&"lint_rule",&"unit_test",&"auto_fix_patch"]
static var TOOL_GLYPH_TINT: Color = Palette.ORANGE.darkened(0.08)
const GLYPHS := {
 &"approve_shield": '<path d="M16 5L27 10V20L16 28L5 20V10Z"/><path d="M10 16L14 20L23 11"/>',
 &"auto_fix": '<path d="M7 26L20 13M19 5L17 11L22 16L28 14M7 23L9 25M6 5V11M3 8H9"/>',
 &"lgtm": '<path d="M5 15H11L16 5H20V13H27L24 27H11V15M5 14V27H10"/>',
 &"nitro": '<path d="M11 22V12L16 4L21 12V22ZM11 16L5 23H11M21 16L27 23H21M13 25L16 29L19 25"/>',
 &"super_jump": '<path d="M16 4L10 10M16 4L22 10M16 4V14M7 16L25 19L7 22L25 25M6 28H26"/>',
 &"code_review": '<circle cx="13" cy="13" r="9"/><path d="M20 20L28 28M8 10H18M8 16H18"/>',
 &"review_comment": '<path d="M4 5H28V22H15L7 28V22H4ZM10 11H22M10 16H19"/>',
 &"lint_rule": '<path d="M5 25H27V28H5ZM7 25V5M13 25V5M19 25V5M25 25V5"/>',
 &"unit_test": '<path d="M4 4H28V28H4ZM9 16L14 21L24 10"/>',
 &"auto_fix_patch": '<path d="M5 5L15 16L5 27M17 5L27 16L17 27"/>'
}
static var glyph_cache: Dictionary = {}
static var beam_mesh: ArrayMesh
static var beam_shader: Shader
static var glyph_shader: Shader
const BEAM_CODE := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_back, fog_disabled;
uniform vec4 tint : source_color;
uniform float clock = 0.0;
uniform float near_fade = 1.0;
uniform float beam_width = 0.35;
uniform float beam_offset = 0.0;
uniform float beam_only = 0.0;
uniform float beam_core_gain = 1.0;
varying float part;
void vertex(){
 part = COLOR.r;
 if(part < 0.5){ VERTEX.x = VERTEX.x*beam_width/0.35*(0.60+0.40*pow(1.0-UV.y,2.0))+beam_offset; }
}
void fragment(){
 float a;
 if(part < 0.5){
  float edge = pow(max(0.0,1.0-pow(UV.x*2.0-1.0,2.0)),2.0);
  float height = smoothstep(0.0,0.06,UV.y)*(1.0-smoothstep(0.65,1.0,UV.y));
  // A slow entwined pair inside a broad sheath, not a corridor pillar stripe.
  float offset = 0.24*sin(UV.y*6.2831853+clock*0.65);
  float ribbons = exp(-pow((UV.x-0.5-offset)*12.0,2.0))+exp(-pow((UV.x-0.5+offset)*12.0,2.0));
  float fresnel = 0.8+0.2*pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.0);
  a = edge*height*fresnel*(0.40+0.18*ribbons)*beam_core_gain;
 }else{
  float r = length(UV-vec2(0.5))*2.0;
  float ring = (1.0-smoothstep(0.025,0.09,abs(r-0.58)));
  float halo = pow(max(0.0,1.0-r),2.0)*0.20;
  a = (ring*0.40+halo)*(1.0-beam_only);
 }
 ALBEDO = tint.rgb*0.85;
 ALPHA = a*near_fade*(1.0+0.30*sin(clock*4.0));
}
"""
const GLYPH_CODE := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;
uniform vec4 tint : source_color;
uniform sampler2D glyph : filter_linear_mipmap;
uniform float depth_alpha = 1.0;
uniform float glyph_gain = 0.75;
uniform float clock = 0.0;
void fragment(){
 float scan = 0.92+0.08*sin(UV.y*25.0-clock*3.0);
 ALBEDO = tint.rgb*glyph_gain;
 ALPHA = texture(glyph,UV).a*scan*depth_alpha;
}
"""
static func material(color: Color, kind: StringName = &"") -> ShaderMaterial:
	var result := ShaderMaterial.new()
	if kind == &"":
		if beam_shader == null:
			beam_shader = Shader.new()
			beam_shader.code = BEAM_CODE
		result.shader = beam_shader
	else:
		if glyph_shader == null:
			glyph_shader = Shader.new()
			glyph_shader.code = GLYPH_CODE
		result.shader = glyph_shader
		if not glyph_cache.has(kind):
			var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 32 32"><g fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % GLYPHS[kind]
			var image := Image.new()
			image.load_svg_from_string(svg)
			image.generate_mipmaps()
			glyph_cache[kind] = ImageTexture.create_from_image(image)
		result.set_shader_parameter("glyph",glyph_cache[kind])
	result.set_shader_parameter("tint",TOOL_GLYPH_TINT if kind in TOOL_KINDS else color)
	if kind != &"": result.set_shader_parameter("glyph_gain",0.675 if kind in TOOL_KINDS else 0.75)
	return result

static func mesh() -> ArrayMesh:
	if beam_mesh != null: return beam_mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Camera-facing sheath, explicit back face and floor halo share one surface.
	quad(surface,[Vector3(-0.175,0,0),Vector3(0.175,0,0),Vector3(0.175,3.2,0),Vector3(-0.175,3.2,0)],Color.BLACK)
	quad(surface,[Vector3(0.175,0,0),Vector3(-0.175,0,0),Vector3(-0.175,3.2,0),Vector3(0.175,3.2,0)],Color.BLACK)
	quad(surface,[Vector3(-1.2,0,1.2),Vector3(1.2,0,1.2),Vector3(1.2,0,-1.2),Vector3(-1.2,0,-1.2)],Color.WHITE)
	surface.generate_normals()
	surface.index()
	beam_mesh = surface.commit()
	return beam_mesh

static func quad(surface: SurfaceTool, points: Array, color: Color) -> void:
	var uv := [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	for i in [0,2,1,0,3,2]:
		surface.set_color(color)
		surface.set_uv(uv[i])
		surface.add_vertex(points[i])
