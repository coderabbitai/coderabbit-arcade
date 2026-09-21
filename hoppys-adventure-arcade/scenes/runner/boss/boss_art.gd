extends Node3D
## CPU-owned instance poses make the animation and its bounds testable headlessly.
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Hologram = preload("res://scenes/runner/shaders/hologram.gdshader")
const CodeWall = preload("res://scenes/runner/shaders/code_wall.gdshader")
const Atlas = preload("res://scenes/runner/shaders/glyph_atlas.gd")
var batches: Array[Dictionary] = []
var state := &"idle"
var phase := 1
var health := 1.0
var clock := 0.0
var age := 0.0
var duration := 0.0
var aim := 0.0
var boss_kind := &""
var core: MeshInstance3D
var ring: MeshInstance3D
var tag: Label3D
var heads: Array[Node3D] = []
var eyes: MultiMeshInstance3D
var shader_materials: Array[ShaderMaterial] = []
var flashes: Array[StandardMaterial3D] = []
var rest_poses: Dictionary = {}

static func shape(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return shape(parent, mesh, pos, Materials.glow(color))

static func sphere(parent: Node3D, pos: Vector3, diameter: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = diameter * 0.5
	mesh.height = diameter
	mesh.radial_segments = 16
	mesh.rings = 8
	return shape(parent, mesh, pos, Materials.glow(color))

static func torus(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.92
	mesh.outer_radius = radius
	mesh.rings = 24
	mesh.ring_segments = 6
	var node := shape(parent, mesh, Vector3(0, 0.55, 0), Materials.additive(color, 0.55))
	node.rotation.x = PI / 2
	return node

static func label(parent: Node3D, words: String, pos: Vector3, pixels: float = 0.006) -> Label3D:
	var node := Materials.label(parent, words, 44, Palette.CREAM)
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.pixel_size = pixels
	node.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	node.outline_size = 10
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.position = pos
	return node

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func batch(poses: Array[Transform3D], color: Color) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	multi.mesh = mesh
	multi.instance_count = poses.size()
	node.multimesh = multi
	var material := Materials.glow(Color.WHITE).duplicate() as StandardMaterial3D
	material.vertex_color_use_as_albedo = true
	node.material_override = material
	flashes.append(material)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	batches.append({"node": node, "rest": poses.duplicate(), "poses": poses.duplicate(), "color": color})
	for i in poses.size():
		multi.set_instance_transform(i, poses[i])
		multi.set_instance_color(i, color)
	return node

static func pose(pos: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), pos)

func build(value: StringName) -> void:
	if core != null: return
	boss_kind = value
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var poses: Array[Transform3D] = []
	match value:
		&"flaky_test_swarm":
			for i in 24:
				var angle := TAU * float(i) / 24.0
				poses.append(pose(Vector3(cos(angle) * 2.5, 0.7 + sin(angle) * 1.15, sin(angle * 3) * 0.5), Vector3.ONE * 0.48))
			batch(poses, Palette.MATRIX)
			core = sphere(self, Vector3(0, 0.6, 0), 0.75, Palette.DANGER)
			var shell := sphere(self, Vector3(0, 0.6, 0), 1.0, Palette.DANGER)
			var hologram := ShaderMaterial.new()
			hologram.shader = Hologram
			hologram.set_shader_parameter("color", Color(Palette.DANGER, 0.5))
			shell.material_override = hologram
			shader_materials.append(hologram)
			for side in [-1, 1]:
				var cloud: Array[Transform3D] = []
				for i in 12:
					cloud.append(pose(Vector3(side * (0.6 + i * 0.07), 1.7 + sin(float(i)) * 0.2, 0), Vector3(0.06, 0.12, 0.03)))
				batch(cloud, Palette.MATRIX if side < 0 else Palette.DANGER)
				label(self, "PASS" if side < 0 else "FAIL", Vector3(side * 0.9, 1.95, 0))
		&"merge_conflict_hydra":
			for head in 4:
				for segment in 5:
					poses.append(pose(Vector3((head - 1.5) * 1.4, -0.65 + segment * 0.49, 0), Vector3(0.5, 0.51, 0.5)))
			batch(poses, Palette.DANGER)
			var eye_poses: Array[Transform3D] = []
			for i in 4:
				var pivot := Node3D.new()
				add_child(pivot)
				pivot.position = Vector3((i - 1.5) * 1.4, 1.75, 0)
				heads.append(pivot)
				var head := box(pivot, Vector3.ZERO, Vector3(1.2, 0.7, 0.8), Palette.NAVY_2)
				head.rotation.z = 0.1 * (i - 1.5)
				eye_poses.append(pose(pivot.position + Vector3(0, 0.03, 0.35), Vector3(0.65, 0.07, 0.04)))
				label(pivot, ["<<<<<<< HEAD", "=======", ">>>>>>> theirs", "CONFLICT"][i], Vector3(0, 0.48, 0), 0.004)
			eyes = batch(eye_poses, Palette.LILAC)
			core = box(self, Vector3(0, 0.4, 0.25), Vector3(0.12, 1.6, 0.08), Palette.ORANGE)
		&"legacy_monolith":
			for row in 3:
				for col in 3:
					poses.append(pose(Vector3((col - 1) * 2.0, (row - 1) * 1.34 + 1.02, 0), Vector3(1.96, 1.3, 2.0)))
			batch(poses, Palette.SLATE)
			var cracks: Array[Transform3D] = []
			for i in 6:
				cracks.append(Transform3D(Basis(Vector3.BACK, 0.22 if i % 2 else -0.22).scaled_local(Vector3(0.035, 0.65, 0.02)), Vector3((i % 3 - 1) * 1.85, 0.1 + (i / 3) * 1.4, 1.04)))
			batch(cracks, Palette.ORANGE)
			var face := QuadMesh.new()
			face.size = Vector2(5.9, 3.9)
			var wall := ShaderMaterial.new()
			wall.shader = CodeWall
			wall.set_shader_parameter("atlas", Atlas.texture())
			wall.set_shader_parameter("horizontal_axis", Vector3.RIGHT)
			shape(self, face, Vector3(0, 1.02, 1.02), wall)
			shader_materials.append(wall)
			for side in [-1, 1]:
				box(self, Vector3(side * 2.1, -0.45, 1.08), Vector3(0.65, 0.16, 0.06), Palette.DANGER)
			core = box(self, Vector3(0, 0.6, 1.1), Vector3(0.3, 0.3, 0.1), Palette.MATRIX)
	ring = torus(self, 0.8, Palette.ORANGE)
	tag = label(self, "", Vector3(0, 3.15, 0), 0.005)
	tag.font_size = 40
	tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	for node: Node3D in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.material_override is StandardMaterial3D:
			mesh.material_override = mesh.material_override.duplicate()
			flashes.append(mesh.material_override)
	for node: Node3D in get_children():
		rest_poses[node] = node.transform
	reset()

func reset() -> void:
	state = &"idle"
	phase = 1
	health = 1.0
	clock = 0.0
	age = 0.0
	show()
	transform = Transform3D.IDENTITY
	advance(0.0)

func react(value: StringName, seconds: float) -> void:
	if state in [&"defeated", &"retreat"]: return
	state = value
	age = 0.0
	duration = maxf(seconds, 0.001)

func flash(resisted: bool = false) -> void:
	react(&"resist" if resisted else &"hurt", 0.25)

func shatter() -> void:
	react(&"defeated", 0.95)

func advance(delta: float) -> void:
	clock += delta
	age += delta
	if age >= duration and state not in [&"idle", &"defeated", &"retreat"]: state = &"idle"
	var u := clampf(age / maxf(duration, 0.001), 0, 1)
	for node: Node3D in rest_poses:
		node.transform = rest_poses[node]
	var charge := u if state == &"telegraph" else 0.0
	core.scale = Vector3.ONE * (1 + 0.6 * charge)
	core.rotation.y = sin(clock * 0.5) * 0.08
	core.position.x += aim * 0.12 * charge
	if state == &"attack": core.position.z -= 0.12 * sin(u * PI)
	if state == &"hurt": core.position.x += sin(age * 90) * 0.06
	ring.visible = state in [&"phase_change", &"attack", &"defeated"]
	ring.scale = Vector3.ONE * (1 + minf(u * 1.5, 1.5))
	# Lift expanding geometry to keep its bottom above the contract floor.
	ring.position.y = 1.2
	for material in flashes:
		material.emission_energy_multiplier = 4.0 if (state == &"hurt" and age < 0.18) or (state == &"phase_change" and sin(age * 32) > 0) else 1.2 + charge
		material.emission = Palette.SLATE if state == &"resist" else (Palette.CREAM if state == &"hurt" else material.albedo_color)
	for shader in shader_materials:
		shader.set_shader_parameter("clock", clock)
		if boss_kind == &"legacy_monolith": shader.set_shader_parameter("intensity", 0.1 + health * 0.65)
	for b in batches.size():
		var entry := batches[b]
		var multi: MultiMesh = entry.node.multimesh
		for i in entry.rest.size():
			var current: Transform3D = entry.rest[i]
			var color: Color = entry.color
			if boss_kind == &"flaky_test_swarm":
				current.origin.x += sin(clock * (2 + phase) + i) * 0.13
				current.origin.y += sin(clock * 3 + i * 0.7) * 0.08
				if phase >= 2 and b == 0:
					var angle: float = clock * 1.4 + (i / 8) * TAU / 3
					current.origin = Vector3(cos(angle) * 2.1 + sin(float(i)) * 0.4, 0.7 + sin(angle) * 0.95 + cos(float(i)) * 0.2, sin(float(i)) * 0.4)
				color = Palette.MATRIX if sin(clock * 11 + i * 7.1) > 0 else Palette.DANGER
			if boss_kind == &"merge_conflict_hydra":
				current.origin.x += sin(clock * 2 + i * 0.2) * 0.07 + aim * charge * 0.06
				if ((b == 0 and i >= 15) or (b == 1 and i == 3)) and phase < 2: current.basis = Basis.from_scale(Vector3.ZERO)
			if boss_kind == &"legacy_monolith" and b == 1:
				current.basis = current.basis.scaled_local(Vector3(1 + phase * 0.35 + (1 - health), 1, 1))
			if state == &"defeated":
				current.origin += Vector3(sin(i * 2.3) * u * 0.3, 1.0 * u - 0.6 * u * u, cos(i * 1.7) * u * 0.12)
				current.basis = current.basis.scaled_local(Vector3.ONE * (1 - u))
				color = color.lerp(Palette.NAVY_BG, u)
			entry.poses[i] = current
			multi.set_instance_transform(i, current)
			multi.set_instance_color(i, color)
	for i in heads.size():
		heads[i].visible = i < 3 or phase >= 2
		heads[i].rotation.y = aim * charge * 0.08
		heads[i].position.x += sin(clock * 2 + i) * 0.07
	if state in [&"defeated", &"retreat"]:
		for node: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
			node.transparency = u
		if u >= 1: hide()
	else:
		for node: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false): node.transparency = 0.0
