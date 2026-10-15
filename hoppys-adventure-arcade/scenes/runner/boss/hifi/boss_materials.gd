extends RefCounted
## Contract 2.6: private PBR copies share Hoppy's hue-preserving lighting.
const Surface = preload("res://scenes/runner/boss/hifi/boss_surface.gdshader")

static func surface_from(source: BaseMaterial3D) -> ShaderMaterial:
	# COLOR stays available for future art; rest positions use reserved UV2/CUSTOM0.
	# BossModel validates those mesh channels before a shader material is installed.
	assert(source != null, "Boss expects imported PBR materials")
	assert(source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Boss surfaces must be opaque")
	# Flat quick builds have no ORM; baked builds must preserve the glTF channels.
	if source.get_texture(BaseMaterial3D.TEXTURE_METALLIC) != null:
		assert(source.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED, "ORM occlusion must be R")
		assert(source.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN, "ORM roughness must be G")
		assert(source.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE, "ORM metallic must be B")
	var material := ShaderMaterial.new()
	material.shader = Surface
	material.resource_name = source.resource_name
	material.set_shader_parameter("albedo_map", source.get_texture(BaseMaterial3D.TEXTURE_ALBEDO))
	material.set_shader_parameter("albedo_color", source.albedo_color)
	material.set_shader_parameter("orm_map", source.get_texture(BaseMaterial3D.TEXTURE_METALLIC))
	material.set_shader_parameter("roughness_factor", source.roughness)
	material.set_shader_parameter("metallic_factor", source.metallic)
	material.set_shader_parameter("normal_map", source.get_texture(BaseMaterial3D.TEXTURE_NORMAL))
	material.set_shader_parameter("normal_scale", source.normal_scale)
	material.set_shader_parameter("has_normal", source.normal_enabled)
	material.set_shader_parameter("emission_map", source.get_texture(BaseMaterial3D.TEXTURE_EMISSION))
	material.set_shader_parameter("emission_color", source.emission)
	material.set_shader_parameter("emission_energy", source.emission_energy_multiplier)
	material.set_shader_parameter("has_emission", source.emission_enabled)
	material.set_shader_parameter("has_emission_map", source.get_texture(BaseMaterial3D.TEXTURE_EMISSION) != null)
	material.set_shader_parameter("chroma_lock", 1.0)
	material.set_shader_parameter("ambient_fill", Color(1.0, 0.972549, 0.913725))
	material.set_shader_parameter("ambient_energy", 0.34)
	material.set_shader_parameter("light_gain", 0.5)
	material.set_shader_parameter("front_fill", 0.0)
	material.set_shader_parameter("dissolve", 0.0)
	material.set_shader_parameter("flash", 0.0)
	material.set_shader_parameter("phase_tint", Color.WHITE)
	return material
