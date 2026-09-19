extends "res://scenes/runner/pursuer/pursuer_visual_base.gd"
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const FarGlow = preload("res://scenes/runner/shaders/far_glow.gdshader")
const HEADLINES := ["PR #3312 UNREVIEWED", "CHANGES REQUESTED", "STALE", "NEEDS REBASE", "DO NOT MERGE", "0 approvals"]
var _wall: MultiMeshInstance3D
var _cards: Array[Transform3D] = []
var _labels: Array[Label3D] = []
var _light: OmniLight3D
var _glitch: GPUParticles3D
var _haze: ShaderMaterial
var _threat := 0.0
var _t := 0.0
var _reaction := &"idle"
var _reaction_time := 0.0
var _retreated := true
var _start_pose := Transform3D.IDENTITY
var _last_threat_pose := Transform3D.IDENTITY

func _ready() -> void:
	_build()
	_apply()

func _build() -> void:
	if _wall != null: return
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_wall = MultiMeshInstance3D.new()
	_wall.name = "Wall"
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cards := MultiMesh.new()
	cards.transform_format = MultiMesh.TRANSFORM_3D
	cards.use_colors = true
	var card := BoxMesh.new()
	card.size = Vector3(0.92, 0.40, 0.16)
	var material := Materials.lit(Color.WHITE).duplicate() as StandardMaterial3D
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	card.material = material
	cards.mesh = card
	cards.instance_count = 20
	for row in 4:
		for column in 5:
			var pose := Transform3D(Basis(Vector3.FORWARD, sin(float(row * 5 + column)) * 0.035), Vector3((column - 2) * 1.04, 0.3 + row * 0.49, 0))
			_cards.append(pose)
			cards.set_instance_transform(row * 5 + column, pose)
	_wall.multimesh = cards
	add_child(_wall)
	for i in HEADLINES.size():
		var label := Materials.label(_wall, HEADLINES[i], 28, Palette.CREAM)
		label.name = "Headline%d" % i
		label.pixel_size = 0.011
		label.outline_size = 0
		# Fit each headline into its half of the wall without reducing glyph height.
		label.scale.x = 0.65
		label.position = Vector3(-1.25 if i % 2 == 0 else 1.25, 0.48 + (i / 2) * 0.51, 0.11)
		_labels.append(label)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.name = "EyeL" if side < 0 else "EyeR"
		var slit := BoxMesh.new()
		slit.size = Vector3(0.68, 0.085, 0.055)
		eye.mesh = slit
		eye.material_override = Materials.glow(Palette.DANGER, 2.5)
		eye.position = Vector3(side * 0.48, 1.88, 0.15)
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
	_glitch = Materials.glyph_particles(48, Vector3(2.35, 0.75, 0.05))
	_glitch.name = "Glitch"
	_glitch.position.y = 1.1
	_glitch.lifetime = 0.25
	_glitch.preprocess = 0.25
	var process := _glitch.process_material as ParticleProcessMaterial
	process.direction = Vector3.UP
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.1
	var glyph_material := _glitch.draw_pass_1.material as StandardMaterial3D
	glyph_material.albedo_color = Color(Palette.DANGER, 0.55)
	_glitch.visibility_aabb = AABB(Vector3(-2.5, -0.9, -0.2), Vector3(5, 1.9, 0.4))
	_wall.add_child(_glitch)
	var haze := MeshInstance3D.new()
	haze.name = "Haze"
	var quad := QuadMesh.new()
	quad.size = Vector2(5.6, 2.3)
	haze.mesh = quad
	haze.position = Vector3(0, 1.18, -0.16)
	_haze = ShaderMaterial.new()
	_haze.shader = FarGlow
	haze.material_override = _haze
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.add_child(haze)

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
	_reaction = &"catch"
	_reaction_time = 0.0
	_start_pose = _wall.transform
	for label in _labels: label.text = "CAUGHT"
	_light.light_energy = 6.0

func play_retreat() -> void:
	_build()
	if _reaction == &"retreat": return
	show()
	_reaction = &"retreat"
	_reaction_time = 0.0
	_start_pose = _last_threat_pose
	_wall.transform = _start_pose
	_light.light_energy = 0.0

func _process(delta: float) -> void:
	_t += delta
	if _wall == null: return
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
	for i in _cards.size():
		_wall.multimesh.set_instance_color(i, Palette.NAVY.lerp(Palette.DANGER, _threat * _threat))
	for i in _labels.size():
		_labels[i].text = HEADLINES[i]
		_labels[i].modulate.a = 1.0 - _threat * 0.3 * maxf(0.0, sin(_t * 27.0 + i))
	_glitch.amount_ratio = _threat
	_light.light_energy = 2.5 * _threat
	_haze.set_shader_parameter("color", Color(Palette.DANGER, 0.08 + 0.3 * _threat))

## The same CPU transforms uploaded to MultiMesh, for meaningful headless validation.
func card_transforms() -> Array[Transform3D]:
	return _cards.duplicate()
