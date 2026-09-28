extends MultiMeshInstance3D
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
var direction := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var bar := BoxMesh.new()
	bar.size = Vector3(0.65, 0.015, 0.10)
	multimesh.mesh = bar
	multimesh.instance_count = 18
	material_override = Materials.additive(Palette.ORANGE, 0.85).duplicate()
	clear()

func announce(value: int) -> void:
	direction = signi(value)
	for lane in 3:
		for row in 3:
			for side in 2:
				var z := float(side * 2 - 1)
				var basis := Basis(Vector3.UP, float(direction) * z * PI / 4.0)
				multimesh.set_instance_transform(lane * 6 + row * 2 + side, Transform3D(basis, Vector3((lane - 1) * 2.0, 0.035, -5.0 - row * 5.0 + z * 0.22)))
	show()

func clear() -> void:
	direction = 0
	hide()
