extends SceneTree
## Deterministic real-game review strips. Run graphically with --always-on-top and the GPU lock.
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const FULL := [0.02, 0.20, 0.40, 0.445, 0.56, 0.72, 0.85, 0.97]
const SHORT := [0.40, 0.78]
const DEFEAT := [0.015, 0.16, 0.33, 0.56, 0.66, 0.84]
var game: Node
var folder := ""

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("BOSS CINEMATIC CAPTURE: graphical display required")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	AudioServer.set_bus_mute(0, true)
	folder = ProjectSettings.globalize_path("res://../docs/previews/runner/bosses")
	DirAccess.make_dir_recursive_absolute(folder)
	game = load("res://scenes/runner/runner_game.tscn").instantiate()
	game.autostart = false
	game.leaderboard_path = "user://capture_boss_cinematics_%d.cfg" % OS.get_process_id()
	root.add_child(game)
	game.start_run(4242)
	game.paused_changed.connect(_ignore_focus_pause)
	await process_frame
	await process_frame
	paused = true
	game.paused = false
	# Hide the menu route's stage-1 opening card before entering the real boss phase.
	game.get_node("HUD/StageBanner").hide()
	for stage in [1, 2, 3]:
		game.stage_manager.stage_index = stage
		game.stage_manager._enter_boss()
		var kind := String(BossDefs.boss_kind(stage))
		await capture_sequence(kind, "intro_full", FULL, 4)
		game.boss_encounter.tick(5.0)
		# Kill through the accepted-tool API; scoring and cinematic start remain backend-owned.
		while game.boss_encounter.hp > 0:
			var accepted := BossDefs.accepted_tools(game.boss_encounter.def, game.boss_encounter.phase)
			game.boss_encounter.apply_tool(accepted[0])
		await capture_sequence(kind, "defeat_full", DEFEAT, 3)
		game.boss_encounter.tick(5.0)
		game.stage_manager.stage_index = stage + 3
		game.stage_manager._enter_boss()
		await capture_sequence(kind, "intro_short", SHORT, 2)
		game.boss_encounter.abort()
	print("BOSS CINEMATIC CAPTURE: PASS (3 full 8-frame, 3 short pairs, 3 defeat 6-frame strips)")
	paused = false
	game.free()
	root.get_node("AudioService").shutdown()
	await process_frame
	quit(0)

func capture_sequence(kind: String, label: String, points: Array, columns: int) -> void:
	var strip := Image.create(columns * 640, ceili(float(points.size()) / columns) * 360, false, Image.FORMAT_RGB8)
	var last := 0.0
	var seconds: float = game.boss_encounter.cinematic_seconds
	for index in points.size():
		var p: float = points[index]
		game.boss_encounter.tick(maxf(0, p - last) * seconds)
		last = p
		game.stage_manager._publish()
		game.stage_manager._apply_boss_camera()
		game.camera_rig.trauma = 0.0
		game.camera_rig._physics_process(0.0)
		game.get_node("HUD/BossCinematic")._process(0.0)
		game.get_node("HUD/PostFX")._process(0.0)
		game.get_node("World/TurnRig/BossArena/BossFX")._process(0.0)
		# Flush bone attachments, labels and controls before the rendered readback.
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		if index == 4 or (label == "intro_short" and index == 0):
			frame.save_png(folder.path_join("%s-%s-hero.png" % [kind, label]))
		frame.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		frame.convert(Image.FORMAT_RGB8)
		strip.blit_rect(frame, Rect2i(0, 0, 640, 360), Vector2i(index % columns * 640, index / columns * 360))
	var path := folder.path_join("%s-%s.png" % [kind, label])
	strip.save_png(path)
	print("BOSS CAPTURE: ", path, " p=", points)

func _ignore_focus_pause(value: bool) -> void:
	# Automated review is frozen by SceneTree, independently of the focus-loss pause UI.
	if value:
		game.resume()
		paused = true
