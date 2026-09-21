extends Node3D
## Cosmetic only. Backend owns floor collision, speed, and gameplay state.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Textures = preload("res://scenes/runner/environment/hifi/texture_forge.gd")
const Racks = preload("res://scenes/runner/environment/hifi/rack_module.gd")
var _rack_poses: Array[Transform3D] = []
var _pillar_material: ShaderMaterial
var _racks: MultiMesh
const Atlas = preload("res://scenes/runner/shaders/glyph_atlas.gd")
@export_range(0.25, 1.0, 0.05) var retro_scale := 0.5
# Mirror RunConfig defaults. Keep these fractions and yaw in sync with the backend camera.
const TURN_SWING_IN := 0.3
const TURN_SWING_OUT := 0.3
const TURN_YAW := 55.0
var turn_progress := 0.0
var turn_direction := 0
var bend := 0.0
var phase: StringName = &"idle"
var boss_arena := false
signal turn_applied(progress: float, direction: int)
var _corner: MeshInstance3D
var _turn_chevron: Label3D
var _corner_material: ShaderMaterial
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
var _metal_bend_materials: Array[ShaderMaterial] = []
var _pillar_z := PackedFloat32Array()
var _pillars: MultiMesh
var _rain: GPUParticles3D
var _speed_lines: GPUParticles3D
var _far_material: ShaderMaterial

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ready() -> void:
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
	wall.set_shader_parameter("panel_period", 8.0)
	_scroll_materials.append(wall)
	_plane("WallL", Vector2(6, 100), Vector3(-Racks.SCREEN_X, 3, -40), Vector3(0, 0, -PI / 2), wall)
	_plane("WallR", Vector2(6, 100), Vector3(Racks.SCREEN_X, 3, -40), Vector3(0, 0, PI / 2), wall)
	var lane := _shader(preload("res://scenes/runner/shaders/far_glow.gdshader"))
	lane.set_shader_parameter("color", Color(Palette.MATRIX, 0.12))
	_quad("LaneGlow", Vector2(6, 8), Vector3(0, 0.012, 0), Vector3(-PI / 2, 0, 0), lane)
	_far_material = _shader(preload("res://scenes/runner/shaders/far_glow.gdshader"))
	_quad("FarGlow", Vector2(8, 8), Vector3(0, 3, -88), Vector3.ZERO, _far_material)
	_corner_material = _shader(preload("res://scenes/runner/shaders/code_wall_fade.gdshader"))
	_corner_material.set_shader_parameter("atlas", Atlas.texture())
	_corner_material.set_shader_parameter("horizontal_axis", Vector3.RIGHT)
	_corner_material.set_shader_parameter("intensity", 0.4)
	_quad("CornerWall", Vector2(18, 8), Vector3(0, 3, -30), Vector3.ZERO, _corner_material)
	_corner = get_node("CornerWall") as MeshInstance3D
	var sign := Materials.label(self, "TURN ►", 104, Palette.MINT)
	_turn_chevron = sign
	sign.name = "TurnChevron"
	sign.reparent(_corner, false)
	sign.position = Vector3(0, 0.5, 6.0)
	sign.pixel_size = 0.014
	sign.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_build_pillars()
	_build_racks()
	_rain = Materials.glyph_particles(64, Vector3(3.9, 0.2, 45))
	_rain.name = "Rain"
	_rain.position = Vector3(0, 6.2, -44)
	# Particle AABBs are local to the emitter; global Z coverage is -96..+12.
	_rain.visibility_aabb = AABB(Vector3(-5, -8, -52), Vector3(10, 10, 108))
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
	_clock_materials.append_array([_corner_material, _far_material, _pillar_material, lane])
	_clock_materials.append_array(_metal_bend_materials)
	_frame_materials.assign(_scroll_materials)
	_frame_materials.append(_far_material)
	_configure_cosmetics(self)
	set_scroll_speed(_speed)
	set_pursuit(_pursuit)
	_apply_turn()
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
	material.set_shader_parameter("base_tint", Palette.SLATE)
	material.set_shader_parameter("baked_gain", 0.85)
	material.set_shader_parameter("rim_gain", 0.10)
	material.set_shader_parameter("ceiling_gain", 0.60)
	return material

func _build_racks() -> void:
	var material := _metal()
	material.set_shader_parameter("module_mode", true)
	_metal_bend_materials.append(material)
	_racks = MultiMesh.new()
	_racks.transform_format = MultiMesh.TRANSFORM_3D
	_racks.use_custom_data = true
	_racks.mesh = Racks.mesh()
	_racks.instance_count = 12
	var instance := MultiMeshInstance3D.new()
	instance.name = "ServerRacks"
	instance.multimesh = _racks
	instance.material_override = material
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	instance.process_mode = Node.PROCESS_MODE_PAUSABLE
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 85.0
	add_child(instance)

func pillar_z_positions() -> PackedFloat32Array:
	return _pillar_z.duplicate()

func _update_pillars() -> void:
	_pillar_z.resize(24)
	if _racks != null:
		_rack_poses.resize(12)
		for i in 12:
			var z := 12.0 - fposmod(float(i) * 8.0 - _offset, 96.0)
			var d := maxf(0.0, -z - 6.0)
			var yaw := -atan(2.0 * bend * d)
			var x := bend * d * d
			_rack_poses[i] = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z))
			_racks.set_instance_custom_data(i, Color(z, x, cos(yaw), sin(yaw)))
			_racks.set_instance_transform(i, _rack_poses[i])
	for i in 24:
		var z := 8.0 - fposmod(float(i % 12) * 8.0 - _offset, 96.0)
		_pillar_z[i] = z
		var x := -3.92 if i < 12 else 3.92
		_pillars.set_instance_transform(i, Transform3D(Basis(Vector3.UP, -atan(2.0 * bend * maxf(0.0, -z - 6.0))), Vector3(x + bend * pow(maxf(0.0, -z - 6.0), 2), 3, z)))

func _simple_particles(node_name: String, count: int, size_: Vector2, alpha: float) -> GPUParticles3D:
	var particles := Materials.glyph_particles(count, Vector3(3.8, 2.5, 45))
	particles.name = node_name
	particles.position = Vector3(0, 3, -44)
	particles.visibility_aabb = AABB(Vector3(-5, -4, -52), Vector3(10, 10, 108))
	var quad := QuadMesh.new()
	quad.size = size_
	var material := Materials.additive(Palette.MINT, alpha).duplicate() as StandardMaterial3D
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = material
	particles.draw_pass_1 = quad
	add_child(particles)
	return particles

func set_scroll_speed(speed: float) -> void:
	_speed = maxf(0.0, speed)
	if not is_instance_valid(_rain):
		return
	var rain_process := _rain.process_material as ParticleProcessMaterial
	# Constant +Z drift without changing the falling velocity.
	rain_process.direction = Vector3(0, -1.8, _speed * 0.12).normalized()
	var velocity := Vector2(1.8, _speed * 0.12).length()
	rain_process.initial_velocity_min = velocity * 0.8
	rain_process.initial_velocity_max = velocity * 1.2
	_speed_lines.emitting = clampf((_speed - 12.0) / 12.0, 0.0, 1.0) > 0.6
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
	_apply_turn()
	# 96 is a common period of the 2 m grid, wall glyph seed, and 8 m pillars.
	_offset = fposmod(_offset + _speed * delta, 96.0)
	_clock += delta
	for material in _scroll_materials:
		material.set_shader_parameter("scroll", _offset)
	for material in _clock_materials:
		material.set_shader_parameter("clock", _clock)
	_update_pillars()

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

func set_turn(progress: float, direction: int) -> void:
	turn_progress = clampf(progress, 0.0, 1.0)
	turn_direction = signi(direction)
	turn_applied.emit(turn_progress, turn_direction)

func _apply_turn() -> void:
	var wave := turn_profile(turn_progress) if turn_direction != 0 else 0.0
	bend = float(turn_direction) * 0.010 * wave
	rotation.y = float(turn_direction) * deg_to_rad(TURN_YAW) * wave
	if _far_material == null: return
	for material in _frame_materials:
		material.set_shader_parameter("bend", bend)
		material.set_shader_parameter("bend_frame", global_transform)
	for material in _metal_bend_materials:
		material.set_shader_parameter("bend", bend)
	var sweep := float(turn_direction) * turn_progress * 48.0 if wave > 0.0 else 0.0
	_scroll_materials[2].set_shader_parameter("lateral_scroll", sweep)
	var blend := wave
	_far_material.set_shader_parameter("opacity", 1.0 - blend)
	_corner_material.set_shader_parameter("opacity", blend)
	_corner_material.set_shader_parameter("lateral_scroll", sweep)
	# Panel transform owns the bend once; its child sign inherits the exact pose.
	_corner_material.set_shader_parameter("bend", 0.0)
	_corner.visible = blend > 0.0
	_corner.position.x = bend * 24.0 * 24.0
	_corner.rotation.y = 0.0
	_turn_chevron.visible = blend > 0.0
	_turn_chevron.modulate.a = blend
	_turn_chevron.text = "◄ TURN" if turn_direction < 0 else "TURN ►"
	_turn_chevron.position.x = bend * pow(24.0 - _turn_chevron.position.z, 2) - _corner.position.x
	_turn_chevron.rotation.y = 0.0
	_rain.amount_ratio = lerpf(0.55, 1.0, wave)
	_dust.amount_ratio = 1.0
	_speed_lines.emitting = wave > 0.95 or clampf((_speed - 12.0) / 12.0, 0.0, 1.0) > 0.6
	_speed_lines.speed_scale = 1.0 + wave
	_rain.speed_scale = 1.0 + wave * 1.5

func set_phase(value: StringName) -> void:
	phase = value
	if value != &"turn": set_turn(0.0, 0)

func set_boss_arena(active: bool) -> void:
	boss_arena = active
	if _far_material != null:
		_far_material.set_shader_parameter("arena", 0.45 if active else 1.0)

static func turn_profile(p: float) -> float:
	if p <= 0.0 or p >= 1.0: return 0.0
	if p < TURN_SWING_IN: return smoothstep(0.0, 1.0, p / TURN_SWING_IN)
	if p > 1.0 - TURN_SWING_OUT: return smoothstep(0.0, 1.0, (1.0 - p) / TURN_SWING_OUT)
	return 1.0

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
