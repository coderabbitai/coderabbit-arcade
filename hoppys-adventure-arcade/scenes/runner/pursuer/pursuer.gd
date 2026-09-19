extends Node3D
## The thing chasing Hoppy. Threat drives z between retreat_z and approach_z (contract §5.4).

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const VISUAL_PATH := "res://scenes/runner/pursuer/pursuer_visual.tscn"

@onready var mount: Node3D = $Visual

var game: RunnerGame
var config: RunConfig
var visual: Node3D
var threat := 0.0

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	_mount_visual()
	reset()

func reset() -> void:
	threat = 0.0
	_apply(0.0)

## 0 retreated .. 1 about to catch.
func set_threat(value: float) -> void:
	_apply(clampf(value, 0.0, 1.0))

func catch() -> void:
	_apply(1.0)
	if visual != null and visual.has_method("play_catch"):
		visual.play_catch()

func retreat() -> void:
	_apply(0.0)
	if visual != null and visual.has_method("play_retreat"):
		visual.play_retreat()

func _apply(value: float) -> void:
	threat = value
	var far := float(config.retreat_z) if config != null else 12.0
	var near := float(config.approach_z) if config != null else 4.5
	position = Vector3(0.0, 0.0, lerpf(far, near, threat))
	if visual != null and visual.has_method("set_threat"):
		visual.set_threat(threat)

func _mount_visual() -> void:
	if mount == null:
		return
	for child in mount.get_children():
		child.queue_free()
	visual = null
	if ResourceLoader.exists(VISUAL_PATH):
		var scene := _load_scene(VISUAL_PATH)
		if scene != null:
			var instance := scene.instantiate()
			if instance is Node3D:
				visual = instance
				mount.add_child(visual)
				return
			if instance != null:
				push_warning("Runner pursuer visual at %s root is %s, expected Node3D; using graybox" % [VISUAL_PATH, instance.get_class()])
				instance.queue_free()
	visual = _build_graybox()
	mount.add_child(visual)

## Contract §3: a mounted resource that fails to load or is not a PackedScene is warned about and
## the code-built graybox is used instead.
func _load_scene(path: String) -> PackedScene:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Runner pursuer visual at %s is not a PackedScene; using graybox" % path)
	return scene

## Code-built stand-in so the pursuer is visible with no frontend art.
func _build_graybox() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Graybox"
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.0, 2.4, 1.2)
	mesh.mesh = box
	mesh.position = Vector3(0.0, 1.2, 0.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("59121f")
	mesh.material_override = material
	holder.add_child(mesh)
	return holder
