extends RefCounted
## Cached materials are immutable to callers; duplicate before changing properties.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
static var _materials: Dictionary = {}
static var _fonts: Dictionary = {}

static func font() -> SystemFont:
	if not _fonts.has("mono"):
		var result := SystemFont.new()
		result.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono"])
		result.font_weight = 700
		_fonts["mono"] = result
	return _fonts["mono"]

static func lit(color: Color) -> StandardMaterial3D:
	var key := "lit:" + color.to_html()
	if not _materials.has(key):
		var result := StandardMaterial3D.new()
		result.albedo_color = color
		result.roughness = 0.85
		result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_materials[key] = result
	return _materials[key]

static func glow(color: Color, energy: float = 1.2) -> StandardMaterial3D:
	var key := "glow:%s:%s" % [color.to_html(), energy]
	if not _materials.has(key):
		var result := lit(color).duplicate() as StandardMaterial3D
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = energy
		_materials[key] = result
	return _materials[key]

static func additive(color: Color, alpha: float) -> StandardMaterial3D:
	var key := "add:%s:%s" % [color.to_html(), alpha]
	if not _materials.has(key):
		var result := lit(color).duplicate() as StandardMaterial3D
		result.albedo_color.a = alpha
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		result.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		result.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = result
	return _materials[key]

static func label(parent: Node, text: String, size: int, color: Color) -> Label3D:
	var result := Label3D.new()
	result.text = text
	result.font = font()
	result.font_size = size
	result.modulate = color
	result.outline_size = 8
	result.outline_modulate = Palette.NAVY_BG
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	parent.add_child(result)
	return result

static func environment() -> Environment:
	var result := Environment.new()
	result.background_mode = Environment.BG_COLOR
	result.background_color = Palette.NAVY_BG
	result.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	result.ambient_light_color = Palette.NAVY_2
	result.ambient_light_energy = 1.2
	result.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	result.glow_enabled = true
	result.glow_intensity = 0.9
	result.glow_bloom = 0.12
	result.glow_hdr_threshold = 0.75
	result.glow_hdr_scale = 2.0
	result.fog_enabled = true
	result.fog_mode = Environment.FOG_MODE_DEPTH
	result.fog_light_color = Palette.NAVY_BG
	result.fog_depth_begin = 22.0
	result.fog_depth_end = 88.0
	result.adjustment_enabled = true
	result.adjustment_saturation = 1.15
	return result

static func glyph_particles(count: int, bounds: Vector3) -> GPUParticles3D:
	var result := GPUParticles3D.new()
	result.amount = count
	result.lifetime = 4.0
	result.preprocess = 4.0
	result.fixed_fps = 30
	result.visibility_aabb = AABB(Vector3(-5, -8, -52), Vector3(10, 16, 108))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = bounds
	process.direction = Vector3.DOWN
	process.spread = 6.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 2.2
	process.gravity = Vector3.ZERO
	process.anim_offset_min = 0.0
	process.anim_offset_max = 1.0
	process.anim_speed_min = 1.0
	process.anim_speed_max = 4.0
	result.process_material = process
	var material := additive(Palette.MATRIX, 0.3).duplicate() as StandardMaterial3D
	material.albedo_texture = preload("res://scenes/runner/shaders/glyph_atlas.gd").texture()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.particles_anim_h_frames = 8
	material.particles_anim_v_frames = 8
	material.particles_anim_loop = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.18)
	quad.material = material
	result.draw_pass_1 = quad
	return result
