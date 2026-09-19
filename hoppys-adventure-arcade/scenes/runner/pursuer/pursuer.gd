extends Node3D
## The thing chasing Hoppy. Threat drives z between retreat_z and approach_z (contract §5.4).
## It listens to the pursuit signals itself: threat = 0.7 · min(t_since_hit / 1.5, 1)
## + 0.3 · (1 − remaining / total), smoothed so the approach glides instead of snapping.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const VISUAL_PATH := "res://scenes/runner/pursuer/pursuer_visual.tscn"
## Weights of the two threat terms (contract §7 Pursuer row).
const THREAT_TIME_WEIGHT := 0.7
const THREAT_RECOVERY_WEIGHT := 0.3
## Exponential follow rate toward the target threat, per second.
const THREAT_SMOOTHING := 4.0
## How far past the player the catch lunge reaches, in metres.
const CATCH_OVERSHOOT := 1.0

@onready var mount: Node3D = $Visual

var game: RunnerGame
var config: RunConfig
var visual: Node3D
var threat := 0.0
## Threat the pursuit signals ask for; `threat` chases it.
var target_threat := 0.0
var pursued := false
var catching := false
var catch_elapsed := 0.0
var catch_from_z := 12.0

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	_mount_visual()
	_connect(runner)
	reset()

## The pursuer reacts to the facade's own signals, so nothing else has to drive it.
func _connect(runner: RunnerGame) -> void:
	if not runner.pursuit_started.is_connected(_on_pursuit_started):
		runner.pursuit_started.connect(_on_pursuit_started)
	if not runner.pursuit_progress.is_connected(_on_pursuit_progress):
		runner.pursuit_progress.connect(_on_pursuit_progress)
	if not runner.pursuit_recovered.is_connected(_on_pursuit_recovered):
		runner.pursuit_recovered.connect(_on_pursuit_recovered)

func reset() -> void:
	threat = 0.0
	target_threat = 0.0
	pursued = false
	catching = false
	catch_elapsed = 0.0
	catch_from_z = retreat_z()
	visible = false
	_apply(0.0)

func retreat_z() -> float:
	return float(config.retreat_z) if config != null else 12.0

func approach_z() -> float:
	return float(config.approach_z) if config != null else 4.5

## 0 retreated .. 1 about to catch. Also the manual entry point for tests and the debug overlay.
func set_threat(value: float) -> void:
	target_threat = clampf(value, 0.0, 1.0)
	_apply(target_threat)

## Second hit while pursued: lunge at the player over the caught sequence. The threat goes to 1
## without _apply(), which would snap position.z to approach_z before the lunge even starts;
## _advance_catch() owns every move from here, starting at catch_from_z.
func catch() -> void:
	pursued = false
	catching = true
	catch_elapsed = 0.0
	catch_from_z = position.z
	threat = 1.0
	target_threat = 1.0
	visible = true
	if is_instance_valid(visual) and visual.has_method("set_threat"):
		visual.set_threat(1.0)
	if is_instance_valid(visual) and visual.has_method("play_catch"):
		visual.play_catch()

## Recovered: glide back to retreat_z.
func retreat() -> void:
	pursued = false
	catching = false
	target_threat = 0.0
	if is_instance_valid(visual) and visual.has_method("play_retreat"):
		visual.play_retreat()

func _on_pursuit_started(_recovery_seconds: float) -> void:
	pursued = true
	catching = false
	visible = true

func _on_pursuit_progress(remaining: float, total: float) -> void:
	if catching:
		return
	pursued = true
	visible = true
	var ramp := float(config.threat_ramp_seconds) if config != null else 1.5
	var since_hit := maxf(total - remaining, 0.0)
	var ramp_term := 1.0 if ramp <= 0.0 else minf(since_hit / ramp, 1.0)
	var recovery_term := 0.0 if total <= 0.0 else 1.0 - clampf(remaining / total, 0.0, 1.0)
	target_threat = clampf(THREAT_TIME_WEIGHT * ramp_term + THREAT_RECOVERY_WEIGHT * recovery_term, 0.0, 1.0)

func _on_pursuit_recovered(_reason: StringName) -> void:
	retreat()

func _physics_process(delta: float) -> void:
	if catching:
		_advance_catch(delta)
		return
	var next := lerpf(threat, target_threat, 1.0 - exp(-THREAT_SMOOTHING * delta))
	if target_threat <= 0.0 and next <= 0.001:
		next = 0.0
	# _apply forwards set_threat, so the visual hears from us every tick while it is on screen.
	if pursued or next > 0.0 or threat > 0.0:
		_apply(next)
	visible = pursued or threat > 0.0

## The catch cinematic: slide from wherever the pursuer is onto the player over the caught sequence.
func _advance_catch(delta: float) -> void:
	var span := float(config.caught_sequence_seconds) if config != null else 1.6
	catch_elapsed += delta
	var t := 1.0 if span <= 0.0 else clampf(catch_elapsed / span, 0.0, 1.0)
	var player_z := 0.0
	if game != null and is_instance_valid(game.player):
		player_z = game.player.global_position.z
	var target_z := player_z - CATCH_OVERSHOOT
	threat = 1.0
	position = Vector3(0.0, 0.0, lerpf(catch_from_z, target_z, smoothstep(0.0, 1.0, t)))
	if is_instance_valid(visual) and visual.has_method("set_threat"):
		visual.set_threat(1.0)

func _apply(value: float) -> void:
	threat = clampf(value, 0.0, 1.0)
	position = Vector3(0.0, 0.0, lerpf(retreat_z(), approach_z(), threat))
	if is_instance_valid(visual) and visual.has_method("set_threat"):
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
