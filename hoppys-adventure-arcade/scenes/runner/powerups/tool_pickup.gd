extends "res://scenes/runner/powerups/power_up.gd"
## A boss tool pickup (contract §11.7, systems spec §10.4): a power_up.gd pickup that auto-fires.
## Collecting one goes to the boss encounter instead of the EffectManager — it deals the tool's
## damage (or 0 when the phase resists that kind), pays config.tool_bonus and frees the pickup.
## There is no fire button and no inventory: reaching the tool is the whole interaction.
## Tools live in their own group (runner_tools) and travel +Z at game.speed like the corridor, so
## Nitro raises how many reach the player rather than making them unreachable.

const ToolDefs = preload("res://scenes/runner/powerups/tool_defs.gd")
## Where runner_game.tscn keeps the encounter (contract §11.3). `game.boss_encounter` is the
## fallback for a tree that mounts the arena somewhere else.
const ARENA_PATH := "World/TurnRig/BossArena"
## Fallback until setup() supplies the config (contract §7 despawn_z).
const DEFAULT_DESPAWN_Z := 12.0
## Graybox tint: one ORANGE for every tool (systems spec §10.4); the tag carries the kind.
const GRAYBOX_COLOR := Color("ff8c42")
const GRAYBOX_LABEL_SIZE := 48
const GRAYBOX_LABEL_PIXEL_SIZE := 0.005
## Tag height above the sphere centre, in metres.
const GRAYBOX_LABEL_Y := 0.55

func _ready() -> void:
	super()
	# A tool is not a power-up: the spawner's pickup bookkeeping, the autopilot's greedy pass and the
	# chunk validator all tell them apart by group (contract §11.7).
	remove_from_group(&"runner_pickups")
	add_to_group(&"runner_tools")

## Tools ride the corridor like chunks do, so the gap the encounter spawns them in survives Nitro.
func _physics_process(delta: float) -> void:
	if game == null or not is_instance_valid(game):
		return
	if game.state != &"running" and game.state != &"caught":
		return
	position.z += float(game.speed) * delta
	if position.z > despawn_z():
		queue_free()

## config.despawn_z once setup() has run, the contract default before that.
func despawn_z() -> float:
	return float(config.despawn_z) if config != null else DEFAULT_DESPAWN_Z

## Auto-fire: the encounter applies the damage and the score, the pickup then frees itself.
## `_player` is unused, exactly as in power_up.gd: the tool is resolved from `kind` alone.
func collect(_player: Node) -> void:
	if consumed:
		return
	consumed = true
	set_deferred(&"monitoring", false)
	var encounter := boss_encounter()
	if encounter != null and encounter.has_method("apply_tool"):
		encounter.apply_tool(kind)
	# A visual without the hook still has to disappear; the backend owns its lifetime.
	if is_instance_valid(visual):
		if visual.has_method("on_collected"):
			visual.on_collected()
		else:
			visual.hide()
	queue_free()

## The BossArena, by tree path first and through the facade property second. Null outside a fight,
## which is what makes a stray tool harmless.
func boss_encounter() -> Node:
	if game == null or not is_instance_valid(game):
		return null
	var node := game.get_node_or_null(NodePath(ARENA_PATH))
	if node != null and is_instance_valid(node):
		return node
	var value: Variant = game.get(&"boss_encounter")
	var encounter := value as Node
	if encounter != null and is_instance_valid(encounter):
		return encounter
	return null

## ORANGE sphere of the pickup radius with a Label3D tag, so a graybox fight still reads which tool
## is coming (systems spec §10.4). power_up.gd keeps `graybox_sphere` in step with config changes.
func _build_graybox() -> Node3D:
	var root := Node3D.new()
	root.name = "Graybox"
	var mesh := MeshInstance3D.new()
	mesh.name = "Sphere"
	graybox_sphere = SphereMesh.new()
	graybox_sphere.radius = pickup_radius()
	graybox_sphere.height = pickup_radius() * 2.0
	mesh.mesh = graybox_sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = GRAYBOX_COLOR
	mesh.material_override = material
	root.add_child(mesh)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = ToolDefs.label(kind)
	tag.font_size = GRAYBOX_LABEL_SIZE
	tag.pixel_size = GRAYBOX_LABEL_PIXEL_SIZE
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = GRAYBOX_COLOR
	tag.position = Vector3(0.0, GRAYBOX_LABEL_Y, 0.0)
	root.add_child(tag)
	return root
