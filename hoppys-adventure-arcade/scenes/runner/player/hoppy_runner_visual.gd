extends "res://scenes/runner/player/runner_visual_base.gd"
## Cosmetic only. Root animates; the scene root owns lane lean.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Hologram = preload("res://scenes/runner/player/hifi/energy.gdshader")
const Forge = preload("res://scenes/runner/player/hifi/forge.gd")
var _pupils: Array[MeshInstance3D] = []
var _glyph_material: ShaderMaterial
var _glyph_trail_material: ShaderMaterial
var _glass: ShaderMaterial
var _glyphs: MultiMeshInstance3D
var _trail: MultiMeshInstance3D
var _trim: MultiMeshInstance3D
var _trim_material: ShaderMaterial
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

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

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
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.name = id
	node.position = at
	parent.add_child(node)
	for property in ["position", "rotation", "scale"]:
		_rest[String(get_path_to(node)) + ":" + property] = node.get(property)
	return node

func _mesh(parent: Node3D, id: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.name = id
	node.mesh = mesh
	node.position = at
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	_meshes.append(node)
	return node

func _capsule(radius: float, height: float) -> ArrayMesh:
	return Forge.shapes([[Vector3.ZERO, Vector3(radius, height * 0.5, radius)]])

func _sphere(radius: float) -> ArrayMesh:
	return _capsule(radius, radius * 2.0)

func _box(size: Vector3) -> ArrayMesh:
	return Forge.bevel_box(size, 0.025)

func _build_model() -> void:
	var pivot := _pivot(self, "Root", Vector3.ZERO)
	var model := _pivot(pivot, "Model", Vector3.ZERO)
	var orange := Forge.material(Palette.ORANGE, "cloth")
	orange.vertex_color_use_as_albedo = true
	orange.rim_enabled = true
	orange.rim = 0.35
	orange.rim_tint = 0.65
	var cream := Forge.material(Palette.CREAM, "fur")
	var pink := Forge.material(Palette.ORANGE.lerp(Palette.CREAM, 0.65), "fur")
	pink.vertex_color_use_as_albedo = true
	var goggles := Materials.lit(Palette.SLATE).duplicate() as StandardMaterial3D
	goggles.metallic = 0.8
	goggles.roughness = 0.28
	_glass = ShaderMaterial.new()
	_glass.shader = Hologram
	_glass.set_shader_parameter("color", Color(0.47, 0.88, 0.77, 0.28))
	_mesh(model, "Body", _capsule(0.28, 0.8), Vector3(0, 0.78, 0), orange)
	_glyph_material = _glass.duplicate()
	_glyph_material.set_shader_parameter("mode", 2.0)
	_glyph_trail_material = _glyph_material.duplicate()
	_glyph_trail_material.set_shader_parameter("color", Palette.MATRIX)
	# The front chest carries a small emissive paired-bracket glyph.
	var logo := QuadMesh.new()
	logo.size = Vector2(0.13, 0.1)
	_mesh(model, "Logo", logo, Vector3(0, 0.87, -0.276), _glyph_material).rotation.y = PI
	_mesh(model, "Hood", Forge.hood(), Vector3(0, 1.045, 0.13), orange)
	var rear_logo := QuadMesh.new()
	rear_logo.size = Vector2(0.17, 0.12)
	_mesh(model, "RearLogo", rear_logo, Vector3(0, 0.86, 0.281), _glyph_material)
	var cords := Forge.shapes([[Vector3(-0.085, 0, 0), Vector3(0.012, 0.105, 0.012)], [Vector3(0.085, 0, 0), Vector3(0.012, 0.1, 0.012)], [Vector3(-0.085, -0.105, 0), Vector3.ONE * 0.021], [Vector3(0.085, -0.10, 0), Vector3.ONE * 0.021]])
	_mesh(model, "Drawstrings", cords, Vector3(0, 0.98, -0.286), cream)
	_mesh(model, "Pocket", Forge.bevel_box(Vector3(0.33, 0.17, 0.055), 0.02), Vector3(0, 0.68, -0.265), orange)
	var head := _pivot(model, "Head", Vector3(0, 1.28, 0))
	_mesh(head, "Skull", Forge.shapes([[Vector3.ZERO, Vector3.ONE * 0.27], [Vector3(-0.07, -0.09, -0.23), Vector3(0.105, 0.085, 0.1)], [Vector3(0.07, -0.09, -0.23), Vector3(0.105, 0.085, 0.1)]]), Vector3.ZERO, cream)
	_mesh(head, "Nose", _sphere(0.045), Vector3(0, -0.055, -0.355), pink)
	var sclera := Materials.lit(Palette.CREAM).duplicate() as StandardMaterial3D
	sclera.emission_enabled = true
	sclera.emission = Palette.CREAM * 0.12
	var iris_material := Materials.lit(Color.WHITE).duplicate() as StandardMaterial3D
	iris_material.vertex_color_use_as_albedo = true
	var iris := Forge.combine([[Forge.tinted(Forge.cylinder(0.034, 0.01, 0.021), Palette.NAVY), Transform3D.IDENTITY], [Forge.tinted(Forge.cylinder(0.021, 0.012), Palette.EYE.darkened(0.6)), Transform3D.IDENTITY]])
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0 else "R"
		_mesh(head, "Eye" + suffix, _sphere(0.049), Vector3(side * 0.115, 0.015, -0.237), sclera)
		_pupils.append(_mesh(head, "Pupil" + suffix, iris, Vector3(side * 0.115, 0.014, -0.287), iris_material))
		_pupils.back().rotation.x = PI / 2.0
		var lens := _mesh(head, "Lens" + suffix, Forge.cylinder(0.063, 0.012), Vector3(side * 0.115, 0.015, -0.313), _glass)
		lens.rotation.x = PI / 2.0
		var goggle := _mesh(head, "Goggles" + suffix, Forge.cylinder(0.083, 0.08, 0.062), Vector3(side * 0.115, 0.015, -0.281), goggles)
		goggle.rotation.x = PI / 2.0
		var ear := _pivot(head, "Ear" + suffix, Vector3(side * 0.135, 0.17, 0))
		_mesh(ear, "Fur", _capsule(0.067, 0.4), Vector3(0, 0.15, 0), cream)
		_mesh(ear, "Inner", Forge.shapes([[Vector3.ZERO, Vector3(0.038, 0.155, 0.021), true]]), Vector3(0, 0.15, -0.055), pink)
		var arm := _pivot(model, "Arm" + suffix, Vector3(side * 0.3, 1.0, 0))
		_mesh(arm, "Sleeve", _capsule(0.085, 0.4), Vector3(0, -0.17, 0), orange)
		_mesh(arm, "Paw", _sphere(0.09), Vector3(0, -0.36, 0), cream)
		var leg := _pivot(model, "Leg" + suffix, Vector3(side * 0.15, 0.42, 0))
		_mesh(leg, "Fur", _capsule(0.095, 0.37), Vector3(0, -0.15, 0), cream)
		_mesh(leg, "Foot", _box(Vector3(0.2, 0.14, 0.32)), Vector3(0, -0.35, -0.07), cream)
	var strap := Forge.cylinder(0.274, 0.046, 0.253)
	var bridge := Forge.bevel_box(Vector3(0.075, 0.028, 0.038), 0.008)
	var temple := Forge.bevel_box(Vector3(0.025, 0.033, 0.247), 0.006)
	var assembly := Forge.combine([
		[strap, Transform3D(Basis.IDENTITY, Vector3(0, 0.015, 0))],
		[bridge, Transform3D(Basis.IDENTITY, Vector3(0, 0.03, -0.305))],
		[temple, Transform3D(Basis(Vector3.UP, 0.245), Vector3(0.215, 0.015, -0.1825))],
		[temple, Transform3D(Basis(Vector3.UP, -0.245), Vector3(-0.215, 0.015, -0.1825))]])
	_mesh(head, "GoggleStrapBridge", assembly, Vector3.ZERO, goggles)
	_mesh(model, "Tail", _sphere(0.095), Vector3(0, 0.70, 0.32), cream)

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

func _build_effects() -> void:
	_aura_material = ShaderMaterial.new()
	_aura_material.shader = Hologram
	_aura_material.set_shader_parameter("sphere_radius", 0.9)
	_aura_material.set_shader_parameter("hex_cell_size", 0.09)
	_aura = _mesh(get_node("Root"), "Aura", _sphere(0.9), Vector3(0, 0.9, 0), _aura_material)
	_rest["Root/Aura:position"] = _aura.position
	_rest["Root/Aura:scale"] = _aura.scale
	_meshes.erase(_aura)
	_aura.hide()
	var shield_mat := ShaderMaterial.new()
	shield_mat.shader = Hologram
	shield_mat.set_shader_parameter("sphere_radius", 0.88)
	shield_mat.set_shader_parameter("hex_cell_size", 0.09)
	shield_mat.set_shader_parameter("mode", 1.0)
	_shield = _mesh(self, "ShieldRing", _sphere(0.88), Vector3(0, 0.9, 0), shield_mat)
	_meshes.erase(_shield)
	_shield.hide()
	_sparks = _particles("HitSparks", 20, true)
	_sparkles = _particles("AuraSparkles", 24, false)
	_glyphs = _repeat("OrbitGlyphs", 12, _glyph_material)
	_trail = _repeat("DataTrail", 16, _glyph_trail_material)
	_trim_material = _glyph_material.duplicate()
	_trim_material.set_shader_parameter("mode", 3.0)
	_trim = _repeat("MintEdgeTrim", 3, _trim_material)
	_trim.multimesh.mesh = Forge.cylinder(1.0, 0.04, 0.975)
	_update_trim()
	_glyphs.hide()
	_trail.hide()
	var seams := _repeat("Stitches", 24, Forge.material(Palette.ORANGE.lerp(Palette.CREAM, 0.3), "cloth"))
	remove_child(seams)
	get_node("Root/Model").add_child(seams)
	for i in 24:
		var a := float(i) / 24.0 * TAU
		var normal := Vector3(sin(a) * 0.92, -0.39, cos(a) * 0.92).normalized()
		var tangent := Vector3(cos(a), 0, -sin(a))
		var basis := Basis(tangent, normal.cross(tangent), normal)
		_instance(seams, i, Transform3D(basis.scaled_local(Vector3(0.95, 0.45, 1)), Vector3(sin(a) * 0.243, 0.57, cos(a) * 0.243)))

func _track(clip: Animation, path: String, times: Array, values: Array) -> void:
	var index := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(index, NodePath(path))
	clip.track_set_interpolation_type(index, Animation.INTERPOLATION_LINEAR)
	for i in times.size():
		clip.track_insert_key(index, times[i], values[i])

func _build_animations() -> void:
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	animation_player.process_mode = Node.PROCESS_MODE_PAUSABLE
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
		&"run":
			_pose(clip, "Root/Model:scale", times, [Vector3(1.025, 0.97, 1.025), Vector3(0.985, 1.025, 0.985), Vector3(1.025, 0.97, 1.025), Vector3(0.985, 1.025, 0.985), Vector3(1.025, 0.97, 1.025)])
			_pose(clip, "Root:position", times, [Vector3.ZERO, Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(0, 0.06, 0), Vector3.ZERO])
			for side in ["L", "R"]:
				var sign_value := 1.0 if side == "L" else -1.0
				for limb in ["Arm", "Leg"]:
					var swing := 0.65 * sign_value * (-1.0 if limb == "Arm" else 1.0)
					_pose(clip, "Root/Model/" + limb + side + ":rotation", [0.0, end * 0.5, end], [Vector3(swing, 0, 0.1 * sign_value), Vector3(-swing, 0, 0.1 * sign_value), Vector3(swing, 0, 0.1 * sign_value)])
				_pose(clip, "Root/Model/Head/Ear" + side + ":rotation", times, [Vector3(0.2, 0, 0), Vector3(0.55, 0, 0), Vector3(0.2, 0, 0), Vector3(0.55, 0, 0), Vector3(0.2, 0, 0)] if state == &"run" else [Vector3.ZERO, Vector3(0, 0, 0.2 * sign_value), Vector3.ZERO, Vector3(0, 0, -0.2 * sign_value), Vector3.ZERO])
			_pose(clip, "Root/Model/Head:rotation", [0.0], [Vector3(-0.12 if state == &"run" else 0.2, 0, 0)])
		&"fall":
			_pose(clip, "Root/Model/Head:rotation", [0.0], [Vector3(0.14, 0, 0)])
			for side in ["L", "R"]:
				_pose(clip, "Root/Model/Leg" + side + ":rotation", [0.0], [Vector3(-0.4, 0, 0)])
				_pose(clip, "Root/Model/Arm" + side + ":rotation", [0.0], [Vector3(-0.6, 0, 0)])
		&"jump":
			_pose(clip, "Root:scale", [0.0, 0.12, end], [Vector3.ONE, Vector3(0.9, 1.08, 0.9), Vector3.ONE])
			for side in ["L", "R"]:
				_pose(clip, "Root/Model/Leg" + side + ":rotation", [0.0, end], [Vector3(-0.8, 0, 0), Vector3(-0.45, 0, 0)])
				_pose(clip, "Root/Model/Arm" + side + ":rotation", [0.0], [Vector3(-1.0, 0, 0)])
		&"roll":
			# Articulated curl. Every rotating ancestor is uniformly scaled.
			_pose(clip, "Root/Aura:position", [0.0], [Vector3.ZERO])
			_pose(clip, "Root/Aura:scale", [0.0], [Vector3.ONE * 0.6])
			_pose(clip, "Root:position", [0.0], [Vector3(0, 0.45, 0)])
			_pose(clip, "Root:scale", [0.0], [Vector3.ONE * 0.54])
			_pose(clip, "Root/Model:position", [0.0], [Vector3(0, -0.86, 0.05)])
			_pose(clip, "Root/Model/Head:position", [0.0], [Vector3(0, 1.17, -0.17)])
			_pose(clip, "Root/Model/Head:rotation", [0.0], [Vector3(-0.55, 0, 0)])
			_pose(clip, "Root:rotation", [0.0, end], [Vector3.ZERO, Vector3(-TAU, 0, 0)])
			for side in ["L", "R"]:
				var sign_value := -1.0 if side == "L" else 1.0
				_pose(clip, "Root/Model/Head/Ear" + side + ":rotation", [0.0], [Vector3(2.4, 0, -sign_value * 0.08)])
				_pose(clip, "Root/Model/Arm" + side + ":position", [0.0], [Vector3(sign_value * 0.25, 0.98, -0.015)])
				_pose(clip, "Root/Model/Arm" + side + ":rotation", [0.0], [Vector3(1.1, 0, -sign_value * 0.55)])
				_pose(clip, "Root/Model/Leg" + side + ":position", [0.0], [Vector3(sign_value * 0.15, 0.60, -0.03)])
				_pose(clip, "Root/Model/Leg" + side + ":rotation", [0.0], [Vector3(0.9, 0, 0)])
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
	var leaving_roll := anim_state == &"roll"
	anim_state = state
	if animation_player != null:
		# Do not cross-fade the wrapped Euler spin into a zero-rotation clip.
		animation_player.play(state, 0.0 if state == &"roll" or leaving_roll else -1.0)
		set_run_speed(_speed)
		animation_player.advance(0.0)

func set_run_speed(normalized: float) -> void:
	_speed = maxf(normalized, 0.0)
	if animation_player != null:
		animation_player.speed_scale = lerpf(0.85, 1.9, _speed) if anim_state == &"run" else 1.0

func set_lane_lean(direction: float) -> void:
	var lean := clampf(direction, -1.0, 1.0)
	for pupil in _pupils:
		pupil.position.x = (-0.115 if pupil.name == "PupilL" else 0.115) + lean * 0.014
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
		if mesh.name == "Body":
			mesh.material_overlay = Materials.glow(Color.WHITE, 1.5)

func _process(delta: float) -> void:
	_clock += delta
	_update_trim()
	_trim_material.set_shader_parameter("clock", _clock)
	_glass.set_shader_parameter("clock", _clock)
	_glyph_material.set_shader_parameter("clock", _clock)
	_glyph_trail_material.set_shader_parameter("clock", _clock)
	_shield.material_override.set_shader_parameter("clock", _clock)
	_shield.scale = Vector3.ONE * (0.48 if anim_state == &"roll" else 1.0)
	_shield.position.y = 0.45 if anim_state == &"roll" else 0.9
	_shield.material_override.set_shader_parameter("hex_cell_size", 0.09 / _shield.global_basis.x.length())
	_aura_material.set_shader_parameter("hex_cell_size", 0.09 / _aura.global_basis.x.length())
	_glyphs.visible = _aura.visible
	_trail.visible = _speed > 0.4 and anim_state == &"run"
	for i in 12:
		var a := _clock * 1.5 + i * TAU / 12.0
		var r := 0.42 if anim_state == &"roll" else 0.65
		_instance(_glyphs, i, Transform3D(_billboard_basis(_glyphs), Vector3(cos(a) * r, 0.45 + sin(a * 2.0) * 0.08, sin(a) * r)))
	var hood: Node3D = get_node("Root/Model/Hood")
	var emitter := to_local(hood.to_global(Vector3(0, -0.025, 0.095)))
	for i in 16:
		var t := fmod(_clock * 0.8 + float(i) / 16.0, 1.0)
		_instance(_trail, i, Transform3D(_billboard_basis(_trail).scaled(Vector3.ONE * (1.0 - t)), emitter + Vector3(sin(i * 8.0) * 0.10 * t, t * 0.12, t * 0.9)))
	_aura_material.set_shader_parameter("clock", _clock)
	if _flash_remaining > 0.0:
		_flash_remaining -= delta
		if _flash_remaining <= 0.0:
			for mesh in _meshes:
				mesh.material_overlay = null

func _animation_finished(state: StringName) -> void:
	if state == &"hurt" and anim_state == &"hurt":
		set_anim_state(_return_state)

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

func _update_trim() -> void:
	for i in 2:
		var frame: Node3D = get_node("Root/Model/Head/Goggles" + ("L" if i == 0 else "R"))
		var pose := global_transform.affine_inverse() * frame.global_transform
		pose = pose * Transform3D(Basis.IDENTITY.scaled(Vector3(0.079, 0.09, 0.079)), Vector3(0, -0.0405, 0))
		_instance(_trim, i, pose)
	var model: Node3D = get_node("Root/Model")
	_instance(_trim, 2, global_transform.affine_inverse() * model.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3(0.243, 0.09, 0.243)), Vector3(0, 0.57, 0)))
