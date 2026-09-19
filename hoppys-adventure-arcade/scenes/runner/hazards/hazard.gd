extends Area3D
## One hit-once hazard hitbox plus its visual mount (systems spec §5.3).
## Static from spawn, except the timed laser, which switches between discrete states with the
## hitbox off in between (contract §8).

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")
const RunnerLayers = preload("res://scenes/runner/runner_layers.gd")
const VISUAL_DIR := "res://scenes/runner/hazards/visuals/"
## Fallbacks until setup() supplies the config (contract §7, lanes and body).
const DEFAULT_HURTBOX_RADIUS := 0.4
const DEFAULT_LANE_WIDTH := 2.0
## Tolerance so a hazard that only just reaches a lane boundary does not claim that lane.
const LANE_REACH_EPSILON := 0.01
const OFF_STATE: StringName = &"off"
## Graybox tint per kind, so a run with no frontend art still reads. Cosmetic only.
const GRAYBOX_COLORS := {
	&"pr_backlog_low": Color("c8354b"),
	&"pr_backlog_high": Color("e0624f"),
	&"bug_swarm": Color("8fd14f"),
	&"merge_conflict": Color("d46ad4"),
	&"deprecated_pit": Color("2b2f45"),
	&"laser_grid": Color("ff4d6d"),
	&"comment_flood": Color("f0a202"),
	&"build_shockwave": Color("ff8c42")
}
const GRAYBOX_DEFAULT_COLOR := Color("c8354b")

@export var kind: StringName = &"pr_backlog_low"
@export var variant: StringName = &""

var game: RunnerGame
var config: RunConfig
var visual: Node3D
var def := {}
var shape_node: CollisionShape3D
var box: BoxShape3D
var dodge_hint: StringName = &""
var consumed := false
var active := true
## ground / high / off for a timed laser; empty for every other hazard.
var laser_state: StringName = &""

## The y range (min, max) the hitbox currently occupies. A timed laser swaps it per state; every
## other hazard keeps the contract §8 range for its whole life.
var _bounds := Vector2.ZERO
var _timed := false
var _graybox: MeshInstance3D
var _graybox_box: BoxMesh

func _ready() -> void:
	collision_layer = RunnerLayers.ENEMY_HITBOX
	collision_mask = RunnerLayers.PLAYER_HURTBOX
	monitoring = true
	monitorable = false
	add_to_group(&"runner_hazards")
	def = HazardDefs.get_def(kind, variant)
	dodge_hint = def.get("dodge_hint", &"")
	_timed = HazardDefs.is_timed(def)
	_bounds = Vector2(float(def.get("y_min", 0.0)), float(def.get("y_max", 0.0)))
	_build_shape()
	_mount_visual()
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	# Only the timed laser needs a per-tick state machine.
	set_physics_process(_timed)

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config

## Still able to damage the player. A timed laser in `off` is still blocking: it will switch back
## on, and Auto-Fix has to be able to remove it.
func is_blocking() -> bool:
	return active and not consumed

## True for the sweeping scanner (laser_grid / timed), which owns `laser_state`.
func is_timed() -> bool:
	return _timed

## World x of lane index 0/1/2 (-lane_width / 0 / +lane_width).
func lane_x(index: int) -> float:
	var width := float(config.lane_width) if config != null else DEFAULT_LANE_WIDTH
	return (float(index) - 1.0) * width

## Lane index 0/1/2 this hitbox can touch: the hazard's x extent against the player's capsule
## radius in that lane (contract §8, systems spec §1). Global x, because a hazard lives inside a
## chunk the spawner places and may mirror.
func occupies_lane(index: int) -> bool:
	var half_width := float(config.hurtbox_radius) if config != null else DEFAULT_HURTBOX_RADIUS
	var reach := hitbox_size().x * 0.5 + half_width - LANE_REACH_EPSILON
	return absf(lane_x(index) - global_position.x) < reach

func lanes_mask() -> int:
	var mask := 0
	for index in 3:
		if occupies_lane(index):
			mask |= 1 << index
	return mask

func hitbox_size() -> Vector3:
	var size: Vector3 = def.get("size", Vector3.ONE)
	if _timed:
		size.y = maxf(_bounds.y - _bounds.x, 0.0)
	return size

func hitbox_offset() -> Vector3:
	return Vector3(0.0, (_bounds.x + _bounds.y) * 0.5, 0.0)

func get_world_aabb() -> AABB:
	var size := hitbox_size()
	return AABB(global_position + hitbox_offset() - size * 0.5, size)

## `_player` is unused: HitManager resolves everything from the hazard itself.
func hit_player(_player: Node) -> void:
	if consumed or not active:
		return
	consumed = true
	set_deferred(&"monitoring", false)
	if game != null and game.hit_manager != null:
		game.hit_manager.report_hit(self)
	if is_instance_valid(visual) and visual.has_method("on_hit_player"):
		visual.on_hit_player()

## Auto-Fix removed this hazard.
func clear() -> void:
	if not active:
		return
	consumed = true
	active = false
	set_deferred(&"monitoring", false)
	remove_from_group(&"runner_hazards")
	if is_instance_valid(visual) and visual.has_method("on_cleared"):
		visual.on_cleared()
	elif is_instance_valid(visual):
		# A frontend visual without on_cleared still has to stop being on screen.
		visual.hide()
	elif _graybox != null:
		_graybox.hide()

func _on_area_entered(area: Area3D) -> void:
	var owner_node := area.get_parent()
	if owner_node != null and owner_node.is_in_group(&"runner_player"):
		hit_player(owner_node)

func _build_shape() -> void:
	box = BoxShape3D.new()
	box.size = hitbox_size()
	shape_node = CollisionShape3D.new()
	shape_node.name = "Shape"
	shape_node.shape = box
	shape_node.position = hitbox_offset()
	add_child(shape_node)

## Timed laser only (systems spec §5.3): ground 1.2 s -> off 0.3 s -> high 1.2 s -> off 0.3 s,
## phased off the run clock so the cycle is deterministic per seed. `monitoring` is driven from
## here and never from an area callback.
func _physics_process(_delta: float) -> void:
	if not _timed:
		return
	var period := maxf(float(def.get("period", 3.0)), 0.0001)
	var run_time := float(game.elapsed) if game != null else 0.0
	var phase := fposmod(run_time, period)
	var slot := _timed_slot(phase)
	var next_state: StringName = slot.get("state", OFF_STATE)
	if next_state != laser_state:
		laser_state = next_state
		_apply_laser_state()
		if is_instance_valid(visual) and visual.has_method("set_laser_state"):
			visual.set_laser_state(laser_state)
	var want := laser_state != OFF_STATE and is_blocking()
	if monitoring != want:
		# Safe here: _physics_process runs outside the physics query flush, unlike area callbacks.
		monitoring = want
	if is_instance_valid(visual) and visual.has_method("set_telegraph"):
		visual.set_telegraph(_telegraph_at(phase, float(slot.get("ends_at", phase))))

## The cycle slot covering `phase`: its state and the phase time it ends at.
func _timed_slot(phase: float) -> Dictionary:
	var states: Array = def.get("states", [])
	if states.is_empty():
		return {"state": OFF_STATE, "ends_at": phase}
	var on_seconds := float(def.get("on_seconds", 1.2))
	var off_seconds := float(def.get("off_seconds", 0.3))
	var cursor := 0.0
	for state in states:
		var span := off_seconds if state == OFF_STATE else on_seconds
		cursor += span
		if phase < cursor:
			return {"state": state, "ends_at": cursor}
	# Rounding tail: the last slot owns whatever is left of the period.
	return {"state": states[states.size() - 1], "ends_at": cursor}

## 0 -> 1 over the telegraph window before the next state change (contract §5.2).
func _telegraph_at(phase: float, ends_at: float) -> float:
	var window := float(def.get("telegraph_seconds", 0.4))
	if window <= 0.0:
		return 0.0
	return clampf(1.0 - (ends_at - phase) / window, 0.0, 1.0)

## Move the hitbox (and the graybox) to the row the current state occupies. `off` keeps the last
## row so get_world_aabb() stays meaningful for the bot and the chunk validator.
func _apply_laser_state() -> void:
	var state_bounds: Dictionary = def.get("state_bounds", {})
	if state_bounds.has(laser_state):
		var row: Vector2 = state_bounds[laser_state]
		_bounds = row
	if box != null:
		box.size = hitbox_size()
	if shape_node != null:
		shape_node.position = hitbox_offset()
	if _graybox == null:
		return
	if _graybox_box != null:
		_graybox_box.size = hitbox_size()
	_graybox.position = hitbox_offset()
	_graybox.visible = laser_state != OFF_STATE

func _mount_visual() -> void:
	var path := VISUAL_DIR + String(kind) + "_visual.tscn"
	if ResourceLoader.exists(path):
		var scene := _load_scene(path)
		if scene != null:
			var instance := scene.instantiate()
			if instance is Node3D:
				visual = instance
				add_child(visual)
				_apply_visual_vars()
				if visual.has_method("on_spawned"):
					visual.on_spawned()
				return
			if instance != null:
				push_warning("Runner hazard visual at %s root is %s, expected Node3D; using graybox" % [path, instance.get_class()])
				instance.queue_free()
	_graybox = _build_graybox()
	visual = _graybox
	add_child(visual)

## Contract §3: a mounted resource that fails to load or is not a PackedScene is warned about and
## the code-built graybox is used instead.
func _load_scene(path: String) -> PackedScene:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Runner hazard visual at %s is not a PackedScene; using graybox" % path)
	return scene

## The base vars from contract §5.2, set before on_spawned(). A visual that does not extend
## hazard_visual_base.gd simply does not receive them.
func _apply_visual_vars() -> void:
	var values := {
		&"kind": kind,
		&"variant": variant,
		&"hitbox_size": hitbox_size(),
		&"hitbox_offset": hitbox_offset(),
		&"lanes_mask": lanes_mask(),
		&"dodge_hint": dodge_hint
	}
	for key in values:
		if key in visual:
			visual.set(key, values[key])

## Box of exactly the hitbox size, tinted per kind, so graybox play reads honestly.
func _build_graybox() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = "Graybox"
	_graybox_box = BoxMesh.new()
	_graybox_box.size = hitbox_size()
	mesh.mesh = _graybox_box
	mesh.position = hitbox_offset()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = GRAYBOX_COLORS.get(kind, GRAYBOX_DEFAULT_COLOR)
	mesh.material_override = material
	return mesh
