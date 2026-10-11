extends SceneTree
## Captures the Code City district-boss and finale stills docs/code-city-brawl.md shows (graphical run only):
## Godot --always-on-top --path hoppys-adventure-arcade --script res://tests/capture_code_city_bosses.gd
## Steps the real game by hand into each district boss and writes docs/previews/code-city/
## mini_boss_{1,2}.png (a slam winding up onto Hoppy), district_boss_down.png (the victory hop),
## district_boss_runoff.png (the exit run) and celebration.png (mid-party, after the Force Merge).
const OUT_DIR := "res://../docs/previews/code-city/"
const DT := 1.0/60.0
var game
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.controlled = false
	for e in game.enemies:
		if is_instance_valid(e): e.set_physics_process(false)
	if is_instance_valid(game.boss): game.boss.set_physics_process(false)

func tick(n := 1) -> void:
	for i in n: game._physics_process(DT)

## Draws the state just stepped (not the last engine tick) and saves it.
func capture(name: String) -> void:
	game.world.reset_physics_interpolation()
	game.camera.reset_physics_interpolation()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := OUT_DIR+name+".png"
	var image := root.get_texture().get_image()
	var ok: bool = image.get_size() == Vector2i(1280, 720) and image.save_png(path) == OK
	print("CODE CITY BOSS CAPTURE: ", path if ok else "failed to write "+path)
	if not ok: failures += 1

## Hit bursts and slam dust fade on tweens; clear them so a still shows the pose, not the fx.
func clear_fx() -> void:
	for child in game.actors.get_children():
		if child is AnimatedSprite2D and child != game.merge_button: child.queue_free()

## Room 3 of `stage` with its wave gone, Hoppy left of centre and the camera on the room.
func boss_room(stage: int) -> void:
	game.flow.cancel()
	game.start_stage(stage)
	freeze()
	var guard := 0
	while game.state != "combat" and guard < 400:
		tick()
		guard += 1
	game.flow.banner("", "", 0)
	game.enter_room(2)
	for e in game.enemies:
		if is_instance_valid(e): e.queue_free()
	game.enemies.clear()
	freeze()
	game.hazard_clock = 30.0
	game.ally_clock = 30.0
	game.camera.position = Vector2(game.room_start()+640, 360)
	game.player.position = Vector2(game.room_start()+430, 590)

func district(stage: int) -> void:
	boss_room(stage)
	tick() # the cleared wave calls in the district boss
	var boss = game.boss
	if not game.has_mini_boss():
		print("CODE CITY BOSS CAPTURE: no district boss in district %d" % (stage+1))
		failures += 1
		return
	boss.set_physics_process(false)
	var guard := 0
	while boss.state == "intro" and guard < 200:
		boss.tick(DT)
		tick()
		guard += 1
	boss.cycle = 0
	boss.telegraph() # cycle 1 is the slam, planted on Hoppy
	for i in 24:
		boss.tick(DT)
		tick()
	game.hide_toast()
	await capture("mini_boss_%d" % (stage+1))
	if stage != 0: return
	# The last hit lands through a real swing, the way play reaches the victory hop.
	game.clear_threats()
	boss.state = "chase"
	boss.hp = 1.0
	var p = game.player
	p.position = boss.position-Vector2(80, 0)
	p.facing = 1.0
	p.start_attack()
	guard = 0
	while game.state != "boss_victory" and guard < 60:
		p.tick(DT)
		guard += 1
	if game.state != "boss_victory":
		print("CODE CITY BOSS CAPTURE: the swing did not defeat %s (state %s)" % [boss.title, game.state])
		failures += 1
		return
	guard = 0
	while game.state == "boss_victory" and game.victory_clock < .7 and guard < 200:
		tick()
		guard += 1
	clear_fx()
	await capture("district_boss_down")
	guard = 0
	while not (game.state == "stage_exit" and game.flow.phase == "exit_run" and game.flow.clock >= .35) and guard < 400:
		tick()
		guard += 1
	await capture("district_boss_runoff")

func finale() -> void:
	boss_room(2)
	var boss = game.boss
	boss.set_physics_process(false)
	for damage in [12, 6, 6]:
		boss.vulnerable = true
		boss.take_hit(damage, 0, Vector2.ZERO, true)
	freeze()
	var guard := 0
	while game.state == "finisher" and guard < 600:
		tick()
		guard += 1
	guard = 0
	while game.state == "celebration" and game.party.clock < 2.6 and guard < 600:
		tick()
		guard += 1
	if game.state != "celebration":
		print("CODE CITY BOSS CAPTURE: the Force Merge did not reach the celebration (state %s)" % game.state)
		failures += 1
		return
	clear_fx()
	await capture("celebration")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("CODE CITY BOSS CAPTURE: requires a graphical display; no images written")
		quit(1)
		return
	# A graphical start is still adding the autoloads' nodes to root for its first frames, and the
	# maximized window can open taller than 720 px; settle, then size it like the other stills.
	await create_timer(.5).timeout
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var sizing := 0
	while Vector2i(root.get_texture().get_size()) != Vector2i(1280, 720) and sizing < 120:
		await process_frame
		sizing += 1
	if Vector2i(root.get_texture().get_size()) != Vector2i(1280, 720):
		print("CODE CITY BOSS CAPTURE: the window stayed %s, not 1280x720; no images written" % root.get_texture().get_size())
		quit(1)
		return
	change_scene_to_file("res://scenes/beatem_up/code_city_brawl.tscn")
	var loading := 0
	while (current_scene == null or current_scene.get("player") == null) and loading < 600:
		await process_frame
		loading += 1
	game = current_scene
	game.test_mode = true
	paused = false
	if game.state == "paused": game.resume()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await district(0)
	await district(1)
	await finale()
	game.queue_free()
	root.get_node("AudioService").shutdown()
	await create_timer(.4).timeout
	quit(1 if failures else 0)
