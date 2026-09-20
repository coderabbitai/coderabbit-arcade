extends Node3D
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
var _pivot: Node3D
var _ring: MeshInstance3D
var _halo: GPUParticles3D
var _tag: Label3D
var _flame: GPUParticles3D
var _ring_material: StandardMaterial3D
var _t := 0.0
var _collect_time := -1.0

func build(kind: StringName) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_ring_material = Materials.additive(Palette.MINT, 0.65).duplicate() as StandardMaterial3D
	_ring = torus(_pivot, 0.34, 0.38, Vector3.ZERO, _ring_material)
	_ring.name = "Ring"
	_halo = Materials.glyph_particles(24, Vector3(0.28, 0.28, 0.08))
	_halo.name = "Halo"
	var sparkle := QuadMesh.new()
	sparkle.size = Vector2(0.035, 0.035)
	var sparkle_material := Materials.additive(Palette.MINT, 0.7).duplicate() as StandardMaterial3D
	sparkle_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sparkle.material = sparkle_material
	_halo.draw_pass_1 = sparkle
	_halo.lifetime = 0.4
	_halo.preprocess = 0.4
	var process := _halo.process_material as ParticleProcessMaterial
	process.direction = Vector3.UP
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.3
	_halo.visibility_aabb = AABB(Vector3(-0.5, -0.5, -0.3), Vector3(1, 1, 0.6))
	_pivot.add_child(_halo)
	var tags := {&"approve_shield": "APPROVED", &"auto_fix": "AUTO-FIX", &"lgtm": "5s", &"nitro": "NITRO COMMIT", &"super_jump": "SUPER JUMP", &"code_review": "CODE REVIEW ×1.5"}
	_tag = Materials.label(self, tags.get(kind, ""), 28, Palette.MINT)
	_tag.name = "Tag"
	_tag.position.y = 0.75
	_tag.pixel_size = 0.007
	_tag.width = 190.0
	_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	match kind:
		&"approve_shield":
			var shield := CylinderMesh.new()
			shield.top_radius = 0.29
			shield.bottom_radius = 0.29
			shield.height = 0.07
			shield.radial_segments = 6
			mesh(_pivot, shield, Vector3.ZERO, Materials.glow(Palette.MINT)).rotation.x = PI / 2
			bar(Vector3(-0.065, -0.025, 0.05), Vector3(0.12, 0.045, 0.035), -0.7, Palette.CREAM)
			bar(Vector3(0.055, 0.025, 0.05), Vector3(0.23, 0.045, 0.035), 0.8, Palette.CREAM)
		&"auto_fix":
			bar(Vector3(-0.035, -0.03, 0), Vector3(0.075, 0.4, 0.07), -0.5, Palette.MINT)
			bar(Vector3(0.005, 0.2, 0), Vector3(0.06, 0.14, 0.07), -0.5, Palette.MINT)
			bar(Vector3(0.14, 0.14, 0), Vector3(0.06, 0.14, 0.07), -0.5, Palette.MINT)
			text("ϟ", 0.32, Vector3(0.17, -0.12, 0.06), Palette.CREAM)
		&"lgtm": text("LGTM", 0.19, Vector3(0, -0.07, 0), Palette.MINT)
		&"nitro":
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.13
			capsule.height = 0.45
			mesh(_pivot, capsule, Vector3(0, 0.04, 0), Materials.glow(Palette.MINT))
			text("+", 0.16, Vector3(0, 0, 0.14), Palette.CREAM)
			_flame = Materials.glyph_particles(20, Vector3(0.055, 0.01, 0.055))
			_flame.name = "Flame"
			_flame.draw_pass_1.material.albedo_color = Color(Palette.MINT, 0.65)
			_flame.position.y = -0.18
			_flame.lifetime = 0.3
			_flame.preprocess = 0.3
			var flame_process := _flame.process_material as ParticleProcessMaterial
			flame_process.initial_velocity_min = 0.5
			flame_process.initial_velocity_max = 0.9
			_flame.visibility_aabb = AABB(Vector3(-0.2, -0.4, -0.2), Vector3(0.4, 0.5, 0.4))
			_pivot.add_child(_flame)
		&"super_jump":
			var coin := CylinderMesh.new()
			coin.top_radius = 0.27
			coin.bottom_radius = 0.27
			coin.height = 0.06
			mesh(_pivot, coin, Vector3.ZERO, Materials.glow(Palette.MINT)).rotation.x = PI / 2
			text("^^", 0.22, Vector3(0, -0.075, 0.04), Palette.CREAM)
		&"code_review":
			torus(_pivot, 0.14, 0.19, Vector3(-0.055, 0.06, 0), Materials.glow(Palette.MINT)).rotation.x = PI / 2
			bar(Vector3(0.13, -0.14, 0), Vector3(0.075, 0.25, 0.07), 0.7, Palette.CREAM)

func mesh(parent: Node3D, shape: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = shape
	result.material_override = material
	result.position = pos
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result

func torus(parent: Node3D, inner: float, outer: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = inner
	shape.outer_radius = outer
	shape.rings = 24
	shape.ring_segments = 8
	return mesh(parent, shape, pos, material)

func bar(pos: Vector3, size: Vector3, angle: float, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	mesh(_pivot, box, pos, Materials.glow(color)).rotation.z = angle

func text(value: String, height: float, pos: Vector3, color: Color) -> void:
	var shape := TextMesh.new()
	shape.font = Materials.font()
	shape.text = value
	shape.font_size = 48
	shape.pixel_size = height / 48.0
	shape.depth = 0.025
	mesh(_pivot, shape, pos, Materials.glow(color))

func reset() -> void:
	set_process(true)
	_t = 0.0
	_collect_time = -1.0
	show()
	_pivot.transform = Transform3D.IDENTITY
	_ring.scale = Vector3.ONE
	_ring_material.albedo_color = Color(Palette.MINT, 0.65)
	_tag.modulate.a = 1.0
	_halo.one_shot = false
	_halo.explosiveness = 0.0
	_halo.restart()
	_halo.emitting = true
	if _flame != null: _flame.emitting = true
	for part: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		part.transparency = 0.0

func collect() -> void:
	if _collect_time >= 0.0: return
	_collect_time = 0.0
	_halo.emitting = false
	_halo.one_shot = true
	_halo.explosiveness = 1.0
	_halo.restart()
	_halo.emitting = true
	if _flame != null: _flame.emitting = false

func _process(delta: float) -> void:
	if _pivot == null: return
	_t += delta
	_pivot.rotation.y = _t * 1.6
	_pivot.position.y = sin(_t * 2.8) * 0.08
	if _collect_time < 0.0: return
	_collect_time += delta
	var u := clampf(_collect_time / 0.25, 0.0, 1.0)
	var size := lerpf(1.0, 1.45, u / 0.35) if u < 0.35 else lerpf(1.45, 0.0, (u - 0.35) / 0.65)
	_pivot.scale = Vector3.ONE * maxf(size, 0.0001)
	# Compensate for the icon shrink so the ring continues expanding outward.
	_ring.scale = Vector3.ONE * (1.0 + u * 1.5) / maxf(size, 0.0001)
	_ring_material.albedo_color.a = 0.65 * (1.0 - u)
	_tag.modulate.a = 1.0 - u
	for part: GeometryInstance3D in _pivot.find_children("*", "GeometryInstance3D", true, false):
		part.transparency = u
	if u >= 1.0:
		get_parent().hide()
		_ring.scale = Vector3.ONE
		set_process(false)
