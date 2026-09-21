extends "res://scenes/runner/pursuer/pursuer_visual_base.gd"
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Forge = preload("res://scenes/runner/pursuer/hifi/forge.gd")
const Plating = preload("res://scenes/runner/pursuer/hifi/plating.gdshader")
const Shock = preload("res://scenes/runner/pursuer/hifi/shockwave.gdshader")
const Exhaust = preload("res://scenes/runner/pursuer/hifi/exhaust.gdshader")
const HEADLINES := ["PR #3312 UNREVIEWED", "CHANGES REQUESTED", "STALE", "NEEDS REBASE", "DO NOT MERGE", "0 approvals"]
var _shockwave: MeshInstance3D
var _shockwave_material: ShaderMaterial
var _metal: ShaderMaterial
var _lens: ShaderMaterial
var _exhaust: ShaderMaterial
var _shockwave_time := 0.0
var _wall: MultiMeshInstance3D
var _cards: Array[Transform3D] = []
var _labels: Array[Label3D] = []
var _light: OmniLight3D
var _glitch: GPUParticles3D
var _threat := 0.0
var _t := 0.0
var _reaction := &"idle"
var _reaction_time := 0.0
var _retreated := true
var _start_pose := Transform3D.IDENTITY
var _last_threat_pose := Transform3D.IDENTITY

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ready() -> void:
	_build()
	_apply()

func _build() -> void:
	if _wall != null: return
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_wall = MultiMeshInstance3D.new()
	_wall.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_wall.name = "Wall"
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cards := MultiMesh.new()
	cards.transform_format = MultiMesh.TRANSFORM_3D
	var card := Forge.bevel_box(Vector3(0.98, 0.43, 0.22), 0.035)
	_metal = ShaderMaterial.new()
	_metal.shader = Plating
	_metal.set_shader_parameter("diff_marks", Forge.diff_marks())
	var maps := Forge.maps()
	_metal.set_shader_parameter("plating", maps[0])
	_metal.set_shader_parameter("normals", maps[1])
	_metal.set_shader_parameter("roughness_map", maps[2])
	card.surface_set_material(0, _metal)
	_lens = _metal.duplicate() as ShaderMaterial
	_lens.set_shader_parameter("lens", 1.0)
	cards.mesh = card
	cards.instance_count = 20
	for row in 4:
		for column in 5:
			var pose := Transform3D(Basis(Vector3.FORWARD, sin(float(row * 5 + column)) * 0.035), Vector3((column - 2) * 1.04, 0.3 + row * 0.49, 0.05 + 0.09 * sin(float(row * 5 + column))))
			# A common mounting depth seats both lenses across the top-center cards.
			if row == 3 and column >= 1 and column <= 3: pose.origin.z = 0.04
			_cards.append(pose)
			cards.set_instance_transform(row * 5 + column, pose)
	_wall.multimesh = cards
	add_child(_wall)
	_shockwave = MeshInstance3D.new()
	_shockwave.name = "Shockwave"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.72
	torus.outer_radius = 2.6 / 3.4
	torus.rings = 64
	torus.ring_segments = 24
	_shockwave.mesh = torus
	_shockwave.position = Vector3(0, 1.2, 0.72)
	_shockwave.rotation.x = PI / 2
	_shockwave_material = ShaderMaterial.new()
	_shockwave_material.shader = Shock
	_shockwave.material_override = _shockwave_material
	_shockwave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.add_child(_shockwave)
	var backing_positions: Array[Vector3] = []
	for i in HEADLINES.size():
		var label := Materials.label(_wall, HEADLINES[i], 28, Palette.CREAM)
		label.name = "Headline%d" % i
		label.pixel_size = 0.011
		label.outline_size = 0
		# Fit each headline into its half of the wall without reducing glyph height.
		label.scale.x = 0.65
		label.position = Vector3(-1.25 if i % 2 == 0 else 1.25, 0.48 + (i / 2) * 0.51, 0.38)
		if i == HEADLINES.find("CHANGES REQUESTED"): label.modulate = Palette.DANGER
		_labels.append(label)
		backing_positions.append(label.position)
	var backing := MeshInstance3D.new()
	backing.name = "HeadlineBackings"
	backing.mesh = Forge.headline_backings(backing_positions)
	var neutral := _metal.duplicate() as ShaderMaterial
	neutral.set_shader_parameter("glyph_enabled", 0.0)
	backing.material_override = neutral
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.add_child(backing)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.name = "EyeL" if side < 0 else "EyeR"
		var slit := Forge.bevel_box(Vector3(0.78, 0.095, 0.09), 0.018)
		eye.mesh = slit
		eye.material_override = _lens
		eye.position = Vector3(side * 0.48, 1.80, 0.18)
		eye.rotation.z = side * 0.19
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wall.add_child(eye)
	_light = OmniLight3D.new()
	_light.name = "RedLight"
	_light.light_color = Palette.DANGER
	_light.omni_range = 6.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.2, 0.6)
	add_child(_light)
	_glitch = GPUParticles3D.new()
	_glitch.amount = 48
	_glitch.name = "Glitch"
	_glitch.position = Vector3(0, 1.1, 0.48)
	_glitch.lifetime = 0.6
	_glitch.preprocess = 0.6
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(2.1, 0.48, 0.02)
	process.direction = Vector3(0, 0, 1)
	process.spread = 5.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 1.6
	process.scale_min = 0.6
	process.scale_max = 1.0
	_glitch.process_material = process
	var streak := QuadMesh.new()
	streak.size = Vector2(0.075, 0.22)
	_exhaust = ShaderMaterial.new()
	_exhaust.shader = Exhaust
	streak.material = _exhaust
	_glitch.draw_pass_1 = streak
	_glitch.visibility_aabb = AABB(Vector3(-2.3, -0.7, -0.05), Vector3(4.6, 1.4, 1.15))
	_wall.add_child(_glitch)
	var cables := MeshInstance3D.new()
	cables.name = "CableTendrils"
	cables.mesh = Forge.cables()
	cables.material_override = neutral
	cables.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.add_child(cables)
	_configure_cosmetics(self)

func _configure_cosmetics(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for child in node.get_children(): _configure_cosmetics(child)

func set_threat(t: float) -> void:
	_build()
	_threat = clampf(t, 0.0, 1.0)
	# The backend calls this every pursuit tick. Do not restart a reaction.
	if _reaction != &"idle":
		if (_reaction == &"catch" and (_threat <= 0.001 or _reaction_time >= 1.4)) or (_threat > 0.001 and (_reaction == &"retreat" or _retreated)):
			_reaction = &"idle"
			_retreated = _threat <= 0.001
		else:
			return
	if _threat > 0.001: _retreated = false
	_apply()

func play_catch() -> void:
	_build()
	if _reaction == &"catch": return
	show()
	_shockwave_time = 0.0
	_retreated = false
	_shockwave.show()
	_reaction = &"catch"
	_reaction_time = 0.0
	_start_pose = _wall.transform
	for label in _labels: label.text = "CAUGHT"
	_light.light_energy = 6.0

func play_retreat() -> void:
	_build()
	if _reaction == &"retreat": return
	show()
	_shockwave.hide()
	_reaction = &"retreat"
	_reaction_time = 0.0
	_start_pose = _last_threat_pose
	_wall.transform = _start_pose
	_light.light_energy = 0.0

func _process(delta: float) -> void:
	_t += delta
	if _wall == null: return
	_shockwave_time += delta
	var pulse_duration := lerpf(1.6, 0.45, _threat)
	if _reaction == &"catch":
		pulse_duration = 0.35 / 3.0
	_shockwave.visible = _reaction != &"retreat" and not _retreated and (_reaction != &"catch" or _shockwave_time < 0.35)
	var pulse := fposmod(_shockwave_time, pulse_duration) / pulse_duration
	_shockwave.scale = Vector3.ONE * lerpf(1.0, 3.4, pulse)
	_shockwave_material.set_shader_parameter("opacity", 0.5 * (1 - pulse))
	_shockwave_material.set_shader_parameter("clock", _t)
	_exhaust.set_shader_parameter("clock", _t)
	for material in [_metal, _lens]:
		material.set_shader_parameter("clock", _t)
		material.set_shader_parameter("threat", _threat)
		material.set_shader_parameter("flash", maxf(0.0, 1.0 - _reaction_time / 0.35) if _reaction == &"catch" else 0.0)
	if _reaction == &"idle":
		_apply()
		return
	_reaction_time += delta
	if _reaction == &"catch":
		var u := clampf(_reaction_time / 1.4, 0.0, 1.0)
		var eased := u * u * (3.0 - 2.0 * u)
		_wall.transform = _start_pose
		_wall.scale = _start_pose.basis.get_scale() * lerpf(1.0, 2.6, eased)
		_wall.position.z = _start_pose.origin.z + 2.3 * eased
		# Preserve the 2.6 m pulse radius while its parent lunges and grows.
		_shockwave.scale /= _wall.scale
		_light.light_energy = 6.0
	else:
		var u := clampf(_reaction_time / 0.7, 0.0, 1.0)
		_wall.transform = _start_pose
		_wall.rotate_x(u * PI * 0.48)
		_wall.scale = _start_pose.basis.get_scale() * maxf(1.0 - u, 0.0001)
		_wall.position.z = _start_pose.origin.z + u * 1.5
		_light.light_energy = 0.0
		if u >= 1.0:
			_retreated = true
			_reaction = &"idle"
			_threat = 0.0
			hide()

func _apply() -> void:
	visible = not (_retreated and _threat <= 0.001)
	_wall.transform = Transform3D.IDENTITY
	_wall.scale.y = lerpf(0.35, 1.0, _threat)
	_wall.rotation.x = -0.1 * _threat
	_wall.position.x = sin(_t * 39.0) * 0.025 * _threat * _threat
	if _threat > 0.001:
		_last_threat_pose = _wall.transform
	_metal.set_shader_parameter("threat", _threat)
	for i in _labels.size():
		_labels[i].text = HEADLINES[i]
		_labels[i].modulate.a = 1.0 - _threat * 0.3 * maxf(0.0, sin(_t * 27.0 + i))
	_glitch.amount_ratio = _threat
	_light.light_energy = 2.5 * _threat

## The same CPU transforms uploaded to MultiMesh, for meaningful headless validation.
func card_transforms() -> Array[Transform3D]:
	return _cards.duplicate()
