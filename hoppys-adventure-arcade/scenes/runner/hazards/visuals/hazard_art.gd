extends Node3D
## Geometry is authored in a unit hitbox, then scaled to the supplied dimensions.
## Floor projections are deliberately separate from the collision-volume artwork.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
var body: Node3D
var beams: Node3D
var scanner: MeshInstance3D
var tag: Label3D
var _kind: StringName
var _variant: StringName
var _size := Vector3.ONE
var _offset := Vector3.ZERO
var _t := 0.0
var _reaction := 0.0
var _hit := false
var _cleared := false
var _parts: Array[Node3D] = []
var _rests: Array[Vector3] = []
# Contract section 8: high laser row spans y=1.1..1.5.
const LASER_HIGH_Y := 1.3
var _glyphs: GPUParticles3D
var _overlay_removed := false
var _geometry: Array[GeometryInstance3D] = []
var _batches: Array[Dictionary] = []
var _core: MeshInstance3D
var _fades: Array[StandardMaterial3D] = []
var _seams: Array[StandardMaterial3D] = []
var _state: StringName = &"ground"

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func build(kind: StringName, variant: StringName, size: Vector3, offset: Vector3) -> void:
	name = "Artwork"
	_kind = kind
	_variant = variant
	_size = size
	_offset = offset
	var marker := MeshInstance3D.new()
	marker.name = "FloorMarker"
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x, size.z)
	marker.mesh = quad
	marker.rotation.x = -PI / 2.0
	marker.position = Vector3(offset.x, 0.006, offset.z)
	marker.material_override = Materials.additive(Palette.DANGER, 0.35)
	add_child(marker)
	if kind == &"pr_backlog_high":
		var safe := marker.duplicate() as MeshInstance3D
		safe.name = "SafeGap"
		safe.position.y = 0.009
		safe.mesh = quad.duplicate()
		(safe.mesh as QuadMesh).size.y *= 0.6
		safe.material_override = Materials.additive(Palette.MATRIX, 0.25)
		add_child(safe)
	body = Node3D.new()
	body.name = "Body"
	body.position = offset
	body.scale = size
	add_child(body)
	match kind:
		&"pr_backlog_low", &"pr_backlog_high": _backlog()
		&"bug_swarm": _bug()
		&"merge_conflict": _merge()
		&"deprecated_pit": _pit()
		&"laser_grid": _laser()
		&"comment_flood": _comments()
		&"build_shockwave": _shockwave()
	for part in _parts:
		_rests.append(part.position)
	_batch_boxes()
	for node in body.find_children("*", "GeometryInstance3D", true, false):
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			_geometry.append(node)

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return shape(parent, mesh, pos, Materials.glow(color) if glow else Materials.lit(color))

func shape(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = mesh
	result.position = pos
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result

func sphere(parent: Node3D, pos: Vector3, diameter: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = diameter * 0.5
	mesh.height = diameter
	mesh.radial_segments = 12
	mesh.rings = 6
	return shape(parent, mesh, pos, Materials.glow(color))

func label(parent: Node3D, text: String, pos: Vector3, width: float, height: float) -> Label3D:
	var result := Materials.label(parent, text, 32, Palette.CREAM)
	result.position = pos
	# Fixed orientation avoids a billboard rotating outside a shallow hitbox.
	result.pixel_size = minf(width / (float(text.length()) * 26.0 + 32.0), height / 64.0)
	result.no_depth_test = false
	return result

func card(pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	body.add_child(pivot)
	pivot.position = pos
	box(pivot, Vector3.ZERO, size, Palette.NAVY)
	box(pivot, Vector3(0, size.y * 0.42, size.z * 0.51), Vector3(size.x, size.y * 0.08, 0.012), color, true)
	_parts.append(pivot)
	return pivot

func _backlog() -> void:
	if _kind == &"pr_backlog_high":
		# Rail at 2.97 m for the contract hitbox, inside its 110% envelope.
		box(body, Vector3(0, 0.535, 0), Vector3(0.96, 0.02, 0.12), Palette.ORANGE, true)
		for i in 3:
			var x := (float(i) - 1.0) * 0.31
			box(body, Vector3(x, 0.34, 0), Vector3(0.008, 0.34, 0.025), Palette.SLATE)
			card(Vector3(x, -0.06, 0), Vector3(0.28, 0.66, 0.32), Palette.DANGER)
	else:
		for row in 3:
			for column in 3:
				card(Vector3((column - 1) * 0.31, (row - 1) * 0.29, 0), Vector3(0.285, 0.25, 0.62), Palette.ORANGE if row % 2 == 0 else Palette.DANGER)
	tag = label(body, "CI FAILING" if _kind == &"pr_backlog_high" else "NEEDS REVIEW", Vector3(0, 0, 0.46), 0.75, 0.14)

func _bug() -> void:
	_core = sphere(body, Vector3.ZERO, 0.44, Palette.DANGER)
	for side in [-1, 1]:
		for i in 3:
			var leg := box(body, Vector3(side * 0.29, -0.09, (i - 1) * 0.17), Vector3(0.25, 0.045, 0.04), Palette.ORANGE, true)
			leg.rotation.z = side * (i - 1) * 0.22
			_parts.append(leg)
	_glyph_cloud(36, false)
	tag = label(body, "throw new Error()", Vector3(0, -0.34, 0.43), 0.85, 0.13)

func _merge() -> void:
	card(Vector3(-0.235, 0, 0), Vector3(0.43, 0.75, 0.65), Palette.MATRIX)
	card(Vector3(0.235, 0, 0), Vector3(0.43, 0.75, 0.65), Palette.LILAC)
	var pulse := Materials.glow(Palette.DANGER).duplicate() as StandardMaterial3D
	_seams.append(pulse)
	for i in 7:
		var seam := box(body, Vector3(0, (i - 3) * 0.1, 0.37), Vector3(0.018, 0.13, 0.03), Palette.DANGER, true)
		seam.rotation.z = 0.3 if i % 2 == 0 else -0.3
		seam.material_override = pulse
	label(body, "=======", Vector3(0, -0.24, 0.43), 0.22, 0.08).outline_size = 0
	tag = label(body, "MERGE CONFLICT", Vector3(0, 0.38, 0.43), 0.65, 0.12)

func _pit() -> void:
	var hole := QuadMesh.new()
	hole.size = Vector2(0.96, 0.96)
	var surface := shape(body, hole, Vector3(0, (0.015 - _offset.y) / _size.y, 0), Materials.lit(Palette.NAVY_BG))
	surface.rotation.x = -PI / 2.0
	for i in 14:
		for side in [-1, 1]:
			box(body, Vector3((i - 6.5) * 0.067, 0.14, side * 0.465), Vector3(0.065, 0.18, 0.06), Palette.ORANGE if i % 2 == 0 else Palette.NAVY)
	for side in [-1, 1]:
		box(body, Vector3(side * 0.465, 0.14, 0), Vector3(0.06, 0.18, 0.88), Palette.ORANGE)
	tag = label(body, "@deprecated", Vector3(0, 0.12, 0), 0.7, 0.3)
	tag.rotation.x = -PI / 2.0
	var since := label(body, "since v0.9", Vector3(0, 0.12, 0.29), 0.45, 0.14)
	since.rotation.x = -PI / 2.0
	since.outline_size = 0
	_glyph_cloud(24, true)

func _laser() -> void:
	for side in [-1, 1]:
		box(body, Vector3(side * 0.465, 0, 0), Vector3(0.035, 0.8, 0.38), Palette.NAVY)
		sphere(body, Vector3(side * 0.465, 0.35, 0), 0.07, Palette.DANGER)
	beams = Node3D.new()
	beams.name = "Beams"
	body.add_child(beams)
	for i in 3:
		var beam := box(beams, Vector3(0, (i - 1) * 0.29, 0), Vector3(0.9, 0.07, 0.1), Palette.DANGER, true)
		beam.material_override = Materials.additive(Palette.DANGER, 0.85)
	scanner = box(body, Vector3.ZERO, Vector3(0.89, 0.055, 0.8), Palette.MINT)
	scanner.name = "Scanner"
	scanner.material_override = Materials.additive(Palette.MINT, 0.4)
	scanner.hide()
	tag = label(body, "SECURITY SCAN", Vector3(0, 0.01, 0.43), 0.6, 0.19)
	_state = &"high" if _variant == &"high" else &"ground"
	_glyph_cloud(12, false)
	_glyphs.hide()

func _comments() -> void:
	var shell := box(body, Vector3.ZERO, Vector3(0.97, 0.98, 0.86), Palette.DANGER)
	shell.material_override = Materials.additive(Palette.DANGER, 0.12)
	for i in 4:
		var bubble := card(Vector3(0.035 if i % 2 else -0.035, (i - 1.5) * 0.21, 0), Vector3(0.8, 0.16, 0.52), Palette.ORANGE)
		box(bubble, Vector3(-0.3, -0.087, 0), Vector3(0.07, 0.035, 0.3), Palette.ORANGE)
	tag = label(body, "BLOCKING // TODO", Vector3(0, 0, 0.46), 0.7, 0.14)

func _shockwave() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.36
	ring.outer_radius = 0.47
	ring.rings = 24
	ring.ring_segments = 8
	var mesh := shape(body, ring, Vector3(0, -0.12, 0), Materials.glow(Palette.DANGER))
	_parts.append(mesh)
	sphere(body, Vector3.ZERO, 0.27, Palette.DANGER)
	for i in 10:
		var angle := float(i) * TAU / 10.0
		var shard := box(body, Vector3(cos(angle) * 0.35, 0.08, sin(angle) * 0.35), Vector3(0.03, 0.14, 0.035), Palette.ORANGE, true)
		_parts.append(shard)
	tag = label(body, "BUILD FAILED  x", Vector3(0, 0.3, 0.38), 0.73, 0.19)

func _glyph_cloud(count: int, falling: bool) -> void:
	_glyphs = Materials.glyph_particles(count, _size * 0.28)
	_glyphs.name = "GlyphParticles"
	_glyphs.process_mode = Node.PROCESS_MODE_PAUSABLE
	_glyphs.position = _offset
	_glyphs.visibility_aabb = AABB(-_size * 0.5, _size)
	_glyphs.trail_enabled = false
	_glyphs.sub_emitter = NodePath()
	var process := _glyphs.process_material as ParticleProcessMaterial
	process.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	# Keep the full lifetime trajectory inside the hitbox, including billboard size.
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = _size.y * 0.035 if falling else 0.0
	process.color = Palette.DANGER
	var quad := _glyphs.draw_pass_1 as QuadMesh
	(quad.material as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.6)
	quad.size = Vector2.ONE * minf(_size.x, minf(_size.y, _size.z)) * 0.07
	add_child(_glyphs)

func _batch_boxes() -> void:
	# Unit boxes share one draw per material; pivots retain per-card animation.
	var groups: Dictionary = {}
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if not mesh.mesh is BoxMesh or mesh == scanner:
			continue
		var material := mesh.material_override
		if not groups.has(material): groups[material] = []
		var pivot := Node3D.new()
		mesh.get_parent().add_child(pivot)
		pivot.transform = mesh.transform
		var index := _parts.find(mesh)
		if index >= 0: _parts[index] = pivot
		groups[material].append([pivot, (mesh.mesh as BoxMesh).size])
		mesh.free()
	for material: Material in groups:
		var batch := MultiMeshInstance3D.new()
		batch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		batch.multimesh.mesh = box
		batch.multimesh.instance_count = groups[material].size()
		batch.material_override = material
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(batch)
		_batches.append({"node": batch, "instances": groups[material]})
	_update_batches()

func _update_batches() -> void:
	for batch in _batches:
		var node: MultiMeshInstance3D = batch.node
		for i in batch.instances.size():
			var instance: Array = batch.instances[i]
			var pivot: Node3D = instance[0]
			var pose := body.global_transform.affine_inverse() * pivot.global_transform
			pose.basis = pose.basis.scaled_local(instance[1])
			# Hidden beam pivots still control the visibility of their instances.
			if not pivot.is_visible_in_tree(): pose.basis = pose.basis.scaled_local(Vector3.ZERO)
			node.multimesh.set_instance_transform(i, pose)

func react(cleared: bool) -> void:
	_hit = not cleared
	_cleared = cleared
	_reaction = 0.0
	_overlay_removed = false
	if cleared:
		get_node("FloorMarker").material_override = Materials.additive(Palette.MINT, 0.35)
	var words := {&"pr_backlog_low": "AUTO-FIXED", &"pr_backlog_high": "AUTO-FIXED", &"bug_swarm": "FIXED", &"merge_conflict": "MERGED", &"deprecated_pit": "REMOVED", &"laser_grid": "SCAN PASSED", &"comment_flood": "RESOLVED", &"build_shockwave": "BUILD FIXED"}
	if scanner != null:
		scanner.hide()
	_fades.clear()
	if cleared:
		tag.text = words[_kind]
		tag.modulate = Palette.MINT
	if _glyphs != null:
		_glyphs.show()
		(_glyphs.process_material as ParticleProcessMaterial).color = Palette.MINT if cleared else Palette.CREAM
	for mesh in _geometry:
		mesh.material_overlay = Materials.additive(Palette.MINT if cleared else Palette.CREAM, 0.65)
		if not cleared and _kind in [&"pr_backlog_low", &"comment_flood"]:
			var fade := mesh.material_override.duplicate() as StandardMaterial3D
			fade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh.material_override = fade
			_fades.append(fade)

func telegraph(t: float) -> void:
	if scanner == null or _variant != &"timed":
		return
	var amount := clampf(t, 0.0, 1.0)
	scanner.visible = amount > 0.0 and not _cleared
	scanner.position.y = lerpf(-0.39, 0.39, amount)
	scanner.scale.x = 0.5 + amount * 0.5

func laser_state(state: StringName) -> void:
	if beams == null or _variant != &"timed" or state not in [&"ground", &"high", &"off"]:
		return
	_state = state
	beams.visible = state != &"off" and not _cleared
	if state != &"off":
		# Discrete contract state, never sweep dangerous geometry through the safe gap.
		body.position.y = LASER_HIGH_Y if state == &"high" else _offset.y
		if _glyphs != null: _glyphs.position.y = body.position.y
	telegraph(0.0)
	_update_batches()

func advance(delta: float) -> void:
	_t += delta
	_reaction += delta
	for material in _seams:
		material.emission_energy_multiplier = 1.2 + 0.5 * sin(_t * 6.0)
	for material in _fades:
		material.albedo_color.a = maxf(0.0, 1.0 - _reaction * 2.5)
	if _core != null and (_hit or _cleared):
		var pop := (1.0 + 0.15 * sin(minf(_reaction * 8.0, PI))) * maxf(0.0, 1.0 - _reaction * 2.5)
		_core.scale = Vector3.ONE * pop
	for i in _parts.size():
		var part := _parts[i]
		part.position = _rests[i]
		part.scale = Vector3.ONE
		var wave := sin(_t * 3.0 + float(i))
		match _kind:
			&"pr_backlog_low", &"pr_backlog_high": part.position.x += wave * 0.01
			&"bug_swarm": part.position.y += wave * 0.015
			&"merge_conflict": part.position.x += wave * 0.012
			&"comment_flood": part.position.y = 0.34 - fmod(float(i) * 0.21 + _t * 0.15, 0.68)
			&"build_shockwave": part.scale = Vector3.ONE * (0.94 + wave * 0.04)
		if _hit:
			var impact := minf(_reaction / 0.35, 1.0)
			part.position.x += sin(float(i) * 2.0) * 0.018 * impact
			if _kind == &"build_shockwave" and i > 0:
				part.position.x *= 1.15
				part.position.z *= 1.15
			if _kind == &"pr_backlog_high":
				part.position.y -= absf(sin(impact * PI)) * 0.04
			if _kind in [&"pr_backlog_low", &"comment_flood"]:
				part.position.z += sin(float(i) * 1.3) * 0.1 * impact
				part.scale *= 1.0 - impact * 0.15
		if _cleared:
			part.scale *= maxf(0.0, 1.0 - _reaction * 3.0)
	if _glyphs != null and (_hit or _cleared):
		var color := Palette.MINT if _cleared else Palette.CREAM
		color.a = maxf(0.0, 1.0 - _reaction * 1.5)
		(_glyphs.process_material as ParticleProcessMaterial).color = color
	if _kind == &"deprecated_pit" and not _hit and not _cleared:
		tag.modulate.a = 0.75 + 0.25 * sin(_t * 8.0)
	if beams != null:
		beams.scale.x = maxf(0.0, 1.0 - _reaction * 4.0) if _cleared else 0.97 + 0.03 * sin(_t * 29.0)
	_update_batches()
	if _cleared and _kind == &"merge_conflict":
		# Reveal one resolved slab after the two branch cards collapse.
		if not body.has_node("Merged"):
			var merged := box(body, Vector3(0, 0, -0.04), Vector3(0.85, 0.62, 0.5), Palette.MINT, true)
			merged.name = "Merged"
	if _hit and _reaction > 0.12 and not _overlay_removed:
		_overlay_removed = true
		for mesh in _geometry:
			mesh.material_overlay = null
