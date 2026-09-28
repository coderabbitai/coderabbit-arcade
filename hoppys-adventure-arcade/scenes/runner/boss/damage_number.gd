extends Node3D
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
var active := false
var age := 0.0
var tag: Label3D
var sparks: Art
var amount := 0
var backing: MeshInstance3D
var spark_material: ShaderMaterial

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	tag = Art.label(self, "", Vector3.ZERO, 0.008)
	backing = Art.box(self, Vector3(0, 0, -0.07), Vector3(2.3, 0.58, 0.1), Palette.NAVY_2)
	tag.font_size = 56
	tag.outline_modulate = Palette.DANGER
	sparks = Art.new()
	add_child(sparks)
	var poses: Array[Transform3D] = []
	for i in 20: poses.append(Art.pose(Vector3.ZERO, Vector3.ONE * 0.04))
	var emitter := sparks.batch(poses, Palette.MATRIX)
	spark_material = ShaderMaterial.new()
	spark_material.shader = preload("res://scenes/runner/boss/hifi/screen.gdshader")
	spark_material.set_shader_parameter("glyph_grid", Vector2(2, 2))
	emitter.material_override = spark_material
	hide()

func start(point: Vector3, damage: int, color: Color, offset: float) -> void:
	position = point + Vector3(offset, 0, 0)
	amount = damage
	age = 0.0
	active = true
	if get_parent().has_method("limit_numbers"): get_parent().limit_numbers(self)
	tag.text = "RESISTED" if damage == 0 else "-%d" % damage
	tag.modulate = Palette.SLATE if damage == 0 else Palette.CREAM
	tag.outline_modulate = Palette.NAVY_BG if damage == 0 else Palette.DANGER
	sparks.visible = damage > 0
	sparks.batches[0].color = color
	spark_material.set_shader_parameter("accent", color)
	show()
	_process(0.0)

func clear() -> void:
	active = false
	hide()

func _process(delta: float) -> void:
	if not active: return
	age += delta
	spark_material.set_shader_parameter("clock", age)
	var u := minf(age / 0.7, 1)
	tag.position.y = u * 1.1
	backing.position.y = tag.position.y
	backing.scale = Vector3.ONE * maxf(1.0 - u, 0.001)
	tag.modulate.a = 1 - u
	var entry: Dictionary = sparks.batches[0]
	for i in 20:
		var pose := Art.pose(Vector3(sin(i * 2.4), cos(i * 1.7), sin(i * 0.7)) * age * 1.7 + Vector3.DOWN * age * age, Vector3(0.025, 0.025, 0.14) * (1 - u))
		entry.poses[i] = pose
		entry.node.multimesh.set_instance_transform(i, pose)
		entry.node.multimesh.set_instance_color(i, entry.color)
	if u >= 1: clear()
