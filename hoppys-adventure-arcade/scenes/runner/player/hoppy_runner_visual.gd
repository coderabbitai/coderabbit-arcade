extends "res://scenes/runner/player/runner_visual_base.gd"
## Imported Blender mascot. Cosmetic transforms never drive player physics.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Glass = preload("res://scenes/runner/player/hifi/hoppy_glass.gdshader")
const Surface = preload("res://scenes/runner/player/hifi/hoppy_surface.gdshader")
const Hologram = preload("res://scenes/runner/player/hifi/energy.gdshader")
const LaneLook = preload("res://scenes/runner/player/hifi/lane_look.gd")
const STATES: Array[StringName] = [&"idle", &"run", &"jump", &"fall", &"roll", &"hurt", &"dead"]
## Grounded, envelope-filling roll re-baked from the Blender clip by dev/bake_hoppy_roll.gd.
const BAKED_ROLL := "res://scenes/runner/player/hifi/hoppy_roll.tres"
## Blend into and out of the roll so Hoppy visibly curls down instead of popping to ball size.
const ROLL_BLEND_IN := 0.07
const ROLL_BLEND_OUT := 0.1
## The bake tool reads the imported clip, so it switches the baked one off.
var use_baked_roll := true
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var anim_state: StringName = &"idle"
var _return_state: StringName = &"idle"
var _speed := 0.0
var _lean := 0.0
var _contact_shadow: MeshInstance3D
var _look: SkeletonModifier3D
var _meshes: Array[MeshInstance3D] = []
var _auras: Dictionary = {}
var _aura: MeshInstance3D
var _aura_material: ShaderMaterial
var _shield: MeshInstance3D
var _shield_requested := false
var _sparks: GPUParticles3D
var _sparkles: GPUParticles3D
var _glyph_material: ShaderMaterial
var _glyph_trail_material: ShaderMaterial
var _glyphs: MultiMeshInstance3D
var _trail: MultiMeshInstance3D
var _flash_remaining := 0.0
var _clock := 0.0

func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ready() -> void:
	var model := get_node("Root/Model")
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	animation_player = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	# Keep the public player path while preserving imported track paths relative to Model.
	animation_player.reparent(self)
	animation_player.root_node = NodePath("../Root/Model")
	var library := AnimationLibrary.new()
	for state in STATES:
		var clip := animation_player.get_animation(state).duplicate(true) as Animation
		if state == &"roll" and use_baked_roll and ResourceLoader.exists(BAKED_ROLL):
			clip = (load(BAKED_ROLL) as Animation).duplicate(true)
		clip.loop_mode = Animation.LOOP_LINEAR if state in [&"idle", &"run", &"fall"] else Animation.LOOP_NONE
		if state == &"hurt":
			var track := clip.add_track(Animation.TYPE_METHOD)
			clip.track_set_path(track, NodePath("../.."))
			for time in [0.001, 0.12, 0.24]:
				clip.track_insert_key(track, time, {"method": &"flash", "args": []})
		library.add_animation(state, clip)
	for key in animation_player.get_animation_library_list():
		animation_player.remove_animation_library(key)
	animation_player.add_animation_library(&"", library)
	animation_player.playback_default_blend_time = 0.08
	animation_player.animation_finished.connect(_animation_finished)
	# Materials are shared by the imported PackedScene; only private duplicates mutate.
	var copies: Dictionary = {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		_meshes.append(mesh)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for index in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(index)
			if not copies.has(source):
				copies[source] = _surface_material(source as BaseMaterial3D)
			mesh.set_surface_override_material(index, copies[source])
	_look = LaneLook.new()
	_look.name = "LaneLook"
	skeleton.add_child(_look)
	_build_contact_shadow()
	_build_effects()
	_configure_cosmetics(self)
	animation_player.play(anim_state, 0.0)
	animation_player.advance(0.0)
	set_lane_lean(_lean)
	set_run_speed(_speed)
	_update_aura()
	show_shield(_shield_requested)
	_process(0.0)

func _build_contact_shadow() -> void:
	_contact_shadow = MeshInstance3D.new()
	_contact_shadow.name = "ContactShadow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.90,0.75)
	_contact_shadow.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://scenes/runner/player/hifi/contact_shadow.gdshader")
	_contact_shadow.material_override = material
	_contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_contact_shadow)

func _surface_material(source: BaseMaterial3D) -> ShaderMaterial:
	assert(source != null, "Hoppy expects imported PBR materials")
	assert(source.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED, "ORM occlusion must be R")
	assert(source.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN, "ORM roughness must be G")
	assert(source.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE, "ORM metallic must be B")
	var material := ShaderMaterial.new()
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		# Godot imports this GLB's BLEND lens as alpha with a depth prepass.
		assert(source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS, "Hoppy glass requires alpha depth prepass; scissor/hash are unsupported")
		# Explicit back-culled glass variant requested by the round-12 art review.
		material.shader = Glass
	else:
		assert(source.albedo_color.a == 1.0, "Opaque Hoppy imports must have full albedo alpha")
		material.shader = Surface
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
	material.set_shader_parameter("ambient_fill", Palette.CREAM)
	material.set_shader_parameter("ambient_energy", 0.34)
	material.set_shader_parameter("light_gain", 0.5)
	material.set_shader_parameter("flash", 0.0)
	return material

func _configure_cosmetics(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for child in node.get_children():
		_configure_cosmetics(child)

func _shell(parent: Node3D, id: String, radius: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = id
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	node.mesh = sphere
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _build_effects() -> void:
	_aura_material = ShaderMaterial.new()
	_aura_material.shader = Hologram
	_aura_material.set_shader_parameter("sphere_radius", 0.9)
	_aura = _shell(get_node("Root"), "Aura", 0.9, _aura_material)
	var shield_material := _aura_material.duplicate() as ShaderMaterial
	shield_material.set_shader_parameter("sphere_radius", 0.88)
	shield_material.set_shader_parameter("mode", 1.0)
	_shield = _shell(self, "ShieldRing", 0.88, shield_material)
	_sparks = _particles("HitSparks", 20, true)
	_sparkles = _particles("AuraSparkles", 24, false)
	_glyph_material = ShaderMaterial.new()
	_glyph_material.shader = Hologram
	_glyph_material.set_shader_parameter("mode", 2.0)
	_glyph_material.set_shader_parameter("color", Palette.MINT)
	_glyph_trail_material = _glyph_material.duplicate()
	_glyph_trail_material.set_shader_parameter("color", Palette.MATRIX)
	_glyphs = _repeat("OrbitGlyphs", 12, _glyph_material)
	_trail = _repeat("DataTrail", 16, _glyph_trail_material)

func set_anim_state(state: StringName) -> void:
	if state not in STATES or state == anim_state:
		return
	if state == &"hurt":
		_return_state = anim_state if anim_state in [&"idle", &"run", &"jump", &"fall", &"roll"] else &"run"
	var leaving_roll := anim_state == &"roll"
	anim_state = state
	if animation_player != null:
		var blend := 0.08
		if state == &"roll":
			blend = ROLL_BLEND_IN
		elif leaving_roll:
			blend = ROLL_BLEND_OUT
		animation_player.play(state, blend)
		set_run_speed(_speed)
		animation_player.advance(0.0)
		_process(0.0)

func set_run_speed(normalized: float) -> void:
	_speed = clampf(normalized, 0.0, 1.0)
	if animation_player != null:
		animation_player.speed_scale = lerpf(0.9, 1.6, _speed) if anim_state == &"run" else 1.0

func set_lane_lean(direction: float) -> void:
	_lean = clampf(direction, -1.0, 1.0)
	rotation.z = -_lean * 0.12
	if _look != null:
		_look.set("direction", _lean)

func _animation_finished(state: StringName) -> void:
	# Locomotion transitions are backend-owned. One-shots hold their final pose;
	# only hurt automatically restores the last requested locomotion state.
	if state == &"hurt" and anim_state == &"hurt":
		set_anim_state(_return_state)

func on_hit() -> void:
	flash()
	if _sparks != null:
		_sparks.restart()

func flash() -> void:
	_flash_remaining = 0.06
	# Flash private uniforms without a full-character overlay draw pass.
	for mesh in _meshes:
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(i) as ShaderMaterial
			material.set_shader_parameter("flash", 1.0)

func _bone_point(bone_name: String, rest_point: Vector3) -> Vector3:
	var bone := skeleton.find_bone(bone_name)
	var pose := skeleton.get_bone_global_pose(bone) * skeleton.get_bone_global_rest(bone).affine_inverse()
	return to_local(skeleton.to_global(pose * rest_point))

func _process(delta: float) -> void:
	if is_instance_valid(_contact_shadow):
		var height := maxf(global_position.y,0.0)
		_contact_shadow.global_transform = Transform3D(Basis.from_scale(Vector3(1.0+height*0.2,1,1.0+height*0.2)),Vector3(global_position.x,0.016,global_position.z))
		_contact_shadow.material_override.set_shader_parameter("height",height)
	_clock += delta
	var rolling := anim_state == &"roll"
	var center := Vector3(0, 0.45, 0) if rolling else _bone_point("chest", Vector3(0, 0.9, 0))
	for shell in [_aura, _shield]:
		shell.position = center
		shell.scale = Vector3.ONE * (0.48 if rolling else 1.0)
		var material := shell.material_override as ShaderMaterial
		material.set_shader_parameter("clock", _clock)
		material.set_shader_parameter("hex_cell_size", 0.09 / shell.global_basis.x.length())
	_sparks.position = center
	_sparkles.position = center
	_glyph_material.set_shader_parameter("clock", _clock)
	_glyph_trail_material.set_shader_parameter("clock", _clock)
	_glyphs.visible = _aura.visible
	_trail.visible = _speed > 0.4 and anim_state == &"run"
	for i in 12:
		var a := _clock * 1.5 + i * TAU / 12.0
		var r := 0.38 if rolling else 0.65
		_instance(_glyphs, i, Transform3D(_billboard_basis(_glyphs), center + Vector3(cos(a) * r, sin(a * 2.0) * 0.08, sin(a) * r)))
	var emitter := _bone_point("chest", Vector3(0, 1.09, 0.26))
	for i in 16:
		var t := fmod(_clock * 0.8 + float(i) / 16.0, 1.0)
		_instance(_trail, i, Transform3D(_billboard_basis(_trail).scaled(Vector3.ONE * (1.0 - t)), emitter + Vector3(sin(i * 8.0) * 0.10 * t, t * 0.12, t * 0.9)))
	if _flash_remaining > 0.0:
		_flash_remaining -= delta
		if _flash_remaining <= 0.0:
			for mesh in _meshes:
				for i in mesh.mesh.get_surface_count():
					var material := mesh.get_surface_override_material(i) as ShaderMaterial
					material.set_shader_parameter("flash", 0.0)

func _particles(id: String, count: int, one_shot: bool) -> GPUParticles3D:
	var node := GPUParticles3D.new()
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.name = id
	node.position.y = 0.8
	node.amount = count
	node.lifetime = 0.4 if one_shot else 1.2
	node.one_shot = one_shot
	node.explosiveness = 1.0 if one_shot else 0.0
	node.emitting = false
	node.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 2.0 if one_shot else 0.8
	process.gravity = Vector3.ZERO
	node.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.025, 0.04)
	mesh.material = Materials.glow(Palette.CREAM)
	node.draw_pass_1 = mesh
	add_child(node)
	return node

func show_aura(kind: StringName, on: bool) -> void:
	if kind not in [&"lgtm", &"nitro", &"code_review"]:
		return
	if on:
		_auras[kind] = true
	else:
		_auras.erase(kind)
	if _aura != null:
		_update_aura()

func _update_aura() -> void:
	_aura.visible = not _auras.is_empty()
	_sparkles.emitting = _aura.visible
	var color := Palette.MATRIX
	color.a = 0.12
	if _auras.has(&"nitro"):
		color = Palette.ORANGE
		color.a = 0.4
	if _auras.has(&"lgtm"):
		color = Palette.MINT
		color.a = 0.55
	_aura_material.set_shader_parameter("color", color)

func show_shield(on: bool) -> void:
	_shield_requested = on
	if _shield != null:
		_shield.visible = on

func _repeat(id: String, count: int, material: Material) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = id
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.055)
	node.multimesh.mesh = quad
	node.multimesh.instance_count = count
	node.material_override = material
	add_child(node)
	return node

func _instance(node: MultiMeshInstance3D, index: int, pose: Transform3D) -> void:
	# Dummy headless renderer does not retain instance transforms for readback.
	var poses: Dictionary = node.get_meta("poses", {})
	poses[index] = pose
	node.set_meta("poses", poses)
	node.multimesh.set_instance_transform(index, pose)

func _billboard_basis(node: Node3D) -> Basis:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Basis.IDENTITY
	return node.global_basis.inverse() * camera.global_basis.orthonormalized()
