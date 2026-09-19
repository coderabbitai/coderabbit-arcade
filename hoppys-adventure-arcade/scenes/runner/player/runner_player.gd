extends CharacterBody3D
## Lanes, jump, roll and hurtbox shapes (systems spec §3). The player never moves in Z; the corridor
## comes to it. Everything is driven from _physics_process in the order input → lanes → gravity/jump
## → roll → move_and_slide → animation.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const VISUAL_PATH := "res://scenes/runner/player/hoppy_runner_visual.tscn"
## Lane 0/1/2 maps to x -2 / 0 / +2.
const LANE_COUNT := 3
## Invulnerability source the Super Jump registers with the HitManager (contract §4.1 reasons).
const SUPER_JUMP_SOURCE := &"super_jump"
## The only auras the player visual knows about (contract §5.1 show_aura).
const AURA_KINDS: Array[StringName] = [&"lgtm", &"nitro", &"code_review"]
## Dodge hints whose hazard the standing capsule does not fit under.
const ROLL_HINTS: Array[StringName] = [&"ROLL", &"ROLL_OR_JUMP"]
## How long the hurt pose holds before the normal state selection takes over again.
const HURT_ANIM_SECONDS := 0.25
## Small downward bias while grounded so move_and_slide keeps floor contact.
const GROUND_STICK_SPEED := 2.0
## Clearance margin in front of the standing capsule, on top of two ticks of corridor travel.
const CLEARANCE_MARGIN := 0.3
## Graybox tint per animation state, so a run with no frontend visual still reads the pose.
const GRAYBOX_TINTS := {
	&"idle": Color("fff0d3"),
	&"run": Color("fff0d3"),
	&"jump": Color("79e0c4"),
	&"fall": Color("6ab7ff"),
	&"roll": Color("ffd75e"),
	&"hurt": Color("ff7185"),
	&"dead": Color("59121f")
}

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

## Floor contact as of the end of the previous tick; move_and_slide only refreshes is_on_floor().
var _on_floor := true
## A roll pressed in the air fires when the feet touch down again.
var _roll_buffered := false
## Lean value last pushed to the visual, so set_lane_lean is only called on change.
var _lane_lean := 0.0
var _hurt_remaining := 0.0
var _dead := false
## Super Jump invulnerability: live in flight, then super_jump_landing_invuln seconds after landing.
var _super_jump_invuln := false
var _super_jump_invuln_remaining := 0.0
## Set only when the code-built graybox stands in for the frontend visual.
var _graybox_material: StandardMaterial3D

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
	_on_floor = true
	_roll_buffered = false
	_hurt_remaining = 0.0
	_dead = false
	_clear_super_jump_invuln()
	_set_roll_shapes(false)
	_set_lane_lean(0.0)
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

## Buffer a jump: it fires as soon as the player is grounded (or inside the coyote window).
func request_jump() -> void:
	jump_buffer_remaining = float(config.jump_buffer) if config != null else 0.0

## On the floor: roll now. In the air: fast-fall and roll on touchdown (systems spec §3.3).
func request_roll() -> void:
	if not _on_floor:
		fast_falling = true
		_roll_buffered = true
		return
	_start_roll()

## Retarget the lane tween. A direction pressed mid-tween is queued (one extra change only).
func request_lane(direction: int) -> void:
	if direction == 0:
		return
	var dir := signi(direction)
	if lane_t < 1.0:
		queued_lane_dir = dir
		return
	_start_lane_change(dir)

func play_hurt() -> void:
	_hurt_remaining = HURT_ANIM_SECONDS
	_set_anim_state(&"hurt")
	_emit_action(&"hurt")
	if is_instance_valid(visual) and visual.has_method("on_hit"):
		visual.on_hit()

func play_dead() -> void:
	_dead = true
	_set_anim_state(&"dead")
	_emit_action(&"dead")

## Power-up aura forwarding (contract §5.1). RunnerGame calls this from power_up_collected/expired.
func apply_aura(kind: StringName, on: bool) -> void:
	if not AURA_KINDS.has(kind):
		return
	if is_instance_valid(visual) and visual.has_method("show_aura"):
		visual.show_aura(kind, on)

## Approve Shield stored or consumed; RunnerGame calls this from shield_changed.
func apply_shield(on: bool) -> void:
	if is_instance_valid(visual) and visual.has_method("show_shield"):
		visual.show_shield(on)

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

func _physics_process(delta: float) -> void:
	_read_input()
	_update_lane(delta)
	_update_jump(delta)
	_update_roll(delta)
	var was_grounded := _on_floor
	velocity.z = 0.0
	move_and_slide()
	_on_floor = is_on_floor()
	is_airborne = not _on_floor
	if _on_floor and not was_grounded:
		_on_land()
	_update_super_jump_invuln(delta)
	_update_anim(delta)

# --- 1. input -----------------------------------------------------------------------------------

## Manual press-edge detection (systems spec §3.1): is_action_just_pressed drops injected events.
func _read_input() -> void:
	if not controls_enabled or game == null or game.state != &"running":
		return
	var jump_pressed := Input.is_action_pressed("jump") or Input.is_action_pressed("move_up")
	if jump_pressed and not held[&"jump"]:
		request_jump()
	held[&"jump"] = jump_pressed
	var roll_pressed := Input.is_action_pressed("roll") or Input.is_action_pressed("move_down")
	if roll_pressed and not held[&"roll"]:
		request_roll()
	held[&"roll"] = roll_pressed
	var left_pressed := Input.is_action_pressed("move_left")
	if left_pressed and not held[&"left"]:
		request_lane(-1)
	held[&"left"] = left_pressed
	var right_pressed := Input.is_action_pressed("move_right")
	if right_pressed and not held[&"right"]:
		request_lane(1)
	held[&"right"] = right_pressed

# --- 2. lanes -----------------------------------------------------------------------------------

func _start_lane_change(direction: int) -> void:
	var next := clampi(target_lane + direction, 0, LANE_COUNT - 1)
	if next == target_lane:
		_emit_action(&"lane_blocked")
		return
	lane = target_lane
	target_lane = next
	lane_from_x = position.x
	lane_t = 0.0
	_emit_action(&"lane_right" if direction > 0 else &"lane_left")

## Ease-out interpolation over lane_change_time, driven through velocity so move_and_slide still
## resolves collisions. velocity.x is a correction term, not a free-running speed.
func _update_lane(delta: float) -> void:
	if lane_t >= 1.0 and queued_lane_dir != 0:
		var queued := queued_lane_dir
		queued_lane_dir = 0
		_start_lane_change(queued)
	var target_x := lane_x(target_lane)
	var desired := target_x
	if lane_t < 1.0:
		var span := float(config.lane_change_time) if config != null else 0.13
		lane_t = 1.0 if span <= 0.0 else minf(lane_t + delta / span, 1.0)
		desired = lerpf(lane_from_x, target_x, 1.0 - pow(1.0 - lane_t, 3.0))
		_set_lane_lean(signf(target_x - lane_from_x))
		if lane_t >= 1.0:
			lane = target_lane
			_set_lane_lean(0.0)
	else:
		_set_lane_lean(0.0)
	velocity.x = (desired - position.x) / delta if delta > 0.0 else 0.0

func _set_lane_lean(value: float) -> void:
	if is_equal_approx(_lane_lean, value):
		return
	_lane_lean = value
	if is_instance_valid(visual) and visual.has_method("set_lane_lean"):
		visual.set_lane_lean(value)

# --- 3. gravity and jump ------------------------------------------------------------------------

func _update_jump(delta: float) -> void:
	var gravity := float(config.gravity) if config != null else 28.0
	var fast_fall := float(config.fast_fall_multiplier) if config != null else 2.5
	if _on_floor:
		coyote_remaining = float(config.coyote_time) if config != null else 0.06
		jumped_this_airtime = false
		fast_falling = false
		# A small downward bias keeps the capsule in contact so is_on_floor() stays true.
		velocity.y = -GROUND_STICK_SPEED
	else:
		coyote_remaining = maxf(coyote_remaining - delta, 0.0)
		velocity.y -= gravity * (fast_fall if fast_falling else 1.0) * delta
	# The buffer is tested before it is aged, so a request made on this tick still gets the whole
	# jump_buffer window (0.10 s = six chances at 60 Hz) instead of losing its first tick.
	# A roll commits for roll_duration: the buffered jump simply expires while it runs.
	var can_jump := not jumped_this_airtime and not is_rolling and (_on_floor or coyote_remaining > 0.0)
	if jump_buffer_remaining > 0.0 and can_jump:
		_do_jump(delta)
	else:
		jump_buffer_remaining = maxf(jump_buffer_remaining - delta, 0.0)

## Launch. Gravity is applied on this tick as well, as a half step: with the full step taken on
## every later tick the discrete arc is exactly the contract's y(t) = 9.8 t - 14 t^2 (apex 1.715 m
## at 0.35 s, airtime 0.70 s). Skipping it here overshoots by half a tick of gravity.
func _do_jump(delta: float) -> void:
	jump_buffer_remaining = 0.0
	coyote_remaining = 0.0
	jumped_this_airtime = true
	fast_falling = false
	_on_floor = false
	is_airborne = true
	var super_jump := false
	var effects := game.effect_manager if game != null else null
	if effects != null and effects.has_method("consume_super_jump"):
		super_jump = bool(effects.consume_super_jump())
	var jump_velocity := float(config.jump_velocity) if config != null else 9.8
	if super_jump:
		jump_velocity = float(config.super_jump_velocity) if config != null else 13.2
	var gravity := float(config.gravity) if config != null else 28.0
	velocity.y = jump_velocity - gravity * delta * 0.5
	_emit_action(&"jump")
	if super_jump:
		_emit_action(&"super_jump")
		_grant_super_jump_invuln()

func _on_land() -> void:
	fast_falling = false
	jumped_this_airtime = false
	_emit_action(&"land")
	if _super_jump_invuln:
		_super_jump_invuln_remaining = float(config.super_jump_landing_invuln) if config != null else 0.5
	if _roll_buffered:
		_roll_buffered = false
		_start_roll()

# --- 4. roll ------------------------------------------------------------------------------------

func _start_roll() -> void:
	if is_rolling or roll_cooldown_remaining > 0.0 or not _on_floor:
		return
	is_rolling = true
	roll_remaining = float(config.roll_duration) if config != null else 0.7
	_set_roll_shapes(true)
	_emit_action(&"roll")

func _update_roll(delta: float) -> void:
	roll_cooldown_remaining = maxf(roll_cooldown_remaining - delta, 0.0)
	if not is_rolling:
		return
	roll_remaining = maxf(roll_remaining - delta, 0.0)
	if roll_remaining > 0.0:
		return
	# Out of roll time but still under something: stay crouched and retry next tick.
	if not _has_standing_clearance():
		return
	is_rolling = false
	roll_cooldown_remaining = float(config.roll_cooldown) if config != null else 0.25
	_set_roll_shapes(false)
	_emit_action(&"roll_end")

## True when the standing capsule, grown two ticks of corridor travel toward -Z, touches no hazard
## that has to be rolled under (systems spec §3.4).
func _has_standing_clearance() -> bool:
	var tree := get_tree()
	if tree == null:
		return true
	var bounds := get_hurtbox_aabb(true)
	var reach := (float(game.speed) if game != null else 0.0) * 2.0 / 60.0 + CLEARANCE_MARGIN
	bounds.position.z -= reach
	bounds.size.z += reach
	for node in tree.get_nodes_in_group(&"runner_hazards"):
		if not is_instance_valid(node):
			continue
		if not (node.has_method("is_blocking") and node.is_blocking()):
			continue
		if not node.has_method("get_world_aabb") or not _requires_rolling(node):
			continue
		if bounds.intersects(node.get_world_aabb()):
			return false
	return true

## A hazard that only the rolling capsule clears: the ROLL hints, or a timed laser in its high state.
func _requires_rolling(hazard: Node) -> bool:
	if not (&"dodge_hint" in hazard):
		return false
	var hint: StringName = hazard.get(&"dodge_hint")
	if ROLL_HINTS.has(hint):
		return true
	if hint != &"TIMED" or not (&"laser_state" in hazard):
		return false
	var laser: StringName = hazard.get(&"laser_state")
	return laser == &"high"

func _set_roll_shapes(rolling: bool) -> void:
	# Deferred: this runs inside the physics step, where shape toggles are not allowed directly.
	if stand_shape != null:
		stand_shape.set_deferred("disabled", rolling)
	if roll_shape != null:
		roll_shape.set_deferred("disabled", not rolling)

# --- 5. Super Jump invulnerability --------------------------------------------------------------

func _grant_super_jump_invuln() -> void:
	if _super_jump_invuln:
		return
	_super_jump_invuln = true
	_super_jump_invuln_remaining = 0.0
	_call_hit_manager(&"add_invulnerability")

func _update_super_jump_invuln(delta: float) -> void:
	if not _super_jump_invuln or _super_jump_invuln_remaining <= 0.0:
		return
	_super_jump_invuln_remaining = maxf(_super_jump_invuln_remaining - delta, 0.0)
	if _super_jump_invuln_remaining <= 0.0:
		_clear_super_jump_invuln()

func _clear_super_jump_invuln() -> void:
	if not _super_jump_invuln:
		return
	_super_jump_invuln = false
	_super_jump_invuln_remaining = 0.0
	_call_hit_manager(&"remove_invulnerability")

## The HitManager owns the invulnerability set (systems spec §4): Super Jump adds and removes
## itself as one named source.
func _call_hit_manager(method: StringName) -> void:
	var manager := game.hit_manager if game != null else null
	if manager == null or not is_instance_valid(manager) or not manager.has_method(method):
		return
	manager.call(method, SUPER_JUMP_SOURCE)

# --- 6. animation -------------------------------------------------------------------------------

func _update_anim(delta: float) -> void:
	if is_instance_valid(visual) and visual.has_method("set_run_speed") and game != null:
		visual.set_run_speed(float(game.normalized_speed))
	if _dead:
		return
	if _hurt_remaining > 0.0:
		_hurt_remaining = maxf(_hurt_remaining - delta, 0.0)
		return
	var next: StringName = &"run"
	if is_rolling:
		next = &"roll"
	elif is_airborne:
		next = &"jump" if velocity.y > 0.0 else &"fall"
	_set_anim_state(next)

func _set_anim_state(state: StringName) -> void:
	if anim_state == state:
		return
	anim_state = state
	if is_instance_valid(visual) and visual.has_method("set_anim_state"):
		visual.set_anim_state(state)
	# With no frontend visual the graybox tint is the only readable pose feedback (systems spec §3).
	if _graybox_material != null:
		_graybox_material.albedo_color = GRAYBOX_TINTS.get(state, GRAYBOX_TINTS[&"run"])

func _emit_action(action: StringName) -> void:
	if game != null:
		game.player_action.emit(action)

# --- visual mount -------------------------------------------------------------------------------

func _mount_visual() -> void:
	if mount == null:
		return
	for child in mount.get_children():
		child.queue_free()
	visual = null
	_graybox_material = null
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
	material.albedo_color = GRAYBOX_TINTS[&"run"]
	_graybox_material = material
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
