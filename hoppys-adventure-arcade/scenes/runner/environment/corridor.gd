extends Node3D
## Cosmetic only. Backend owns floor collision, speed, and gameplay state.
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
static var _warmed := false
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Textures = preload("res://scenes/runner/environment/hifi/texture_forge.gd")
const Racks = preload("res://scenes/runner/environment/hifi/rack_module.gd")
var _rack_poses: Array[Transform3D] = []
var _rack_data: Array[Color] = []
var _pillar_material: ShaderMaterial
var _rack_batches: Array[MultiMesh] = []
var _racks: MultiMesh
const Atlas = preload("res://scenes/runner/environment/hifi/wall_atlas.gd")
@export_range(0.25, 1.0, 0.05) var retro_scale := 0.5
var phase: StringName = &"idle"
var boss_arena := false
var _dust: GPUParticles3D
var _speed := 0.0
var _offset := 0.0
var _clock := 0.0
var _pursuit := 0.0
var _viewport: Viewport
static var _scaling_owners: Dictionary = {}
var _scaling_registered := false
var _environment: Environment
var _sun: DirectionalLight3D
var _scroll_materials: Array[ShaderMaterial] = []
var _clock_materials: Array[ShaderMaterial] = []
var _frame_materials: Array[ShaderMaterial] = []
var _rack_materials: Array[ShaderMaterial] = []
var _pillar_z := PackedFloat32Array()
var _pillars: MultiMesh
var _rain: GPUParticles3D
var _speed_lines: GPUParticles3D
var _far_material: ShaderMaterial
## The spawner of the bound run, if any. While one is bound the scroll is read off the same physics
## ticks that move the chunks, so floor markers and hazards can never swim against each other.
var _spawner: Node = null
## The corridor frame last written to the frame-space shaders. The corridor never turns, so it only
## changes when a fixture moves the node; until then nothing is re-uploaded.
var _dressing_frame := Transform3D()
var _dressing_frame_written := false
## Speed the particle process materials were last written for; -1 forces the first write.
var _particle_speed := -1.0
## Rain drift and streak velocity only need to track the speed to a few cm/s.
const PARTICLE_SPEED_STEP := 0.05

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ready() -> void:
	if not Engine.is_editor_hint() and not _warmed:
		Prewarm.warm()
		_warmed = true
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_viewport = get_viewport()
	_apply_retro_scale()
	var env := WorldEnvironment.new()
	env.name = "Env"
	_environment = Materials.environment()
	env.environment = _environment
	add_child(env)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_color = Palette.MATRIX
	_sun.light_energy = 0.35
	_sun.rotation_degrees = Vector3(-50, -25, 0)
	_sun.shadow_enabled = false
	add_child(_sun)
	var key := OmniLight3D.new()
	key.name = "KeyLight"
	key.position = Vector3(0, 1.8, 1)
	key.light_color = Palette.MINT
	key.light_energy = 0.65
	key.omni_range = 3.2
	key.shadow_enabled = false
	add_child(key)
	var floor_material := _shader(preload("res://scenes/runner/shaders/floor_grid.gdshader"))
	floor_material.set_shader_parameter("grid_strength", 0.45)
	floor_material.set_shader_parameter("floor_metallic", 0.28)
	floor_material.set_shader_parameter("base_tint", Palette.SLATE)
	floor_material.set_shader_parameter("baked_gain", 0.255)
	floor_material.set_shader_parameter("plate_normal_depth", 0.9)
	floor_material.set_shader_parameter("plate_rivet_radius", 0.085)
	for map_key in Textures.floor_maps():
		floor_material.set_shader_parameter(map_key, Textures.floor_maps()[map_key])
	_scroll_materials.append(floor_material)
	_plane("Floor", Vector2(8, 100), Vector3(0, 0, -40), Vector3.ZERO, floor_material)
	var ceiling := floor_material.duplicate() as ShaderMaterial
	ceiling.set_shader_parameter("baked_gain", 0.36)
	ceiling.set_shader_parameter("intensity", 0.14)
	_scroll_materials.append(ceiling)
	_plane("Ceiling", Vector2(8, 100), Vector3(0, 6.6, -40), Vector3(PI, 0, 0), ceiling)
	var wall := _shader(preload("res://scenes/runner/shaders/code_wall.gdshader"))
	wall.set_shader_parameter("atlas", Atlas.texture())
	wall.set_shader_parameter("wall_atlas", Atlas.texture())
	wall.set_shader_parameter("panel_period", 8.0)
	_scroll_materials.append(wall)
	_plane("WallL", Vector2(6, 100), Vector3(-Racks.SCREEN_X, 3, -40), Vector3(0, 0, -PI / 2), wall)
	_plane("WallR", Vector2(6, 100), Vector3(Racks.SCREEN_X, 3, -40), Vector3(0, 0, PI / 2), wall)
	var lane := _shader(preload("res://scenes/runner/shaders/far_glow.gdshader"))
	lane.set_shader_parameter("color", Color(Palette.MATRIX, 0.12))
	_quad("LaneGlow", Vector2(6, 8), Vector3(0, 0.012, 0), Vector3(-PI / 2, 0, 0), lane)
	_far_material = _shader(preload("res://scenes/runner/shaders/far_glow.gdshader"))
	_quad("FarGlow", Vector2(8, 8), Vector3(0, 3, -88), Vector3.ZERO, _far_material)
	_build_pillars()
	_build_racks()
	_rain = Materials.glyph_particles(64, Vector3(3.9, 0.2, 45))
	(_rain.draw_pass_1.material as StandardMaterial3D).albedo_texture = Atlas.texture()
	_rain.name = "Rain"
	_rain.position = Vector3(0, 6.2, -44)
	# Particle AABBs are local to the emitter; global Z coverage is -96..+12.
	_rain.visibility_aabb = AABB(Vector3(-5, -8, -52), Vector3(10, 10, 108))
	_rain.amount_ratio = 0.55
	add_child(_rain)
	_speed_lines = _simple_particles("SpeedLines", 64, Vector2(0.018, 0.75), 0.18)
	_speed_lines.emitting = false
	var dust := _simple_particles("Dust", 60, Vector2(0.035, 0.035), 0.15)
	_dust = dust
	var dust_process := dust.process_material as ParticleProcessMaterial
	dust_process.direction = Vector3.UP
	dust_process.initial_velocity_min = 0.1
	dust_process.initial_velocity_max = 0.3
	# Persistent capability lists avoid temporary arrays and dead uniform sets per frame.
	_clock_materials.assign(_scroll_materials)
	_clock_materials.append_array([_far_material, _pillar_material, lane])
	_clock_materials.append_array(_rack_materials)
	_frame_materials.assign(_scroll_materials)
	_frame_materials.append(_far_material)
	_configure_cosmetics(self)
	set_scroll_speed(_speed)
	set_pursuit(_pursuit)
	_refresh_dressing()
	_update_pillars()

func _shader(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _mesh(node_name: String, mesh: Mesh, position_: Vector3, rotation_: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position_
	instance.rotation = rotation_
	instance.extra_cull_margin = 40.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _plane(node_name: String, size_: Vector2, position_: Vector3, rotation_: Vector3, material: Material) -> void:
	var plane := PlaneMesh.new()
	plane.size = size_
	plane.subdivide_depth = 72
	_mesh(node_name, plane, position_, rotation_, material)

func _quad(node_name: String, size_: Vector2, position_: Vector3, rotation_: Vector3, material: Material) -> void:
	var quad := QuadMesh.new()
	quad.size = size_
	_mesh(node_name, quad, position_, rotation_, material)

func _build_pillars() -> void:
	var mesh := Racks.pillar()
	_pillar_material = _metal()
	mesh.surface_set_material(0, _pillar_material)
	_pillars = MultiMesh.new()
	_pillars.transform_format = MultiMesh.TRANSFORM_3D
	_pillars.mesh = mesh
	_pillars.instance_count = 24
	var instance := MultiMeshInstance3D.new()
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	instance.name = "Pillars"
	instance.multimesh = _pillars
	instance.extra_cull_margin = 40.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _metal() -> ShaderMaterial:
	var material := _shader(preload("res://scenes/runner/environment/hifi/rack_metal.gdshader"))
	for key in Textures.maps(): material.set_shader_parameter(key, Textures.maps()[key])
	material.set_shader_parameter("frame_metallic", 0.28)
	material.set_shader_parameter("atlas", Atlas.texture())
	material.set_shader_parameter("base_tint", Palette.SLATE)
	material.set_shader_parameter("baked_gain", 0.85)
	material.set_shader_parameter("rim_gain", 0.10)
	material.set_shader_parameter("ceiling_gain", 0.60)
	return material

func _build_racks() -> void:
	var material := _metal()
	material.set_shader_parameter("module_mode", true)
	_rack_materials.append(material)
	for batch_index in Racks.BATCH_COUNT:
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_custom_data = true
		batch.mesh = Racks.batch_mesh(batch_index)
		batch.instance_count = 0
		for variant in Racks.PATTERN:
			if Racks.BATCH_FOR_VARIANT[variant] == batch_index: batch.instance_count += 1
		_rack_batches.append(batch)
		var instance := MultiMeshInstance3D.new()
		instance.name = "ServerRacks" if batch_index == 0 else "ServerRacks%d" % batch_index
		instance.multimesh = batch
		instance.material_override = material
		instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		instance.process_mode = Node.PROCESS_MODE_PAUSABLE
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = 85.0
		add_child(instance)
	_racks = _rack_batches[0]

func pillar_z_positions() -> PackedFloat32Array:
	return _pillar_z.duplicate()

func _update_pillars() -> void:
	_pillar_z.resize(24)
	if _racks != null:
		_rack_poses.resize(12)
		_rack_data.resize(12)
		var slots := [0, 0, 0]
		for i in 12:
			var z := 12.0 - fposmod(float(i) * 8.0 - _offset, 96.0)
			_rack_poses[i] = Transform3D(Basis.IDENTITY, Vector3(0, 0, z))
			var variant: int = Racks.PATTERN[i]
			var batch_index: int = Racks.BATCH_FOR_VARIANT[variant]
			var batch := _rack_batches[batch_index]
			# Custom data is (z, x offset, cos yaw, tag); the corridor is straight, so x is 0 and cos 1.
			_rack_data[i] = Color(z, 0.0, 1.0, Racks.instance_tag(i))
			batch.set_instance_custom_data(slots[batch_index], _rack_data[i])
			batch.set_instance_transform(slots[batch_index], _rack_poses[i])
			slots[batch_index] += 1
	for i in 24:
		var z := 8.0 - fposmod(float(i % 12) * 8.0 - _offset, 96.0)
		_pillar_z[i] = z
		var x := -3.92 if i < 12 else 3.92
		_pillars.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, 3, z)))

func _simple_particles(node_name: String, count: int, size_: Vector2, alpha: float) -> GPUParticles3D:
	var particles := Materials.glyph_particles(count, Vector3(3.8, 2.5, 45))
	particles.name = node_name
	particles.position = Vector3(0, 3, -44)
	particles.visibility_aabb = AABB(Vector3(-5, -4, -52), Vector3(10, 10, 108))
	var quad := QuadMesh.new()
	quad.size = size_
	var material := Materials.additive(Palette.MINT, alpha).duplicate() as StandardMaterial3D
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if node_name == "SpeedLines":
		var screen_safe := _shader(preload("res://scenes/runner/environment/hifi/speed_lines.gdshader"))
		quad.material = screen_safe
	else:
		quad.material = material
	particles.draw_pass_1 = quad
	add_child(particles)
	return particles

## Contract §3 mount hook. Only the spawner's scroll accumulators are read, never written.
func bind(runner: Node) -> void:
	_spawner = runner.get(&"spawner") as Node if runner != null else null
	if _spawner != null and not (&"scroll_travel" in _spawner):
		_spawner = null

func set_scroll_speed(speed: float) -> void:
	_speed = maxf(0.0, speed)
	if not is_instance_valid(_rain):
		return
	# Rewriting both process materials on every physics tick only re-uploads their uniforms.
	if absf(_speed - _particle_speed) < PARTICLE_SPEED_STEP and not (_speed == 0.0 and _particle_speed != 0.0):
		return
	_particle_speed = _speed
	var rain_process := _rain.process_material as ParticleProcessMaterial
	# Constant +Z drift without changing the falling velocity.
	rain_process.direction = Vector3(0, -1.8, _speed * 0.12).normalized()
	var velocity := Vector2(1.8, _speed * 0.12).length()
	rain_process.initial_velocity_min = velocity * 0.8
	rain_process.initial_velocity_max = velocity * 1.2
	# Emission is decided in _refresh_dressing() alone; a second writer here made the streaks sputter.
	var lines_process := _speed_lines.process_material as ParticleProcessMaterial
	lines_process.direction = Vector3.BACK
	lines_process.initial_velocity_min = _speed * 0.7
	lines_process.initial_velocity_max = _speed

func set_pursuit(t: float) -> void:
	_pursuit = clampf(t, 0.0, 1.0)
	if _environment == null:
		return
	_environment.fog_light_color = Palette.NAVY_BG.lerp(Palette.DANGER.darkened(0.85), _pursuit * 0.65)
	_sun.light_color = Palette.MATRIX.lerp(Palette.DANGER, _pursuit * 0.8)
	_far_material.set_shader_parameter("color", Color(Palette.MATRIX.lerp(Palette.DANGER, _pursuit), 0.3))

func _process(delta: float) -> void:
	_refresh_dressing()
	# 96 is a common period of the 2 m grid, wall glyph seed, and 8 m pillars.
	var travel := _bound_travel()
	_offset = fposmod(travel if not is_nan(travel) else _offset + _speed * delta, 96.0)
	_clock += delta
	for material in _scroll_materials:
		material.set_shader_parameter("scroll", _offset)
	for material in _clock_materials:
		material.set_shader_parameter("clock", _clock)
	_update_pillars()

## Metres the bound spawner has scrolled the chunks, at the point between its last two physics ticks
## that this frame renders, which is where the interpolated chunk transforms are drawn. NAN when no
## run is bound (menu, fixtures): the corridor then keeps its own render-delta clock.
func _bound_travel() -> float:
	if _spawner == null or not is_instance_valid(_spawner):
		return NAN
	var current := float(_spawner.scroll_travel)
	if not _interpolating():
		return current
	return lerpf(float(_spawner.scroll_travel_previous), current, Engine.get_physics_interpolation_fraction())

func _interpolating() -> bool:
	return is_inside_tree() and get_tree().physics_interpolation

func _apply_retro_scale() -> void:
	var viewport_id := _viewport.get_instance_id()
	if not _scaling_owners.has(viewport_id):
		_scaling_owners[viewport_id] = []
	var owners: Array = _scaling_owners[viewport_id]
	owners.append({
		"id": get_instance_id(),
		"previous_scale": _viewport.scaling_3d_scale,
		"previous_mode": _viewport.scaling_3d_mode,
		"applied_scale": retro_scale,
	})
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_viewport.scaling_3d_scale = retro_scale
	_scaling_registered = true

func _exit_tree() -> void:
	if not _scaling_registered or not is_instance_valid(_viewport):
		return
	var viewport_id := _viewport.get_instance_id()
	var owners: Array = _scaling_owners[viewport_id]
	for i in owners.size():
		var entry: Dictionary = owners[i]
		if entry.id != get_instance_id():
			continue
		if i + 1 < owners.size():
			# Transfer the original baseline when an older corridor exits first.
			var next: Dictionary = owners[i + 1]
			if is_equal_approx(next.previous_scale, entry.applied_scale) and next.previous_mode == Viewport.SCALING_3D_MODE_BILINEAR:
				next.previous_scale = entry.previous_scale
				next.previous_mode = entry.previous_mode
		elif is_equal_approx(_viewport.scaling_3d_scale, entry.applied_scale) and _viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR:
			# Do not overwrite settings applied by a different viewport user.
			_viewport.scaling_3d_scale = entry.previous_scale
			_viewport.scaling_3d_mode = entry.previous_mode
		owners.remove_at(i)
		break
	if owners.is_empty():
		_scaling_owners.erase(viewport_id)
	_scaling_registered = false

## Per-frame dressing: the corridor frame the frame-space shaders read (written only when the node
## has moved), and the speed-line emission.
func _refresh_dressing() -> void:
	if _far_material == null: return
	if not _dressing_frame_written or global_transform != _dressing_frame:
		_dressing_frame = global_transform
		_dressing_frame_written = true
		for material in _frame_materials:
			material.set_shader_parameter("bend_frame", _dressing_frame)
		_speed_lines.draw_pass_1.material.set_shader_parameter("corridor_frame", _dressing_frame)
	# Single writer for emission, and only on a change: a hidden emitter (the starship corridor hides
	# the legacy streaks) is never switched on just to be switched off again in the same frame.
	var streaks := _speed_lines.visible and clampf((_speed - 12.0) / 12.0, 0.0, 1.0) > 0.6
	if _speed_lines.emitting != streaks:
		_speed_lines.emitting = streaks

func set_phase(value: StringName) -> void:
	phase = value

func set_boss_arena(active: bool) -> void:
	boss_arena = active
	if _far_material != null:
		_far_material.set_shader_parameter("arena", 0.45 if active else 1.0)

func _configure_cosmetics(node: Node) -> void:
	for child in node.get_children():
		child.process_mode = Node.PROCESS_MODE_PAUSABLE
		child.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		if child is GPUParticles3D:
			var mesh: Mesh = child.draw_pass_1
			if mesh.material is StandardMaterial3D:
				var material := mesh.material.duplicate() as StandardMaterial3D
				material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
				material.distance_fade_min_distance = 88.0
				material.distance_fade_max_distance = 55.0
				mesh.material = material
		_configure_cosmetics(child)
