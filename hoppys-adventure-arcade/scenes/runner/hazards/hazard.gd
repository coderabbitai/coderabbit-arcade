extends Area3D
## One hit-once hazard hitbox plus its visual mount (systems spec §5.3).
## PR 1 scaffold: layers, hitbox, group, visual mount; timed lasers land in PR 2.

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
var laser_state: StringName = &""

func _ready() -> void:
	collision_layer = RunnerLayers.ENEMY_HITBOX
	collision_mask = RunnerLayers.PLAYER_HURTBOX
	monitoring = true
	monitorable = false
	add_to_group(&"runner_hazards")
	def = HazardDefs.get_def(kind, variant)
	dodge_hint = def.get("dodge_hint", &"")
	_build_shape()
	_mount_visual()
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config

## Still able to damage the player.
func is_blocking() -> bool:
	return active and not consumed

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
	return def.get("size", Vector3.ONE)

func hitbox_offset() -> Vector3:
	return Vector3(0.0, HazardDefs.center_y(def), 0.0)

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
	if visual != null and visual.has_method("on_hit_player"):
		visual.on_hit_player()

## Auto-Fix removed this hazard.
func clear() -> void:
	if not active:
		return
	consumed = true
	active = false
	set_deferred(&"monitoring", false)
	remove_from_group(&"runner_hazards")
	if visual != null and visual.has_method("on_cleared"):
		visual.on_cleared()

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

func _physics_process(_delta: float) -> void:
	pass # PR 2: timed laser state machine (ground 1.2 / off 0.3 / high 1.2 / off 0.3).

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
	visual = _build_graybox()
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

## Red box of exactly the hitbox size, so graybox play reads honestly.
func _build_graybox() -> Node3D:
	var mesh := MeshInstance3D.new()
	mesh.name = "Graybox"
	var box_mesh := BoxMesh.new()
	box_mesh.size = hitbox_size()
	mesh.mesh = box_mesh
	mesh.position = hitbox_offset()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("c8354b")
	mesh.material_override = material
	return mesh
