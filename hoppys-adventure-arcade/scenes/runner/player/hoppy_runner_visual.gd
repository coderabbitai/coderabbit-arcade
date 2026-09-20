extends "res://scenes/runner/player/runner_visual_base.gd"
## Cosmetic only. Root animates; the scene root owns lane lean.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Hologram = preload("res://scenes/runner/shaders/hologram.gdshader")
const STATES: Array[StringName] = [&"idle", &"run", &"jump", &"fall", &"roll", &"hurt", &"dead"]
var animation_player: AnimationPlayer
var anim_state: StringName = &"idle"
var _return_state: StringName = &"idle"
var _speed := 0.0
var _meshes: Array[MeshInstance3D] = []
var _rest: Dictionary = {}
var _auras: Dictionary = {}
var _aura: MeshInstance3D
var _aura_material: ShaderMaterial
var _shield: MeshInstance3D
var _shield_requested := false
var _sparks: GPUParticles3D
var _sparkles: GPUParticles3D
var _flash_remaining := 0.0
var _clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_model()
	_build_effects()
	_build_animations()
	animation_player.animation_finished.connect(_animation_finished)
	animation_player.play(anim_state)
	set_run_speed(_speed)
	_update_aura()
	show_shield(_shield_requested)

func _pivot(parent: Node3D, id: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = id
	node.position = at
	parent.add_child(node)
	for property in ["position", "rotation", "scale"]:
		_rest[String(get_path_to(node)) + ":" + property] = node.get(property)
	return node

func _mesh(parent: Node3D, id: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = mesh
	node.position = at
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	_meshes.append(node)
	return node

func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	return mesh

func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh

func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _ring(inner: float, outer: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 16
	mesh.ring_segments = 8
	return mesh

func _build_model() -> void:
	var pivot := _pivot(self, "Root", Vector3.ZERO)
	var model := _pivot(pivot, "Model", Vector3.ZERO)
	var orange := Materials.lit(Palette.ORANGE)
	var cream := Materials.lit(Palette.CREAM)
	var pink := Materials.lit(Palette.EAR_PINK)
	var dark := Materials.lit(Palette.EYE)
	var goggles := Materials.glow(Palette.ORANGE)
	_mesh(model, "Body", _capsule(0.28, 0.8), Vector3(0, 0.78, 0), orange)
	var logo := QuadMesh.new()
	logo.size = Vector2(0.19, 0.12)
	var patch := _mesh(model, "Logo", logo, Vector3(0, 0.86, 0.275), cream)
	var mark := Materials.label(patch, "</>", 24, Palette.EYE)
	mark.pixel_size = 0.0025
	mark.position.z = 0.002
	var head := _pivot(model, "Head", Vector3(0, 1.28, 0))
	_mesh(head, "Skull", _sphere(0.27), Vector3.ZERO, cream)
	_mesh(head, "Muzzle", _sphere(0.14), Vector3(0, -0.09, -0.23), cream)
	_mesh(head, "Nose", _sphere(0.045), Vector3(0, -0.055, -0.355), pink)
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0 else "R"
		_mesh(head, "Eye" + suffix, _sphere(0.045), Vector3(side * 0.115, 0.015, -0.237), dark)
		var goggle := _mesh(head, "Goggles" + suffix, _ring(0.062, 0.088), Vector3(side * 0.105, 0.16, -0.205), goggles)
		goggle.rotation.x = PI / 2.0
		var ear := _pivot(head, "Ear" + suffix, Vector3(side * 0.135, 0.2, 0))
		_mesh(ear, "Fur", _capsule(0.07, 0.58), Vector3(0, 0.03, 0), cream)
		_mesh(ear, "Inner", _capsule(0.038, 0.43), Vector3(0, 0.04, -0.047), pink)
		var arm := _pivot(model, "Arm" + suffix, Vector3(side * 0.3, 1.0, 0))
		_mesh(arm, "Sleeve", _capsule(0.085, 0.4), Vector3(0, -0.17, 0), orange)
		_mesh(arm, "Paw", _sphere(0.09), Vector3(0, -0.36, 0), cream)
		var leg := _pivot(model, "Leg" + suffix, Vector3(side * 0.15, 0.42, 0))
		_mesh(leg, "Fur", _capsule(0.095, 0.32), Vector3(0, -0.15, 0), cream)
		_mesh(leg, "Foot", _box(Vector3(0.2, 0.14, 0.32)), Vector3(0, -0.35, -0.07), cream)
	_mesh(model, "Tail", _sphere(0.13), Vector3(0, 0.55, 0.29), cream)

func _particles(id: String, count: int, one_shot: bool) -> GPUParticles3D:
	var node := GPUParticles3D.new()
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
	var mesh := _sphere(0.025)
	mesh.material = Materials.glow(Palette.CREAM)
	node.draw_pass_1 = mesh
	add_child(node)
	return node

func _build_effects() -> void:
	_aura_material = ShaderMaterial.new()
	_aura_material.shader = Hologram
	_aura = _mesh(get_node("Root"), "Aura", _sphere(0.9), Vector3(0, 0.9, 0), _aura_material)
	_rest["Root/Aura:position"] = _aura.position
	_rest["Root/Aura:scale"] = _aura.scale
	_meshes.erase(_aura)
	_aura.hide()
	_shield = _mesh(self, "ShieldRing", _ring(0.48, 0.53), Vector3(0, 0.055, 0), Materials.glow(Palette.MINT))
	_meshes.erase(_shield)
	_shield.hide()
	_sparks = _particles("HitSparks", 20, true)
	_sparkles = _particles("AuraSparkles", 24, false)

func _track(clip: Animation, path: String, times: Array, values: Array) -> void:
	var index := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(index, NodePath(path))
	clip.track_set_interpolation_type(index, Animation.INTERPOLATION_LINEAR)
	for i in times.size():
		clip.track_insert_key(index, times[i], values[i])

func _build_animations() -> void:
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	animation_player.playback_default_blend_time = 0.08
	add_child(animation_player)
	var library := AnimationLibrary.new()
	var durations := [1.6, 0.5, 0.35, 0.6, 0.5, 0.45, 0.9]
	for i in STATES.size():
		var state := STATES[i]
		var clip := Animation.new()
		clip.length = durations[i]
		clip.step = 1.0 / 30.0
		if state in [&"idle", &"run", &"fall"]:
			clip.loop_mode = Animation.LOOP_LINEAR
		# Explicit rest tracks prevent a held pose leaking into the next clip.
		for path: String in _rest:
			_track(clip, path, [0.0], [_rest[path]])
		_pose_clip(clip, state)
		library.add_animation(state, clip)
	animation_player.add_animation_library(&"", library)

func _pose(clip: Animation, path: String, times: Array, values: Array) -> void:
	var existing := clip.find_track(NodePath(path), Animation.TYPE_VALUE)
	if existing >= 0:
		clip.remove_track(existing)
	_track(clip, path, times, values)

func _pose_clip(clip: Animation, state: StringName) -> void:
	var end := clip.length
	var times := [0.0, end * 0.25, end * 0.5, end * 0.75, end]
	match state:
		&"idle":
			_pose(clip, "Root/Model:scale", [0.0, 0.8, end], [Vector3.ONE, Vector3(1.015, 0.985, 1.015), Vector3.ONE])
			_pose(clip, "Root/Model/Head/EarL:rotation", times, [Vector3.ZERO, Vector3(0, 0, -0.12), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
		&"run", &"fall":
			_pose(clip, "Root:position", times, [Vector3.ZERO, Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(0, 0.06, 0), Vector3.ZERO])
			for side in ["L", "R"]:
				var sign_value := 1.0 if side == "L" else -1.0
				for limb in ["Arm", "Leg"]:
					var swing := 0.65 * sign_value * (-1.0 if limb == "Arm" else 1.0)
					_pose(clip, "Root/Model/" + limb + side + ":rotation", [0.0, end * 0.5, end], [Vector3(swing, 0, 0.1 * sign_value), Vector3(-swing, 0, 0.1 * sign_value), Vector3(swing, 0, 0.1 * sign_value)])
				_pose(clip, "Root/Model/Head/Ear" + side + ":rotation", times, [Vector3(0.2, 0, 0), Vector3(0.55, 0, 0), Vector3(0.2, 0, 0), Vector3(0.55, 0, 0), Vector3(0.2, 0, 0)] if state == &"run" else [Vector3.ZERO, Vector3(0, 0, 0.2 * sign_value), Vector3.ZERO, Vector3(0, 0, -0.2 * sign_value), Vector3.ZERO])
			_pose(clip, "Root/Model/Head:rotation", [0.0], [Vector3(-0.12 if state == &"run" else 0.2, 0, 0)])
		&"jump":
			_pose(clip, "Root:scale", [0.0, 0.12, end], [Vector3.ONE, Vector3(0.9, 1.08, 0.9), Vector3.ONE])
			for side in ["L", "R"]:
				_pose(clip, "Root/Model/Leg" + side + ":rotation", [0.0, end], [Vector3(-0.8, 0, 0), Vector3(-0.45, 0, 0)])
				_pose(clip, "Root/Model/Arm" + side + ":rotation", [0.0], [Vector3(-1.0, 0, 0)])
		&"roll":
			# Keep the aura centered and inside the rotating tucked bounds.
			_pose(clip, "Root/Aura:position", [0.0], [Vector3.ZERO])
			_pose(clip, "Root/Aura:scale", [0.0], [Vector3.ONE * 0.6])
			# Center the tucked model before spinning; keep the held roll below 0.9 m.
			_pose(clip, "Root:position", [0.0], [Vector3(0, 0.45, 0)])
			_pose(clip, "Root:scale", [0.0], [Vector3(0.5, 0.55, 0.5)])
			_pose(clip, "Root/Model:position", [0.0], [Vector3(0, -0.76, 0)])
			_pose(clip, "Root/Model:scale", [0.0], [Vector3.ONE * 0.95])
			_pose(clip, "Root:rotation", [0.0, end * 0.999, end], [Vector3.ZERO, Vector3(-TAU, 0, 0), Vector3.ZERO])
			for side in ["L", "R"]:
				_pose(clip, "Root/Model/Head/Ear" + side + ":rotation", [0.0], [Vector3(PI / 2.0, 0, 0)])
				_pose(clip, "Root/Model/Arm" + side + ":rotation", [0.0], [Vector3(-0.8, 0, 0)])
		&"hurt":
			_pose(clip, "Root:rotation", [0.0, 0.12, end], [Vector3.ZERO, Vector3(0.3, 0, 0), Vector3.ZERO])
			for side in ["L", "R"]:
				_pose(clip, "Root/Model/Head/Ear" + side + ":rotation", [0.0, end], [Vector3(0.3, 0, -0.5 if side == "L" else 0.5), Vector3.ZERO])
			var track := clip.add_track(Animation.TYPE_METHOD)
			clip.track_set_path(track, NodePath("."))
			for time in [0.001, 0.12, 0.24]:
				clip.track_insert_key(track, time, {"method": &"flash", "args": []})
		&"dead":
			_pose(clip, "Root:rotation", [0.0, 0.55, end], [Vector3.ZERO, Vector3(PI / 2.0, 0, 0), Vector3(PI / 2.0, 0, 0)])
			_pose(clip, "Root:position", [0.0, 0.55, end], [Vector3.ZERO, Vector3(0, 0.3, 0), Vector3(0, 0.3, 0)])
			for side in ["L", "R"]:
				_pose(clip, "Root/Model/Arm" + side + ":rotation", [0.0, end], [Vector3.ZERO, Vector3(0, 0, -0.65 if side == "L" else 0.65)])

func set_anim_state(state: StringName) -> void:
	if state not in STATES or state == anim_state:
		return
	if state == &"hurt":
		_return_state = anim_state if anim_state in [&"idle", &"run", &"jump", &"fall", &"roll"] else &"run"
	anim_state = state
	if animation_player != null:
		# Roll must enter its compact pose immediately to match the active hurtbox.
		animation_player.play(state, 0.0 if state == &"roll" else -1.0)
		set_run_speed(_speed)
		animation_player.advance(0.0)

func set_run_speed(normalized: float) -> void:
	_speed = maxf(normalized, 0.0)
	if animation_player != null:
		animation_player.speed_scale = lerpf(0.85, 1.9, _speed) if anim_state == &"run" else 1.0

func set_lane_lean(direction: float) -> void:
	var lean := clampf(direction, -1.0, 1.0)
	rotation.z = -lean * 0.12
	rotation.y = -lean * 0.1

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

func on_hit() -> void:
	flash()
	if _sparks != null:
		_sparks.restart()

func flash() -> void:
	_flash_remaining = 0.06
	for mesh in _meshes:
		mesh.material_overlay = Materials.glow(Color.WHITE, 1.5)

func _process(delta: float) -> void:
	_clock += delta
	_aura_material.set_shader_parameter("clock", _clock)
	if _flash_remaining > 0.0:
		_flash_remaining -= delta
		if _flash_remaining <= 0.0:
			for mesh in _meshes:
				mesh.material_overlay = null

func _animation_finished(state: StringName) -> void:
	if state == &"hurt" and anim_state == &"hurt":
		set_anim_state(_return_state)
