extends SceneTree
## Contract scaffold check: runner_game.tscn and runner_menu.tscn load, the contract §3 tree is
## complete and the contract §4 facade exists.
## Run with --path <project> --script res://tests/runner_scaffold_check.gd.

const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")
const PowerUpDefs = preload("res://scenes/runner/powerups/power_up_defs.gd")

## Contract §3, node path -> expected class.
const TREE := {
	"Systems": "Node",
	"Systems/SpeedController": "Node",
	"Systems/HitManager": "Node",
	"Systems/ScoreManager": "Node",
	"Systems/EffectManager": "Node",
	"Systems/Spawner": "Node",
	"Systems/Autopilot": "Node",
	"World": "Node3D",
	"World/Floor": "StaticBody3D",
	"World/Chunks": "Node3D",
	"World/Environment": "Node3D",
	"Player": "CharacterBody3D",
	"Player/BodyShape": "CollisionShape3D",
	"Player/Hurtbox": "Area3D",
	"Player/Hurtbox/StandShape": "CollisionShape3D",
	"Player/Hurtbox/RollShape": "CollisionShape3D",
	"Player/Visual": "Node3D",
	"Pursuer": "Node3D",
	"Pursuer/Visual": "Node3D",
	"CameraRig": "Node3D",
	"CameraRig/Camera": "Camera3D",
	"HUD": "CanvasLayer",
	"Overlays": "CanvasLayer",
	"Audio": "Node",
	"DebugOverlay": "CanvasLayer"
}

## Contract §4.1.
const SIGNALS := [
	"run_started", "state_changed", "health_changed", "damage_taken", "damage_blocked",
	"shield_changed", "pursuit_started", "pursuit_progress", "pursuit_recovered", "caught",
	"run_finished", "leaderboard_saved", "score_changed", "bonus_awarded", "speed_changed",
	"difficulty_changed", "power_up_collected", "power_up_expired", "hazard_cleared",
	"hazards_blasted", "player_action", "chunk_spawned", "paused_changed"
]

## Contract §4.3.
const METHODS := [
	"pause", "resume", "toggle_pause", "retry", "go_to_menu", "hit_stop", "submit_name",
	"get_leaderboard", "get_result", "get_active_effects", "start_run", "set_autopilot"
]

## Contract §4.2.
const PROPERTIES := [
	"config", "state", "paused", "seed", "run_id", "elapsed", "distance", "speed",
	"normalized_speed", "difficulty", "hp", "score", "multiplier", "player", "camera_rig",
	"cosmetic_rng"
]

## Contract §6.
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "roll", "pause"]

## Contract §8: kind, variant, W x H x D, y_min, y_max, dodge_hint.
const HAZARDS := [
	[&"pr_backlog_low", &"", Vector3(5.6, 1.0, 1.2), 0.0, 1.0, &"JUMP"],
	[&"pr_backlog_high", &"", Vector3(5.6, 1.8, 1.2), 1.1, 2.9, &"ROLL"],
	[&"bug_swarm", &"", Vector3(1.6, 0.9, 1.2), 0.0, 0.9, &"JUMP_OR_LANE"],
	[&"merge_conflict", &"", Vector3(3.6, 1.0, 1.2), 0.0, 1.0, &"JUMP_OR_LANE"],
	[&"deprecated_pit", &"full", Vector3(5.6, 0.4, 3.0), -0.2, 0.2, &"JUMP"],
	[&"deprecated_pit", &"two_lane", Vector3(3.6, 0.4, 3.0), -0.2, 0.2, &"JUMP_OR_LANE"],
	[&"laser_grid", &"ground", Vector3(5.6, 0.4, 1.2), 0.1, 0.5, &"JUMP"],
	[&"laser_grid", &"mid", Vector3(5.6, 0.3, 1.2), 1.0, 1.3, &"ROLL_OR_JUMP"],
	[&"laser_grid", &"high", Vector3(5.6, 0.4, 1.2), 1.1, 1.5, &"ROLL"],
	[&"laser_grid", &"timed", Vector3(5.6, 0.4, 1.2), 0.1, 0.5, &"TIMED"],
	[&"comment_flood", &"", Vector3(3.6, 4.0, 1.2), 0.0, 4.0, &"LANE"],
	[&"build_shockwave", &"", Vector3(5.6, 0.5, 1.2), 0.0, 0.5, &"JUMP"]
]

const POWER_UP_KINDS := [&"approve_shield", &"code_review", &"super_jump", &"nitro", &"auto_fix", &"lgtm"]

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RUNNER SCAFFOLD: " + message)

func run() -> void:
	for action in ACTIONS:
		check(InputMap.has_action(action), "input action missing: " + action)
	check(ProjectSettings.get_setting("physics/common/physics_interpolation", false) == true,
		"physics_interpolation is not enabled")
	var layer_names := ["World", "PlayerBody", "EnemyHitbox", "PlayerHurtbox", "Pickup"]
	for i in layer_names.size():
		var expected: String = layer_names[i]
		check(String(ProjectSettings.get_setting("layer_names/3d_physics/layer_%d" % (i + 1), "")) == expected,
			"3d physics layer %d is not %s" % [i + 1, expected])
	var router := root.get_node("AppRouter")
	check(router.ROUTES.has("runner_game"), "AppRouter is missing the runner_game route")
	check(router.process_mode == Node.PROCESS_MODE_ALWAYS, "AppRouter must process while paused")

	var game := _instantiate("res://scenes/runner/runner_game.tscn")
	if game == null:
		await _report()
		return
	root.add_child(game)
	for i in 3:
		await process_frame

	check(game.name == "RunnerGame", "runner_game.tscn root is not named RunnerGame")
	check(game.process_mode == Node.PROCESS_MODE_ALWAYS, "RunnerGame is not PROCESS_MODE_ALWAYS")
	for path in TREE:
		var node := game.get_node_or_null(NodePath(path))
		check(node != null, "missing node: " + path)
		if node != null:
			check(node.is_class(TREE[path]), "%s is a %s, expected %s" % [path, node.get_class(), TREE[path]])
	_check_environment(game)
	for signal_name in SIGNALS:
		check(game.has_signal(signal_name), "missing signal: " + signal_name)
	for method in METHODS:
		check(game.has_method(method), "missing method: " + method)
	for property in PROPERTIES:
		check(property in game, "missing property: " + property)

	check(game.config != null, "RunnerGame.config is null")
	check(game.player != null and game.camera_rig != null, "player / camera_rig references are null")

	var floor_body: StaticBody3D = game.get_node("World/Floor")
	check(floor_body.collision_layer == 1 and floor_body.collision_mask == 2,
		"World/Floor layer/mask should be 1/2")
	var player: CharacterBody3D = game.get_node("Player")
	check(player.collision_layer == 2 and player.collision_mask == 1, "Player layer/mask should be 2/1")
	check(player.axis_lock_linear_z, "Player must lock linear Z")
	check(player.is_in_group("runner_player"), "Player is not in group runner_player")
	var hurtbox: Area3D = game.get_node("Player/Hurtbox")
	check(hurtbox.collision_layer == 8 and hurtbox.collision_mask == 0, "Hurtbox layer/mask should be 8/0")
	check(hurtbox.monitorable and not hurtbox.monitoring, "Hurtbox must be monitorable only")
	check(game.get_node("Player/Hurtbox/RollShape").disabled, "RollShape must start disabled")
	var camera: Camera3D = game.get_node("CameraRig/Camera")
	check(camera.current, "CameraRig/Camera must be current")
	check(is_equal_approx(camera.fov, float(game.config.camera_fov)), "Camera fov does not match the config")
	check(camera.position.is_equal_approx(game.config.camera_position), "Camera position does not match the config")
	check((game.get_node("HUD") as CanvasLayer).layer == 10, "HUD layer should be 10")
	check((game.get_node("Overlays") as CanvasLayer).layer == 20, "Overlays layer should be 20")
	check((game.get_node("DebugOverlay") as CanvasLayer).layer == 90, "DebugOverlay layer should be 90")
	check(game.state == &"running", "autostart should leave the game running")

	# Pause facade: it must toggle and always leave the tree unpaused on the way out.
	game.toggle_pause()
	await process_frame
	check(game.paused and paused, "toggle_pause did not pause the tree")
	game.toggle_pause()
	await process_frame
	check(not game.paused and not paused, "toggle_pause did not resume the tree")
	check(game.get_result().is_empty(), "get_result must be empty before the run finishes")
	check(game.get_active_effects().is_empty(), "get_active_effects must start empty")
	check(not game.submit_name("Test"), "submit_name must fail before the run finishes")
	check(game.get_leaderboard() is Array, "get_leaderboard must return an Array")

	# The graybox overlays mounted under Overlays and bound themselves.
	check(game.get_node("Overlays").get_child_count() == 2, "expected the pause and game over overlays")
	check(game.get_node("HUD").get_child_count() == 1, "expected the graybox HUD")

	game.free()
	await process_frame
	check(not paused, "freeing RunnerGame must leave the tree unpaused")

	var menu := _instantiate("res://scenes/runner/runner_menu.tscn")
	if menu != null:
		root.add_child(menu)
		for i in 3:
			await process_frame
		check(menu.name == "RunnerMenu", "runner_menu.tscn root is not named RunnerMenu")
		check(menu.buttons.size() == 3, "runner menu should offer Play / Main Menu / Quit")
		menu.free()
	await process_frame

	_check_hazards()
	_check_power_ups()

	# Routing: runner_game resolves, the tree is never handed over paused, and the facade's
	# go_to_menu() lands back on the runner menu.
	router.go("runner_game")
	await wait(0.7)
	check(current_scene != null and current_scene.scene_file_path == router.ROUTES["runner_game"],
		"AppRouter.go(\"runner_game\") did not load runner_game.tscn")
	check(not paused, "routing to runner_game left the tree paused")
	if current_scene != null and current_scene.has_method("go_to_menu"):
		current_scene.go_to_menu()
		await wait(0.7)
		check(current_scene.scene_file_path == router.ROUTES["runner"],
			"go_to_menu() did not return to the runner menu")
	check(not router.busy, "AppRouter stayed busy after routing")
	await _report()

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

## Contract §3: World carries the backend graybox environment, and a mounted frontend corridor
## frees it. Either shape is valid, so accept the graybox or a populated World/Environment.
func _check_environment(game: Node) -> void:
	var graybox := game.get_node_or_null("World/GrayboxEnvironment")
	if graybox != null and graybox.is_queued_for_deletion():
		graybox = null
	if graybox != null:
		check(graybox is Node3D, "World/GrayboxEnvironment is a %s, expected Node3D" % graybox.get_class())
	var mount := game.get_node_or_null("World/Environment")
	var mounted := mount != null and mount.get_child_count() > 0
	check(graybox != null or mounted,
		"World needs the graybox environment, or a corridor mounted under World/Environment")
	if mounted:
		check(graybox == null, "a mounted corridor must free World/GrayboxEnvironment")

## Every row of the contract §8 hazard table survives a round trip through hazard.tscn.
func _check_hazards() -> void:
	var scene := load("res://scenes/runner/hazards/hazard.tscn") as PackedScene
	check(scene != null, "hazard.tscn failed to load")
	if scene == null:
		return
	for row in HAZARDS:
		var id := "%s/%s" % [row[0], row[1]]
		var hazard: Area3D = scene.instantiate()
		hazard.kind = row[0]
		hazard.variant = row[1]
		root.add_child(hazard)
		check(hazard.collision_layer == 4 and hazard.collision_mask == 8,
			"%s: hazard layer/mask should be 4/8" % id)
		check(hazard.monitoring and not hazard.monitorable, "%s: hazard must monitor only" % id)
		check(hazard.is_in_group("runner_hazards"), "%s: hazard not in group runner_hazards" % id)
		check(hazard.is_blocking(), "%s: a fresh hazard must be blocking" % id)
		check(hazard.hitbox_size().is_equal_approx(row[2]),
			"%s: hitbox %v, expected %v" % [id, hazard.hitbox_size(), row[2]])
		var bounds: AABB = hazard.get_world_aabb()
		check(is_equal_approx(bounds.position.y, row[3]) and is_equal_approx(bounds.end.y, row[4]),
			"%s: y range %.2f..%.2f, expected %.2f..%.2f" % [id, bounds.position.y, bounds.end.y, row[3], row[4]])
		check(hazard.dodge_hint == row[5], "%s: dodge hint %s, expected %s" % [id, hazard.dodge_hint, row[5]])
		# Contract §7: min_hazard_depth 1.2 keeps Area3D overlap from tunnelling at the Nitro cap.
		check(hazard.hitbox_size().z >= 1.2, "%s: depth below the 1.2 m minimum" % id)
		hazard.free()
	var timed: Dictionary = HazardDefs.get_def(&"laser_grid", &"timed")
	check(bool(timed.get("timed", false)), "the timed laser variant must carry timed = true")
	check(is_equal_approx(float(timed.get("on_seconds", 0.0)), 1.2), "timed laser on_seconds should be 1.2")
	check(is_equal_approx(float(timed.get("off_seconds", 0.0)), 0.3), "timed laser off_seconds should be 0.3")

## Every power-up kind instantiates on the Pickup layer with the contract §7 sphere.
func _check_power_ups() -> void:
	var scene := load("res://scenes/runner/powerups/power_up.tscn") as PackedScene
	check(scene != null, "power_up.tscn failed to load")
	if scene == null:
		return
	for kind in POWER_UP_KINDS:
		var pickup: Area3D = scene.instantiate()
		pickup.kind = kind
		root.add_child(pickup)
		check(pickup.collision_layer == 16 and pickup.collision_mask == 8,
			"%s: pickup layer/mask should be 16/8" % kind)
		check(pickup.monitoring and not pickup.monitorable, "%s: pickup must monitor only" % kind)
		var shape := pickup.get_node_or_null("Shape") as CollisionShape3D
		check(shape != null and shape.shape is SphereShape3D, "%s: pickup needs a sphere shape" % kind)
		if shape != null and shape.shape is SphereShape3D:
			check(is_equal_approx((shape.shape as SphereShape3D).radius, 0.35),
				"%s: pickup radius should be 0.35" % kind)
		pickup.free()
	check(PowerUpDefs.kinds().size() == POWER_UP_KINDS.size(), "power_up_defs must list six kinds")

func _instantiate(path: String) -> Node:
	if not ResourceLoader.exists(path):
		check(false, "scene does not exist: " + path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		check(false, "scene failed to load: " + path)
		return null
	return packed.instantiate()

func _report() -> void:
	print("RUNNER SCAFFOLD: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures / ", checks, " checks)")
	root.get_node("AudioService").shutdown()
	await wait(0.3)
	quit(failures)
