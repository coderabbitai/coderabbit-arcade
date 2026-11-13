extends SceneTree
## Captures the Endless Runner stills the main menu showcases (graphical run only):
## Godot --always-on-top --path hoppys-adventure-arcade --script res://tests/capture_runner_menu_previews.gd
## Plays a real autopilot run with every 2D layer hidden, catches the bot jumping a blocking hazard,
## fast-forwards the stage to its boss and writes
## res://Assets/runner/menu_previews/runner_{gameplay,powerup,dodge,boss}.png.
const OUT_DIR := "res://Assets/runner/menu_previews/"
const RUN_SEED := 4242
const DEADLINE_SECONDS := 240.0
var game: Node
var wanted := {"powerup": false, "dodge": false, "boss": false}
## A jump only counts as a dodge when a blocking hazard is this close ahead (track z).
const DODGE_REACH := 9.0
var pending: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# The saved fullscreen setting is applied while the autoloads are still being added, and on macOS
	# that mode switch pumps frames and deferred calls: wait until the root has finished setting up.
	await process_frame
	while not root.is_node_ready():
		await process_frame
	if DisplayServer.get_name() == "headless":
		print("RUNNER MENU CAPTURE: requires a graphical display; no images written")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	game = (load("res://scenes/runner/runner_game.tscn") as PackedScene).instantiate()
	game.autostart = false
	game.leaderboard_path = OS.get_temp_dir().path_join("runner_menu_capture_leaderboard.cfg")
	root.add_child(game)
	game.player_action.connect(_on_action)
	game.boss_spawned.connect(func(_kind, _hp): _want("boss"))
	# The stills are gameplay: no run intro in front of them.
	game.pending_intro_mode = &""
	game.start_run(RUN_SEED)
	game.set_autopilot(true)
	_hide_hud_panels()
	var failures := 0
	await create_timer(5.0).timeout
	failures += await _capture("gameplay")
	var deadline := Time.get_ticks_msec() + int(DEADLINE_SECONDS * 1000)
	while wanted.values().has(false) and Time.get_ticks_msec() < deadline:
		# The runner pauses when the app loses focus (another window in front); keep the bot running.
		if game.paused:
			game.resume()
		if game.state != &"running":
			game.pending_intro_mode = &""
			game.start_run(RUN_SEED + Time.get_ticks_msec() % 997)
			game.set_autopilot(true)
		# A pickup glowing a few metres ahead reads better than the frame after a grab.
		if not wanted.powerup and not pending.has("powerup"):
			for pickup: Node3D in get_nodes_in_group(&"runner_pickups"):
				if pickup.is_visible_in_tree() and pickup.global_position.z > -11.0 and pickup.global_position.z < -7.0:
					_want("powerup")
					break
		if wanted.powerup and wanted.dodge and not wanted.boss and game.phase == &"run":
			var stages = game.stage_manager
			stages.stage_distance = maxf(stages.stage_distance, stages.stage_distance_target - 40.0)
		if not pending.is_empty():
			var shot: String = pending.pop_front()
			# Let the moment develop: Hoppy is at the top of the jump, and the boss fight is under way
			# (the intro cinematic takes the camera off Hoppy, so wait it out first).
			await create_timer({"powerup": 0.0, "dodge": 0.15, "boss": 0.5}[shot]).timeout
			if shot == "boss":
				var intro_deadline := Time.get_ticks_msec() + 20000
				while game.boss_cinematic_mode != &"" and Time.get_ticks_msec() < intro_deadline:
					if game.paused:
						game.resume()
					await process_frame
				if game.boss_cinematic_mode != &"":
					push_error("RUNNER MENU CAPTURE: boss cinematic timed out")
					failures += 1
					continue
				await create_timer(1.5).timeout
			_hide_hud_panels()
			failures += await _capture(shot)
			wanted[shot] = true
		await process_frame
	for shot in wanted:
		if not wanted[shot]:
			push_error("RUNNER MENU CAPTURE: never reached " + shot)
			failures += 1
	print("RUNNER MENU CAPTURE: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	game.queue_free()
	await create_timer(0.3).timeout
	quit(failures)

## The bot jumped: keep it as the dodge still only when a blocking hazard is right in front of it.
func _on_action(action: StringName) -> void:
	if action != &"jump" or wanted.dodge:
		return
	for hazard: Node3D in get_nodes_in_group(&"runner_hazards"):
		if not hazard.has_method("is_blocking") or not hazard.is_blocking():
			continue
		var z: float = game.track_z(hazard)
		if z < 0.0 and z > -DODGE_REACH:
			_want("dodge")
			return

func _want(shot: String) -> void:
	if not wanted.get(shot, true) and not pending.has(shot):
		pending.append(shot)

# The menu composes its own text over the still, so every 2D layer (HUD panels, toasts, banners) is
# redirected into an offscreen viewport. HUD scripts re-show their own nodes, so hiding is not enough.
var _offscreen: SubViewport
func _hide_hud_panels() -> void:
	if _offscreen == null:
		_offscreen = SubViewport.new()
		_offscreen.size = Vector2i(8, 8)
		_offscreen.render_target_update_mode = SubViewport.UPDATE_DISABLED
		root.add_child(_offscreen)
	for layer in game.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).custom_viewport = _offscreen

func _capture(shot: String) -> int:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT_DIR + "runner_%s.png" % shot)
	var image := root.get_texture().get_image()
	# A maximized or HiDPI window renders larger than the 1280x720 the menu stills are stored at:
	# crop to 16:9 around the centre, then scale down.
	var crop := Vector2i(image.get_width(), image.get_width() * 9 / 16)
	if crop.y > image.get_height():
		crop = Vector2i(image.get_height() * 16 / 9, image.get_height())
	if crop != image.get_size():
		image = image.get_region(Rect2i((image.get_size() - crop) / 2, crop))
	if image.get_size() != Vector2i(1280, 720):
		image.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	var error := image.save_png(path)
	print("CAPTURE: ", shot, " -> ", path, " error=", error)
	return 0 if error == OK else 1
