extends SceneTree
## Contract scaffold check: runner_game.tscn and runner_menu.tscn load, the contract §3 tree is
## complete and the contract §4 facade exists.
## Run with --path <project> --script res://tests/runner_scaffold_check.gd.

const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")
const PowerUpDefs = preload("res://scenes/runner/powerups/power_up_defs.gd")

## Contract §3 and the §11.3 delta, node path -> expected class.
const TREE := {
	"Systems": "Node",
	"Systems/SpeedController": "Node",
	"Systems/HitManager": "Node",
	"Systems/ScoreManager": "Node",
	"Systems/EffectManager": "Node",
	"Systems/Spawner": "Node",
	"Systems/StageManager": "Node",
	"Systems/Autopilot": "Node",
	"World": "Node3D",
	"World/Floor": "StaticBody3D",
	"World/Chunks": "Node3D",
	"World/TurnRig": "Node3D",
	"World/TurnRig/Environment": "Node3D",
	"World/TurnRig/BossArena": "Node3D",
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

## Contract §4.1 and the §11.4 additions.
const SIGNALS := [
	"run_started", "state_changed", "health_changed", "damage_taken", "damage_blocked",
	"shield_changed", "pursuit_started", "pursuit_progress", "pursuit_recovered", "caught",
	"run_finished", "leaderboard_saved", "score_changed", "bonus_awarded", "speed_changed",
	"difficulty_changed", "power_up_collected", "power_up_expired", "hazard_cleared",
	"hazards_blasted", "player_action", "chunk_spawned", "paused_changed",
	"phase_changed", "stage_started", "stage_cleared", "turn_incoming", "turn_started", "turn_finished",
	"boss_intro", "boss_spawned", "boss_health_changed", "boss_phase_changed", "boss_attack_telegraph",
	"boss_projectile_fired", "boss_defeated", "boss_retreated", "tool_collected",
	"pursuit_alert", "pursuer_distance_changed"
]

## Contract §4.3 and the §11.4 additions.
const METHODS := [
	"pause", "resume", "toggle_pause", "retry", "go_to_menu", "hit_stop", "submit_name",
	"get_leaderboard", "get_result", "get_active_effects", "start_run", "set_autopilot",
	"get_stage_info", "get_boss_info", "track_z", "track_aabb", "on_tool_hit"
]

## Contract §4.2 and the §11.4 additions.
const PROPERTIES := [
	"config", "state", "paused", "seed", "run_id", "elapsed", "distance", "speed",
	"normalized_speed", "difficulty", "hp", "score", "multiplier", "player", "camera_rig",
	"cosmetic_rng",
	"phase", "stage_index", "stage_name", "stage_distance", "stage_distance_target", "run_clock",
	"next_turn_direction",
	"boss", "boss_kind", "boss_hp", "boss_max_hp", "boss_phase",
	"stage_manager", "turn_rig", "boss_encounter"
]

## Contract §11.3 and §11.8: the optional 3D fight effects, mounted inside the arena. Like the HUD
## panels it is tolerated when absent, and when it exists it must be PAUSABLE.
const BOSS_FX_SCENE := "res://scenes/runner/boss/boss_fx.tscn"

## Contract §11.8: optional, never grayboxed, tolerated when absent.
const OPTIONAL_HUD_MOUNTS := [
	"res://scenes/runner/ui/pursuit_alert.tscn",
	"res://scenes/runner/ui/boss_hud.tscn",
	"res://scenes/runner/ui/stage_banner.tscn",
	"res://scenes/runner/ui/stage_clear.tscn"
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
## Never the default board: this test drives real RunnerGame instances with `autostart` on, so a
## check that stalls long enough lets a run reach `caught` and write the player's own
## user://leaderboard.cfg. Every RunnerGame here is pointed at this throwaway file before it can
## start, and _report() removes it on every exit path (systems spec §8).
var leaderboard_path := "user://scaffold_leaderboard_%d.cfg" % OS.get_process_id()

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
	# Before add_child: _ready() honours `autostart`, so the run is already live by the time the
	# node is in the tree and a later assignment would race it.
	game.leaderboard_path = leaderboard_path
	root.add_child(game)
	for i in 3:
		await process_frame

	check(game.name == "RunnerGame", "runner_game.tscn root is not named RunnerGame")
	check(game.process_mode == Node.PROCESS_MODE_ALWAYS, "RunnerGame is not PROCESS_MODE_ALWAYS")
	# Everything below dereferences these paths through typed get_node() calls, which abort the whole
	# run on a null. Report every missing node first, then stop: an incomplete scene has already
	# failed the contract §3 check, and carrying on would trade the report for a crash.
	var tree_complete := true
	for path in TREE:
		var node := game.get_node_or_null(NodePath(path))
		check(node != null, "missing node: " + path)
		if node == null:
			tree_complete = false
			continue
		check(node.is_class(TREE[path]), "%s is a %s, expected %s" % [path, node.get_class(), TREE[path]])
	if not tree_complete:
		await _report()
		return
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

	# Contract §4.3: a restart asked for while paused must never begin frozen.
	var pause_events: Array[bool] = []
	game.paused_changed.connect(func(value: bool) -> void: pause_events.append(value))
	game.pause()
	await process_frame
	check(game.paused and paused, "pause() did not pause the tree before the restart")
	game.start_run(4321)
	await process_frame
	check(not game.paused, "start_run from a paused state left the facade paused")
	check(not paused, "start_run from a paused state left the tree paused")
	check(game.state == &"running", "start_run from a paused state did not go live (state %s)" % game.state)
	check(not pause_events.is_empty() and not pause_events[pause_events.size() - 1],
		"start_run did not emit paused_changed(false) on its way out of the pause")
	check(game.get_result().is_empty(), "get_result must be empty before the run finishes")
	check(game.get_active_effects().is_empty(), "get_active_effects must start empty")
	check(not game.submit_name("Test"), "submit_name must fail before the run finishes")
	check(game.get_leaderboard() is Array, "get_leaderboard must return an Array")

	# The graybox overlays mounted under Overlays and bound themselves.
	check(game.get_node("Overlays").get_child_count() == 2, "expected the pause and game over overlays")
	_check_hud_mounts(game)
	_check_stage_scaffold(game)

	game.free()
	await process_frame
	check(not paused, "freeing RunnerGame must leave the tree unpaused")

	var menu := _instantiate("res://scenes/runner/runner_menu.tscn")
	if menu != null:
		root.add_child(menu)
		for i in 3:
			await process_frame
		check(menu.name == "RunnerMenu", "runner_menu.tscn root is not named RunnerMenu")
		check(menu.buttons.size() == 4,
			"runner menu should offer Play / Leaderboard / Return to Main Menu / Quit Game (contract §2)")
		menu.free()
	await process_frame

	_check_hazards()
	_check_power_ups()

	# Routing: runner_game resolves, the tree is never handed over paused, and the facade's
	# go_to_menu() lands back on the runner menu.
	router.go("runner_game")
	var routed := await _wait_router_idle(router)
	check(routed, "AppRouter.go(\"runner_game\") never went idle")
	check(current_scene != null and current_scene.scene_file_path == router.ROUTES["runner_game"],
		"AppRouter.go(\"runner_game\") did not load runner_game.tscn")
	# The router owns this instance, so the override cannot precede its _ready(); it is set as early
	# as the transition settles so a run that outlives the teardown still cannot reach the default
	# board. Only the direct instantiation above is race-free.
	if current_scene != null and "leaderboard_path" in current_scene:
		current_scene.leaderboard_path = leaderboard_path
	check(not paused, "routing to runner_game left the tree paused")
	if current_scene != null and current_scene.has_method("go_to_menu"):
		current_scene.go_to_menu()
		var returned := await _wait_router_idle(router)
		check(returned, "go_to_menu() left AppRouter busy")
		check(current_scene.scene_file_path == router.ROUTES["runner"],
			"go_to_menu() did not return to the runner menu")
	check(not router.busy, "AppRouter stayed busy after routing")
	await _report()

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

## Wait out an AppRouter transition rather than guessing at its duration. `go()` sets `busy` before
## its first await and clears it only after the fade-out, the `change_scene_to_file()` and the
## fade-in have all finished, so `not busy` is exactly the point where `current_scene` is the new
## scene and the veil is back to pass-through — there is no separate transition flag to poll.
## Returns false on timeout, which keeps a stuck router a reported failure instead of a hung run.
func _wait_router_idle(router: Node, timeout_seconds := 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while router.busy:
		if Time.get_ticks_msec() > deadline:
			return false
		await process_frame
	return true

## Contract §3 and §11.3: the TurnRig carries the backend graybox environment, and a mounted
## frontend corridor frees it. Either shape is valid, so accept the graybox or a populated mount.
func _check_environment(game: Node) -> void:
	var graybox := game.get_node_or_null("World/TurnRig/GrayboxEnvironment")
	if graybox != null and graybox.is_queued_for_deletion():
		graybox = null
	if graybox != null:
		check(graybox is Node3D, "World/TurnRig/GrayboxEnvironment is a %s, expected Node3D" % graybox.get_class())
	var mount := game.get_node_or_null("World/TurnRig/Environment")
	var mounted := mount != null and mount.get_child_count() > 0
	check(graybox != null or mounted,
		"World/TurnRig needs the graybox environment, or a corridor mounted under Environment")
	if mounted:
		check(graybox == null, "a mounted corridor must free World/TurnRig/GrayboxEnvironment")

## Contract §11.8: the graybox HUD is always there; the four v2 panels mount only when the frontend
## has authored them, so the count is a range and every extra child has to be one of those scenes.
func _check_hud_mounts(game: Node) -> void:
	var hud := game.get_node("HUD") as CanvasLayer
	var expected := 1
	for path in OPTIONAL_HUD_MOUNTS:
		if ResourceLoader.exists(path):
			expected += 1
	check(hud.get_child_count() == expected,
		"HUD holds %d children, expected %d (graybox HUD plus the optional v2 panels that exist)"
			% [hud.get_child_count(), expected])

## Contract §11.1-§11.4: the stage machine is live, the phases line up with the state, the rig
## accessors resolve and the boss block reads empty outside a fight.
func _check_stage_scaffold(game: Node) -> void:
	check(game.stage_manager != null and is_instance_valid(game.stage_manager),
		"Systems/StageManager is missing from the facade")
	check(game.turn_rig != null and is_instance_valid(game.turn_rig), "World/TurnRig is missing from the facade")
	check(game.phase == &"run", "a running game should be in the run phase, not %s" % game.phase)
	check(game.stage_index == 1, "the first stage should be index 1, got %d" % game.stage_index)
	check(game.stage_name == &"Flaky Test Swarm",
		"stage 1 should name the Flaky Test Swarm, got %s" % game.stage_name)
	check(game.stage_distance_target > 0.0, "stage 1 has no distance target")
	check(game.run_clock >= 0.0, "run_clock must never be negative")
	# Contract §11.4: the seam's direction is only picked once the stage drains, and a stage that has
	# barely opened is nowhere near that.
	check(int(game.next_turn_direction) == 0,
		"next_turn_direction must read 0 with no turn pending, got %d" % int(game.next_turn_direction))
	check(game.boss == null and game.boss_kind == &"" and game.boss_phase == 0,
		"the boss block must read empty outside a fight")

	var info: Dictionary = game.get_stage_info()
	for key in ["index", "name", "phase", "distance", "target", "speed_bonus", "difficulty_floor"]:
		check(info.has(key), "get_stage_info() is missing the %s key" % key)
	var boss_info: Dictionary = game.get_boss_info()
	for key in ["kind", "name", "hp", "max_hp", "phase", "phase_count", "accepted_tools", "pending_attacks"]:
		check(boss_info.has(key), "get_boss_info() is missing the %s key" % key)

	# track_z is the identity while the rig is square, which is every frame outside a turn.
	check(is_equal_approx(game.track_z(game.player), game.player.global_position.z),
		"track_z should equal global z while the TurnRig is unrotated")
	check(game.track_aabb(game.player) is AABB, "track_aabb must return an AABB")
	# The shake hook is backend-owned and must survive being called outside a fight.
	game.on_tool_hit()

	# Contract §11.3: a bare arena is a valid placeholder, but it must never be missing.
	check(game.boss_encounter != null and is_instance_valid(game.boss_encounter),
		"World/TurnRig/BossArena did not resolve into boss_encounter")
	_check_boss_fx_mount(game)

## Contract §11.3 and §11.8: boss/boss_fx.tscn mounts inside the arena when the frontend has
## authored it, and is simply absent until then — the fight never depends on it.
func _check_boss_fx_mount(game: Node) -> void:
	var arena: Node = game.boss_encounter
	if arena == null or not is_instance_valid(arena):
		return
	var fx: Node = null
	for child in arena.get_children():
		if child.scene_file_path == BOSS_FX_SCENE:
			fx = child
	if ResourceLoader.exists(BOSS_FX_SCENE):
		check(fx != null and fx.process_mode == Node.PROCESS_MODE_PAUSABLE,
			"boss_fx.tscn exists but is not mounted under the arena as a PAUSABLE child")
	else:
		check(fx == null, "boss_fx.tscn does not exist, so nothing may be mounted for it")

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

## Every exit path comes through here, including the two early returns in run(), so the throwaway
## board and the scratch files of a half-finished write never outlive the test.
func _report() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(leaderboard_path + suffix):
			DirAccess.remove_absolute(leaderboard_path + suffix)
	print("RUNNER SCAFFOLD: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures / ", checks, " checks)")
	# Nullable, like runner_smoke.gd: a missing or renamed autoload is a project problem this test
	# should report through `failures`, not crash on during teardown — the verdict is already
	# printed, and quit(failures) still has to run.
	var audio := root.get_node_or_null("AudioService")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	await wait(0.3)
	quit(failures)
