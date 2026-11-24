extends SceneTree
## Code City Brawl's walkable depth band is the paved floor of each stage's background: Hoppy,
## enemies, spawns and bosses stay below the railing, fence or balustrade (Catalog.FLOOR_TOP).
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const Boss = preload("res://modes/beatem_up/boss.gd")
const DT := 1.0/60.0
## Where each background's railing base ends (world px), read off the art; the band starts below.
const ART_FLOOR_LINE := [495.0, 440.0, 455.0]
var failures := 0
var game
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures += 1
func frames(n: int) -> void:
	for i in n: await physics_frame
func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for e in game.enemies: e.set_physics_process(false)
	if is_instance_valid(game.boss): game.boss.set_physics_process(false)
## Hold a depth direction for `seconds` of player ticks and return where Hoppy ends up.
func drive(action: String, seconds: float) -> Vector2:
	var p = game.player
	p.controlled = true
	p.input_lock = 0
	p.stagger = 0
	p.knock = Vector2.ZERO
	Input.action_press(action)
	for i in int(seconds/DT): p.tick(DT)
	Input.action_release(action)
	p.tick(DT)
	return p.position
func run() -> void:
	change_scene_to_file("res://scenes/beatem_up/code_city_brawl.tscn")
	await process_frame
	await process_frame
	await frames(5)
	game = current_scene
	game.test_mode = true
	paused = false
	if game.state == "paused": game.resume()
	freeze()
	check(Catalog.FLOOR_TOP.size() == Catalog.THEMES.size(), "Every stage theme has a floor line")
	for stage in Catalog.THEMES.size():
		var top: float = Catalog.FLOOR_TOP[stage]
		var bottom: float = Catalog.FLOOR_BOTTOM
		var label: String = Catalog.THEMES[stage]
		check(top > ART_FLOOR_LINE[stage] and bottom > top + 100 and bottom <= 720, "%s: the band is on the paved floor, under the railing base" % label)
		game.start_stage(stage)
		await process_frame
		freeze()
		check(game.stage_index == stage and is_equal_approx(game.floor_top(), top), "%s: the stage reports its floor line" % label)
		check(game.clamp_ground(Vector2(640, 0)).y == top and game.clamp_ground(Vector2(640, 9999)).y == bottom, "%s: clamp_ground keeps the ground plane in the band" % label)
		for e in game.enemies:
			check(e.position.y >= top and e.position.y <= bottom, "%s: %s spawns on the floor at y=%d" % [label, e.kind, int(e.position.y)])
		var spawned = game.spawn_enemy("cli_gremlin", Vector2(game.room_start()+700, 100), false)
		check(spawned != null and is_equal_approx(spawned.position.y, top), "%s: a spawn above the floor lands on its edge" % label)
		if spawned != null:
			spawned.set_physics_process(false)
			game.enemies.erase(spawned)
			spawned.queue_free()
		for prop in game.props:
			check(prop.node.position.y >= top and prop.node.position.y <= bottom, "%s: props stand on the floor" % label)
		var p = game.player
		p.position = Vector2(game.room_start()+640, 580)
		p.height = 0; p.rise = 0
		var up := drive("move_up", 3.0)
		check(is_equal_approx(up.y, top) and p.height == 0, "%s: walking up stops at the floor line (y=%d)" % [label, int(up.y)])
		var down := drive("move_down", 3.0)
		check(is_equal_approx(down.y, bottom), "%s: walking down stops at the lowest lane" % label)
		p.position = Vector2(game.room_start()+640, 580)
		# Knockback cannot push Hoppy past the floor line either.
		p.knock = Vector2(0, -2000)
		p.tick(DT)
		check(p.position.y >= top, "%s: knockback keeps Hoppy on the floor" % label)
		p.knock = Vector2.ZERO
		if Catalog.MINI_BOSS_STAGES[stage] != "":
			game.call_mini_boss()
			await process_frame
			game.boss.set_physics_process(false)
			var spot: Vector2 = game.boss.arena_point(Vector2(game.room_start()+640, 0))
			check(spot.y >= top and game.boss.position.y >= top, "%s: the district boss keeps to the floor" % label)
		else:
			var boss := Boss.new()
			boss.arena = game
			var spot: Vector2 = boss.arena_point(Vector2(game.room_start()+640, 0))
			check(spot.y >= top and boss.arena_point(Vector2(0, 9999)).y <= bottom, "%s: the Grand Merge Conflict keeps to the floor" % label)
			boss.free()
	print("Code City floor failures: ",failures)
	game.queue_free()
	await root.get_node("AudioService").settle()
	quit(1 if failures else 0)
