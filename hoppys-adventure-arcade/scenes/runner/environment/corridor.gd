extends Node3D
## Cosmetic only. Backend owns floor collision, speed, and gameplay state.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Atlas = preload("res://scenes/runner/shaders/glyph_atlas.gd")
@export_range(0.25, 1.0, 0.05) var retro_scale := 0.5
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
var _pillars: MultiMesh
var _rain: GPUParticles3D
var _speed_lines: GPUParticles3D
var _far_material: ShaderMaterial

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
	key.position = Vector3(0, 3, 1)
	key.light_color = Palette.CREAM
	key.light_energy = 1.6
	key.omni_range = 9.0
	key.shadow_enabled = false
	add_child(key)
	var floor_material := _shader(preload("res://scenes/runner/shaders/floor_grid.gdshader"))
	_scroll_materials.append(floor_material)
	_plane("Floor", Vector2(8, 100), Vector3(0, 0, -40), Vector3.ZERO, floor_material)
	var ceiling := floor_material.duplicate() as ShaderMaterial
	ceiling.set_shader_parameter("intensity", 0.35 * 0.15)
	_scroll_materials.append(ceiling)
	_plane("Ceiling", Vector2(8, 100), Vector3(0, 6, -40), Vector3(PI, 0, 0), ceiling)
	var wall := _shader(preload("res://scenes/runner/shaders/code_wall.gdshader"))
	wall.set_shader_parameter("atlas", Atlas.texture())
	_scroll_materials.append(wall)
	_plane("WallL", Vector2(6, 100), Vector3(-4, 3, -40), Vector3(0, 0, -PI / 2), wall)
	_plane("WallR", Vector2(6, 100), Vector3(4, 3, -40), Vector3(0, 0, PI / 2), wall)
	var lane := _shader(preload("res://scenes/runner/shaders/far_glow.gdshader"))
	lane.set_shader_parameter("color", Color(Palette.MATRIX, 0.12))
	_quad("LaneGlow", Vector2(6, 8), Vector3(0, 0.012, 0), Vector3(-PI / 2, 0, 0), lane)
	_far_material = _shader(preload("res://scenes/runner/shaders/far_glow.gdshader"))
	_quad("FarGlow", Vector2(8, 8), Vector3(0, 3, -88), Vector3.ZERO, _far_material)
	_build_pillars()
	_rain = Materials.glyph_particles(320, Vector3(3.9, 0.2, 45))
	_rain.name = "Rain"
	_rain.position = Vector3(0, 6.2, -44)
	# Particle AABBs are local to the emitter; global Z coverage is -96..+12.
	_rain.visibility_aabb = AABB(Vector3(-5, -8, -52), Vector3(10, 10, 108))
	add_child(_rain)
	_speed_lines = _simple_particles("SpeedLines", 80, Vector2(0.018, 0.75), 0.18)
	_speed_lines.emitting = false
	var dust := _simple_particles("Dust", 60, Vector2(0.035, 0.035), 0.15)
	var dust_process := dust.process_material as ParticleProcessMaterial
	dust_process.direction = Vector3.UP
	dust_process.initial_velocity_min = 0.1
	dust_process.initial_velocity_max = 0.3
	set_scroll_speed(_speed)
	set_pursuit(_pursuit)
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
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _plane(node_name: String, size_: Vector2, position_: Vector3, rotation_: Vector3, material: Material) -> void:
	var plane := PlaneMesh.new()
	plane.size = size_
	_mesh(node_name, plane, position_, rotation_, material)

func _quad(node_name: String, size_: Vector2, position_: Vector3, rotation_: Vector3, material: Material) -> void:
	var quad := QuadMesh.new()
	quad.size = size_
	_mesh(node_name, quad, position_, rotation_, material)

func _build_pillars() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.075, 6, 0.075)
	mesh.material = Materials.glow(Palette.MATRIX.darkened(0.75), 0.3)
	_pillars = MultiMesh.new()
	_pillars.transform_format = MultiMesh.TRANSFORM_3D
	_pillars.mesh = mesh
	_pillars.instance_count = 24
	var instance := MultiMeshInstance3D.new()
	instance.name = "Pillars"
	instance.multimesh = _pillars
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _update_pillars() -> void:
	for i in 24:
		var z := 8.0 - fposmod(float(i % 12) * 8.0 - _offset, 96.0)
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
	# 96 is a common period of the 2 m grid, wall glyph seed, and 8 m pillars.
	_offset = fposmod(_offset + _speed * delta, 96.0)
	_clock += delta
	for material in _scroll_materials:
		material.set_shader_parameter("scroll", _offset)
	_scroll_materials[2].set_shader_parameter("clock", _clock)
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
		var owner: Dictionary = owners[i]
		if owner.id != get_instance_id():
			continue
		if i + 1 < owners.size():
			# Transfer the original baseline when an older corridor exits first.
			var next: Dictionary = owners[i + 1]
			if is_equal_approx(next.previous_scale, owner.applied_scale) and next.previous_mode == Viewport.SCALING_3D_MODE_BILINEAR:
				next.previous_scale = owner.previous_scale
				next.previous_mode = owner.previous_mode
		elif is_equal_approx(_viewport.scaling_3d_scale, owner.applied_scale) and _viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR:
			# Do not overwrite settings applied by a different viewport user.
			_viewport.scaling_3d_scale = owner.previous_scale
			_viewport.scaling_3d_mode = owner.previous_mode
		owners.remove_at(i)
		break
	if owners.is_empty():
		_scaling_owners.erase(viewport_id)
	_scaling_registered = false
