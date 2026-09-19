extends Area3D
## Pickup sphere plus its visual mount (systems spec §5.4).

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const PowerUpDefs = preload("res://scenes/runner/powerups/power_up_defs.gd")
const RunnerLayers = preload("res://scenes/runner/runner_layers.gd")
const VISUAL_DIR := "res://scenes/runner/powerups/visuals/"
## Contract §5.3 default; setup() switches to config.pickup_radius.
const DEFAULT_PICKUP_RADIUS := 0.35

@export var kind: StringName = &"approve_shield"

var game: RunnerGame
var config: RunConfig
var visual: Node3D
var consumed := false
## Both are built in code, so resizing them never touches a shared resource.
var sphere: SphereShape3D
var graybox_sphere: SphereMesh

func _ready() -> void:
	collision_layer = RunnerLayers.PICKUP
	collision_mask = RunnerLayers.PLAYER_HURTBOX
	monitoring = true
	monitorable = false
	add_to_group(&"runner_pickups")
	_build_shape()
	_mount_visual()
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	_apply_pickup_radius()

## config.pickup_radius once setup() has run, the contract default before that.
func pickup_radius() -> float:
	if config == null:
		return DEFAULT_PICKUP_RADIUS
	return float(config.pickup_radius)

func _apply_pickup_radius() -> void:
	var radius := pickup_radius()
	if sphere != null:
		sphere.radius = radius
	if graybox_sphere != null:
		graybox_sphere.radius = radius
		graybox_sphere.height = radius * 2.0

## `_player` is unused: EffectManager resolves the pickup from `kind` alone.
func collect(_player: Node) -> void:
	if consumed:
		return
	consumed = true
	set_deferred(&"monitoring", false)
	if game != null and game.effect_manager != null:
		game.effect_manager.apply(kind)
	# A visual without the hook still has to disappear; the backend owns its lifetime.
	if visual != null:
		if visual.has_method("on_collected"):
			visual.on_collected()
		else:
			visual.hide()

func _on_area_entered(area: Area3D) -> void:
	var owner_node := area.get_parent()
	if owner_node != null and owner_node.is_in_group(&"runner_player"):
		collect(owner_node)

func _build_shape() -> void:
	sphere = SphereShape3D.new()
	sphere.radius = pickup_radius()
	var shape_node := CollisionShape3D.new()
	shape_node.name = "Shape"
	shape_node.shape = sphere
	add_child(shape_node)

func _mount_visual() -> void:
	var path := VISUAL_DIR + String(kind) + "_visual.tscn"
	if ResourceLoader.exists(path):
		var scene := _load_scene(path)
		if scene != null:
			var instance := scene.instantiate()
			if instance is Node3D:
				visual = instance
				add_child(visual)
				if &"kind" in visual:
					visual.set(&"kind", kind)
				if visual.has_method("on_spawned"):
					visual.on_spawned()
				return
			if instance != null:
				push_warning("Runner power-up visual at %s root is %s, expected Node3D; using graybox" % [path, instance.get_class()])
				instance.queue_free()
	visual = _build_graybox()
	add_child(visual)

## Contract §3: a mounted resource that fails to load or is not a PackedScene is warned about and
## the code-built graybox is used instead.
func _load_scene(path: String) -> PackedScene:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Runner power-up visual at %s is not a PackedScene; using graybox" % path)
	return scene

## Coloured sphere of the pickup radius per kind.
func _build_graybox() -> Node3D:
	var mesh := MeshInstance3D.new()
	mesh.name = "Graybox"
	graybox_sphere = SphereMesh.new()
	graybox_sphere.radius = pickup_radius()
	graybox_sphere.height = pickup_radius() * 2.0
	mesh.mesh = graybox_sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = PowerUpDefs.color(kind)
	mesh.material_override = material
	return mesh
