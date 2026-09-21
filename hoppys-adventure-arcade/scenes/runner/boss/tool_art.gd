extends Node3D
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
var clock := 0.0
var collected := false
var pivot: Node3D

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func build(kind: StringName) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	pivot = Node3D.new()
	add_child(pivot)
	var ring := Art.torus(pivot, 0.35, Palette.ORANGE)
	ring.position = Vector3.ZERO
	var builder := Art.new()
	pivot.add_child(builder)
	var poses: Array[Transform3D] = []
	match kind:
		&"review_comment":
			Art.box(pivot, Vector3.ZERO, Vector3(0.48, 0.32, 0.14), Palette.MATRIX)
			Art.box(pivot, Vector3(-0.12, -0.19, 0), Vector3(0.12, 0.12, 0.1), Palette.MATRIX).rotation.z = 0.4
			Art.label(pivot, "//", Vector3(0, 0, 0.09), 0.004)
		&"lint_rule":
			for i in 5: poses.append(Art.pose(Vector3((i - 2) * 0.09, 0.02, 0), Vector3(0.035, 0.34, 0.08)))
			builder.batch(poses, Palette.ORANGE)
			Art.box(pivot, Vector3(0, -0.17, 0), Vector3(0.44, 0.06, 0.1), Palette.MATRIX)
		&"unit_test":
			for side in [-1, 1]:
				poses.append(Art.pose(Vector3(side * 0.23, 0, 0), Vector3(0.035, 0.46, 0.04)))
				poses.append(Art.pose(Vector3(0, side * 0.23, 0), Vector3(0.46, 0.035, 0.04)))
			builder.batch(poses, Palette.CREAM)
			Art.box(pivot, Vector3(-0.06, -0.04, 0.04), Vector3(0.15, 0.045, 0.05), Palette.MATRIX).rotation.z = -0.7
			Art.box(pivot, Vector3(0.07, 0.02, 0.04), Vector3(0.26, 0.045, 0.05), Palette.MATRIX).rotation.z = 0.8
		&"auto_fix_patch":
			for x in [-0.12, 0.12]:
				for side in [-1, 1]:
					poses.append(Transform3D(Basis(Vector3.BACK, side * -0.75).scaled_local(Vector3(0.22, 0.065, 0.09)), Vector3(x, side * 0.085, 0)))
			builder.batch(poses, Palette.MATRIX)
			Art.box(pivot, Vector3(0, 0, 0.08), Vector3(0.05, 0.25, 0.035), Palette.CREAM).rotation.z = -0.4
	var tags := {&"review_comment": "REVIEW COMMENT", &"lint_rule": "LINT", &"unit_test": "UNIT TEST", &"auto_fix_patch": "AUTO-FIX"}
	Art.label(self, tags.get(kind, "TOOL"), Vector3(0, 0.6, 0), 0.009)

func reset() -> void:
	clock = 0.0
	collected = false
	show()
	pivot.transform = Transform3D.IDENTITY

func collect() -> void:
	collected = true
	hide()

func _process(delta: float) -> void:
	if collected or pivot == null: return
	clock += delta
	pivot.position.y = sin(clock * PI) * 0.06
	pivot.position.z = -0.025 * (1 - cos(clock * PI))
	pivot.scale = Vector3.ONE * (0.97 + 0.03 * sin(clock * PI))
