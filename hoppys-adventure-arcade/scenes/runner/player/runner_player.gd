extends CharacterBody3D
## Lanes, jump, roll and hurtbox shapes (systems spec §3).
## PR 1 scaffold: state, the public API and the visual mount; movement lands in PR 2.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const VISUAL_PATH := "res://scenes/runner/player/hoppy_runner_visual.tscn"
## Lane 0/1/2 maps to x -2 / 0 / +2.
const LANE_COUNT := 3

@onready var body_shape: CollisionShape3D = $BodyShape
@onready var hurtbox: Area3D = $Hurtbox
@onready var stand_shape: CollisionShape3D = $Hurtbox/StandShape
@onready var roll_shape: CollisionShape3D = $Hurtbox/RollShape
@onready var mount: Node3D = $Visual

var game: RunnerGame
var config: RunConfig
var visual: Node3D
var controls_enabled := false
var lane := 1
var target_lane := 1
## 0..1 progress of the current lane tween.
var lane_t := 1.0
var lane_from_x := 0.0
var queued_lane_dir := 0
var is_rolling := false
var is_airborne := false
var roll_remaining := 0.0
var roll_cooldown_remaining := 0.0
var jump_buffer_remaining := 0.0
var coyote_remaining := 0.0
var fast_falling := false
var jumped_this_airtime := false
var anim_state: StringName = &"idle"
## Manual press-edge detection; is_action_just_pressed is fragile with injected test input.
var held := {&"jump": false, &"roll": false, &"left": false, &"right": false}

func _ready() -> void:
	add_to_group(&"runner_player")

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	_apply_body_metrics()
	_mount_visual()
	reset()

## Size the body and hurtbox capsules from the config, so a duplicated or overridden RunConfig
## drives the physics shapes as well as get_hurtbox_aabb(). Each shape is duplicated first: the
## .tscn sub-resources are shared between instances and must never be mutated.
func _apply_body_metrics() -> void:
	var radius := float(config.hurtbox_radius) if config != null else 0.4
	var stand := float(config.stand_height) if config != null else 1.8
	var roll := float(config.roll_height) if config != null else 0.9
	_size_capsule(body_shape, radius, stand)
	_size_capsule(stand_shape, radius, stand)
	_size_capsule(roll_shape, radius, roll)

## Feet stay at the node origin, so the capsule centre sits at half its height.
func _size_capsule(node: CollisionShape3D, radius: float, height: float) -> void:
	if node == null or not (node.shape is CapsuleShape3D):
		return
	var capsule := (node.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	node.shape = capsule
	node.position.y = capsule.height * 0.5

func reset() -> void:
	controls_enabled = false
	lane = 1
	target_lane = 1
	lane_t = 1.0
	lane_from_x = 0.0
	queued_lane_dir = 0
	is_rolling = false
	is_airborne = false
	roll_remaining = 0.0
	roll_cooldown_remaining = 0.0
	jump_buffer_remaining = 0.0
	coyote_remaining = 0.0
	fast_falling = false
	jumped_this_airtime = false
	velocity = Vector3.ZERO
	position = Vector3(lane_x(lane), 0.0, 0.0)
	_set_roll_shapes(false)
	sync_input_state()
	_set_anim_state(&"idle")

func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if enabled:
		sync_input_state()

## Copy the current pressed state into `held` so nothing fires on unpause.
func sync_input_state() -> void:
	held[&"jump"] = Input.is_action_pressed("jump") or Input.is_action_pressed("move_up")
	held[&"roll"] = Input.is_action_pressed("roll") or Input.is_action_pressed("move_down")
	held[&"left"] = Input.is_action_pressed("move_left")
	held[&"right"] = Input.is_action_pressed("move_right")

func request_jump() -> void:
	jump_buffer_remaining = float(config.jump_buffer) if config != null else 0.0

func request_roll() -> void:
	pass # PR 2: start the roll or buffer it for landing.

func request_lane(_direction: int) -> void:
	pass # PR 2: retarget the lane tween, queue one extra change, emit lane_left/right/blocked.

func play_hurt() -> void:
	_set_anim_state(&"hurt")
	if visual != null and visual.has_method("on_hit"):
		visual.on_hit()

func play_dead() -> void:
	_set_anim_state(&"dead")

## World x of a lane index.
func lane_x(index: int) -> float:
	var width := float(config.lane_width) if config != null else 2.0
	return (float(clampi(index, 0, LANE_COUNT - 1)) - 1.0) * width

## Axis-aligned bounds of the hurtbox capsule, feet at the player's y.
func get_hurtbox_aabb(standing := true) -> AABB:
	var radius := float(config.hurtbox_radius) if config != null else 0.4
	var height := float(config.stand_height) if config != null else 1.8
	if not standing:
		height = float(config.roll_height) if config != null else 0.9
	return AABB(global_position - Vector3(radius, 0.0, radius), Vector3(radius * 2.0, height, radius * 2.0))

func _set_roll_shapes(rolling: bool) -> void:
	if stand_shape != null:
		stand_shape.set_deferred("disabled", rolling)
	if roll_shape != null:
		roll_shape.set_deferred("disabled", not rolling)

func _set_anim_state(state: StringName) -> void:
	if anim_state == state:
		return
	anim_state = state
	if visual != null and visual.has_method("set_anim_state"):
		visual.set_anim_state(state)

func _physics_process(_delta: float) -> void:
	pass # PR 2: input, lane tween, gravity/jump, roll, move_and_slide, animation.

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
				push_warning("Runner player visual at %s root is %s, expected Node3D; using graybox" % [VISUAL_PATH, instance.get_class()])
				instance.queue_free()
	visual = _build_graybox()
	mount.add_child(visual)

## Contract §3: a mounted resource that fails to load or is not a PackedScene is warned about and
## the code-built graybox is used instead.
func _load_scene(path: String) -> PackedScene:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Runner player visual at %s is not a PackedScene; using graybox" % path)
	return scene

## Capsule plus two ears so graybox testers can still read Hoppy's facing and pose.
func _build_graybox() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Graybox"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("fff0d3")
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	body.mesh = capsule
	body.position = Vector3(0.0, 0.9, 0.0)
	body.material_override = material
	holder.add_child(body)
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.14, 0.5, 0.14)
		ear.mesh = box
		ear.position = Vector3(0.16 * side, 1.95, -0.05)
		ear.material_override = material
		holder.add_child(ear)
	return holder
